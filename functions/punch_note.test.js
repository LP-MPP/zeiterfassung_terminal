const test = require("node:test");
const assert = require("node:assert/strict");
const {MAX_PUNCH_NOTE_LENGTH, preparePunchNote} = require("./punch_note");

test("accepts an optional activity note for a minijob checkout", () => {
  assert.deepEqual(
      preparePunchNote("  Lager aufgeräumt  ", "OUT", "MINIJOB"),
      {ok: true, note: "Lager aufgeräumt"},
  );
});

test("accepts an empty minijob checkout note", () => {
  assert.deepEqual(
      preparePunchNote("   ", "OUT", "MINIJOB"),
      {ok: true, note: null},
  );
});

test("accepts a note at the configured maximum", () => {
  const note = "x".repeat(MAX_PUNCH_NOTE_LENGTH);
  assert.deepEqual(
      preparePunchNote(note, "OUT", "MINIJOB"),
      {ok: true, note},
  );
});

test("rejects notes longer than the configured maximum", () => {
  const result = preparePunchNote("x".repeat(MAX_PUNCH_NOTE_LENGTH + 1), "OUT", "MINIJOB");
  assert.equal(result.ok, false);
});

test("rejects an activity note on non-checkout events", () => {
  const result = preparePunchNote("Kommissioniert", "IN", "MINIJOB");
  assert.equal(result.ok, false);
});

test("rejects an activity note for non-minijob employees", () => {
  const result = preparePunchNote("Kommissioniert", "OUT", "FESTANSTELLUNG");
  assert.equal(result.ok, false);
});

test("rejects non-string note payloads", () => {
  const result = preparePunchNote({text: "Kommissioniert"}, "OUT", "MINIJOB");
  assert.equal(result.ok, false);
});
