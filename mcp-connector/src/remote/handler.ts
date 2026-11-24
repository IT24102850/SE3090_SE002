import { randomBytes } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { UnifyClient, type UnifyUser } from "../client.js";
import { loadConfig, type UnifyConfig } from "../config.js";
import { buildServer } from "../server.js";
import { jwtExpiry, pkceS256, Sealer } from "./crypto.js";
import { errorPage, infoPage, loginPage } from "./pages.js";

/*
 * Remote (Streamable HTTP) Unify connector with a built-in OAuth 2.1
 * authorization server, as Claude's custom connectors expect:
 *
 *   /.well-known/oauth-protected-resource      RFC 9728 resource metadata
 *   /.well-known/oauth-authorization-server    RFC 8414 server metadata
 *   /oauth/register                            RFC 7591 dynamic client registration
 *   /oauth/authorize                           Unify sign-in page (PKCE S256 required)
 *   /oauth/token                               authorization_code + refresh_token grants
 *   /mcp                                       the MCP endpoint (Bearer token)
 *
 * It keeps no state. Every artefact is sealed with UNIFY_MCP_SECRET (see crypto.ts):
 * the access token wraps the user's Unify JWT, and the refresh token wraps their
 * Unify refresh token, so refreshing the connector rotates the Unify session too.
 */

type Req = IncomingMessage & { body?: unknown; query?: Record<string, unknown> };
type Res = ServerResponse;

interface ClientInfo { r: string[]; n: string; m: "none" | "client_secret_post" | "client_secret_basic"; t: number }
interface CodePayload { cid: string; ru: string; cc: string; ua: string; ur: string; u: UnifyUser; ro: boolean; exp: number }
interface AccessPayload { ua: string; u: UnifyUser; ro: boolean; exp: number; cid: string }
interface RefreshPayload { ur: string; ro: boolean; cid: string; iat: number }
interface UnifyAuth { accessToken: string; refreshToken: string; user: UnifyUser }

const CODE_TTL = 300;
const SCOPE = "unify";

export interface RemoteOptions {
  env?: NodeJS.ProcessEnv;
  fetchImpl?: typeof fetch;
}

export function createRemoteHandler(opts: RemoteOptions = {}) {
  const env = opts.env ?? process.env;
  const fetchImpl = opts.fetchImpl ?? fetch;
  const base = loadConfig({
    ...env,
    // The function talks to the backend directly, not back through the site's /api rewrite.
    UNIFY_API_URL: env.UNIFY_API_URL || "https://sme-backend-lxsp.onrender.com/api",
    UNIFY_TIMEOUT_SECONDS: env.UNIFY_TIMEOUT_SECONDS || "50",
    UNIFY_EMAIL: "",
    UNIFY_PASSWORD: "",
    UNIFY_ACCESS_TOKEN: "",
  });
  let sealer: Sealer | undefined;
  let sealerError: string | undefined;
  try {
    sealer = new Sealer(env.UNIFY_MCP_SECRET ?? "");
  } catch (e) {
    sealerError = (e as Error).message;
  }

  return async function handler(req: Req, res: Res): Promise<void> {
    try {
      const url = new URL(req.url ?? "/", "http://localhost");
      const route = routeOf(url);
      const origin = publicBase(req, env);

      if (req.method === "OPTIONS") {
        cors(res, 204).end();
        return;
      }

      if (route === "prm") {
        return json(cors(res), 200, {
          resource: `${origin}/mcp`,
          authorization_servers: [origin],
          bearer_methods_supported: ["header"],
          scopes_supported: [SCOPE],
          resource_name: "Unify",
          resource_documentation: `${origin}/mcp`,
        });
      }
      if (route === "asm") {
        return json(cors(res), 200, {
          issuer: origin,
          authorization_endpoint: `${origin}/oauth/authorize`,
          token_endpoint: `${origin}/oauth/token`,
          registration_endpoint: `${origin}/oauth/register`,
          response_types_supported: ["code"],
          grant_types_supported: ["authorization_code", "refresh_token"],
          code_challenge_methods_supported: ["S256"],
          token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
          scopes_supported: [SCOPE],
          service_documentation: `${origin}/mcp`,
        });
      }

      if (route === "mcp" && req.method === "GET" && /text\/html/.test(String(req.headers.accept ?? ""))) {
        return html(res, 200, infoPage(origin));
      }

      if (!sealer) {
        const msg = `The Unify connector is not configured yet: ${sealerError}`;
        if (route === "authorize") return html(res, 503, errorPage("Connector not configured", msg));
        return json(cors(res), 503, { error: "temporarily_unavailable", error_description: msg });
      }

      switch (route) {
        case "register": return await register(req, res, sealer);
        case "authorize": return await authorize(req, res, url, sealer, base, fetchImpl, origin);
        case "token": return await token(req, res, sealer, base, fetchImpl);
        case "mcp": return await mcp(req, res, url, sealer, base, fetchImpl, origin);
        default:
          return json(cors(res), 404, { error: "not_found" });
      }
    } catch (e) {
      console.error("[unify-mcp] unhandled", e);
      if (!res.headersSent) json(cors(res), 500, { error: "server_error", error_description: "Unexpected error" });
      else res.end();
    }
  };
}

