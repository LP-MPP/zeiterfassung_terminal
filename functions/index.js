const crypto = require("crypto");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {addAbsenceToBalance} = require("./absence_balance");
const {buildApprovalEmail, shouldNotifyApproval} = require("./absence_email");
const {buildOnboardingEmail} = require("./onboarding_email");
const {normalizeEmail, sendGraphEmail} = require("./graph_mail");
const {preparePunchNote} = require("./punch_note");
const {
  normalizePunchRequestId,
  punchEventDocumentId,
} = require("./punch_request");
const {
  isMinorOnDate,
  sanitizeOnboardingProfile,
  validateSignatureDataUrl,
} = require("./public_submission");
const {
  isAbsenceTransitionAllowed,
  monthKeysForRange,
} = require("./month_lock");
const {publicLastEventType} = require("./terminal_presence");

initializeApp();

const db = getFirestore();
const REGION = "europe-west3";
const SESSION_TTL_MS = 2 * 60 * 1000;
const LOGIN_WINDOW_MS = 10 * 60 * 1000;
const MAX_LOGIN_ATTEMPTS = 8;
const BERLIN_TIME_ZONE = "Europe/Berlin";
const ALLOWED_EVENT_TYPES = new Set(["IN", "OUT", "BREAK_START", "BREAK_END"]);
const DAY_PARTS = new Set(["FULL", "MORNING", "AFTERNOON"]);
const SPECIAL_LEAVE_CATEGORIES = new Set(["HOCHZEIT", "TRAUERFALL", "GEBURT", "UMZUG", "SONSTIGES"]);
const ADMIN_ROLES = new Set(["superadmin", "admin", "viewer"]);
const WRITE_ADMIN_ROLES = new Set(["superadmin", "admin"]);
const SUPERADMIN_ROLES = new Set(["superadmin"]);
const MS_GRAPH_CLIENT_SECRET = defineSecret("MS_GRAPH_CLIENT_SECRET");
const MS_GRAPH_TENANT_ID = "cf421be2-a9d5-48e5-baac-e2c17f17eaf3";
const MS_GRAPH_CLIENT_ID = "48dc5957-a552-4271-895b-0512211851ca";
const MS_GRAPH_SENDER = "no-reply@mpp-solutions.com";

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
      updatedAt: FieldValue.serverTimestamp(),
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
    updatedAt: FieldValue.serverTimestamp(),
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
  const employeeDocs = snap.docs
      // Führungskräfte stempeln nicht → nicht am Terminal anzeigen.
      .filter((doc) => (doc.data() || {}).employmentType !== "FUEHRUNGSKRAFT");
  const stateSnapshots = employeeDocs.length > 0 ?
    await db.getAll(...employeeDocs.map((doc) => db.collection("employee_state").doc(String(doc.data()?.id || doc.id)))) : [];
  const stateByEmployee = new Map(stateSnapshots.map((state) => [state.id, state.data() || {}]));
  const todayKey = dayKeyBerlinFromUtcMs(Date.now());
  const employees = employeeDocs
      .map((doc) => {
        const data = doc.data() || {};
        const employeeId = String(data.id || doc.id);
        const state = stateByEmployee.get(employeeId) || {};
        return {
          id: employeeId,
          name: String(data.name || ""),
          active: data.active === true,
          // Do not expose timestamps or terminal metadata on the public kiosk.
          lastEventType: publicLastEventType(state, todayKey),
        };
      }).sort((a, b) => a.id.localeCompare(b.id, "de"));

  return {employees, serverTimeUtcMs: Date.now()};
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
    employmentType: String(employee.employmentType || "FESTANSTELLUNG"),
    terminalId,
    expiresAtMs,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    sessionId: sessionRef.id,
    employeeId,
    employeeName: String(employee.name || ""),
    employmentType: String(employee.employmentType || "FESTANSTELLUNG"),
    lastEventType,
    expiresAtMs,
  };
});

