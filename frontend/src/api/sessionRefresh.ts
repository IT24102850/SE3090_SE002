import { API_BASE_URL } from './apiBaseUrl';

/* Refresh-token handling shared by both API clients - axiosConfig.ts and the
 * RTK Query base query in bookingApi.ts.
 *
 * Access tokens live 2 hours. When one expires, the first 401 trades the
 * refresh token (POST /auth/refresh) for a new pair and the request is
 * replayed. Refresh tokens are single-use on the server, so concurrent 401s
 * must share one refresh rather than each spending the token: `inFlight`
 * makes every caller wait on the same promise.
 *
 * Plain fetch, not the axios instance, so a 401 from /auth/refresh itself can
 * never recurse into another refresh. */

const TOKEN = 'token';
const REFRESH = 'refreshToken';
const USER = 'user';

let inFlight: Promise<string | null> | null = null;

export function refreshSession(): Promise<string | null> {
  inFlight ??= doRefresh().finally(() => {
    inFlight = null;
  });
  return inFlight;
}

/**
 * Fetch an authenticated API resource and transparently rotate an expired
 * access token once before replaying the request.
 *
 * Some feature pages use fetch directly instead of the shared Axios client.
 * Keeping the retry here prevents those pages from diverging from the app-wide
 * session behaviour.
 */
export async function fetchWithAuth(
  input: RequestInfo | URL,
  init: RequestInit = {},
): Promise<Response> {
  const requestInit: RequestInit = {
    ...init,
    headers: new Headers(init.headers),
  };

  const send = () => {
    const headers = new Headers(requestInit.headers);
    const token = localStorage.getItem(TOKEN);
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return fetch(input, { ...requestInit, headers });
  };

  const response = await send();
  if (response.status !== 401) return response;

  const token = await refreshSession();
  if (!token) {
    expireSession();
    return response;
  }

  return send();
}

async function doRefresh(): Promise<string | null> {
  const refreshToken = localStorage.getItem(REFRESH);
  if (!refreshToken) return null;
  try {
    const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken }),
    });
    if (!response.ok) return null;
    const body = (await response.json()) as { accessToken?: string; refreshToken?: string; user?: unknown };
    if (!body.accessToken) return null;
    localStorage.setItem(TOKEN, body.accessToken);
    if (body.refreshToken) localStorage.setItem(REFRESH, body.refreshToken);
    if (body.user) localStorage.setItem(USER, JSON.stringify(body.user));
    return body.accessToken;
  } catch {
    return null;
  }
}

/** Ends the session locally and sends the browser to the login page. */
export function expireSession(): void {
  localStorage.removeItem(TOKEN);
  localStorage.removeItem(REFRESH);
  localStorage.removeItem(USER);
  window.location.href = '/login';
}

/** Best-effort server-side sign-out: revokes the refresh token so it can never be redeemed again. */
export function revokeRefreshToken(): void {
  const refreshToken = localStorage.getItem(REFRESH);
  if (!refreshToken) return;
  void fetch(`${API_BASE_URL}/auth/logout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
    keepalive: true,
  }).catch(() => {
    /* offline: the local sign-out still happens */
  });
}
