const ONBOARDING_STRING_FIELDS = new Set([
  "firstName",
  "lastName",
  "birthName",
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
  "healthInsuranceType",
  "bankName",
  "iban",
  "accountHolder",
  "startDate",
  "employmentStatus",
  "employmentStatusDetails",
  "employmentAgencyCity",
  "otherEmployment1Employer",
  "otherEmployment1StartDate",
  "otherEmployment1Type",
  "otherEmployment1MonthlyGross",
  "otherEmployment2Employer",
  "otherEmployment2StartDate",
  "otherEmployment2Type",
  "otherEmployment2MonthlyGross",
  "foreignEmploymentDetails",
  "pensionInsuranceChoice",
  "privacyNoticeVersion",
  "confirmationName",
  "confirmationPlace",
  "legalRepresentativeName",
  "emergencyName",
  "emergencyPhone",
  "emergencyRelation",
  "notes",
]);

const ONBOARDING_BOOLEAN_FIELDS = new Set([
  "pensionExemption",
  "otherEmployment",
  "hasOtherEmployment",
  "hasForeignEmployment",
  "truthConfirmed",
  "changeNotificationConfirmed",
  "privacyNoticeConfirmed",
  "employmentAgencyRegistered",
  "employmentAgencyReceivesBenefits",
]);

const ONBOARDING_SIGNATURE_FIELDS = new Set([
  "signatureDataUrl",
  "legalRepresentativeSignatureDataUrl",
]);

const ONBOARDING_EMPLOYMENT_STATUSES = new Set([
  "PUPIL", "STUDENT", "SCHOOL_LEAVER_TRAINING", "SCHOOL_LEAVER_STUDY",
  "SCHOOL_LEAVER_VOLUNTEER", "MAIN_EMPLOYMENT", "SELF_EMPLOYED", "JOB_SEEKER",
  "PARENTAL_LEAVE", "UNPAID_LEAVE", "PENSIONER_BEFORE_RETIREMENT_AGE",
  "PENSIONER_AFTER_RETIREMENT_AGE", "PENSION_RECIPIENT_AFTER_AGE", "CIVIL_SERVANT",
  "VOLUNTEER", "INTERN", "OTHER",
]);
const ONBOARDING_HEALTH_INSURANCE_TYPES = new Set(["STATUTORY_OWN", "STATUTORY_FAMILY", "PRIVATE"]);
const ONBOARDING_OTHER_EMPLOYMENT_TYPES = new Set([
  "MINIJOB_WITH_PENSION", "MINIJOB_EXEMPT_PENSION", "REGULAR_EMPLOYMENT", "SELF_EMPLOYED", "OTHER",
]);
const ONBOARDING_PENSION_CHOICES = new Set([
  "MANDATORY", "EXEMPTION_REQUESTED", "EXEMPT_BY_STATUS", "REVOCATION_REQUESTED",
]);

function isIsoDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function normalizeIban(value) {
  return String(value || "").replace(/\s+/g, "").toUpperCase();
}

function isValidIban(value) {
  const iban = normalizeIban(value);
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  const rearranged = `${iban.slice(4)}${iban.slice(0, 4)}`;
  const numeric = rearranged.replace(/[A-Z]/g, (letter) => String(letter.charCodeAt(0) - 55));
  let remainder = 0;
  for (const digit of numeric) remainder = (remainder * 10 + Number(digit)) % 97;
  return remainder === 1;
}

function isMinorOnDate(birthDate, referenceDate) {
  if (!isIsoDate(birthDate) || !isIsoDate(referenceDate)) return false;
  const birth = new Date(`${birthDate}T00:00:00Z`);
  const reference = new Date(`${referenceDate}T00:00:00Z`);
  let age = reference.getUTCFullYear() - birth.getUTCFullYear();
  const monthDifference = reference.getUTCMonth() - birth.getUTCMonth();
  if (monthDifference < 0 || (monthDifference === 0 && reference.getUTCDate() < birth.getUTCDate())) age -= 1;
  return age < 18;
}

