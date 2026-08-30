const crypto = require("crypto");

const PUNCH_REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{16,100}$/;

function normalizePunchRequestId(value) {
  if (value == null || value === "") {
    return {ok: true, requestId: null};
  }
  if (typeof value !== "string") {
    return {ok: false, message: "Vorgangs-ID ist ungültig."};
  }

  const requestId = value.trim();
  if (!PUNCH_REQUEST_ID_PATTERN.test(requestId)) {
    return {ok: false, message: "Vorgangs-ID ist ungültig."};
  }
  return {ok: true, requestId};
}

function punchEventDocumentId(uid, requestId) {
  return crypto
      .createHash("sha256")
      .update(`${uid}:${requestId}`)
      .digest("hex");
}

module.exports = {
  normalizePunchRequestId,
  punchEventDocumentId,
};
