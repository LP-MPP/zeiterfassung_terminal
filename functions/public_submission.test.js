const assert = require("node:assert/strict");
const test = require("node:test");
const {
  sanitizeOnboardingProfile,
  isMinorOnDate,
  isValidIban,
  validateSignatureDataUrl,
} = require("./public_submission");

function validProfile(overrides = {}) {
  return {
    firstName: "Ada",
    lastName: "Lovelace",
    birthName: "Byron",
    birthDate: "1990-01-02",
    birthPlace: "London",
    nationality: "Britisch",
    gender: "W",
    email: "ada@example.com",
    street: "Teststraße 1",
    zip: "70173",
    city: "Stuttgart",
    taxId: "12345678901",
    socialSecurityNumber: "12 020190 L 123",
    healthInsuranceName: "AOK",
    healthInsuranceType: "STATUTORY_OWN",
    bankName: "Testbank",
    iban: "DE89370400440532013000",
    employmentStatus: "STUDENT",
    hasOtherEmployment: false,
    hasForeignEmployment: false,
    pensionInsuranceChoice: "MANDATORY",
    truthConfirmed: true,
    changeNotificationConfirmed: true,
    privacyNoticeConfirmed: true,
    confirmationName: "Ada Lovelace",
    confirmationPlace: "Stuttgart",
    signatureDataUrl: "data:image/png;base64,aGVsbG8=",
    privacyNoticeVersion: "2026-09-01",
    onboardingVersion: 2,
    ...overrides,
  };
}

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
  const result = sanitizeOnboardingProfile(validProfile({
    firstName: " Ada ",
    employeeId: "ADMIN",
    status: "APPROVED",
  }));

  assert.equal(result.firstName, "Ada");
  assert.equal(result.employeeId, undefined);
  assert.equal(result.status, undefined);
  assert.equal(result.otherEmployment, false);
  assert.equal(result.pensionExemption, false);
});

test("requires the onboarding identity fields", () => {
  assert.throws(
      () => sanitizeOnboardingProfile({firstName: "Ada"}),
      /PROFILE_REQUIRED_FIELDS_MISSING/,
  );
});

test("validates IBAN checksum", () => {
  assert.equal(isValidIban("DE89 3704 0044 0532 0130 00"), true);
  assert.equal(isValidIban("DE89 3704 0044 0532 0130 01"), false);
});

test("requires explicit minijob declarations", () => {
  assert.throws(
      () => sanitizeOnboardingProfile(validProfile({hasOtherEmployment: null})),
      /PROFILE_FIELD_INVALID:hasOtherEmployment/,
  );
  assert.throws(
      () => sanitizeOnboardingProfile(validProfile({truthConfirmed: false})),
      /PROFILE_CONFIRMATIONS_MISSING/,
  );
});

test("requires details for another employment", () => {
  assert.throws(
      () => sanitizeOnboardingProfile(validProfile({hasOtherEmployment: true})),
      /PROFILE_OTHER_EMPLOYMENT_INCOMPLETE/,
  );
});

test("requires job-seeker agency details", () => {
  assert.throws(
      () => sanitizeOnboardingProfile(validProfile({employmentStatus: "JOB_SEEKER"})),
      /PROFILE_AGENCY_DECLARATION_MISSING/,
  );
  assert.doesNotThrow(() => sanitizeOnboardingProfile(validProfile({
    employmentStatus: "JOB_SEEKER",
    employmentAgencyRegistered: true,
    employmentAgencyCity: "Stuttgart",
    employmentAgencyReceivesBenefits: false,
  })));
});

test("detects a minor at employment start", () => {
  assert.equal(isMinorOnDate("2010-09-02", "2026-09-01"), true);
  assert.equal(isMinorOnDate("2008-09-01", "2026-09-01"), false);
});
