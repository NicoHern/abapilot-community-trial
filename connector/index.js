#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { callSap, configuration, TOOLS, VERSION } from "./lib.mjs";

const cfg = configuration();
const server = new Server(
  { name: "abapilot-community-trial", version: VERSION },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS.map(({ endpoint, ...tool }) => tool),
}));

server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  const tool = TOOLS.find((candidate) => candidate.name === params.name);
  if (!tool) throw new Error(`Unknown Community Trial tool: ${params.name}`);
  try {
    const result = await callSap(cfg, tool, params.arguments ?? {});
    return { content: [{ type: "text", text: typeof result === "string" ? result : JSON.stringify(result, null, 2) }] };
  } catch (error) {
    return { isError: true, content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }] };
  }
});

await server.connect(new StdioServerTransport());
