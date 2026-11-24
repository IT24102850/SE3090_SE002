#!/usr/bin/env node
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { loadConfig } from "./config.js";
import { createServer, VERSION } from "./server.js";

export { createServer, buildServer, VERSION } from "./server.js";

async function main() {
  const config = loadConfig();
  const { server, client } = createServer(config);
  if (!client.hasCredentials()) {
    console.error(
      "[unify-mcp] Warning: no credentials configured. Set UNIFY_EMAIL and UNIFY_PASSWORD (or UNIFY_ACCESS_TOKEN). " +
        "Tools will return a sign-in error until then.",
    );
  }
  await server.connect(new StdioServerTransport());
  console.error(`[unify-mcp] v${VERSION} ready - API ${config.apiUrl}, time zone ${config.timeZone}${config.readOnly ? ", read-only" : ""}`);
}

const isEntry = process.argv[1] && /(index|server)\.(c?js|ts)$/.test(process.argv[1]);
if (isEntry) {
  main().catch((err) => {
    console.error("[unify-mcp] Fatal:", err);
    process.exit(1);
  });
}