exports.refreshEmployeeSession = onCall({region: REGION}, async (request) => {
  ensureSignedIn(request);
  const sessionId = String(request.data?.sessionId || "").trim();
  const terminalId = normalizeTerminalId(request.data?.terminalId);
  if (!sessionId || !terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-Session fehlt.");
  }

  const sessionRef = db.collection("terminal_sessions").doc(sessionId);
  const expiresAtMs = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionRef);
    if (!snapshot.exists) {
      throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
    }
    const data = snapshot.data() || {};
    if (String(data.uid || "") !== request.auth.uid || String(data.terminalId || "") !== terminalId) {
      throw new HttpsError("permission-denied", "Terminal-Session ist ungültig.");
    }
    if (Number(data.expiresAtMs || 0) <= Date.now()) {
      throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
    }
    const refreshedExpiry = Date.now() + SESSION_TTL_MS;
    transaction.update(sessionRef, {
      expiresAtMs: refreshedExpiry,
      lastActivityAt: FieldValue.serverTimestamp(),
    });
    return refreshedExpiry;
  });

  return {success: true, expiresAtMs};
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
    updatedAt: FieldValue.serverTimestamp(),
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

  const absenceRef = db.collection("absences").doc();
  const auditRef = db.collection("audit").doc();
  await db.runTransaction(async (transaction) => {
    await assertMonthsOpen(transaction, employeeId, range.startDate, range.endDate);
    const existing = await transaction.get(
        db.collection("absences").where("employeeId", "==", employeeId),
    );
    const overlaps = existing.docs.some((doc) => {
      const data = doc.data() || {};
      if (!["PENDING", "APPROVED"].includes(String(data.status || ""))) return false;
      return String(data.startDate || "") <= range.endDate &&
        String(data.endDate || "") >= range.startDate;
    });
    if (overlaps) {
      throw new HttpsError("already-exists", "Für diesen Zeitraum besteht bereits eine Abwesenheit.");
    }

    const timestamp = FieldValue.serverTimestamp();
    transaction.create(absenceRef, {
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
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    transaction.create(auditRef, {
      action: "VACATION_REQUESTED_BY_EMPLOYEE",
      employeeId,
      absenceId: absenceRef.id,
      startDate: range.startDate,
      endDate: range.endDate,
      startDayPart: range.startDayPart,
      endDayPart: range.endDayPart,
      vacationDaysConsumed: consumedDays,
      createdAt: timestamp,
    });
  });

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
    specialLeaveDays: 0,
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
        specialLeaveCategory: data.specialLeaveCategory || null,
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
      specialLeaveDays: Number(balance.specialLeaveDays ?? 0),
    },
    absences,
  };
});

// ── Public one-time submissions ──

const ONBOARDING_LINK_TTL_MS = 14 * 24 * 60 * 60 * 1000;

function onboardingExpiryMs(data) {
  const explicit = data?.expiresAt?.toMillis?.();
  if (Number.isFinite(explicit)) return explicit;
  const created = data?.createdAt?.toMillis?.();
  return Number.isFinite(created) ? created + ONBOARDING_LINK_TTL_MS : 0;
}

exports.getOnboardingRequest = onCall({region: REGION}, async (request) => {
  const requestId = publicRequestId(request.data?.requestId);
  const snapshot = await db.collection("onboarding_requests").doc(requestId).get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Der Einladungslink ist ungültig.");

  const data = snapshot.data() || {};
  const status = String(data.status || "ONBOARDING");
  const expired = status === "ONBOARDING" && onboardingExpiryMs(data) <= Date.now();
  return {
    employeeName: String(data.employeeName || ""),
    status: expired ? "EXPIRED" : status,
    employmentType: String(data.employmentType || "MINIJOB"),
    startDate: String(data.startDate || ""),
  };
});

function publicRequestId(value) {
  const requestId = String(value || "").trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId)) {
    throw new HttpsError("invalid-argument", "Ungültiger Link.");
  }
  return requestId;
}

exports.submitOnboardingRequest = onCall({region: REGION}, async (request) => {
  const requestId = publicRequestId(request.data?.requestId);
  let profileData;
  try {
    profileData = sanitizeOnboardingProfile(request.data?.profileData);
  } catch (err) {
    logger.warn("Invalid public onboarding submission", {requestId, error: err.message});
    throw new HttpsError("invalid-argument", "Die eingegebenen Daten sind ungültig.");
  }

  const requestRef = db.collection("onboarding_requests").doc(requestId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(requestRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Der Einladungslink ist ungültig.");
    }
    if (snapshot.data()?.status !== "ONBOARDING") {
      throw new HttpsError("failed-precondition", "Diese Einladung wurde bereits verwendet.");
    }
    const invitation = snapshot.data() || {};
    if (onboardingExpiryMs(invitation) <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "Diese Einladung ist abgelaufen.");
    }
    const startDate = String(invitation.startDate || profileData.startDate || "");
    if (isMinorOnDate(profileData.birthDate, startDate) &&
        (!profileData.legalRepresentativeName || !profileData.legalRepresentativeSignatureDataUrl)) {
      throw new HttpsError("invalid-argument", "Bei Minderjährigen ist die Zustimmung der gesetzlichen Vertretung erforderlich.");
    }
    transaction.update(requestRef, {
      profileData: {
        ...profileData,
        startDate,
        confirmationDate: new Date().toISOString(),
      },
      status: "SUBMITTED",
      submittedAt: FieldValue.serverTimestamp(),
      tokenRevokedAt: FieldValue.serverTimestamp(),
    });
  });

  return {success: true};
});

