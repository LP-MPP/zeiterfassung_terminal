"use strict";

function escapeHtml(value) {
  return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
}

function buildOnboardingEmail(data) {
  const kind = String(data?.kind || "").toUpperCase();
  const employeeName = String(data?.employeeName || "").trim();
  const greeting = employeeName ? `Guten Tag ${escapeHtml(employeeName)},` : "Guten Tag,";
  let title;
  let subject;
  let content;

  if (kind === "INVITATION") {
    const link = String(data?.link || "").trim();
    if (!/^https:\/\//.test(link)) throw new Error("Onboarding link is invalid.");
    title = "Ihre Mitarbeiter-Registrierung";
    subject = "MPP Personal & Organisation – Mitarbeiter-Registrierung";
    content = `<p style="margin:0 0 18px;line-height:1.55;">bitte vervollständigen Sie vor Ihrem Beschäftigungsbeginn den sicheren Personalfragebogen.</p>
            <p style="margin:0 0 22px;"><a href="${escapeHtml(link)}" style="display:inline-block;background:#173a67;color:#ffffff;padding:12px 20px;border-radius:8px;text-decoration:none;font-weight:700;">Personalfragebogen öffnen</a></p>
            <p style="margin:0;line-height:1.55;color:#5a687a;font-size:13px;">Der persönliche Link ist 14 Tage gültig und darf nicht weitergegeben werden.</p>`;
  } else if (kind === "APPROVED") {
    title = "Registrierung abgeschlossen";
    subject = "MPP Personal & Organisation – Registrierung abgeschlossen";
    content = `<p style="margin:0 0 18px;line-height:1.55;">Ihre Angaben wurden geprüft und Ihr Mitarbeiterkonto wurde freigeschaltet.</p>
            <p style="margin:0;line-height:1.55;">Ihre persönliche Mitarbeiter-ID und PIN erhalten Sie separat von Ihrer Ansprechperson.</p>`;
  } else {
    throw new Error("Unsupported onboarding email kind.");
  }

  const html = `<!doctype html>
<html lang="de">
  <body style="margin:0;padding:0;background:#f4f6f9;font-family:Arial,sans-serif;color:#13233a;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f6f9;padding:28px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border:1px solid #dfe5ee;border-radius:12px;overflow:hidden;">
          <tr><td style="background:#173a67;color:#ffffff;padding:22px 28px;font-size:21px;font-weight:700;">${title}</td></tr>
          <tr><td style="padding:28px;">
            <p style="margin:0 0 16px;line-height:1.55;">${greeting}</p>
            ${content}
            <p style="margin:28px 0 0;padding-top:18px;border-top:1px solid #e1e7ef;color:#6a7686;font-size:12px;line-height:1.5;">Dies ist eine automatisch erstellte Nachricht von MPP Personal &amp; Organisation. Bitte antworten Sie nicht auf diese E-Mail.</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;

  return {subject, html};
}

module.exports = {buildOnboardingEmail};
