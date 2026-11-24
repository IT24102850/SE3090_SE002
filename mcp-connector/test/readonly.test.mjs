import { test } from "node:test";
import assert from "node:assert/strict";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

test("read-only mode registers only read tools", async () => {
  const client = new Client({ name: "ro", version: "1" });
  await client.connect(new StdioClientTransport({
    command: "node", args: ["dist/index.js"],
    env: { ...process.env, UNIFY_READ_ONLY: "true", UNIFY_EMAIL: "${user_config.email}" }, stderr: "ignore",
  }));
  const { tools } = await client.listTools();
  assert.ok(tools.length > 15);
  for (const t of tools) assert.equal(t.annotations.readOnlyHint, true, t.name);
  assert.ok(!tools.some((t) => t.name === "unify_create_booking"));
  // Unfilled ${user_config.*} placeholder counts as "not set"
  const r = await client.callTool({ name: "unify_whoami", arguments: {} });
  assert.equal(r.isError, true);
  assert.match(r.content[0].text, /Not signed in/);
  await client.close();
});
