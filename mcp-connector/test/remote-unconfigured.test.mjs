import { test } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";

test("without UNIFY_MCP_SECRET the endpoints explain what to configure", async () => {
  delete process.env.UNIFY_MCP_SECRET;
  const { default: handler } = await import("../../frontend/api/claude-mcp.js?unconfigured");
  const srv = http.createServer((req, res) => handler(req, res));
  await new Promise((r) => srv.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  const meta = await fetch(`${base}/api/claude-mcp?route=asm`);
  assert.equal(meta.status, 200, "discovery still works");
  const r = await fetch(`${base}/api/claude-mcp?route=register`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
  assert.equal(r.status, 503);
  assert.match((await r.json()).error_description, /UNIFY_MCP_SECRET/);
  srv.close();
});