exports.signTimesheet = onCall({region: REGION}, async (request) => {
  const requestId = publicRequestId(request.data?.requestId);
  let signatureDataUrl;
  try {
    signatureDataUrl = validateSignatureDataUrl(request.data?.signatureDataUrl);
  } catch (err) {
    logger.warn("Invalid public signature submission", {requestId, error: err.message});
    throw new HttpsError("invalid-argument", "Die Unterschrift ist ungültig oder zu groß.");
  }

  const requestRef = db.collection("sign_requests").doc(requestId);
  const auditRef = db.collection("audit").doc();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(requestRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Der Unterschriftslink ist ungültig.");
    }
    const data = snapshot.data() || {};
    if (data.status !== "PENDING") {
      throw new HttpsError("failed-precondition", "Dieser Nachweis wurde bereits unterschrieben.");
    }

    const timestamp = FieldValue.serverTimestamp();
    transaction.update(requestRef, {
      status: "SIGNED",
      signatureDataUrl,
      signedAt: timestamp,
    });
    transaction.create(auditRef, {
      action: "TIMESHEET_SIGNED_BY_EMPLOYEE",
      employeeId: data.employeeId || null,
      yearMonth: data.yearMonth || null,
      employeeName: data.employeeName || null,
      signRequestId: requestId,
      createdAt: timestamp,
    });
  });

  return {success: true};
});

// ── Admin user management ──

async function ensureAdmin(request, allowedRoles = ADMIN_ROLES) {
  ensureSignedIn(request);
  const uid = request.auth.uid;
  const adminDoc = await db.collection("admins").doc(uid).get();
  if (!adminDoc.exists || adminDoc.data()?.active !== true) {
    throw new HttpsError("permission-denied", "Nur Admins dürfen diese Aktion ausführen.");
  }
  const role = String(adminDoc.data()?.role || "admin");
  if (!allowedRoles.has(role)) {
    throw new HttpsError("permission-denied", "Für diese Aktion fehlen die Berechtigungen.");
  }
  return {uid, role, data: adminDoc.data()};
}

function optionalUtcMs(value, fieldName, dayKey) {
  if (value === null || value === undefined || value === "") return null;
  const result = Number(value);
  if (!Number.isFinite(result) || result <= 0 || dayKeyBerlinFromUtcMs(result) !== dayKey) {
    throw new HttpsError("invalid-argument", `${fieldName} ist ungültig.`);
  }
  return result;
}

async function assertMonthsOpen(transaction, employeeId, startDate, endDate) {
  let monthKeys;
  try {
    monthKeys = monthKeysForRange(startDate, endDate);
  } catch {
    throw new HttpsError("invalid-argument", "Der Abwesenheitszeitraum ist ungültig oder zu lang.");
  }
  const refs = monthKeys.map((yearMonth) =>
    db.collection("month_approvals").doc(`${employeeId}_${yearMonth}`),
  );
  const approvals = await Promise.all(refs.map((ref) => transaction.get(ref)));
  if (approvals.some((snapshot) => snapshot.exists)) {
    throw new HttpsError("failed-precondition", "Mindestens ein betroffener Monat ist freigegeben. Bitte zuerst die Freigabe zurücknehmen.");
  }
}

exports.setDayOverride = onCall({region: REGION}, async (request) => {
  const actor = await ensureAdmin(request, WRITE_ADMIN_ROLES);
  const employeeId = normalizeEmployeeId(request.data?.employeeId);
  const dayKey = String(request.data?.dayKey || "");
  const reason = String(request.data?.reason || "").trim();
  if (!employeeId || !isValidDayKey(dayKey) || !reason || reason.length > 1000) {
    throw new HttpsError("invalid-argument", "Mitarbeiter, Datum oder Grund ist ungültig.");
  }

  const inUtcMs = optionalUtcMs(request.data?.inUtcMs, "Kommen", dayKey);
  const outUtcMs = optionalUtcMs(request.data?.outUtcMs, "Gehen", dayKey);
  const breakStartUtcMs = optionalUtcMs(request.data?.breakStartUtcMs, "Pausenbeginn", dayKey);
  const breakEndUtcMs = optionalUtcMs(request.data?.breakEndUtcMs, "Pausenende", dayKey);
  if (inUtcMs && outUtcMs && outUtcMs <= inUtcMs) {
    throw new HttpsError("invalid-argument", "Gehen muss nach Kommen sein.");
  }
  if (breakStartUtcMs && breakEndUtcMs && breakEndUtcMs <= breakStartUtcMs) {
    throw new HttpsError("invalid-argument", "Pausenende muss nach Pausenbeginn sein.");
  }

  const yearMonth = dayKey.slice(0, 7);
  const overrideRef = db.collection("day_overrides").doc(`${employeeId}_${dayKey}`);
  const approvalRef = db.collection("month_approvals").doc(`${employeeId}_${yearMonth}`);
  const auditRef = db.collection("audit").doc();
  await db.runTransaction(async (transaction) => {
    const approval = await transaction.get(approvalRef);
    if (approval.exists) {
      throw new HttpsError("failed-precondition", "Der Monat ist freigegeben. Bitte zuerst die Freigabe zurücknehmen.");
    }
    const timestamp = FieldValue.serverTimestamp();
    transaction.set(overrideRef, {
      employeeId,
      dayKey,
      yearMonth,
      reason,
      adminUid: actor.uid,
      inUtcMs,
      outUtcMs,
      breakStartUtcMs,
      breakEndUtcMs,
      updatedAt: timestamp,
    });
    transaction.create(auditRef, {
      action: "DAY_OVERRIDE_SET",
      employeeId,
      dayKey,
      reason,
      adminUid: actor.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: timestamp,
    });
  });

  return {
    success: true,
    override: {employeeId, dayKey, yearMonth, reason, inUtcMs, outUtcMs, breakStartUtcMs, breakEndUtcMs},
  };
});

