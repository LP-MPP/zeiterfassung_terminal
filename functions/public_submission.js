const ONBOARDING_STRING_FIELDS = new Set([
  "firstName",
  "lastName",
  "birthDate",
  "birthPlace",
  "nationality",
  "gender",
  "email",
  "phone",
  "street",
  "zip",
  "city",
  "taxId",
  "socialSecurityNumber",
  "taxClass",
  "religion",
  "healthInsuranceName",
  "healthInsuranceNumber",
  "iban",
  "accountHolder",
  "startDate",
  "emergencyName",
  "emergencyPhone",
  "emergencyRelation",
  "notes",
]);

const ONBOARDING_BOOLEAN_FIELDS = new Set([
  "pensionExemption",
  "otherEmployment",
]);

function validateSignatureDataUrl(value) {
  if (typeof value !== "string") {
    throw new Error("SIGNATURE_INVALID");
  }
  if (!value.startsWith("data:image/png;base64,")) {
    throw new Error("SIGNATURE_INVALID");
  }
  if (value.length > 500000) {
    throw new Error("SIGNATURE_TOO_LARGE");
  }
  return value;
}

function sanitizeOnboardingProfile(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("PROFILE_INVALID");
  }

  const result = {};
  for (const [key, rawValue] of Object.entries(value)) {
    if (ONBOARDING_STRING_FIELDS.has(key)) {
      if (typeof rawValue !== "string") {
        throw new Error(`PROFILE_FIELD_INVALID:${key}`);
      }
      const maxLength = key === "notes" ? 2000 : 500;
      result[key] = rawValue.trim().slice(0, maxLength);
    } else if (ONBOARDING_BOOLEAN_FIELDS.has(key)) {
      if (typeof rawValue !== "boolean") {
        throw new Error(`PROFILE_FIELD_INVALID:${key}`);
      }
      result[key] = rawValue;
    }
  }

  if (!result.firstName || !result.lastName || !result.email) {
    throw new Error("PROFILE_REQUIRED_FIELDS_MISSING");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) {
    throw new Error("PROFILE_EMAIL_INVALID");
  }

  return result;
}

module.exports = {
  sanitizeOnboardingProfile,
  validateSignatureDataUrl,
};
