const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizePunchRequestId,
  punchEventDocumentId,
} = require("./punch_request");

test("accepts a UUID punch request id", () => {
  assert.deepEqual(
      normalizePunchRequestId("f9fe12f2-c875-49bb-901d-c2af1802c344"),
      {ok: true, requestId: "f9fe12f2-c875-49bb-901d-c2af1802c344"},
  );
});

test("keeps request ids optional for older terminal versions", () => {
  assert.deepEqual(normalizePunchRequestId(null), {ok: true, requestId: null});
});

test("rejects malformed request ids", () => {
  assert.equal(normalizePunchRequestId("too-short").ok, false);
  assert.equal(normalizePunchRequestId({id: "invalid"}).ok, false);
});

test("derives stable ids per authenticated device and request", () => {
  const first = punchEventDocumentId("device-a", "request-123456789");
  const repeated = punchEventDocumentId("device-a", "request-123456789");
  const otherDevice = punchEventDocumentId("device-b", "request-123456789");

  assert.equal(first, repeated);
  assert.notEqual(first, otherDevice);
  assert.match(first, /^[a-f0-9]{64}$/);
});