exports.deleteDayOverride = onCall({region: REGION}, async (request) => {
  const actor = await ensureAdmin(request, WRITE_ADMIN_ROLES);
  const employeeId = normalizeEmployeeId(request.data?.employeeId);
  const dayKey = String(request.data?.dayKey || "");
  if (!employeeId || !isValidDayKey(dayKey)) {
    throw new HttpsError("invalid-argument", "Mitarbeiter oder Datum ist ungültig.");
  }

  const yearMonth = dayKey.slice(0, 7);
  const overrideRef = db.collection("day_overrides").doc(`${employeeId}_${dayKey}`);
  const approvalRef = db.collection("month_approvals").doc(`${employeeId}_${yearMonth}`);
  const auditRef = db.collection("audit").doc();
  await db.runTransaction(async (transaction) => {
    const [approval, override] = await Promise.all([
      transaction.get(approvalRef),
      transaction.get(overrideRef),
    ]);
    if (approval.exists) {
      throw new HttpsError("failed-precondition", "Der Monat ist freigegeben. Bitte zuerst die Freigabe zurücknehmen.");
    }
    if (!override.exists) return;
    const timestamp = FieldValue.serverTimestamp();
    transaction.delete(overrideRef);
    transaction.create(auditRef, {
      action: "DAY_OVERRIDE_DELETED",
      employeeId,
      dayKey,
      adminUid: actor.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: timestamp,
    });
  });

  return {success: true};
});

function queueApprovalEmail(transaction, absenceId, absence, actor, timestamp) {
  if (!shouldNotifyApproval(absence)) return;

  const jobRef = db.collection("absence_email_jobs").doc(`approved_${absenceId}`);
  transaction.create(jobRef, {
    absenceId,
    employeeId: String(absence.employeeId || ""),
    type: String(absence.type || ""),
    startDate: String(absence.startDate || ""),
    endDate: String(absence.endDate || ""),
    startDayPart: normalizeDayPart(absence.startDayPart),
    endDayPart: normalizeDayPart(absence.endDayPart),
    vacationDaysConsumed: Number(absence.vacationDaysConsumed || 0),
    status: "PENDING",
    attempts: 0,
    adminUid: actor.uid,
    createdAt: timestamp,
    updatedAt: timestamp,
  });
}

exports.createAdminAbsence = onCall({region: REGION}, async (request) => {
  const actor = await ensureAdmin(request, WRITE_ADMIN_ROLES);
  const employeeId = normalizeEmployeeId(request.data?.employeeId);
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Mitarbeiter fehlt.");
  }
  const range = validateAbsenceRange(request.data);
  const dayPart = range.startDate === range.endDate ? range.startDayPart : null;
  const consumedDays = calculateAbsenceDays(range);
  if (consumedDays <= 0) {
    throw new HttpsError("invalid-argument", "Der Zeitraum enthält keine Arbeitstage.");
  }
  const specialLeaveCategory = range.type === "SONDERURLAUB" ?
    String(request.data?.specialLeaveCategory || "") : null;
  if (range.type === "SONDERURLAUB" && !SPECIAL_LEAVE_CATEGORIES.has(specialLeaveCategory)) {
    throw new HttpsError("invalid-argument", "Anlass für Sonderurlaub ist ungültig.");
  }
  const reason = String(request.data?.reason || "").trim().slice(0, 2000) || null;
  const isApproved = range.type === "SONDERURLAUB" || request.data?.autoApprove === true;
  const absenceRef = db.collection("absences").doc();
  const auditRef = db.collection("audit").doc();

  await db.runTransaction(async (transaction) => {
    const employee = await transaction.get(db.collection("employees").doc(employeeId));
    if (!employee.exists) {
      throw new HttpsError("not-found", "Mitarbeiter nicht gefunden.");
    }
    await assertMonthsOpen(transaction, employeeId, range.startDate, range.endDate);
    const existing = await transaction.get(
        db.collection("absences").where("employeeId", "==", employeeId),
    );
    const overlaps = existing.docs.some((doc) => {
      const data = doc.data() || {};
      return ["PENDING", "APPROVED"].includes(String(data.status || "")) &&
        String(data.startDate || "") <= range.endDate &&
        String(data.endDate || "") >= range.startDate;
    });
    if (overlaps) {
      throw new HttpsError("already-exists", "Für diesen Zeitraum besteht bereits eine Abwesenheit.");
    }

    const timestamp = FieldValue.serverTimestamp();
    const absence = {
      employeeId,
      type: range.type,
      startDate: range.startDate,
      endDate: range.endDate,
      startDayPart: range.startDayPart,
      endDayPart: range.endDayPart,
      status: isApproved ? "APPROVED" : "PENDING",
      vacationDaysConsumed: consumedDays,
      specialLeaveCategory,
      reason,
      createdByEmployee: false,
      adminUid: actor.uid,
      approvedBy: isApproved ? (request.auth.token.email || "Admin") : null,
      approvedAt: isApproved ? timestamp : null,
      rejectionReason: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    transaction.create(absenceRef, absence);
    queueApprovalEmail(transaction, absenceRef.id, absence, actor, timestamp);
    transaction.create(auditRef, {
      action: range.type === "SONDERURLAUB" ? "SPECIAL_LEAVE_GRANTED" : "ABSENCE_CREATED",
      absenceId: absenceRef.id,
      employeeId,
      adminUid: actor.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: timestamp,
      payload: {
        type: range.type,
        startDate: range.startDate,
        endDate: range.endDate,
        dayPart,
        workDays: consumedDays,
        specialLeaveCategory,
      },
    });
  });

  return {success: true, absenceId: absenceRef.id, vacationDaysConsumed: consumedDays};
});

