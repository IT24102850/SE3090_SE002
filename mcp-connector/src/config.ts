export interface UnifyConfig {
  /** Base URL of the Unify API, ending in /api. */
  apiUrl: string;
  email?: string;
  password?: string;
  /** Optional pre-issued access token (skips email/password login). */
  accessToken?: string;
  /** IANA time zone used to interpret times given without an offset. */
  timeZone: string;
  /** When true, only read-only tools are registered. */
  readOnly: boolean;
  /** Per-request timeout in ms. Render's free tier can take ~60s to wake up. */
  timeoutMs: number;
}

const DEFAULT_API_URL = "https://se-3090-se-002.vercel.app/api";

function clean(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  // Strip a pasted UTF-8 BOM and whitespace (a BOM once broke sign-in on the web app).
  const v = value.replace(/^﻿/, "").trim();
  // Claude Desktop passes "${user_config.x}" through literally when a field is left empty.
  if (v === "" || /^\$\{user_config\.[^}]+\}$/.test(v)) return undefined;
  return v;
}

function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): UnifyConfig {
  let apiUrl = clean(env.UNIFY_API_URL) ?? DEFAULT_API_URL;
  apiUrl = apiUrl.replace(/\/+$/, "");
  if (!/\/api$/i.test(apiUrl)) apiUrl += "/api";

  const tz = clean(env.UNIFY_TIMEZONE) ?? "Asia/Colombo";
  const timeoutSec = Number(clean(env.UNIFY_TIMEOUT_SECONDS) ?? "90");

  return {
    apiUrl,
    email: clean(env.UNIFY_EMAIL),
    password: clean(env.UNIFY_PASSWORD),
    accessToken: clean(env.UNIFY_ACCESS_TOKEN),
    timeZone: isValidTimeZone(tz) ? tz : "UTC",
    readOnly: /^(1|true|yes|on)$/i.test(clean(env.UNIFY_READ_ONLY) ?? ""),
    timeoutMs: Number.isFinite(timeoutSec) && timeoutSec > 0 ? timeoutSec * 1000 : 90_000,
  };
}
