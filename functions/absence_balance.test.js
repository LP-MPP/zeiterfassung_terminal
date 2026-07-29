"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {addAbsenceToBalance} = require("./absence_balance");

function emptyBalance() {
  return {used: 0, planned: 0, sickDays: 0, specialLeaveDays: 0};
}

test("approved paid special leave is tracked without consuming vacation", () => {
  const result = addAbsenceToBalance(emptyBalance(), {
    type: "SONDERURLAUB",
    status: "APPROVED",
    days: 1,
  });

  assert.deepEqual(result, {
    used: 0,
    planned: 0,
    sickDays: 0,
    specialLeaveDays: 1,
  });
});

test("half-day paid special leave stays fractional", () => {
  const result = addAbsenceToBalance(emptyBalance(), {
    type: "SONDERURLAUB",
    status: "APPROVED",
    days: 0.5,
  });

  assert.equal(result.specialLeaveDays, 0.5);
  assert.equal(result.used, 0);
});

test("cancelled paid special leave is ignored", () => {
  const result = addAbsenceToBalance(emptyBalance(), {
    type: "SONDERURLAUB",
    status: "CANCELLED",
    days: 2,
  });

  assert.deepEqual(result, emptyBalance());
});

test("regular vacation still consumes the vacation balance", () => {
  const result = addAbsenceToBalance(emptyBalance(), {
    type: "URLAUB",
    status: "APPROVED",
    days: 2,
  });

  assert.equal(result.used, 2);
  assert.equal(result.specialLeaveDays, 0);
});