function isValidMoney(value) {
  const compact = String(value || "").replace(/[€\s]/g, "");
  if (!compact) return false;
  const normalized = compact.includes(",") ? compact.replace(/\./g, "").replace(",", ".") : compact;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) && parsed >= 0;
}

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
      if (rawValue === null && (key === "employmentAgencyRegistered" || key === "employmentAgencyReceivesBenefits")) {
        result[key] = null;
        continue;
      }
      if (typeof rawValue !== "boolean") {
        throw new Error(`PROFILE_FIELD_INVALID:${key}`);
      }
      result[key] = rawValue;
    } else if (ONBOARDING_SIGNATURE_FIELDS.has(key)) {
      if (!rawValue && key === "legalRepresentativeSignatureDataUrl") {
        result[key] = "";
      } else {
        result[key] = validateSignatureDataUrl(rawValue);
      }
    } else if (key === "onboardingVersion") {
      if (rawValue !== 2) throw new Error("PROFILE_FIELD_INVALID:onboardingVersion");
      result[key] = 2;
    }
  }

  const requiredStrings = [
    "firstName", "lastName", "birthDate", "birthPlace", "nationality", "gender",
    "email", "street", "zip", "city", "taxId", "healthInsuranceName", "healthInsuranceType",
    "bankName", "iban", "employmentStatus", "pensionInsuranceChoice", "confirmationName",
    "confirmationPlace", "signatureDataUrl", "privacyNoticeVersion",
  ];
  if (requiredStrings.some((field) => !result[field])) {
    throw new Error("PROFILE_REQUIRED_FIELDS_MISSING");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) {
    throw new Error("PROFILE_EMAIL_INVALID");
  }
  if (!isIsoDate(result.birthDate) || (result.startDate && !isIsoDate(result.startDate))) {
    throw new Error("PROFILE_DATE_INVALID");
  }
  if (!/^\d{5}$/.test(result.zip)) throw new Error("PROFILE_ZIP_INVALID");
  result.taxId = result.taxId.replace(/\D/g, "");
  if (!/^\d{11}$/.test(result.taxId)) throw new Error("PROFILE_TAX_ID_INVALID");
  result.iban = normalizeIban(result.iban);
  if (!isValidIban(result.iban)) throw new Error("PROFILE_IBAN_INVALID");
  if (!result.socialSecurityNumber && !result.birthName) throw new Error("PROFILE_SOCIAL_SECURITY_IDENTITY_MISSING");
  if (!ONBOARDING_EMPLOYMENT_STATUSES.has(result.employmentStatus)) throw new Error("PROFILE_EMPLOYMENT_STATUS_INVALID");
  if (!ONBOARDING_HEALTH_INSURANCE_TYPES.has(result.healthInsuranceType)) throw new Error("PROFILE_HEALTH_INSURANCE_INVALID");
  if (!ONBOARDING_PENSION_CHOICES.has(result.pensionInsuranceChoice)) throw new Error("PROFILE_PENSION_CHOICE_INVALID");
  if (result.pensionInsuranceChoice === "EXEMPT_BY_STATUS" &&
      result.employmentStatus !== "PENSIONER_AFTER_RETIREMENT_AGE" &&
      result.employmentStatus !== "PENSION_RECIPIENT_AFTER_AGE") {
    throw new Error("PROFILE_PENSION_STATUS_CONFLICT");
  }
  if (result.employmentStatus === "JOB_SEEKER") {
    if (typeof result.employmentAgencyRegistered !== "boolean") throw new Error("PROFILE_AGENCY_DECLARATION_MISSING");
    if (result.employmentAgencyRegistered && (!result.employmentAgencyCity || typeof result.employmentAgencyReceivesBenefits !== "boolean")) {
      throw new Error("PROFILE_AGENCY_DECLARATION_INCOMPLETE");
    }
  }
  if (typeof result.hasOtherEmployment !== "boolean" || typeof result.hasForeignEmployment !== "boolean") {
    throw new Error("PROFILE_EMPLOYMENT_DECLARATION_MISSING");
  }
  if (result.hasOtherEmployment) {
    if (!result.otherEmployment1Employer || !isValidMoney(result.otherEmployment1MonthlyGross) ||
        !ONBOARDING_OTHER_EMPLOYMENT_TYPES.has(result.otherEmployment1Type)) {
      throw new Error("PROFILE_OTHER_EMPLOYMENT_INCOMPLETE");
    }
    if (result.otherEmployment1StartDate && !isIsoDate(result.otherEmployment1StartDate)) {
      throw new Error("PROFILE_OTHER_EMPLOYMENT_INCOMPLETE");
    }
  }
  const hasSecondEmployment = Boolean(result.otherEmployment2Employer || result.otherEmployment2StartDate ||
    result.otherEmployment2Type || result.otherEmployment2MonthlyGross);
  if (hasSecondEmployment) {
    if (!result.otherEmployment2Employer || !isValidMoney(result.otherEmployment2MonthlyGross) ||
        !ONBOARDING_OTHER_EMPLOYMENT_TYPES.has(result.otherEmployment2Type) ||
        (result.otherEmployment2StartDate && !isIsoDate(result.otherEmployment2StartDate))) {
      throw new Error("PROFILE_OTHER_EMPLOYMENT_INCOMPLETE");
    }
  }
  if (result.hasForeignEmployment && !result.foreignEmploymentDetails) {
    throw new Error("PROFILE_FOREIGN_EMPLOYMENT_INCOMPLETE");
  }
  if (result.employmentStatus === "OTHER" && !result.employmentStatusDetails) {
    throw new Error("PROFILE_EMPLOYMENT_STATUS_INCOMPLETE");
  }
  if (result.truthConfirmed !== true || result.changeNotificationConfirmed !== true ||
      result.privacyNoticeConfirmed !== true) {
    throw new Error("PROFILE_CONFIRMATIONS_MISSING");
  }
  if (result.privacyNoticeVersion !== "2026-09-01" || result.onboardingVersion !== 2) {
    throw new Error("PROFILE_ONBOARDING_VERSION_INVALID");
  }

  // Compatibility fields are derived from the explicit answers, never from defaults.
  result.otherEmployment = result.hasOtherEmployment;
  result.pensionExemption = result.pensionInsuranceChoice === "EXEMPTION_REQUESTED";

  return result;
}

module.exports = {
  sanitizeOnboardingProfile,
  isMinorOnDate,
  isValidIban,
  validateSignatureDataUrl,
};
