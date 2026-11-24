#!/usr/bin/env node
/* Standalone remote connector (Streamable HTTP + OAuth) for local testing or self-hosting:
 *   UNIFY_MCP_SECRET=... PORT=8787 node dist/http.js   ->  http://localhost:8787/mcp */
import { createServer } from "node:http";
import { createRemoteHandler } from "./remote/handler.js";

const handler = createRemoteHandler();
const port = Number(process.env.PORT ?? 8787);
createServer((req, res) => void handler(req, res)).listen(port, () => {
  console.error(`[unify-mcp] remote connector on http://localhost:${port}/mcp`);
});
