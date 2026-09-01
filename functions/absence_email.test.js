"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildApprovalEmail,
  describeAbsenceRange,
  formatDayCount,
  shouldNotifyApproval,
} = require("./absence_email");

test("formats full and partial absence ranges in German", () => {
  assert.equal(describeAbsenceRange({
    startDate: "2026-09-14",
    endDate: "2026-09-14",
    startDayPart: "MORNING",
    endDayPart: "MORNING",
  }), "14.09.2026 (vormittags)");
  assert.equal(describeAbsenceRange({
    startDate: "2026-09-14",
    endDate: "2026-09-18",
    startDayPart: "AFTERNOON",
    endDayPart: "MORNING",
  }), "14.09.2026 (ab nachmittags) bis 18.09.2026 (bis mittags)");
  assert.equal(formatDayCount(0.5), "0,5 Arbeitstage");
  assert.equal(formatDayCount(1), "1 Arbeitstag");
});

test("notifies only approved vacation and paid special leave", () => {
  assert.equal(shouldNotifyApproval({type: "URLAUB", status: "APPROVED"}), true);
  assert.equal(shouldNotifyApproval({type: "SONDERURLAUB", status: "APPROVED"}), true);
  assert.equal(shouldNotifyApproval({type: "KRANKHEIT", status: "APPROVED"}), false);
  assert.equal(shouldNotifyApproval({type: "URLAUB", status: "PENDING"}), false);
});

test("builds a privacy-conscious vacation approval email", () => {
  const message = buildApprovalEmail({
    type: "URLAUB",
    employeeName: "Ada <Admin>",
    startDate: "2026-09-14",
    endDate: "2026-09-14",
    startDayPart: "FULL",
    endDayPart: "FULL",
    vacationDaysConsumed: 1,
    reason: "Must not appear",
  });

  assert.equal(message.subject, "Urlaub genehmigt: 14.09.2026");
  assert.match(message.html, /Ada &lt;Admin&gt;/);
  assert.match(message.html, /MPP Personal &amp; Organisation/);
  assert.doesNotMatch(message.html, /Must not appear/);
});

test("uses neutral wording for paid special leave", () => {
  const message = buildApprovalEmail({
    type: "SONDERURLAUB",
    employeeName: "Max Mustermann",
    startDate: "2026-09-14",
    endDate: "2026-09-14",
    vacationDaysConsumed: 1,
  });

  assert.match(message.subject, /^Bezahlter Sonderurlaub genehmigt:/);
  assert.match(message.html, /für Sie wurde bezahlter Sonderurlaub genehmigt/);
});
