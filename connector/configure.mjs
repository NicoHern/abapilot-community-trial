#!/usr/bin/env node
import { writeFile } from "node:fs/promises";
import { createInterface } from "node:readline/promises";
import { argv, stdin, stdout } from "node:process";

let [sapUrl, sapClient, sapUser] = argv.slice(2);
if (!sapUrl || !sapClient || !sapUser) {
  const rl = createInterface({ input: stdin, output: stdout });
  sapUrl = (await rl.question("SAP trial URL (for example https://sap.example/sap/bc/zabapilot_trial): ")).trim();
  sapClient = (await rl.question("SAP client: ")).trim();
  sapUser = (await rl.question("SAP user created by your SAP administrator: ")).trim();
  rl.close();
}

if (!/^https?:\/\//.test(sapUrl) || !/^\d{3}$/.test(sapClient) || !sapUser) {
  console.error("Invalid input. Supply an HTTP(S) URL, a three-digit SAP client, and a SAP user.");
  process.exit(2);
}

const config = {
  mcpServers: {
    "abapilot-community-trial": {
      command: "npx",
      args: ["-y", "@abapilot/community-trial"],
      env: {
        ABAPILOT_LICENSE_KEY: "PASTE_KEY_FROM_ABAPILOT_PORTAL",
        ABAPILOT_TRIAL_URL: sapUrl.replace(/\/+$/, ""),
        ABAPILOT_TRIAL_SAP_USER: sapUser,
        ABAPILOT_TRIAL_SAP_PASSWORD: "STORE_WITH_YOUR_MCP_CLIENT_SECRET_MECHANISM",
        ABAPILOT_TRIAL_SAP_CLIENT: sapClient,
      },
    },
  },
};

const output = "abapilot-community-trial.mcp.json";
await writeFile(output, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
console.log(`Created ${output}. Add the Portal key and SAP password using your MCP client's secret mechanism.`);
console.log("The Portal account controls the trial. The SAP user remains owned by your organization.");
