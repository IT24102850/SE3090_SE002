// End-to-end test of the deployed artefact (frontend/api/claude-mcp.js): OAuth discovery,
// dynamic registration, the Unify sign-in form, PKCE token exchange, MCP calls and refresh.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { createHash, randomBytes } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { startMockBackend } from "./mock-backend.mjs";

const SECRET = "test-secret-0123456789-abcdefghijklmnop";
let mock, server, base, handlerMod;

// Simulates Vercel: rewrites the public path to the function with ?route=, and pre-parses the body.
const REWRITES = [
  [/^\/mcp$/, "mcp"], [/^\/oauth\/register$/, "register"], [/^\/oauth\/authorize$/, "authorize"], [/^\/oauth\/token$/, "token"],
  [/^\/\.well-known\/oauth-protected-resource(\/.*)?$/, "prm"], [/^\/\.well-known\/oauth-authorization-server(\/.*)?$/, "asm"],
];

before(async () => {
  mock = await startMockBackend();
  process.env.UNIFY_MCP_SECRET = SECRET;
  process.env.UNIFY_API_URL = mock.url + "/api";
  handlerMod = await import("../../frontend/api/claude-mcp.js");
  assert.equal(handlerMod.config.maxDuration, 60);
  server = http.createServer(async (req, res) => {
    const u = new URL(req.url, "http://x");
    const hit = REWRITES.find(([re]) => re.test(u.pathname));
    if (!hit) { res.statusCode = 404; return res.end(); }
    u.searchParams.set("route", hit[1]);
    req.url = "/api/claude-mcp" + u.search;
    if (req.method === "POST") {
      let raw = ""; for await (const c of req) raw += c;
      const ct = req.headers["content-type"] ?? "";
      req.body = ct.includes("json") ? JSON.parse(raw || "{}") : Object.fromEntries(new URLSearchParams(raw));
    }
    await handlerMod.default(req, res);
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server?.close(); mock?.close(); });

const form = (o) => new URLSearchParams(o).toString();
const FORM = { "content-type": "application/x-www-form-urlencoded" };

async function connectFlow({ allowWrite = true } = {}) {
  // 1. Unauthenticated MCP call -> 401 pointing at resource metadata
  const r401 = await fetch(`${base}/mcp`, { method: "POST", headers: { "content-type": "application/json", accept: "application/json, text/event-stream" }, body: "{}" });
  assert.equal(r401.status, 401);
  const wa = r401.headers.get("www-authenticate");
  const prmUrl = /resource_metadata="([^"]+)"/.exec(wa)[1];
  const prm = await (await fetch(prmUrl)).json();
  assert.equal(prm.resource, `${base}/mcp`);
  const asm = await (await fetch(`${prm.authorization_servers[0]}/.well-known/oauth-authorization-server`)).json();
  assert.deepEqual(asm.code_challenge_methods_supported, ["S256"]);

  // 2. Dynamic client registration
  const reg = await (await fetch(asm.registration_endpoint, { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_name: "Claude", redirect_uris: ["https://claude.ai/api/mcp/auth_callback"], token_endpoint_auth_method: "none" }) })).json();
  assert.match(reg.client_id, /^uc_/);

  // 3. Authorize: GET shows the Unify sign-in page
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const q = { response_type: "code", client_id: reg.client_id, redirect_uri: "https://claude.ai/api/mcp/auth_callback",
    code_challenge: challenge, code_challenge_method: "S256", state: "xyz", scope: "unify", resource: `${base}/mcp` };
  const page = await fetch(`${asm.authorization_endpoint}?${form(q)}`);
  assert.equal(page.status, 200);
  const htmlText = await page.text();
  assert.match(htmlText, /Connect Claude to Unify/);
  assert.match(page.headers.get("content-security-policy"), /form-action 'self' https:\/\/claude\.ai/);

  // wrong password -> form again with an error
  const bad = await fetch(asm.authorization_endpoint, { method: "POST", headers: FORM, redirect: "manual",
    body: form({ ...q, email: "admin@clinic.lk", password: "nope", allow_write: "1" }) });
  assert.equal(bad.status, 401);
  assert.match(await bad.text(), /Incorrect email or password/);

  // 4. Correct password -> redirect back with code + state
  const ok = await fetch(asm.authorization_endpoint, { method: "POST", headers: FORM, redirect: "manual",
    body: form({ ...q, email: "admin@clinic.lk", password: "secret", ...(allowWrite ? { allow_write: "1" } : {}) }) });
  assert.equal(ok.status, 302);
  const loc = new URL(ok.headers.get("location"));
  assert.equal(loc.origin + loc.pathname, "https://claude.ai/api/mcp/auth_callback");
  assert.equal(loc.searchParams.get("state"), "xyz");
  const code = loc.searchParams.get("code");

  // 5. Token exchange: wrong verifier fails, right one succeeds
  const badTok = await fetch(asm.token_endpoint, { method: "POST", headers: FORM,
    body: form({ grant_type: "authorization_code", code, client_id: reg.client_id, redirect_uri: q.redirect_uri, code_verifier: "wrong" }) });
  assert.equal(badTok.status, 400);
  const tok = await (await fetch(asm.token_endpoint, { method: "POST", headers: FORM,
    body: form({ grant_type: "authorization_code", code, client_id: reg.client_id, redirect_uri: q.redirect_uri, code_verifier: verifier }) })).json();
  assert.equal(tok.token_type, "Bearer");
  assert.ok(tok.access_token && tok.refresh_token && tok.expires_in > 60);
  assert.ok(!tok.access_token.includes("access-"), "Unify token is not visible inside the connector token");
  return { tok, reg, asm };
}

