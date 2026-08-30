const assert = require("node:assert/strict");
const test = require("node:test");
const {
  isAbsenceTransitionAllowed,
  monthKeysForRange,
} = require("./month_lock");

test("enumerates every touched calendar month", () => {
  assert.deepEqual(monthKeysForRange("2026-01-31", "2026-03-01"), ["2026-01", "2026-02", "2026-03"]);
});

test("rejects an invalid date range", () => {
  assert.throws(() => monthKeysForRange("2026-03-01", "2026-02-28"), /ABSENCE_RANGE_INVALID/);
});

test("allows only valid pending absence decisions", () => {
  assert.equal(isAbsenceTransitionAllowed("PENDING", "APPROVED"), true);
  assert.equal(isAbsenceTransitionAllowed("PENDING", "REJECTED"), true);
  assert.equal(isAbsenceTransitionAllowed("PENDING", "CANCELLED"), true);
  assert.equal(isAbsenceTransitionAllowed("PENDING", "PENDING"), false);
});

test("allows an approved absence to be cancelled only", () => {
  assert.equal(isAbsenceTransitionAllowed("APPROVED", "CANCELLED"), true);
  assert.equal(isAbsenceTransitionAllowed("APPROVED", "REJECTED"), false);
  assert.equal(isAbsenceTransitionAllowed("CANCELLED", "APPROVED"), false);
});
