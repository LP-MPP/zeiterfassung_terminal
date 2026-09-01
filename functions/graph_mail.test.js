"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {normalizeEmail, sendGraphEmail} = require("./graph_mail");

test("normalizes valid email addresses and rejects invalid ones", () => {
  assert.equal(normalizeEmail(" Lukas.Pfau@MPP-Solutions.com "), "lukas.pfau@mpp-solutions.com");
  assert.equal(normalizeEmail("not-an-email"), null);
});

test("sends mail through the scoped Graph mailbox endpoint", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({url, options});
    if (calls.length === 1) {
      return {
        status: 200,
        headers: {get: () => null},
        json: async () => ({access_token: "test-access-token"}),
      };
    }
    return {status: 202, headers: {get: () => null}};
  };

  await sendGraphEmail({
    tenantId: "tenant-id",
    clientId: "client-id",
    clientSecret: "client-secret",
    sender: "no-reply@mpp-solutions.com",
    to: "employee@mpp-solutions.com",
    subject: "Urlaub genehmigt",
    html: "<p>Genehmigt</p>",
    fetchImpl,
  });

  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /login\.microsoftonline\.com\/tenant-id/);
  assert.equal(calls[0].options.body.get("client_secret"), "client-secret");
  assert.equal(
      calls[1].url,
      "https://graph.microsoft.com/v1.0/users/no-reply%40mpp-solutions.com/sendMail",
  );
  assert.equal(calls[1].options.headers.authorization, "Bearer test-access-token");
  const payload = JSON.parse(calls[1].options.body);
  assert.equal(payload.message.toRecipients[0].emailAddress.address, "employee@mpp-solutions.com");
  assert.equal(payload.saveToSentItems, true);
});

test("does not request a token for an invalid recipient", async () => {
  let called = false;
  await assert.rejects(() => sendGraphEmail({
    tenantId: "tenant-id",
    clientId: "client-id",
    clientSecret: "client-secret",
    sender: "no-reply@mpp-solutions.com",
    to: "invalid",
    subject: "Test",
    html: "Test",
    fetchImpl: async () => {
      called = true;
      throw new Error("must not run");
    },
  }), /invalid/);
  assert.equal(called, false);
});
