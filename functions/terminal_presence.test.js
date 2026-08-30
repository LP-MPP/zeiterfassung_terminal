const assert = require("node:assert/strict");
const test = require("node:test");
const {publicLastEventType} = require("./terminal_presence");

test("keeps a current presence state", () => {
  assert.equal(publicLastEventType({dayKey: "2026-08-30", lastEventType: "BREAK_START"}, "2026-08-30"), "BREAK_START");
});

test("does not show a stale open shift as present", () => {
  assert.equal(publicLastEventType({dayKey: "2026-08-29", lastEventType: "IN"}, "2026-08-30"), "OUT");
});

test("normalizes unknown states to absent", () => {
  assert.equal(publicLastEventType({dayKey: "2026-08-30", lastEventType: "UNKNOWN"}, "2026-08-30"), "OUT");
});
