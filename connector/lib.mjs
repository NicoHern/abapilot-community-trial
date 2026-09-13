export const VERSION = "0.1.0";

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
  const started = Date.now();
  let authorized = false;
  let status = "error";
  let errorMessage = "";
  try {
    await authorize(cfg);
    authorized = true;
    const payload = { ...args };
    if (typeof payload.object_name === "string") payload.object_name = payload.object_name.toUpperCase();
    if (typeof payload.table_name === "string") payload.table_name = payload.table_name.toUpperCase();
    const response = await fetch(sapUrl(cfg, tool.endpoint), {
      method: tool.endpoint === "/ping" ? "GET" : "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(`${cfg.sapUser}:${cfg.sapPassword}`).toString("base64")}`,
        "Content-Type": "application/json",
        "X-ABAPilot-Connector": `community-trial/${VERSION}`,
      },
      body: tool.endpoint === "/ping" ? undefined : JSON.stringify(payload),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`SAP trial endpoint returned HTTP ${response.status}: ${text.slice(0, 500)}`);
    status = "success";
    try { return JSON.parse(text); } catch { return text; }
  } catch (error) {
    errorMessage = error instanceof Error ? error.message : String(error);
    throw error;
  } finally {
    if (authorized) {
      await portalRequest(cfg, "/api/v1/mcp/telemetry/events", {
        method: "POST",
        body: JSON.stringify({ events: [{
          event_type: "tool_call", feature: "community_trial", sap_endpoint: tool.endpoint,
          status, duration_ms: Date.now() - started, tool_calls: [tool.name], tool_calls_count: 1,
          channel: "mcp", error_message: errorMessage, timestamp: new Date().toISOString(),
        }] }),
      }).catch(() => {});
    }
  }
}