// ── routing helpers ──────────────────────────────────────────────────────

function routeOf(url: URL): string {
  const q = url.searchParams.get("route");
  if (q) return q;
  const p = url.pathname.replace(/\/+$/, "");
  if (p.endsWith("/mcp") || p === "/api/claude-mcp") return "mcp";
  if (p.startsWith("/.well-known/oauth-protected-resource")) return "prm";
  if (p.startsWith("/.well-known/oauth-authorization-server") || p === "/.well-known/openid-configuration") return "asm";
  if (p === "/oauth/register") return "register";
  if (p === "/oauth/authorize") return "authorize";
  if (p === "/oauth/token") return "token";
  return "";
}

function publicBase(req: Req, env: NodeJS.ProcessEnv): string {
  if (env.PUBLIC_BASE_URL) return env.PUBLIC_BASE_URL.replace(/\/+$/, "");
  const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "localhost").split(",")[0].trim();
  const local = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host);
  const proto = String(req.headers["x-forwarded-proto"] ?? (local ? "http" : "https")).split(",")[0].trim();
  return `${proto}://${host}`;
}

function cors(res: Res, status?: number): Res {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id, Last-Event-ID",
  );
  res.setHeader("Access-Control-Expose-Headers", "WWW-Authenticate, Mcp-Session-Id, Mcp-Protocol-Version");
  res.setHeader("Access-Control-Max-Age", "86400");
  if (status) res.statusCode = status;
  return res;
}

