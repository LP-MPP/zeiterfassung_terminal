"use strict";

const NOTIFIABLE_TYPES = new Set(["URLAUB", "SONDERURLAUB"]);
const DAY_PART_LABELS = {
  FULL: "ganztägig",
  MORNING: "vormittags",
  AFTERNOON: "nachmittags",
};

function escapeHtml(value) {
  return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
}

function normalizeDayPart(value) {
  const dayPart = String(value || "FULL").trim().toUpperCase();
  return Object.hasOwn(DAY_PART_LABELS, dayPart) ? dayPart : "FULL";
}

function formatGermanDate(dayKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dayKey || ""));
  if (!match) return String(dayKey || "");
  return `${match[3]}.${match[2]}.${match[1]}`;
}

function describeAbsenceRange(data) {
  const startDate = String(data?.startDate || "");
  const endDate = String(data?.endDate || "");
  const startDayPart = normalizeDayPart(data?.startDayPart);
  const endDayPart = normalizeDayPart(data?.endDayPart);

  if (startDate === endDate) {
    return `${formatGermanDate(startDate)} (${DAY_PART_LABELS[startDayPart]})`;
  }

  const startSuffix = startDayPart === "AFTERNOON" ? " (ab nachmittags)" : "";
  const endSuffix = endDayPart === "MORNING" ? " (bis mittags)" : "";
  return `${formatGermanDate(startDate)}${startSuffix} bis ${formatGermanDate(endDate)}${endSuffix}`;
}

function formatDayCount(value) {
  const days = Number(value || 0);
  const formatted = new Intl.NumberFormat("de-DE", {
    minimumFractionDigits: Number.isInteger(days) ? 0 : 1,
    maximumFractionDigits: 1,
  }).format(days);
  return `${formatted} ${days === 1 ? "Arbeitstag" : "Arbeitstage"}`;
}

function shouldNotifyApproval(data) {
  return String(data?.status || "") === "APPROVED" &&
    NOTIFIABLE_TYPES.has(String(data?.type || ""));
}

function buildApprovalEmail(data) {
  const type = String(data?.type || "URLAUB");
  if (!NOTIFIABLE_TYPES.has(type)) {
    throw new Error("Unsupported absence type for approval email.");
  }

  const employeeName = String(data?.employeeName || "").trim();
  const greeting = employeeName ? `Guten Tag ${escapeHtml(employeeName)},` : "Guten Tag,";
  const range = describeAbsenceRange(data);
  const dayCount = formatDayCount(data?.vacationDaysConsumed);
  const isSpecialLeave = type === "SONDERURLAUB";
  const title = isSpecialLeave ? "Bezahlter Sonderurlaub genehmigt" : "Urlaub genehmigt";
  const intro = isSpecialLeave ?
    "für Sie wurde bezahlter Sonderurlaub genehmigt." :
    "Ihr Urlaubsantrag wurde genehmigt.";

  const html = `<!doctype html>
<html lang="de">
  <body style="margin:0;padding:0;background:#f4f6f9;font-family:Arial,sans-serif;color:#13233a;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f6f9;padding:28px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border:1px solid #dfe5ee;border-radius:12px;overflow:hidden;">
          <tr><td style="background:#173a67;color:#ffffff;padding:22px 28px;font-size:21px;font-weight:700;">${title}</td></tr>
          <tr><td style="padding:28px;">
            <p style="margin:0 0 16px;line-height:1.55;">${greeting}</p>
            <p style="margin:0 0 22px;line-height:1.55;">${intro}</p>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;background:#f7f9fc;border-radius:8px;">
              <tr><td style="padding:13px 16px;border-bottom:1px solid #e1e7ef;color:#5a687a;width:120px;">Art</td><td style="padding:13px 16px;border-bottom:1px solid #e1e7ef;font-weight:600;">${isSpecialLeave ? "Bezahlter Sonderurlaub" : "Urlaub"}</td></tr>
              <tr><td style="padding:13px 16px;border-bottom:1px solid #e1e7ef;color:#5a687a;">Zeitraum</td><td style="padding:13px 16px;border-bottom:1px solid #e1e7ef;font-weight:600;">${escapeHtml(range)}</td></tr>
              <tr><td style="padding:13px 16px;color:#5a687a;">Umfang</td><td style="padding:13px 16px;font-weight:600;">${escapeHtml(dayCount)}</td></tr>
            </table>
            <p style="margin:22px 0 0;line-height:1.55;">Die Genehmigung ist in der Zeiterfassung hinterlegt.</p>
            <p style="margin:28px 0 0;padding-top:18px;border-top:1px solid #e1e7ef;color:#6a7686;font-size:12px;line-height:1.5;">Dies ist eine automatisch erstellte Nachricht von MPP Personal &amp; Organisation. Bitte antworten Sie nicht auf diese E-Mail.</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;

  return {
    subject: `${title}: ${formatGermanDate(data?.startDate)}`,
    html,
  };
}

module.exports = {
  buildApprovalEmail,
  describeAbsenceRange,
  formatDayCount,
  formatGermanDate,
  shouldNotifyApproval,
};
