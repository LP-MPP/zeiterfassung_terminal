"use strict";

const RETRYABLE_STATUS = new Set([408, 429, 500, 502, 503, 504]);

function normalizeEmail(value) {
  const email = String(value || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return null;
  return email;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry(fetchImpl, url, options, acceptedStatuses) {
  let lastStatus = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    const response = await fetchImpl(url, options);
    lastStatus = response.status;
    if (acceptedStatuses.has(response.status)) return response;
    if (!RETRYABLE_STATUS.has(response.status) || attempt === 3) break;

    const retryAfterSeconds = Number(response.headers?.get?.("retry-after") || 0);
    const retryDelayMs = retryAfterSeconds > 0 ?
      Math.min(retryAfterSeconds * 1000, 10000) :
      attempt * 500;
    await wait(retryDelayMs);
  }
  throw new Error(`Microsoft Graph request failed with status ${lastStatus ?? "unknown"}.`);
}

async function sendGraphEmail({
  tenantId,
  clientId,
  clientSecret,
  sender,
  to,
  subject,
  html,
  fetchImpl = globalThis.fetch,
}) {
  const recipient = normalizeEmail(to);
  const senderEmail = normalizeEmail(sender);
  if (!recipient || !senderEmail) throw new Error("Sender or recipient email is invalid.");
  if (!tenantId || !clientId || !clientSecret) throw new Error("Microsoft Graph credentials are incomplete.");
  if (typeof fetchImpl !== "function") throw new Error("Fetch implementation is unavailable.");

  const tokenBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    scope: "https://graph.microsoft.com/.default",
    grant_type: "client_credentials",
  });
  const tokenResponse = await fetchWithRetry(
      fetchImpl,
      `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`,
      {
        method: "POST",
        headers: {"content-type": "application/x-www-form-urlencoded"},
        body: tokenBody,
      },
      new Set([200]),
  );
  const tokenData = await tokenResponse.json();
  const accessToken = String(tokenData?.access_token || "");
  if (!accessToken) throw new Error("Microsoft Graph did not return an access token.");

  await fetchWithRetry(
      fetchImpl,
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(senderEmail)}/sendMail`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            subject: String(subject || ""),
            body: {
              contentType: "HTML",
              content: String(html || ""),
            },
            toRecipients: [{emailAddress: {address: recipient}}],
          },
          saveToSentItems: true,
        }),
      },
      new Set([202]),
  );
}

module.exports = {normalizeEmail, sendGraphEmail};
