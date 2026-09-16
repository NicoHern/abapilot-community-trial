import assert from "node:assert/strict";
import test from "node:test";
import { assertConfigured, authorize, callSap, configuration, TOOLS, VERSION } from "../lib.mjs";

test("trial exposes bounded evaluation and isolated lab tools", () => {
  assert.deepEqual(TOOLS.map((tool) => tool.name), [
    "sap_ping", "sap_read_code", "sap_read_object", "sap_read_table_structure",
    "sap_read_table_data", "sap_query_custom_table", "sap_diagnose_error",
    "sap_analyze_change", "sap_syntax_check", "sap_trial_lab_status",
    "sap_trial_lab_apply", "sap_trial_lab_reset", "sap_trial_lab_test",
  ]);
  assert.equal(TOOLS.some((tool) => /transport|business|execute_transaction/.test(tool.name)), false);
});

test("error diagnosis accepts text transcribed from a screenshot", () => {
  const tool = TOOLS.find((item) => item.name === "sap_diagnose_error");
  assert.ok(tool.inputSchema.properties.message_text);
  assert.ok(tool.inputSchema.properties.screenshot_text);
  assert.match(tool.description, /screenshot/i);
});

test("table query exposes only one validated filter and a 50-row cap", () => {
  const tool = TOOLS.find((item) => item.name === "sap_query_custom_table");
  assert.equal(tool.inputSchema.properties.max_rows.maximum, 50);
  assert.deepEqual(tool.inputSchema.properties.filter_operator.enum, ["EQ", "NE", "GT", "GE", "LT", "LE", "LIKE"]);
  assert.equal(tool.inputSchema.additionalProperties, false);
});

test("the only persistent mutation is the fixed resettable lab", () => {
  const mutationTools = TOOLS.filter((tool) => /apply|reset|write|create|delete|transport/.test(tool.name));
  assert.deepEqual(mutationTools.map((tool) => tool.name), ["sap_trial_lab_apply", "sap_trial_lab_reset"]);
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

test("SAP Basic credentials require HTTPS by default", () => {
  const base = {
    ABAPILOT_LICENSE_KEY: "abp_test_key",
    ABAPILOT_TRIAL_URL: "http://10.0.48.10:8000/sap/bc/zabapilot_trial",
    ABAPILOT_TRIAL_SAP_USER: "TRIAL",
    ABAPILOT_TRIAL_SAP_PASSWORD: "secret",
  };
  assert.throws(() => assertConfigured(configuration(base)), /must use HTTPS/);
  assert.doesNotThrow(() => assertConfigured(configuration({
    ...base,
    ABAPILOT_ALLOW_INSECURE_HTTP: "true",
  })));
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

test("one MCP tool call makes one SAP request and no connector-side Portal request", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const requests = [];
  globalThis.fetch = async (url, init) => {
    requests.push({ url: String(url), init });
    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
  const cfg = configuration({
    ABAPILOT_LICENSE_KEY: "abp_test_key",
    ABAPILOT_TRIAL_URL: "https://sap.example/sap/bc/zabapilot_trial",
    ABAPILOT_TRIAL_SAP_USER: "TRIAL",
    ABAPILOT_TRIAL_SAP_PASSWORD: "secret",
    ABAPILOT_TRIAL_SAP_CLIENT: "100",
  });
  const tool = TOOLS.find((item) => item.name === "sap_read_object");
  await callSap(cfg, tool, { object_name: "zexample", object_type: "PROG" });
  assert.equal(requests.length, 1);
  assert.match(requests[0].url, /sap\.example/);
  assert.match(requests[0].url, /sap-client=100/);
  assert.equal(requests[0].init.headers["X-ABAPilot-License-Key"], "abp_test_key");
  assert.equal(requests[0].init.headers["X-ABAPilot-Connector"], `community-trial/${VERSION}`);
  assert.deepEqual(JSON.parse(requests[0].init.body), { object_name: "ZEXAMPLE", object_type: "PROG" });
});
