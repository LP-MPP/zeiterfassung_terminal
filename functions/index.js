const crypto = require("crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

admin.initializeApp();

const db = admin.firestore();
const REGION = "europe-west3";
const SESSION_TTL_MS = 2 * 60 * 1000;
const LOGIN_WINDOW_MS = 10 * 60 * 1000;
const MAX_LOGIN_ATTEMPTS = 8;
const BERLIN_TIME_ZONE = "Europe/Berlin";
const ALLOWED_EVENT_TYPES = new Set(["IN", "OUT", "BREAK_START", "BREAK_END"]);

function ensureSignedIn(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Bitte App neu starten.");
  }
}

function normalizeEmployeeId(value) {
  return String(value || "").trim().toUpperCase();
}

function normalizeTerminalId(value) {
  return String(value || "").trim();
}

function normalizeEventType(value) {
  return String(value || "").trim().toUpperCase();
}

function hashPin(employeeId, pin) {
  return crypto.createHash("sha256").update(`${employeeId}:${pin}`).digest("hex");
}

function dayKeyBerlinFromUtcMs(utcMs) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: BERLIN_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(utcMs));
}

function stateFromLastEvent(lastEventType) {
  switch (lastEventType) {
    case "IN":
    case "BREAK_END":
      return "working";
    case "BREAK_START":
      return "onBreak";
    case "OUT":
    default:
      return "off";
  }
}

function isAllowed(lastEventType, nextEventType) {
  const state = stateFromLastEvent(lastEventType);
  switch (state) {
    case "off":
      return nextEventType === "IN";
    case "working":
      return nextEventType === "BREAK_START" || nextEventType === "OUT";
    case "onBreak":
      return nextEventType === "BREAK_END";
    default:
      return false;
  }
}