async function mcpClient(accessToken, path = "/mcp") {
  const c = new Client({ name: "claude-sim", version: "1" });
  await c.connect(new StreamableHTTPClientTransport(new URL(base + path), { requestInit: { headers: { Authorization: `Bearer ${accessToken}` } } }));
  return c;
}

test("full OAuth connect flow, then tools work over Streamable HTTP", async () => {
  const { tok } = await connectFlow();
  const c = await mcpClient(tok.access_token);
  const { tools } = await c.listTools();
  assert.equal(tools.length, 42);
  const who = await c.callTool({ name: "unify_whoami", arguments: {} });
  assert.ok(!who.isError, who.content[0].text);
  assert.match(who.content[0].text, /Asia MediHealth/);
  const create = await c.callTool({ name: "unify_create_booking", arguments: {
    resourceId: "33333333-3333-4333-8333-333333333333", bookingTypeId: "44444444-4444-4444-8444-444444444444",
    startTime: "2026-11-25T10:00", durationMinutes: 30 } });
  assert.ok(!create.isError, create.content[0].text);
  const sent = [...mock.log].reverse().find((l) => l.path === "/api/bookings" && l.method === "POST");
  assert.equal(sent.body.startTime, "2026-11-25T04:30:00.000Z");
  assert.match(sent.auth, /^access-/, "uses the user's own Unify token");
  await c.close();
});

test("view-only consent registers only read tools", async () => {
  const { tok } = await connectFlow({ allowWrite: false });
  const c = await mcpClient(tok.access_token);
  const { tools } = await c.listTools();
  assert.ok(tools.every((t) => t.annotations.readOnlyHint), "all read-only");
  assert.ok(!tools.some((t) => t.name === "unify_cancel_booking"));
  await c.close();
});

test("?readonly=1 URL also limits tools", async () => {
  const { tok } = await connectFlow();
  const c = await mcpClient(tok.access_token, "/mcp?readonly=1");
  const { tools } = await c.listTools();
  assert.ok(tools.every((t) => t.annotations.readOnlyHint));
  await c.close();
});

test("refresh grant rotates the Unify session", async () => {
  const { tok, reg, asm } = await connectFlow();
  const before = mock.log.filter((l) => l.path === "/api/auth/refresh").length;
  const r = await fetch(asm.token_endpoint, { method: "POST", headers: FORM,
    body: form({ grant_type: "refresh_token", refresh_token: tok.refresh_token, client_id: reg.client_id }) });
  assert.equal(r.status, 200);
  const next = await r.json();
  assert.equal(mock.log.filter((l) => l.path === "/api/auth/refresh").length, before + 1);
  const c = await mcpClient(next.access_token);
  const res = await c.callTool({ name: "unify_list_bookings", arguments: {} });
  assert.ok(!res.isError, res.content[0].text);
  await c.close();
  // the old refresh token was single-use at Unify -> invalid_grant now
  const again = await fetch(asm.token_endpoint, { method: "POST", headers: FORM,
    body: form({ grant_type: "refresh_token", refresh_token: tok.refresh_token, client_id: reg.client_id }) });
  assert.equal(again.status, 400);
  assert.equal((await again.json()).error, "invalid_grant");
});

test("forged, foreign and malformed tokens are rejected", async () => {
  const r = await fetch(`${base}/mcp`, { method: "POST", headers: { Authorization: "Bearer abc.def", "content-type": "application/json" }, body: "{}" });
  assert.equal(r.status, 401);
  assert.match(r.headers.get("www-authenticate"), /invalid_token/);
  const { tok } = await connectFlow();
  // a refresh token is not accepted as an access token (kind is bound into the seal)
  const r2 = await fetch(`${base}/mcp`, { method: "POST", headers: { Authorization: `Bearer ${tok.refresh_token}`, "content-type": "application/json" }, body: "{}" });
  assert.equal(r2.status, 401);
});

test("authorize rejects unregistered redirect URIs and unknown clients", async () => {
  const reg = await (await fetch(`${base}/oauth/register`, { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ redirect_uris: ["https://claude.ai/api/mcp/auth_callback"] }) })).json();
  const bad = await fetch(`${base}/oauth/authorize?${form({ response_type: "code", client_id: reg.client_id, redirect_uri: "https://evil.example/cb", code_challenge: "x", code_challenge_method: "S256" })}`);
  assert.equal(bad.status, 400);
  const unknown = await fetch(`${base}/oauth/authorize?${form({ response_type: "code", client_id: "uc_forged", redirect_uri: "https://claude.ai/api/mcp/auth_callback", code_challenge: "x", code_challenge_method: "S256" })}`);
  assert.equal(unknown.status, 400);
  const noPkce = await fetch(`${base}/oauth/authorize?${form({ response_type: "code", client_id: reg.client_id, redirect_uri: "https://claude.ai/api/mcp/auth_callback", state: "s" })}`, { redirect: "manual" });
  assert.equal(noPkce.status, 302);
  assert.match(noPkce.headers.get("location"), /error=invalid_request/);
  const reject = await fetch(`${base}/oauth/register`, { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ redirect_uris: ["javascript:alert(1)"] }) });
  assert.equal(reject.status, 400);
});

test("browser visit to /mcp shows setup instructions", async () => {
  const r = await fetch(`${base}/mcp`, { headers: { accept: "text/html" } });
  assert.equal(r.status, 200);
  assert.match(await r.text(), /Add custom connector/);
});
