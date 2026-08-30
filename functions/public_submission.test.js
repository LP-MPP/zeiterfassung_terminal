const assert = require("node:assert/strict");
const test = require("node:test");
const {
  sanitizeOnboardingProfile,
  validateSignatureDataUrl,
} = require("./public_submission");

test("accepts a PNG data URL as signature", () => {
  const signature = "data:image/png;base64,aGVsbG8=";
  assert.equal(validateSignatureDataUrl(signature), signature);
});

test("rejects non-PNG signature data", () => {
  assert.throws(
      () => validateSignatureDataUrl("data:image/svg+xml;base64,PHN2Zz4="),
      /SIGNATURE_INVALID/,
  );
});

test("keeps only supported onboarding fields", () => {
  const result = sanitizeOnboardingProfile({
    firstName: " Ada ",
    lastName: "Lovelace",
    email: "ada@example.com",
    employeeId: "ADMIN",
    status: "APPROVED",
    pensionExemption: false,
  });

  assert.deepEqual(result, {
    firstName: "Ada",
    lastName: "Lovelace",
    email: "ada@example.com",
    pensionExemption: false,
  });
});

test("requires the onboarding identity fields", () => {
  assert.throws(
      () => sanitizeOnboardingProfile({firstName: "Ada"}),
      /PROFILE_REQUIRED_FIELDS_MISSING/,
  );
});
