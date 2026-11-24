import type { UnifyConfig } from "./config.js";

export interface UnifyUser {
  id: string;
  email: string;
  fullName: string;
  phone?: string;
  role: string;
  tenantId: string;
  branchId?: string | null;
}

interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  expiresAt?: string;
  user: UnifyUser;
}

export type Query = Record<string, string | number | boolean | null | undefined | string[]>;

export interface RequestOptions {
  query?: Query;
  body?: unknown;
  /** Send without the bearer token (public endpoints). */
  anonymous?: boolean;
}

export class UnifyApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly method: string,
    public readonly path: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "UnifyApiError";
  }
}

const RETRYABLE = new Set([502, 503, 504]);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class UnifyClient {
  private accessToken?: string;
  private refreshToken?: string;
  private user?: UnifyUser;
  private loginInFlight?: Promise<void>;

  constructor(
    private readonly config: UnifyConfig,
    private readonly fetchImpl: typeof fetch = fetch,
    initialUser?: UnifyUser,
  ) {
    this.accessToken = config.accessToken;
    this.user = initialUser;
  }

  get baseUrl(): string {
    return this.config.apiUrl;
  }

  get timeZone(): string {
    return this.config.timeZone;
  }

  hasCredentials(): boolean {
    return Boolean(this.config.accessToken || (this.config.email && this.config.password));
  }

  /** The signed-in user; signs in on first use. */
  async me(): Promise<UnifyUser> {
    await this.ensureSession();
    if (!this.user) {
      const u = (await this.request("GET", "/auth/me")) as UnifyUser;
      this.user = u;
    }
    return this.user!;
  }

  async tenantId(): Promise<string> {
    return (await this.me()).tenantId;
  }

  private async ensureSession(): Promise<void> {
    if (this.accessToken) return;
    await this.login();
  }

  private async login(): Promise<void> {
    if (this.loginInFlight) return this.loginInFlight;
    this.loginInFlight = (async () => {
      const { email, password } = this.config;
      if (!email || !password) {
        throw new UnifyApiError(
          401,
          "Not signed in to Unify. Set your Unify email and password in the connector settings " +
            "(UNIFY_EMAIL / UNIFY_PASSWORD), or provide UNIFY_ACCESS_TOKEN.",
          "POST",
          "/auth/login",
        );
      }
      const res = (await this.raw("POST", "/auth/login", { body: { email, password }, anonymous: true }, 2)) as AuthResponse;
      this.setSession(res);
    })();
    try {
      await this.loginInFlight;
    } finally {
      this.loginInFlight = undefined;
    }
  }

  private setSession(res: AuthResponse) {
    this.accessToken = res.accessToken;
    this.refreshToken = res.refreshToken;
    if (res.user) this.user = res.user;
  }

  private async refresh(): Promise<boolean> {
    if (!this.refreshToken) return false;
    try {
      const res = (await this.raw(
        "POST",
        "/auth/refresh",
        { body: { refreshToken: this.refreshToken }, anonymous: true },
        0,
      )) as AuthResponse;
      this.setSession(res);
      return true;
    } catch {
      this.refreshToken = undefined;
      return false;
    }
  }

  /**
   * Authenticated request. On 401 it refreshes the session (or signs in again)
   * once and retries.
   */
  async request(method: string, path: string, opts: RequestOptions = {}): Promise<unknown> {
    if (!opts.anonymous) await this.ensureSession();
    const retries = method === "GET" ? 2 : 0;
    try {
      return await this.raw(method, path, opts, retries);
    } catch (err) {
      if (!(err instanceof UnifyApiError) || err.status !== 401 || opts.anonymous) throw err;
      this.accessToken = undefined;
      const refreshed = await this.refresh();
      if (!refreshed) {
        if (!(this.config.email && this.config.password)) throw err;
        this.user = undefined;
        await this.login();
      }
      return await this.raw(method, path, opts, retries);
    }
  }

  private buildUrl(path: string, query?: Query): string {
    const p = path.startsWith("/") ? path : `/${path}`;
    const url = new URL(this.config.apiUrl + p);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v === undefined || v === null || v === "") continue;
      if (Array.isArray(v)) v.forEach((item) => url.searchParams.append(k, item));
      else url.searchParams.set(k, String(v));
    }
    return url.toString();
  }

  private async raw(method: string, path: string, opts: RequestOptions, retries: number): Promise<unknown> {
    const url = this.buildUrl(path, opts.query);
    const headers: Record<string, string> = {
      Accept: "application/json",
      "User-Agent": "unify-mcp/1.0 (+Claude connector)",
    };
    if (opts.body !== undefined) headers["Content-Type"] = "application/json";
    if (!opts.anonymous && this.accessToken) headers.Authorization = `Bearer ${this.accessToken}`;

    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await this.fetchImpl(url, {
          method,
          headers,
          body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
          signal: AbortSignal.timeout(this.config.timeoutMs),
        });
      } catch (e) {
        const reason = (e as Error)?.name === "TimeoutError"
          ? `timed out after ${Math.round(this.config.timeoutMs / 1000)}s (the Unify backend may be waking up - try again in a minute)`
          : (e as Error)?.message ?? String(e);
        if (attempt < retries) {
          await sleep(1500 * (attempt + 1));
          continue;
        }
        throw new UnifyApiError(0, `Could not reach Unify at ${this.config.apiUrl}: ${reason}`, method, path);
      }

      if (RETRYABLE.has(res.status) && attempt < retries) {
        await sleep(2000 * (attempt + 1));
        continue;
      }

      const text = await res.text();
      let data: unknown = text;
      const ct = res.headers.get("content-type") ?? "";
      if (text && (ct.includes("json") || /^[\[{]/.test(text.trim()))) {
        try {
          data = JSON.parse(text);
        } catch {
          /* keep text */
        }
      }

      if (!res.ok) throw new UnifyApiError(res.status, describeError(res.status, data, text), method, path, data);
      if (res.status === 204 || text === "") return { ok: true, status: res.status };
      return data;
    }
  }
}

function describeError(status: number, data: unknown, text: string): string {
  let msg = "";
  if (data && typeof data === "object") {
    const d = data as Record<string, unknown>;
    msg = String(d.message ?? d.error ?? d.title ?? d.detail ?? "");
    if (d.errors && typeof d.errors === "object") {
      const parts = Object.entries(d.errors as Record<string, unknown>).map(
        ([k, v]) => `${k}: ${Array.isArray(v) ? v.join(", ") : String(v)}`,
      );
      if (parts.length) msg += (msg ? " - " : "") + parts.join("; ");
    }
  } else if (text && text.length < 500 && !/<html/i.test(text)) {
    msg = text;
  }
  const hint: Record<number, string> = {
    400: "The request was rejected",
    401: "Not authorised (sign-in failed or expired)",
    403: "Your Unify role is not allowed to do this",
    404: "Not found",
    409: "Conflict",
    429: "Too many requests - slow down",
  };
  const base = hint[status] ?? (status >= 500 ? "The Unify server had an error" : `HTTP ${status}`);
  return msg ? `${base}: ${msg}` : `${base} (HTTP ${status})`;
}