async function getLastEventType(employeeId) {
  const stateRef = db.collection("employee_state").doc(employeeId);
  const stateSnap = await stateRef.get();
  if (stateSnap.exists) {
    return stateSnap.data()?.lastEventType || null;
  }

  const eventsSnap = await db.collection("events").where("employeeId", "==", employeeId).get();
  let lastEventType = null;
  let lastTimestampUtcMs = 0;
  let lastTerminalId = null;
  let lastSource = null;

  for (const doc of eventsSnap.docs) {
    const data = doc.data() || {};
    const timestampUtcMs = Number(data.timestampUtcMs || 0);
    if (timestampUtcMs >= lastTimestampUtcMs) {
      lastTimestampUtcMs = timestampUtcMs;
      lastEventType = data.eventType || null;
      lastTerminalId = data.terminalId || null;
      lastSource = data.source || null;
    }
  }

  if (lastEventType) {
    await stateRef.set({
      employeeId,
      lastEventType,
      timestampUtcMs: lastTimestampUtcMs,
      terminalId: lastTerminalId,
      source: lastSource,
      dayKey: dayKeyBerlinFromUtcMs(lastTimestampUtcMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  return lastEventType;
}

async function noteFailedLogin(uid, employeeId) {
  const attemptRef = db.collection("login_attempts").doc(`${uid}_${employeeId}`);
  const now = Date.now();
  const snap = await attemptRef.get();
  const data = snap.data() || {};
  const resetAtMs = Number(data.resetAtMs || 0);
  const isExpired = resetAtMs <= now;
  const count = isExpired ? 0 : Number(data.count || 0);

  await attemptRef.set({
    count: count + 1,
    resetAtMs: now + LOGIN_WINDOW_MS,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function assertLoginLimit(uid, employeeId) {
  const attemptRef = db.collection("login_attempts").doc(`${uid}_${employeeId}`);
  const snap = await attemptRef.get();
  if (!snap.exists) return;

  const data = snap.data() || {};
  const now = Date.now();
  const resetAtMs = Number(data.resetAtMs || 0);
  if (resetAtMs <= now) return;

  const count = Number(data.count || 0);
  if (count >= MAX_LOGIN_ATTEMPTS) {
    throw new HttpsError("resource-exhausted", "Zu viele PIN-Versuche. Bitte kurz warten.");
  }
}

async function clearLoginLimit(uid, employeeId) {
  await db.collection("login_attempts").doc(`${uid}_${employeeId}`).delete().catch(() => {});
}

exports.listActiveEmployeesPublic = onCall({region: REGION}, async (request) => {
  ensureSignedIn(request);

  const snap = await db.collection("employees").where("active", "==", true).get();
  const employees = snap.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      id: String(data.id || doc.id),
      name: String(data.name || ""),
      active: data.active === true,
    };
  }).sort((a, b) => a.id.localeCompare(b.id, "de"));

  return employees;
});

exports.authenticateEmployeePin = onCall({region: REGION}, async (request) => {
  ensureSignedIn(request);

  const employeeId = normalizeEmployeeId(request.data?.employeeId);
  const pin = String(request.data?.pin || "").trim();
  const terminalId = normalizeTerminalId(request.data?.terminalId);

  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Mitarbeiter-ID fehlt.");
  }
  if (!/^[0-9]{4,8}$/.test(pin)) {
    throw new HttpsError("invalid-argument", "PIN muss 4 bis 8 Ziffern haben.");
  }
  if (!terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-ID fehlt.");
  }

  await assertLoginLimit(request.auth.uid, employeeId);

  const employeeSnap = await db.collection("employees").doc(employeeId).get();
  if (!employeeSnap.exists) {
    await noteFailedLogin(request.auth.uid, employeeId);
    throw new HttpsError("permission-denied", "PIN oder Mitarbeiter ist ungültig.");
  }

  const employee = employeeSnap.data() || {};
  if (employee.active !== true) {
    throw new HttpsError("failed-precondition", "Mitarbeiter ist inaktiv.");
  }

  const expectedHash = String(employee.pinHash || "");
  if (!expectedHash || expectedHash !== hashPin(employeeId, pin)) {
    await noteFailedLogin(request.auth.uid, employeeId);
    throw new HttpsError("permission-denied", "PIN oder Mitarbeiter ist ungültig.");
  }

  await clearLoginLimit(request.auth.uid, employeeId);

  const sessionRef = db.collection("terminal_sessions").doc();
  const expiresAtMs = Date.now() + SESSION_TTL_MS;
  const lastEventType = await getLastEventType(employeeId);

  await sessionRef.set({
    uid: request.auth.uid,
    employeeId,
    employeeName: String(employee.name || ""),
    terminalId,
    expiresAtMs,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    sessionId: sessionRef.id,
    employeeId,
    employeeName: String(employee.name || ""),
    lastEventType,
    expiresAtMs,
  };
});

exports.createPunchEvent = onCall({region: REGION}, async (request) => {
  ensureSignedIn(request);

  const sessionId = String(request.data?.sessionId || "").trim();
  const eventType = normalizeEventType(request.data?.eventType);
  const terminalId = normalizeTerminalId(request.data?.terminalId);

  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Session fehlt.");
  }
  if (!ALLOWED_EVENT_TYPES.has(eventType)) {
    throw new HttpsError("invalid-argument", "Event-Typ ist ungültig.");
  }
  if (!terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-ID fehlt.");
  }

  const sessionRef = db.collection("terminal_sessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
  }

  const session = sessionSnap.data() || {};
  if (String(session.uid || "") != request.auth.uid) {
    throw new HttpsError("permission-denied", "Session gehört zu einem anderen Gerät.");
  }
  if (String(session.terminalId || "") !== terminalId) {
    throw new HttpsError("permission-denied", "Terminal-ID stimmt nicht mit der Session überein.");
  }
  if (Number(session.expiresAtMs || 0) <= Date.now()) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
  }

  const employeeId = String(session.employeeId || "");
  const employeeSnap = await db.collection("employees").doc(employeeId).get();
  if (!employeeSnap.exists || employeeSnap.data()?.active !== true) {
    await sessionRef.delete().catch(() => {});
    throw new HttpsError("failed-precondition", "Mitarbeiter ist nicht mehr aktiv.");
  }

  const lastEventType = await getLastEventType(employeeId);
  if (!isAllowed(lastEventType, eventType)) {
    throw new HttpsError("failed-precondition", "Aktion ist in diesem Zustand nicht zulässig.");
  }

  const timestampUtcMs = Date.now();
  const eventRef = db.collection("events").doc();
  await eventRef.set({
    employeeId,
    eventType,
    timestampUtcMs,
    terminalId,
    source: "PIN",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    dayKey: dayKeyBerlinFromUtcMs(timestampUtcMs),
  });

  await db.collection("employee_state").doc(employeeId).set({
    employeeId,
    lastEventType: eventType,
    timestampUtcMs,
    terminalId,
    source: "PIN",
    dayKey: dayKeyBerlinFromUtcMs(timestampUtcMs),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await sessionRef.delete().catch(() => {});

  return {
    employeeId,
    eventType,
    timestampUtcMs,
  };
});