function json(res: Res, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function html(res: Res, status: number, page: string, extraHeaders: Record<string, string> = {}) {
  res.statusCode = status;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  for (const [k, v] of Object.entries(extraHeaders)) res.setHeader(k, v);
  res.end(page);
}

function redirect(res: Res, location: string) {
  res.statusCode = 302;
  res.setHeader("Location", location);
  res.setHeader("Cache-Control", "no-store");
  res.end();
}

async function readBody(req: Req): Promise<Record<string, unknown> | unknown> {
  let body: unknown = req.body;
  if (body === undefined) {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(typeof c === "string" ? Buffer.from(c) : c);
    body = Buffer.concat(chunks).toString("utf8");
  }
  if (Buffer.isBuffer(body)) body = body.toString("utf8");
  if (typeof body !== "string") return body ?? {};
  const ct = String(req.headers["content-type"] ?? "");
  if (!body) return {};
  if (ct.includes("application/x-www-form-urlencoded")) return Object.fromEntries(new URLSearchParams(body));
  try {
    return JSON.parse(body);
  } catch {
    return Object.fromEntries(new URLSearchParams(body));
  }
}

const str = (v: unknown) => (typeof v === "string" ? v : Array.isArray(v) && typeof v[0] === "string" ? v[0] : undefined);
const now = () => Math.floor(Date.now() / 1000);

function oauthError(res: Res, status: number, error: string, description: string) {
  return json(cors(res), status, { error, error_description: description });
}

// ── redirect URIs ────────────────────────────────────────────────────────

const LOOPBACK = /^(localhost|127\.0\.0\.1|\[::1\])$/;

function validRedirect(uri: string): boolean {
  try {
    const u = new URL(uri);
    if (u.hash) return false;
    if (u.protocol === "https:") return true;
    return u.protocol === "http:" && LOOPBACK.test(u.hostname);
  } catch {
    return false;
  }
}

function redirectMatches(registered: string[], uri: string): boolean {
  if (registered.includes(uri)) return true;
  // RFC 8252 7.3: loopback redirects may use any port.
  try {
    const u = new URL(uri);
    if (!LOOPBACK.test(u.hostname)) return false;
    return registered.some((r) => {
      const v = new URL(r);
      return LOOPBACK.test(v.hostname) && v.protocol === u.protocol && v.pathname === u.pathname && v.search === u.search;
    });
  } catch {
    return false;
  }
}

// ── /oauth/register ──────────────────────────────────────────────────────

async function register(req: Req, res: Res, sealer: Sealer) {
  if (req.method !== "POST") return oauthError(res, 405, "invalid_request", "Use POST");
  const b = (await readBody(req)) as Record<string, unknown>;
  const uris = Array.isArray(b.redirect_uris) ? b.redirect_uris.filter((x): x is string => typeof x === "string") : [];
  if (!uris.length || uris.length > 10 || !uris.every(validRedirect)) {
    return oauthError(res, 400, "invalid_redirect_uri", "redirect_uris must be https URLs (or http://localhost).");
  }
  const requested = str(b.token_endpoint_auth_method) ?? "none";
  const method: ClientInfo["m"] =
    requested === "client_secret_post" || requested === "client_secret_basic" ? requested : "none";
  const name = (str(b.client_name) ?? "Claude").slice(0, 80);
  const info: ClientInfo = { r: uris, n: name, m: method, t: now() };
  const clientId = `uc_${sealer.seal("client", info)}`;
  const out: Record<string, unknown> = {
    client_id: clientId,
    client_id_issued_at: info.t,
    client_name: name,
    redirect_uris: uris,
    token_endpoint_auth_method: method,
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    scope: SCOPE,
  };
  if (method !== "none") {
    out.client_secret = sealer.clientSecret(clientId);
    out.client_secret_expires_at = 0;
  }
  return json(cors(res), 201, out);
}

function openClient(sealer: Sealer, clientId: string | undefined): ClientInfo | undefined {
  if (!clientId?.startsWith("uc_")) return undefined;
  return sealer.open<ClientInfo>("client", clientId.slice(3));
}

// ── /oauth/authorize ─────────────────────────────────────────────────────

async function authorize(
  req: Req, res: Res, url: URL, sealer: Sealer, cfg: UnifyConfig, fetchImpl: typeof fetch, origin: string,
) {
  const isPost = req.method === "POST";
  const p: Record<string, string> = {};
  if (isPost) {
    const b = (await readBody(req)) as Record<string, unknown>;
    for (const [k, v] of Object.entries(b)) if (str(v) !== undefined) p[k] = str(v)!;
  } else {
    url.searchParams.forEach((v, k) => { if (k !== "route") p[k] = v; });
  }

  const client = openClient(sealer, p.client_id);
  if (!client) return html(res, 400, errorPage("Unknown app", "This connection request is not valid. Remove the connector in Claude and add it again."));
  const redirectUri = p.redirect_uri || (client.r.length === 1 ? client.r[0] : "");
  if (!redirectUri || !redirectMatches(client.r, redirectUri)) {
    return html(res, 400, errorPage("Invalid redirect", "The app's redirect address does not match its registration."));
  }

  const back = (params: Record<string, string>) => {
    const u = new URL(redirectUri);
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    if (p.state) u.searchParams.set("state", p.state);
    u.searchParams.set("iss", origin);
    return u.toString();
  };

  if (p.response_type !== "code") {
    return redirect(res, back({ error: "unsupported_response_type", error_description: "Only response_type=code is supported" }));
  }
  if (!p.code_challenge || (p.code_challenge_method ?? "plain") !== "S256") {
    return redirect(res, back({ error: "invalid_request", error_description: "PKCE with S256 is required" }));
  }

  const hidden: Record<string, string> = {};
  for (const k of ["response_type", "client_id", "redirect_uri", "code_challenge", "code_challenge_method", "state", "scope", "resource"]) {
    if (p[k] !== undefined) hidden[k] = p[k];
  }
  if (!hidden.redirect_uri) hidden.redirect_uri = redirectUri;

  const redirectOrigin = new URL(redirectUri).origin;
  const show = (error?: string, status = 200) => {
    const nonce = randomBytes(16).toString("base64");
    return html(res, status, loginPage({
      clientName: client.n, hidden, error, email: p.email, allowWrite: isPost ? p.allow_write === "1" : true, nonce,
    }), {
      "Content-Security-Policy":
        `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src 'self' data:; ` +
        `form-action 'self' ${redirectOrigin}; frame-ancestors 'none'; base-uri 'none'`,
    });
  };

  if (!isPost) return show();
  if (p.action === "deny") return redirect(res, back({ error: "access_denied", error_description: "The user declined" }));
  if (!p.email || !p.password) return show("Enter your email and password.", 400);

  let auth: UnifyAuth;
  try {
    auth = await unifyAuth(cfg, fetchImpl, "/auth/login", { email: p.email.trim(), password: p.password });
  } catch (e) {
    const err = e as Error & { status?: number };
    if (err.status === 401 || err.status === 400) return show("Incorrect email or password.", 401);
    return show(`Could not reach Unify right now (${err.message}). Please try again in a minute.`, 502);
  }

  const code = sealer.seal("code", {
    cid: p.client_id, ru: redirectUri, cc: p.code_challenge, ua: auth.accessToken, ur: auth.refreshToken,
    u: slimUser(auth.user), ro: p.allow_write !== "1", exp: now() + CODE_TTL,
  } satisfies CodePayload);
  return redirect(res, back({ code }));
}

function slimUser(u: UnifyUser): UnifyUser {
  return { id: u.id, email: u.email, fullName: u.fullName, role: u.role, tenantId: u.tenantId, branchId: u.branchId ?? null };
}

async function unifyAuth(cfg: UnifyConfig, fetchImpl: typeof fetch, path: string, body: unknown): Promise<UnifyAuth> {
  const r = await fetchImpl(`${cfg.apiUrl}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json", "User-Agent": "unify-mcp-remote/1.0" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(cfg.timeoutMs),
  }).catch((e: Error) => {
    throw Object.assign(new Error(e.name === "TimeoutError" ? "timed out" : e.message), { status: 0 });
  });
  const text = await r.text();
  if (!r.ok) throw Object.assign(new Error(`HTTP ${r.status}`), { status: r.status });
  const data = JSON.parse(text) as UnifyAuth;
  if (!data.accessToken || !data.refreshToken || !data.user) throw Object.assign(new Error("unexpected sign-in response"), { status: 502 });
  return data;
}

// ── /oauth/token ─────────────────────────────────────────────────────────

function clientCredentials(req: Req, b: Record<string, unknown>) {
  let id = str(b.client_id);
  let secret = str(b.client_secret);
  const h = String(req.headers.authorization ?? "");
  if (h.startsWith("Basic ")) {
    const [u, s] = Buffer.from(h.slice(6), "base64").toString("utf8").split(":");
    id = decodeURIComponent(u ?? "");
    secret = decodeURIComponent(s ?? "");
  }
  return { id, secret };
}

function issueTokens(sealer: Sealer, cid: string, ua: string, ur: string, u: UnifyUser, ro: boolean) {
  const exp = Math.min(jwtExpiry(ua) ?? now() + 7200, now() + 7200) - 60;
  const access = sealer.seal("at", { ua, u, ro, exp, cid } satisfies AccessPayload);
  const refresh = sealer.seal("rt", { ur, ro, cid, iat: now() } satisfies RefreshPayload);
  return {
    access_token: access,
    token_type: "Bearer",
    expires_in: Math.max(exp - now(), 60),
    refresh_token: refresh,
    scope: SCOPE,
  };
}

async function token(req: Req, res: Res, sealer: Sealer, cfg: UnifyConfig, fetchImpl: typeof fetch) {
  if (req.method !== "POST") return oauthError(res, 405, "invalid_request", "Use POST");
  const b = (await readBody(req)) as Record<string, unknown>;
  const { id: clientId, secret } = clientCredentials(req, b);
  const client = openClient(sealer, clientId);
  if (!client) return oauthError(res, 401, "invalid_client", "Unknown client");
  if (client.m !== "none" && !(secret && sealer.safeEqual(secret, sealer.clientSecret(clientId!)))) {
    return oauthError(res, 401, "invalid_client", "Client authentication failed");
  }

  const grant = str(b.grant_type);
  if (grant === "authorization_code") {
    const code = sealer.open<CodePayload>("code", str(b.code));
    if (!code || code.exp < now()) return oauthError(res, 400, "invalid_grant", "The authorization code is invalid or expired");
    if (code.cid !== clientId) return oauthError(res, 400, "invalid_grant", "Code was issued to another client");
    const ru = str(b.redirect_uri);
    if (ru && ru !== code.ru) return oauthError(res, 400, "invalid_grant", "redirect_uri mismatch");
    const verifier = str(b.code_verifier);
    if (!verifier || !sealer.safeEqual(pkceS256(verifier), code.cc)) {
      return oauthError(res, 400, "invalid_grant", "PKCE verification failed");
    }
    return json(cors(res), 200, issueTokens(sealer, clientId!, code.ua, code.ur, code.u, code.ro));
  }

  if (grant === "refresh_token") {
    const rt = sealer.open<RefreshPayload>("rt", str(b.refresh_token));
    if (!rt || rt.cid !== clientId) return oauthError(res, 400, "invalid_grant", "The refresh token is invalid");
    let auth: UnifyAuth;
    try {
      auth = await unifyAuth(cfg, fetchImpl, "/auth/refresh", { refreshToken: rt.ur });
    } catch (e) {
      const status = (e as { status?: number }).status ?? 0;
      if (status === 401 || status === 400) {
        return oauthError(res, 400, "invalid_grant", "Your Unify session ended. Reconnect the connector to sign in again.");
      }
      return oauthError(res, 503, "temporarily_unavailable", "Unify could not be reached. Try again shortly.");
    }
    return json(cors(res), 200, issueTokens(sealer, clientId!, auth.accessToken, auth.refreshToken, slimUser(auth.user), rt.ro));
  }

  return oauthError(res, 400, "unsupported_grant_type", "Use authorization_code or refresh_token");
}

// ── /mcp ─────────────────────────────────────────────────────────────────

async function mcp(
  req: Req, res: Res, url: URL, sealer: Sealer, cfg: UnifyConfig, fetchImpl: typeof fetch, origin: string,
) {
  cors(res);
  const challenge = (error?: string) => {
    const meta = `${origin}/.well-known/oauth-protected-resource/mcp`;
    res.setHeader(
      "WWW-Authenticate",
      `Bearer realm="unify", resource_metadata="${meta}", scope="${SCOPE}"` +
        (error ? `, error="${error}", error_description="The access token is missing, invalid or expired"` : ""),
    );
    return json(res, 401, { error: error ?? "unauthorized", error_description: "Sign in to Unify to use this connector" });
  };

  const auth = String(req.headers.authorization ?? "");
  if (!auth.startsWith("Bearer ")) return challenge();
  const at = sealer.open<AccessPayload>("at", auth.slice(7).trim());
  if (!at || at.exp <= now()) return challenge("invalid_token");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST, OPTIONS");
    return json(res, 405, { jsonrpc: "2.0", error: { code: -32000, message: "Method not allowed. This server is stateless; use POST." }, id: null });
  }

  const readOnly = at.ro || /^(1|true|yes)$/i.test(url.searchParams.get("readonly") ?? "");
  const client = new UnifyClient({ ...cfg, accessToken: at.ua, readOnly }, fetchImpl, at.u);
  const server = buildServer(client, { readOnly, timeZone: cfg.timeZone });
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  const body = await readBody(req);
  await server.connect(transport);
  await transport.handleRequest(req, res, body);
}
