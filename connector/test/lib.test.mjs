import assert from "node:assert/strict";
import test from "node:test";
import { assertConfigured, authorize, configuration, TOOLS } from "../lib.mjs";

test("trial exposes only the five bounded read-only tools", () => {
  assert.deepEqual(TOOLS.map((tool) => tool.name), [
    "sap_ping", "sap_read_code", "sap_read_table_structure", "sap_read_table_data", "sap_diagnose_error",
  ]);
  assert.equal(TOOLS.some((tool) => /write|create|update|delete|execute/.test(tool.name)), false);
});

test("portal key and SAP credentials are mandatory", () => {
  const cfg = configuration({ ABAPILOT_PORTAL_URL: "https://portal.example" });
  assert.throws(() => assertConfigured(cfg), /ABAPILOT_LICENSE_KEY/);
  assert.throws(() => assertConfigured(cfg), /ABAPILOT_TRIAL_URL/);
});

test("portal URL is normalized", () => {
  const cfg = configuration({ ABAPILOT_PORTAL_URL: "https://portal.example///" });
  assert.equal(cfg.portalUrl, "https://portal.example");
});

test("authorization requires a finite Portal allowance", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => new Response(JSON.stringify({
    valid: true,
    tenant_name: "Trial Company",
    quota: { queries_used: 0, queries_limit: 0 },
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  const cfg = configuration({
    ABAPILOT_LICENSE_KEY: "abp_test_key",
    ABAPILOT_TRIAL_URL: "https://sap.example/trial",
    ABAPILOT_TRIAL_SAP_USER: "TRIAL",
    ABAPILOT_TRIAL_SAP_PASSWORD: "secret",
  });
  await assert.rejects(authorize(cfg), /no Community Trial cap assigned/);
});

test("authorization blocks an exhausted Portal allowance", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => new Response(JSON.stringify({
    valid: true,
    tenant_name: "Trial Company",
    quota: { queries_used: 50, queries_limit: 50 },
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  const cfg = configuration({
    ABAPILOT_LICENSE_KEY: "abp_test_key",
    ABAPILOT_TRIAL_URL: "https://sap.example/trial",
    ABAPILOT_TRIAL_SAP_USER: "TRIAL",
    ABAPILOT_TRIAL_SAP_PASSWORD: "secret",
  });
  await assert.rejects(authorize(cfg), /exhausted \(50\/50/);
});