exports.updateAdminAbsenceStatus = onCall({region: REGION}, async (request) => {
  const actor = await ensureAdmin(request, WRITE_ADMIN_ROLES);
  const absenceId = String(request.data?.absenceId || "").trim();
  const nextStatus = String(request.data?.status || "").trim();
  const rejectionReason = String(request.data?.rejectionReason || "").trim().slice(0, 2000) || null;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(absenceId) || !["APPROVED", "REJECTED", "CANCELLED"].includes(nextStatus)) {
    throw new HttpsError("invalid-argument", "Abwesenheit oder Status ist ungültig.");
  }

  const absenceRef = db.collection("absences").doc(absenceId);
  const auditRef = db.collection("audit").doc();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(absenceRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Abwesenheit nicht gefunden.");
    }
    const data = snapshot.data() || {};
    const currentStatus = String(data.status || "");
    if (!isAbsenceTransitionAllowed(currentStatus, nextStatus)) {
      throw new HttpsError("failed-precondition", "Diese Statusänderung ist nicht zulässig.");
    }
    await assertMonthsOpen(transaction, String(data.employeeId || ""), String(data.startDate || ""), String(data.endDate || ""));

    const timestamp = FieldValue.serverTimestamp();
    const update = {
      status: nextStatus,
      updatedAt: timestamp,
    };
    if (nextStatus === "APPROVED") {
      update.approvedBy = request.auth.token.email || "Admin";
      update.approvedAt = timestamp;
      update.rejectionReason = null;
    } else if (nextStatus === "REJECTED") {
      update.rejectionReason = rejectionReason;
    }
    transaction.update(absenceRef, update);
    if (nextStatus === "APPROVED") {
      queueApprovalEmail(
          transaction,
          absenceId,
          {...data, ...update, status: "APPROVED"},
          actor,
          timestamp,
      );
    }

    const action = nextStatus === "APPROVED" ? "ABSENCE_APPROVED" :
      nextStatus === "REJECTED" ? "ABSENCE_REJECTED" : "ABSENCE_CANCELLED";
    transaction.create(auditRef, {
      action,
      absenceId,
      employeeId: data.employeeId || null,
      rejectionReason: nextStatus === "REJECTED" ? rejectionReason : null,
      adminUid: actor.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: timestamp,
    });
  });

  return {success: true};
});

