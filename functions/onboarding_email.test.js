const assert = require("node:assert/strict");
const test = require("node:test");
const {buildOnboardingEmail} = require("./onboarding_email");

test("builds an escaped onboarding invitation", () => {
  const message = buildOnboardingEmail({
    kind: "INVITATION",
    employeeName: "Ada <Lovelace>",
    link: "https://zeiterfassung-admin.vercel.app/onboarding/token_123",
  });
  assert.match(message.subject, /Mitarbeiter-Registrierung/);
  assert.match(message.html, /Ada &lt;Lovelace&gt;/);
  assert.match(message.html, /token_123/);
  assert.doesNotMatch(message.html, /Ada <Lovelace>/);
});

test("builds an approval message without PIN", () => {
  const message = buildOnboardingEmail({kind: "APPROVED", employeeName: "Ada Lovelace"});
  assert.match(message.subject, /abgeschlossen/);
  assert.match(message.html, /separat/);
  assert.doesNotMatch(message.html, /1234/);
});

test("rejects unsafe invitation links", () => {
  assert.throws(() => buildOnboardingEmail({kind: "INVITATION", link: "javascript:alert(1)"}), /invalid/);
});
