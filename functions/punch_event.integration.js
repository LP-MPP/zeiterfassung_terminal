const assert = require("node:assert/strict");
const admin = require("firebase-admin");

const PROJECT_ID = "zeiterfassung-ebafa";
const TERMINAL_ID = "TEST-TERMINAL";
const UID = "test-terminal-device";

async function seedPunchState(db, {sessionId, employeeId, lastEventType}) {
  await Promise.all([
    db.collection("employees").doc(employeeId).set({
      id: employeeId,
      name: "Integration Test",
      active: true,
      employmentType: "FESTANSTELLUNG",
    }),
    db.collection("employee_state").doc(employeeId).set({
      employeeId,
      lastEventType,
      timestampUtcMs: Date.now() - 60_000,
      terminalId: TERMINAL_ID,
      source: "PIN",
    }),
    db.collection("terminal_sessions").doc(sessionId).set({
      uid: UID,
      employeeId,
      terminalId: TERMINAL_ID,
      expiresAtMs: Date.now() + 60_000,
    }),
  ]);
}

async function invoke(createPunchEvent, data) {
  return createPunchEvent.run({
    auth: {uid: UID, token: {}},
    data,
  });
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is required.");
  }

  const {createPunchEvent} = require("./index");
  const db = admin.firestore();

  await seedPunchState(db, {
    sessionId: "retry-session",
    employeeId: "RETRY-EMPLOYEE",
    lastEventType: "BREAK_START",
  });

  const retryData = {
    sessionId: "retry-session",
    eventType: "BREAK_END",
    terminalId: TERMINAL_ID,
    requestId: "retry-request-123456789",
  };
  const first = await invoke(createPunchEvent, retryData);
  const repeated = await invoke(createPunchEvent, retryData);

  assert.equal(first.replayed, false);
  assert.equal(repeated.replayed, true);
  assert.equal(repeated.timestampUtcMs, first.timestampUtcMs);
  const retryEvents = await db.collection("events")
      .where("employeeId", "==", "RETRY-EMPLOYEE")
      .get();
  assert.equal(retryEvents.size, 1);

  await seedPunchState(db, {
    sessionId: "race-session",
    employeeId: "RACE-EMPLOYEE",
    lastEventType: "BREAK_START",
  });

  const raceBase = {
    sessionId: "race-session",
    eventType: "BREAK_END",
    terminalId: TERMINAL_ID,
  };
  const raceResults = await Promise.allSettled([
    invoke(createPunchEvent, {...raceBase, requestId: "race-request-123456789-a"}),
    invoke(createPunchEvent, {...raceBase, requestId: "race-request-123456789-b"}),
  ]);
  assert.equal(raceResults.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(raceResults.filter((result) => result.status === "rejected").length, 1);

  const raceEvents = await db.collection("events")
      .where("employeeId", "==", "RACE-EMPLOYEE")
      .get();
  assert.equal(raceEvents.size, 1);
  const raceState = await db.collection("employee_state").doc("RACE-EMPLOYEE").get();
  assert.equal(raceState.data().lastEventType, "BREAK_END");

  console.log("Punch transaction integration checks passed.");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