exports.onAbsenceApprovalEmailJobCreated = onDocumentCreated(
    {
      region: REGION,
      document: "absence_email_jobs/{jobId}",
      secrets: [MS_GRAPH_CLIENT_SECRET],
      retry: false,
    },
    async (event) => {
      if (!event.data) return;
      const jobRef = event.data.ref;
      const job = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobRef);
        if (!snapshot.exists) return null;
        const data = snapshot.data() || {};
        if (String(data.status || "") !== "PENDING") return null;
        transaction.update(jobRef, {
          status: "PROCESSING",
          attempts: FieldValue.increment(1),
          processingStartedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return data;
      });
      if (!job) return;

      try {
        const employeeId = normalizeEmployeeId(job.employeeId);
        const [profileSnapshot, employeeSnapshot] = await Promise.all([
          db.collection("employee_profiles").doc(employeeId).get(),
          db.collection("employees").doc(employeeId).get(),
        ]);
        const profile = profileSnapshot.data() || {};
        const employee = employeeSnapshot.data() || {};
        const recipient = normalizeEmail(profile.email);
        if (!recipient) {
          await jobRef.update({
            status: "SKIPPED_NO_EMAIL",
            completedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          logger.info("Approval email skipped because no valid employee email is stored.", {
            jobId: event.params.jobId,
            absenceId: job.absenceId || null,
            employeeId,
          });
          return;
        }

        const profileName = `${String(profile.firstName || "").trim()} ${String(profile.lastName || "").trim()}`.trim();
        const message = buildApprovalEmail({
          ...job,
          employeeName: profileName || String(employee.name || "").trim(),
        });
        await sendGraphEmail({
          tenantId: MS_GRAPH_TENANT_ID,
          clientId: MS_GRAPH_CLIENT_ID,
          clientSecret: MS_GRAPH_CLIENT_SECRET.value(),
          sender: MS_GRAPH_SENDER,
          to: recipient,
          subject: message.subject,
          html: message.html,
        });

        await jobRef.update({
          status: "SENT",
          sentAt: FieldValue.serverTimestamp(),
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        logger.info("Approval email sent.", {
          jobId: event.params.jobId,
          absenceId: job.absenceId || null,
          employeeId,
        });
      } catch (error) {
        const safeMessage = String(error?.message || "Unbekannter Versandfehler.").slice(0, 500);
        await jobRef.update({
          status: "FAILED",
          lastError: safeMessage,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }).catch(() => {});
        logger.error("Approval email failed.", {
          jobId: event.params.jobId,
          absenceId: job.absenceId || null,
          error: safeMessage,
        });
      }
    },
);

exports.onOnboardingEmailJobCreated = onDocumentCreated(
    {
      region: REGION,
      document: "onboarding_email_jobs/{jobId}",
      secrets: [MS_GRAPH_CLIENT_SECRET],
      retry: false,
    },
    async (event) => {
      if (!event.data) return;
      const jobRef = event.data.ref;
      const job = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobRef);
        if (!snapshot.exists) return null;
        const data = snapshot.data() || {};
        if (String(data.status || "") !== "PENDING") return null;
        transaction.update(jobRef, {
          status: "PROCESSING",
          attempts: FieldValue.increment(1),
          processingStartedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return data;
      });
      if (!job) return;

      try {
        const recipient = normalizeEmail(job.to);
        if (!recipient) throw new Error("Onboarding recipient is invalid.");
        const message = buildOnboardingEmail(job);
        await sendGraphEmail({
          tenantId: MS_GRAPH_TENANT_ID,
          clientId: MS_GRAPH_CLIENT_ID,
          clientSecret: MS_GRAPH_CLIENT_SECRET.value(),
          sender: MS_GRAPH_SENDER,
          to: recipient,
          subject: message.subject,
          html: message.html,
        });
        await jobRef.update({
          status: "SENT",
          sentAt: FieldValue.serverTimestamp(),
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        const safeMessage = String(error?.message || "Unbekannter Versandfehler.").slice(0, 500);
        await jobRef.update({
          status: "FAILED",
          lastError: safeMessage,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }).catch(() => {});
        logger.error("Onboarding email failed.", {jobId: event.params.jobId, error: safeMessage});
      }
    },
);

exports.createAdminUser = onCall({region: REGION}, async (request) => {
  await ensureAdmin(request, SUPERADMIN_ROLES);

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
  if (!ADMIN_ROLES.has(role)) {
    throw new HttpsError("invalid-argument", "Ungültige Rolle.");
  }

  let userRecord = null;
  try {
    userRecord = await getAuth().createUser({
      email,
      password,
      displayName,
    });

    const adminRef = db.collection("admins").doc(userRecord.uid);
    const auditRef = db.collection("audit").doc();
    const batch = db.batch();
    batch.set(adminRef, {
      uid: userRecord.uid,
      email,
      displayName,
      role,
      active: true,
      createdBy: request.auth.uid,
      createdByEmail: request.auth.token.email || null,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.create(auditRef, {
      action: "ADMIN_CREATED",
      targetUid: userRecord.uid,
      targetEmail: email,
      targetDisplayName: displayName,
      targetRole: role,
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return {
      uid: userRecord.uid,
      email,
      displayName,
    };
  } catch (err) {
    if (err.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Ein Benutzer mit dieser E-Mail existiert bereits.");
    }
    if (userRecord) {
      try {
        await getAuth().deleteUser(userRecord.uid);
      } catch (rollbackError) {
        logger.error("Failed to roll back admin Auth user", {
          uid: userRecord.uid,
          error: rollbackError.message,
        });
      }
    }
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err.message || "Admin konnte nicht erstellt werden.");
  }
});

exports.updateAdminUser = onCall({region: REGION}, async (request) => {
  await ensureAdmin(request, SUPERADMIN_ROLES);

  const targetUid = String(request.data?.uid || "").trim();
  const displayName = request.data?.displayName !== undefined ? String(request.data.displayName).trim() : null;
  const active = request.data?.active !== undefined ? request.data.active : null;
  const newPassword = request.data?.newPassword ? String(request.data.newPassword) : null;
  const role = request.data?.role !== undefined ? String(request.data.role).trim() : null;

  if (!targetUid) {
    throw new HttpsError("invalid-argument", "User-ID fehlt.");
  }
  if (active !== null && typeof active !== "boolean") {
    throw new HttpsError("invalid-argument", "Ungültiger Aktiv-Status.");
  }
  if (role !== null && !ADMIN_ROLES.has(role)) {
    throw new HttpsError("invalid-argument", "Ungültige Rolle.");
  }
  if (newPassword && newPassword.length < 6) {
    throw new HttpsError("invalid-argument", "Passwort muss mindestens 6 Zeichen haben.");
  }
  if (targetUid === request.auth.uid && active === false) {
    throw new HttpsError("failed-precondition", "Das eigene Konto kann nicht deaktiviert werden.");
  }
  if (targetUid === request.auth.uid && role !== null && role !== "superadmin") {
    throw new HttpsError("failed-precondition", "Die eigene Superadmin-Rolle kann nicht entfernt werden.");
  }

  try {
    const targetRef = db.collection("admins").doc(targetUid);
    const targetSnapshot = await targetRef.get();
    if (!targetSnapshot.exists) {
      throw new HttpsError("not-found", "Admin-Konto nicht gefunden.");
    }
    const targetData = targetSnapshot.data() || {};
    const removesSuperAdmin = targetData.role === "superadmin" &&
      (active === false || (role !== null && role !== "superadmin"));
    if (removesSuperAdmin) {
      const superAdmins = await db.collection("admins").where("role", "==", "superadmin").get();
      const activeSuperAdmins = superAdmins.docs.filter((doc) => doc.data()?.active === true);
      if (activeSuperAdmins.length <= 1) {
        throw new HttpsError("failed-precondition", "Mindestens ein aktiver Superadmin muss erhalten bleiben.");
      }
    }

    const authUpdate = {};
    if (displayName) authUpdate.displayName = displayName;
    if (newPassword) authUpdate.password = newPassword;
    if (active === false) authUpdate.disabled = true;
    if (active === true) authUpdate.disabled = false;

    if (Object.keys(authUpdate).length > 0) {
      await getAuth().updateUser(targetUid, authUpdate);
    }

    const fsUpdate = {updatedAt: FieldValue.serverTimestamp()};
    if (displayName) fsUpdate.displayName = displayName;
    if (active !== null) fsUpdate.active = active;
    if (role) fsUpdate.role = role;

    const auditRef = db.collection("audit").doc();
    const batch = db.batch();
    batch.update(targetRef, fsUpdate);
    batch.create(auditRef, {
      action: "ADMIN_UPDATED",
      targetUid,
      changes: Object.keys(fsUpdate).filter((k) => k !== "updatedAt"),
      adminUid: request.auth.uid,
      adminEmail: request.auth.token.email || null,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return {success: true};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
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
  if (!["URLAUB", "KRANKHEIT", "SONDERURLAUB"].includes(type)) {
    throw new HttpsError("invalid-argument", "Abwesenheitstyp ist ungültig.");
  }
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
  const startDayPart = normalizeDayPart(data?.startDayPart);
  const endDayPart = normalizeDayPart(data?.endDayPart);
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

  let totals = {used: 0, planned: 0, sickDays: 0, specialLeaveDays: 0};

  for (const doc of absSnap.docs) {
    const a = doc.data() || {};
    const startDate = String(a.startDate || "");
    const endDate = String(a.endDate || "");
    if (!startDate || !endDate) continue;
    if (endDate < yearStart || startDate > yearEnd) continue;

    const days = calculateAbsenceDays(a, year);

    const type = String(a.type || "");
    const status = String(a.status || "");
    totals = addAbsenceToBalance(totals, {type, status, days});
  }

  let carryOver = 0;
  const prevSnap = await db.collection("vacation_balances")
      .doc(`${employeeId}_${year - 1}`).get();
  if (prevSnap.exists) {
    const prevRemaining = Number(prevSnap.data()?.remaining ?? 0);
    if (prevRemaining > 0) carryOver = prevRemaining;
  }

  const remaining = entitlement + carryOver - totals.used;

  await db.collection("vacation_balances").doc(`${employeeId}_${year}`).set({
    employeeId,
    year,
    entitlement,
    carryOver,
    used: totals.used,
    planned: totals.planned,
    remaining,
    sickDays: totals.sickDays,
    specialLeaveDays: totals.specialLeaveDays,
    updatedAt: FieldValue.serverTimestamp(),
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
            updatedAt: FieldValue.serverTimestamp(),
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
  await ensureAdmin(request, WRITE_ADMIN_ROLES);

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
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });

exports.createPunchEvent = onCall({region: REGION}, async (request) => {
  const startedAtMs = Date.now();
  ensureSignedIn(request);

  const sessionId = String(request.data?.sessionId || "").trim();
  const eventType = normalizeEventType(request.data?.eventType);
  const terminalId = normalizeTerminalId(request.data?.terminalId);
  const normalizedRequestId = normalizePunchRequestId(request.data?.requestId);

  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Session fehlt.");
  }
  if (!ALLOWED_EVENT_TYPES.has(eventType)) {
    throw new HttpsError("invalid-argument", "Event-Typ ist ungültig.");
  }
  if (!terminalId) {
    throw new HttpsError("invalid-argument", "Terminal-ID fehlt.");
  }
  if (!normalizedRequestId.ok) {
    throw new HttpsError("invalid-argument", normalizedRequestId.message);
  }

  const requestId = normalizedRequestId.requestId;
  const sessionRef = db.collection("terminal_sessions").doc(sessionId);
  const eventRef = requestId ?
    db.collection("events").doc(punchEventDocumentId(request.auth.uid, requestId)) :
    db.collection("events").doc();

  try {
    const result = await db.runTransaction(async (transaction) => {
      // A repeated request is acknowledged before checking the now-deleted
      // terminal session. This makes a lost network response safe to retry.
      const existingEventSnap = await transaction.get(eventRef);
      if (existingEventSnap.exists) {
        const existing = existingEventSnap.data() || {};
        if (String(existing.eventType || "") !== eventType ||
            String(existing.terminalId || "") !== terminalId) {
          throw new HttpsError("already-exists", "Vorgangs-ID wurde bereits verwendet.");
        }
        return {
          employeeId: String(existing.employeeId || ""),
          eventType,
          timestampUtcMs: Number(existing.timestampUtcMs || 0),
          replayed: true,
        };
      }

      const sessionSnap = await transaction.get(sessionRef);
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
        throw new HttpsError("failed-precondition", "Session ist abgelaufen. Bitte erneut anmelden.");
      }

      const employeeId = String(session.employeeId || "");
      const employeeRef = db.collection("employees").doc(employeeId);
      const stateRef = db.collection("employee_state").doc(employeeId);
      const [employeeSnap, stateSnap] = await transaction.getAll(
          employeeRef,
          stateRef,
      );

      if (!employeeSnap.exists || employeeSnap.data()?.active !== true) {
        throw new HttpsError("failed-precondition", "Mitarbeiter ist nicht mehr aktiv.");
      }

      const employee = employeeSnap.data() || {};
      const employmentType = String(employee.employmentType || "FESTANSTELLUNG");
      const preparedNote = preparePunchNote(request.data?.note, eventType, employmentType);
      if (!preparedNote.ok) {
        throw new HttpsError("invalid-argument", preparedNote.message);
      }

      const lastEventType = stateSnap.exists ?
        stateSnap.data()?.lastEventType || null :
        null;
      if (!isAllowed(lastEventType, eventType)) {
        throw new HttpsError("failed-precondition", "Aktion ist in diesem Zustand nicht zulässig.");
      }

      const timestampUtcMs = Date.now();
      const dayKey = dayKeyBerlinFromUtcMs(timestampUtcMs);
      const eventData = {
        employeeId,
        eventType,
        timestampUtcMs,
        terminalId,
        source: "PIN",
        createdAt: FieldValue.serverTimestamp(),
        dayKey,
      };
      if (preparedNote.note) eventData.note = preparedNote.note;

      transaction.create(eventRef, eventData);
      transaction.set(stateRef, {
        employeeId,
        lastEventType: eventType,
        timestampUtcMs,
        terminalId,
        source: "PIN",
        dayKey,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.delete(sessionRef);

      return {employeeId, eventType, timestampUtcMs, replayed: false};
    });

    logger.info(result.replayed ? "Punch retry acknowledged" : "Punch event stored", {
      employeeId: result.employeeId,
      eventType: result.eventType,
      terminalId,
      replayed: result.replayed,
      requestIdPresent: requestId != null,
      durationMs: Date.now() - startedAtMs,
    });
    return result;
  } catch (error) {
    const details = {
      eventType,
      terminalId,
      requestIdPresent: requestId != null,
      durationMs: Date.now() - startedAtMs,
      code: String(error?.code || "internal"),
    };
    if (error instanceof HttpsError) {
      logger.warn("Punch event rejected", details);
      throw error;
    }
    logger.error("Punch event failed", details);
    throw new HttpsError("internal", "Buchung konnte nicht gespeichert werden.");
  }
});
