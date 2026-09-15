export const VERSION = "0.4.0";

export const TOOLS = [
  {
    name: "sap_ping",
    endpoint: "/ping",
    description: "Verify the ABAPilot trial connection and identify the SAP system.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "sap_read_code",
    endpoint: "/read_code",
    description: "Read the active source of one custom Z or Y ABAP report.",
    inputSchema: {
      type: "object",
      properties: { object_name: { type: "string", description: "Z or Y report name" } },
      required: ["object_name"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_read_object",
    endpoint: "/read_object",
    description: "Read an authorized custom Z or Y report, include, class pool, function module, or function group.",
    inputSchema: {
      type: "object",
      properties: {
        object_name: { type: "string", description: "Custom repository object name" },
        object_type: { type: "string", enum: ["PROG", "INCL", "CLAS", "FUNC", "FUGR"] },
      },
      required: ["object_name", "object_type"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_read_table_structure",
    endpoint: "/read_table_structure",
    description: "Read DDIC field metadata for one custom Z or Y table or structure.",
    inputSchema: {
      type: "object",
      properties: { table_name: { type: "string", description: "Z or Y DDIC object" } },
      required: ["table_name"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_read_table_data",
    endpoint: "/read_table_data",
    description: "Read up to 20 rows from one authorized custom Z or Y table. Free-form filters are unavailable.",
    inputSchema: {
      type: "object",
      properties: {
        table_name: { type: "string", description: "Z or Y database table" },
        max_rows: { type: "integer", minimum: 1, maximum: 20, default: 10 },
      },
      required: ["table_name"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_query_custom_table",
    endpoint: "/query_table",
    description: "Query up to 50 rows from an authorized custom Z or Y table using an optional validated field filter and explicit field projection.",
    inputSchema: {
      type: "object",
      properties: {
        table_name: { type: "string", description: "Z or Y database table" },
        fields: { type: "string", description: "Optional comma-separated DDIC field names" },
        filter_field: { type: "string", description: "Optional DDIC field name" },
        filter_operator: { type: "string", enum: ["EQ", "NE", "GT", "GE", "LT", "LE", "LIKE"] },
        filter_value: { type: "string", description: "Literal comparison value" },
        max_rows: { type: "integer", minimum: 1, maximum: 50, default: 20 },
      },
      required: ["table_name"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_diagnose_error",
    endpoint: "/diagnose_error",
    description: "Diagnose an SAP error from pasted text or text transcribed from a screenshot. Rank matching T100 messages while ignoring runtime values, then search up to 5,000 authorized programs in each Z and Y namespace and return at most five calls. If the user supplies an image, read the visible error text first and pass it as screenshot_text. Standard SAP source is not exposed.",
    inputSchema: {
      type: "object",
      properties: {
        message_id: { type: "string", description: "SAP message class, for example ZSD or ME" },
        message_number: { type: "string", description: "Three-digit SAP message number" },
        message_text: { type: "string", description: "Error text copied from SAP; runtime values may differ from the T100 template" },
        screenshot_text: { type: "string", description: "Visible error text transcribed by the multimodal AI client from a supplied screenshot" },
        transaction: { type: "string", description: "Optional transaction used to scope the custom-program search" },
        program_name: { type: "string", description: "Optional Z or Y program/include used to scope the search" },
        language: { type: "string", description: "One-character SAP language key; defaults to the SAP session language" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "sap_analyze_change",
    endpoint: "/analyze_change",
    description: "Inspect one custom Z or Y repository object and return bounded source, include relationships, and change-planning evidence without modifying SAP.",
    inputSchema: {
      type: "object",
      properties: {
        object_name: { type: "string" },
        object_type: { type: "string", enum: ["PROG", "INCL", "CLAS", "FUNC", "FUGR"] },
      },
      required: ["object_name", "object_type"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_syntax_check",
    endpoint: "/syntax_check",
    description: "Syntax-check candidate ABAP source in memory without saving it.",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Complete ABAP source text" },
        program_name: { type: "string", description: "Optional Z or Y context name" },
      },
      required: ["source"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_trial_lab_status",
    endpoint: "/lab_status",
    description: "Read the fixed ABAPilot trial laboratory report and its safety boundary.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "sap_trial_lab_apply",
    endpoint: "/lab_apply",
    description: "Replace only the body of the fixed ZABP_TRIAL_LAB report, activate it after a syntax check, and preserve a resettable baseline. Sandbox use only.",
    inputSchema: {
      type: "object",
      properties: { source: { type: "string", description: "Complete source for ZABP_TRIAL_LAB" } },
      required: ["source"],
      additionalProperties: false,
    },
  },
  {
    name: "sap_trial_lab_reset",
    endpoint: "/lab_reset",
    description: "Restore the fixed ZABP_TRIAL_LAB report to the shipped baseline.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "sap_trial_lab_test",
    endpoint: "/lab_test",
    description: "Run fixed functional checks against ZABP_TRIAL_LAB and return pass/fail evidence.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

export function configuration(env = process.env) {
  return {
    sapUrl: env.ABAPILOT_TRIAL_URL ?? "",
    sapUser: env.ABAPILOT_TRIAL_SAP_USER ?? "",
    sapPassword: env.ABAPILOT_TRIAL_SAP_PASSWORD ?? "",
    sapClient: env.ABAPILOT_TRIAL_SAP_CLIENT ?? "",
    portalUrl: (env.ABAPILOT_PORTAL_URL ?? "https://abapilot-portal.kindwater-835c4d5f.westeurope.azurecontainerapps.io").replace(/\/+$/, ""),
    portalKey: env.ABAPILOT_LICENSE_KEY ?? env.ABAPILOT_PORTAL_KEY ?? "",
  };
}

export function assertConfigured(cfg) {
  const missing = [];
  if (!cfg.portalKey) missing.push("ABAPILOT_LICENSE_KEY");
  if (!cfg.sapUrl) missing.push("ABAPILOT_TRIAL_URL");
  if (!cfg.sapUser || !cfg.sapPassword) missing.push("ABAPILOT_TRIAL_SAP_USER/ABAPILOT_TRIAL_SAP_PASSWORD");
  if (missing.length) throw new Error(`ABAPilot Community Trial is not configured: ${missing.join(", ")}`);
}

async function portalRequest(cfg, path, init = {}) {
  const response = await fetch(`${cfg.portalUrl}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${cfg.portalKey}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Portal rejected the trial session (HTTP ${response.status}): ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

export async function authorize(cfg, hostname = "community-trial") {
  assertConfigured(cfg);
  const license = await portalRequest(cfg, "/api/v1/mcp/license/validate", {
    method: "POST",
    body: JSON.stringify({ server_version: VERSION, hostname }),
  });
  if (!license.valid) throw new Error("Portal license is not valid.");
  const used = Number(license.quota?.queries_used ?? 0);
  const limit = Number(license.quota?.queries_limit ?? 0);
  if (limit <= 0) throw new Error("This Portal account has no Community Trial cap assigned. Contact ABAPilot support.");
  if (used >= limit) throw new Error(`Community Trial allowance exhausted (${used}/${limit} calls this month).`);
  return { tenant: license.tenant_name, used, limit };
}

function sapUrl(cfg, endpoint) {
  const url = new URL(cfg.sapUrl);
  url.pathname = `${url.pathname.replace(/\/+$/, "")}${endpoint}`;
  if (cfg.sapClient) url.searchParams.set("sap-client", cfg.sapClient);
  return url;
}

export async function callSap(cfg, tool, args = {}) {
  const payload = { ...args };
  if (typeof payload.object_name === "string") payload.object_name = payload.object_name.toUpperCase();
  if (typeof payload.table_name === "string") payload.table_name = payload.table_name.toUpperCase();
  const response = await fetch(sapUrl(cfg, tool.endpoint), {
    method: tool.endpoint === "/ping" ? "GET" : "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${cfg.sapUser}:${cfg.sapPassword}`).toString("base64")}`,
      "X-ABAPilot-License-Key": cfg.portalKey,
      "Content-Type": "application/json",
      "X-ABAPilot-Connector": `community-trial/${VERSION}`,
    },
    body: tool.endpoint === "/ping" ? undefined : JSON.stringify(payload),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`SAP trial endpoint returned HTTP ${response.status}: ${text.slice(0, 500)}`);
  try { return JSON.parse(text); } catch { return text; }
}
