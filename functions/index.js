const crypto = require("crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");

admin.initializeApp();

const db = admin.firestore();
const REGION = "europe-west3";
const SESSION_TTL_MS = 2 * 60 * 1000;
const LOGIN_WINDOW_MS = 10 * 60 * 1000;
const MAX_LOGIN_ATTEMPTS = 8;
const BERLIN_TIME_ZONE = "Europe/Berlin";
const ALLOWED_EVENT_TYPES = new Set(["IN", "OUT", "BREAK_START", "BREAK_END"]);
const DAY_PARTS = new Set(["FULL", "MORNING", "AFTERNOON"]);

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

function normalizeDayPart(value) {
  const part = String(value || "FULL").trim().toUpperCase();
  return DAY_PARTS.has(part) ? part : "FULL";
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
  const employees = snap.docs
      // Führungskräfte stempeln nicht → nicht am Terminal anzeigen.
      .filter((doc) => (doc.data() || {}).employmentType !== "FUEHRUNGSKRAFT")
      .map((doc) => {
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
  if (employee.employmentType === "FUEHRUNGSKRAFT") {
    throw new HttpsError("failed-precondition", "Führungskräfte erfassen keine Zeiten.");
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

exports.changeEmployeePin = onCall({region: REGION}, async (request) => {
  ensureSignedIn(request);

  const sessionId = String(request.data?.sessionId || "").trim();
  const terminalId = normalizeTerminalId(request.data?.terminalId);
  const newPin = String(request.data?.newPin || "").trim();

  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Session fehlt.");
  }
  if (!terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-ID fehlt.");
  }
  if (!/^[0-9]{4,8}$/.test(newPin)) {
    throw new HttpsError("invalid-argument", "Neuer PIN muss 4 bis 8 Ziffern haben.");
  }

  // Verify session
  const sessionRef = db.collection("terminal_sessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
  }

  const session = sessionSnap.data() || {};
  if (String(session.uid || "") !== request.auth.uid) {
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
  const employeeRef = db.collection("employees").doc(employeeId);
  const employeeSnap = await employeeRef.get();
  if (!employeeSnap.exists || employeeSnap.data()?.active !== true) {
    throw new HttpsError("failed-precondition", "Mitarbeiter ist nicht mehr aktiv.");
  }

  // Update PIN
  const newHash = hashPin(employeeId, newPin);
  await employeeRef.update({
    pinHash: newHash,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {success: true};
});

async function getValidatedTerminalSession(request) {
  ensureSignedIn(request);
  const sessionId = String(request.data?.sessionId || "").trim();
  const terminalId = normalizeTerminalId(request.data?.terminalId);
  if (!sessionId || !terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-Session fehlt.");
  }

  const sessionRef = db.collection("terminal_sessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
  }
  const session = sessionSnap.data() || {};
  if (String(session.uid || "") !== request.auth.uid || String(session.terminalId || "") !== terminalId) {
    throw new HttpsError("permission-denied", "Terminal-Session ist ungültig.");
  }
  if (Number(session.expiresAtMs || 0) <= Date.now()) {
    await sessionSnap.ref.delete().catch(() => {});
    throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
  }

  const employeeId = String(session.employeeId || "");
  const employeeSnap = await db.collection("employees").doc(employeeId).get();
  if (!employeeSnap.exists || employeeSnap.data()?.active !== true) {
    throw new HttpsError("failed-precondition", "Mitarbeiter ist nicht mehr aktiv.");
  }
  return {employeeId, employee: employeeSnap.data() || {}, sessionRef};
}

exports.createEmployeeVacationRequest = onCall({region: REGION}, async (request) => {
  const {employeeId, sessionRef} = await getValidatedTerminalSession(request);
  const range = validateAbsenceRange({
    type: "URLAUB",
    startDate: request.data?.startDate,
    endDate: request.data?.endDate,
    startDayPart: request.data?.startDayPart,
    endDayPart: request.data?.endDayPart,
  });
  const consumedDays = calculateAbsenceDays(range);
  if (consumedDays <= 0) {
    throw new HttpsError("invalid-argument", "Der Zeitraum enthält keine Arbeitstage.");
  }

  const existingSnap = await db.collection("absences")
      .where("employeeId", "==", employeeId).get();
  const overlaps = existingSnap.docs.some((doc) => {
    const data = doc.data() || {};
    if (!["PENDING", "APPROVED"].includes(String(data.status || ""))) return false;
    return String(data.startDate || "") <= range.endDate &&
      String(data.endDate || "") >= range.startDate;
  });
  if (overlaps) {
    throw new HttpsError("already-exists", "Für diesen Zeitraum besteht bereits eine Abwesenheit.");
  }

  const absenceRef = db.collection("absences").doc();
  const auditRef = db.collection("audit").doc();
  const batch = db.batch();
  batch.set(absenceRef, {
    employeeId,
    type: "URLAUB",
    startDate: range.startDate,
    endDate: range.endDate,
    startDayPart: range.startDayPart,
    endDayPart: range.endDayPart,
    status: "PENDING",
    vacationDaysConsumed: consumedDays,
    reason: null,
    createdByEmployee: true,
    adminUid: null,
    approvedBy: null,
    approvedAt: null,
    rejectionReason: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  batch.set(auditRef, {
    action: "VACATION_REQUESTED_BY_EMPLOYEE",
    employeeId,
    absenceId: absenceRef.id,
    startDate: range.startDate,
    endDate: range.endDate,
    startDayPart: range.startDayPart,
    endDayPart: range.endDayPart,
    vacationDaysConsumed: consumedDays,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  await sessionRef.delete().catch(() => {});

  return {success: true, absenceId: absenceRef.id, vacationDaysConsumed: consumedDays};
});

exports.getEmployeeVacationOverview = onCall({region: REGION}, async (request) => {
  const {employeeId, employee} = await getValidatedTerminalSession(request);
  const year = Number(request.data?.year || new Date().getFullYear());
  if (!Number.isInteger(year) || year < 2000 || year > 2200) {
    throw new HttpsError("invalid-argument", "Jahr ist ungültig.");
  }

  let balanceSnap = await db.collection("vacation_balances").doc(`${employeeId}_${year}`).get();
  if (!balanceSnap.exists) {
    await recalculateVacationBalance(employeeId, year);
    balanceSnap = await db.collection("vacation_balances").doc(`${employeeId}_${year}`).get();
  }
  const entitlement = Number(employee.vacationDaysPerYear ?? 25);
  const balance = balanceSnap.data() || {
    employeeId,
    year,
    entitlement,
    carryOver: 0,
    used: 0,
    planned: 0,
    remaining: entitlement,
    sickDays: 0,
  };

  const yearStart = `${year}-01-01`;
  const yearEnd = `${year}-12-31`;
  const absenceSnap = await db.collection("absences")
      .where("employeeId", "==", employeeId).get();
  const absences = absenceSnap.docs
      .map((doc) => ({id: doc.id, ...doc.data()}))
      .filter((data) => String(data.endDate || "") >= yearStart && String(data.startDate || "") <= yearEnd)
      .map((data) => ({
        id: data.id,
        employeeId,
        type: String(data.type || "URLAUB"),
        startDate: String(data.startDate || ""),
        endDate: String(data.endDate || ""),
        startDayPart: normalizeDayPart(data.startDayPart),
        endDayPart: normalizeDayPart(data.endDayPart),
        status: String(data.status || "PENDING"),
        vacationDaysConsumed: Number(data.vacationDaysConsumed ?? calculateAbsenceDays(data)),
        reason: data.reason || null,
        rejectionReason: data.rejectionReason || null,
      }))
      .sort((a, b) => a.startDate.localeCompare(b.startDate));

  return {
    employeeId,
    year,
    balance: {
      entitlement: Number(balance.entitlement ?? entitlement),
      carryOver: Number(balance.carryOver ?? 0),
      used: Number(balance.used ?? 0),
      planned: Number(balance.planned ?? 0),
      remaining: Number(balance.remaining ?? entitlement),
      sickDays: Number(balance.sickDays ?? 0),
    },
    absences,
  };
});

// ── Admin user management ──

async function ensureAdmin(request) {
  ensureSignedIn(request);
  const uid = request.auth.uid;
  // Check if caller is in admins collection
  const adminDoc = await db.collection("admins").doc(uid).get();
  if (!adminDoc.exists || adminDoc.data()?.active !== true) {
    throw new HttpsError("permission-denied", "Nur Admins dürfen diese Aktion ausführen.");
  }
}

exports.createAdminUser = onCall({region: REGION}, async (request) => {
  await ensureAdmin(request);

  const email = String(request.data?.email || "").trim().toLowerCase();
  const password = String(request.data?.password || "");
  const displayName = String(request.data?.displayName || "").trim();
  const role = String(request.data?.role || "admin").trim();

  if (!email || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "Gültige E-Mail-Adresse erforderlich.");
  }
  if (password.length < 6) {
    throw new HttpsError("invalid-argument", "Passwort muss mindestens 6 Zeichen haben.");
  }
  if (!displayName) {
    throw new HttpsError("invalid-argument", "Name ist erforderlich.");
  }

  try {
    // Create Firebase Auth user
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName,
    });

    // Store in admins collection
    await db.collection("admins").doc(userRecord.uid).set({
      uid: userRecord.uid,
      email,
      displayName,
      role,
      active: true,
      createdBy: request.auth.uid,
      createdByEmail: request.auth.token.email || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log
    await db.collection("audit").add({
      action: "ADMIN_CREATED",
      targetEmail: email,
      targetDisplayName: displayName,
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      uid: userRecord.uid,
      email,
      displayName,
    };
  } catch (err) {
    if (err.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Ein Benutzer mit dieser E-Mail existiert bereits.");
    }
    throw new HttpsError("internal", err.message || "Admin konnte nicht erstellt werden.");
  }
});

exports.updateAdminUser = onCall({region: REGION}, async (request) => {
  await ensureAdmin(request);

  const targetUid = String(request.data?.uid || "").trim();
  const displayName = request.data?.displayName !== undefined ? String(request.data.displayName).trim() : null;
  const active = request.data?.active !== undefined ? request.data.active === true : null;
  const newPassword = request.data?.newPassword ? String(request.data.newPassword) : null;
  const role = request.data?.role !== undefined ? String(request.data.role).trim() : null;

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "User-ID fehlt.");
  }

  try {
    // Update Auth user if needed
    const authUpdate = {};
    if (displayName) authUpdate.displayName = displayName;
    if (newPassword && newPassword.length >= 6) authUpdate.password = newPassword;
    if (active === false) authUpdate.disabled = true;
    if (active === true) authUpdate.disabled = false;

    if (Object.keys(authUpdate).length > 0) {
      await admin.auth().updateUser(targetUid, authUpdate);
    }

    // Update Firestore
    const fsUpdate = {updatedAt: admin.firestore.FieldValue.serverTimestamp()};
    if (displayName) fsUpdate.displayName = displayName;
    if (active !== null) fsUpdate.active = active;
    if (role) fsUpdate.role = role;

    await db.collection("admins").doc(targetUid).update(fsUpdate);

    // Audit
    await db.collection("audit").add({
      action: "ADMIN_UPDATED",
      targetUid,
      changes: Object.keys(fsUpdate).filter((k) => k !== "updatedAt"),
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {success: true};
  } catch (err) {
    throw new HttpsError("internal", err.message || "Admin konnte nicht aktualisiert werden.");
  }
});

// ── Vacation balance recalculation ──
// Ported from the former Flutter admin (lib/core/absence_helpers.dart) so the
// React admin keeps balances in sync automatically via Firestore trigger.

function easterSunday(year) {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31);
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return Date.UTC(year, month - 1, day);
}

function publicHolidaysBW(year) {
  const easter = easterSunday(year);
  const dayMs = 24 * 60 * 60 * 1000;
  const dates = [
    Date.UTC(year, 0, 1), // Neujahr
    Date.UTC(year, 0, 6), // Heilige Drei Koenige
    easter - 2 * dayMs, // Karfreitag
    easter + 1 * dayMs, // Ostermontag
    Date.UTC(year, 4, 1), // Tag der Arbeit
    easter + 39 * dayMs, // Christi Himmelfahrt
    easter + 50 * dayMs, // Pfingstmontag
    easter + 60 * dayMs, // Fronleichnam
    Date.UTC(year, 9, 3), // Tag der Deutschen Einheit
    Date.UTC(year, 10, 1), // Allerheiligen
    Date.UTC(year, 11, 25), // 1. Weihnachtstag
    Date.UTC(year, 11, 26), // 2. Weihnachtstag
  ];
  return new Set(dates.map((ms) => new Date(ms).toISOString().slice(0, 10)));
}

function isValidDayKey(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function validateAbsenceRange(data) {
  const startDate = String(data?.startDate || "");
  const endDate = String(data?.endDate || "");
  const type = String(data?.type || "URLAUB");
  const startDayPart = normalizeDayPart(data?.startDayPart);
  const endDayPart = normalizeDayPart(data?.endDayPart);

  for (const rawPart of [data?.startDayPart, data?.endDayPart]) {
    if (rawPart != null && !DAY_PARTS.has(String(rawPart).trim().toUpperCase())) {
      throw new HttpsError("invalid-argument", "Tagesabschnitt ist ungültig.");
    }
  }

  if (!isValidDayKey(startDate) || !isValidDayKey(endDate) || endDate < startDate) {
    throw new HttpsError("invalid-argument", "Der Urlaubszeitraum ist ungültig.");
  }
  if (type !== "URLAUB" && (startDayPart !== "FULL" || endDayPart !== "FULL")) {
    throw new HttpsError("invalid-argument", "Halbe Tage sind nur für Urlaub zulässig.");
  }
  if (startDate === endDate && startDayPart !== endDayPart) {
    throw new HttpsError("invalid-argument", "Bei einem einzelnen Tag muss derselbe Tagesabschnitt gewählt werden.");
  }
  if (startDate !== endDate && startDayPart === "MORNING") {
    throw new HttpsError("invalid-argument", "Ein mehrtägiger Urlaub kann nur ganztägig oder nachmittags beginnen.");
  }
  if (startDate !== endDate && endDayPart === "AFTERNOON") {
    throw new HttpsError("invalid-argument", "Ein mehrtägiger Urlaub kann nur ganztägig oder vormittags enden.");
  }

  return {startDate, endDate, type, startDayPart, endDayPart};
}

function expandAbsenceDays(data) {
  const startDate = String(data?.startDate || "");
  const endDate = String(data?.endDate || "");
  if (!isValidDayKey(startDate) || !isValidDayKey(endDate) || endDate < startDate) return [];

  const type = String(data?.type || "URLAUB");
  const startDayPart = type === "URLAUB" ? normalizeDayPart(data?.startDayPart) : "FULL";
  const endDayPart = type === "URLAUB" ? normalizeDayPart(data?.endDayPart) : "FULL";
  const singleDay = startDate === endDate;
  const holidayCache = new Map();
  const entries = [];

  const start = new Date(`${startDate}T00:00:00Z`);
  const end = new Date(`${endDate}T00:00:00Z`);
  for (const d = new Date(start); d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    const dow = d.getUTCDay();
    if (dow === 0 || dow === 6) continue;

    const dayKey = d.toISOString().slice(0, 10);
    const year = d.getUTCFullYear();
    if (!holidayCache.has(year)) holidayCache.set(year, publicHolidaysBW(year));
    if (holidayCache.get(year).has(dayKey)) continue;

    let fraction = 1;
    let dayPart = "FULL";
    if (type === "URLAUB") {
      if (singleDay && startDayPart !== "FULL") {
        fraction = 0.5;
        dayPart = startDayPart;
      } else if (!singleDay && dayKey === startDate && startDayPart === "AFTERNOON") {
        fraction = 0.5;
        dayPart = "AFTERNOON";
      } else if (!singleDay && dayKey === endDate && endDayPart === "MORNING") {
        fraction = 0.5;
        dayPart = "MORNING";
      }
    }
    entries.push({dayKey, year, fraction, dayPart});
  }
  return entries;
}

function calculateAbsenceDays(data, year = null) {
  return expandAbsenceDays(data)
      .filter((entry) => year == null || entry.year === year)
      .reduce((sum, entry) => sum + entry.fraction, 0);
}

async function recalculateVacationBalance(employeeId, year) {
  const empSnap = await db.collection("employees").doc(employeeId).get();
  const empData = empSnap.data() || {};
  const entitlement = Number(empData.vacationDaysPerYear ?? 25);

  const yearStart = `${year}-01-01`;
  const yearEnd = `${year}-12-31`;
  const absSnap = await db.collection("absences")
      .where("employeeId", "==", employeeId)
      .get();

  let used = 0;
  let planned = 0;
  let sickDays = 0;

  for (const doc of absSnap.docs) {
    const a = doc.data() || {};
    const startDate = String(a.startDate || "");
    const endDate = String(a.endDate || "");
    if (!startDate || !endDate) continue;
    if (endDate < yearStart || startDate > yearEnd) continue;

    const days = calculateAbsenceDays(a, year);

    const type = String(a.type || "");
    const status = String(a.status || "");
    if (type === "URLAUB") {
      if (status === "APPROVED") used += days;
      else if (status === "PENDING") planned += days;
    } else if (type === "KRANKHEIT" && status === "APPROVED") {
      sickDays += days;
    }
  }

  let carryOver = 0;
  const prevSnap = await db.collection("vacation_balances")
      .doc(`${employeeId}_${year - 1}`).get();
  if (prevSnap.exists) {
    const prevRemaining = Number(prevSnap.data()?.remaining ?? 0);
    if (prevRemaining > 0) carryOver = prevRemaining;
  }

  const remaining = entitlement + carryOver - used;

  await db.collection("vacation_balances").doc(`${employeeId}_${year}`).set({
    employeeId,
    year,
    entitlement,
    carryOver,
    used,
    planned,
    remaining,
    sickDays,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

exports.onAbsenceWritten = onDocumentWritten(
    {region: REGION, document: "absences/{absenceId}"},
    async (event) => {
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      // vacationDaysConsumed is derived data. Keep old and new clients safe by
      // normalizing it on the server; the follow-up trigger performs the balance update.
      if (after) {
        const canonicalDays = calculateAbsenceDays(after);
        const storedDays = Number(after.vacationDaysConsumed ?? -1);
        if (Math.abs(storedDays - canonicalDays) > 0.001) {
          await event.data.after.ref.update({
            vacationDaysConsumed: canonicalDays,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return;
        }
      }

      // Collect affected employee/year pairs from both versions of the doc
      const targets = new Map();
      for (const d of [before, after]) {
        if (!d || !d.employeeId) continue;
        const employeeId = String(d.employeeId);
        const yStart = parseInt(String(d.startDate || "").slice(0, 4), 10);
        const yEnd = parseInt(String(d.endDate || "").slice(0, 4), 10);
        if (isNaN(yStart)) continue;
        const last = isNaN(yEnd) ? yStart : Math.min(yEnd, yStart + 10);
        for (let y = yStart; y <= last; y++) {
          targets.set(`${employeeId}|${y}`, {employeeId, year: y});
        }
      }

      for (const {employeeId, year} of targets.values()) {
        await recalculateVacationBalance(employeeId, year);
        // Follow-up year inherits carryOver — refresh it if it already exists
        const nextSnap = await db.collection("vacation_balances")
            .doc(`${employeeId}_${year + 1}`).get();
        if (nextSnap.exists) {
          await recalculateVacationBalance(employeeId, year + 1);
        }
      }
    });

exports.recalculateAllVacationBalances = onCall({region: REGION}, async (request) => {
  await ensureAdmin(request);

  const year = Number(request.data?.year || new Date().getFullYear());
  const empSnap = await db.collection("employees").get();

  let count = 0;
  for (const doc of empSnap.docs) {
    const employeeId = String(doc.data()?.id || doc.id);
    await recalculateVacationBalance(employeeId, year);
    count++;
  }

  return {success: true, year, employees: count};
});

// When an admin corrects a day and sets an OUT (checkout) time, close the
// employee's live session if it is still open on that same day. Otherwise the
// presence overview keeps showing "anwesend" + a checkout error, and the
// terminal state machine would still think the employee is clocked in.
exports.onDayOverrideWritten = onDocumentWritten(
    {region: REGION, document: "day_overrides/{overrideId}"},
    async (event) => {
      const after = event.data?.after?.exists ? event.data.after.data() : null;
      if (!after) return;

      const employeeId = String(after.employeeId || "");
      const dayKey = String(after.dayKey || "");
      if (!employeeId || !dayKey) return;

      const stateRef = db.collection("employee_state").doc(employeeId);
      const stateSnap = await stateRef.get();
      if (!stateSnap.exists) return;

      const st = stateSnap.data() || {};
      const openStates = ["IN", "BREAK_START", "BREAK_END"];
      if (String(st.dayKey || "") !== dayKey || !openStates.includes(st.lastEventType)) {
        return;
      }

      // Close the open live session when the admin corrected this day, IF either
      //  - the correction provides a checkout time, OR
      //  - the corrected day is already in the past (a past day with an admin
      //    correction is "handled"; a stuck-open session there is an anomaly).
      const outUtcMs = after.outUtcMs;
      const todayKey = dayKeyBerlinFromUtcMs(Date.now());
      const isPast = dayKey < todayKey;
      if (outUtcMs == null && !isPast) return;

      await stateRef.set({
        lastEventType: "OUT",
        timestampUtcMs: outUtcMs != null ? Number(outUtcMs) : Number(st.timestampUtcMs || Date.now()),
        dayKey,
        source: "ADMIN",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
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
