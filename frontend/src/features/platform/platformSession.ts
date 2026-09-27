/* The platform console's session, kept apart from the tenant app's.
 *
 * A different storage key, so signing in as the owner never touches (or is
 * touched by) a tenant login in the same browser, and sessionStorage rather
 * than localStorage: the token dies with the tab. The server enforces the
 * real limits (60 min hard, 15 min idle, revocable); these helpers only let
 * the UI show them and log out first. */

export const PLATFORM_TOKEN_KEY = 'unify-platform-token';
export const PLATFORM_EXPIRY_KEY = 'unify-platform-expires';
export const PLATFORM_IDLE_KEY = 'unify-platform-idle-minutes';

export interface PlatformUser {
  id: string;
  email: string;
  fullName: string;
  role: string;
}

export function getPlatformToken(): string | null {
  try { return sessionStorage.getItem(PLATFORM_TOKEN_KEY); } catch { return null; }
}

export function getPlatformExpiry(): Date | null {
  try {
    const raw = sessionStorage.getItem(PLATFORM_EXPIRY_KEY);
    return raw ? new Date(raw) : null;
  } catch { return null; }
}

export function getIdleMinutes(): number {
  try { return Number(sessionStorage.getItem(PLATFORM_IDLE_KEY) || 15) || 15; } catch { return 15; }
}

export function storePlatformSession(token: string, expiresAt: string, idleTimeoutMinutes: number) {
  try {
    sessionStorage.setItem(PLATFORM_TOKEN_KEY, token);
    sessionStorage.setItem(PLATFORM_EXPIRY_KEY, expiresAt);
    sessionStorage.setItem(PLATFORM_IDLE_KEY, String(idleTimeoutMinutes));
  } catch { /* private mode: the session simply lives in memory-less limbo and the next request 401s */ }
}

export function clearPlatformSession() {
  try {
    sessionStorage.removeItem(PLATFORM_TOKEN_KEY);
    sessionStorage.removeItem(PLATFORM_EXPIRY_KEY);
    sessionStorage.removeItem(PLATFORM_IDLE_KEY);
  } catch { /* ignore */ }
}

export function isPlatformSessionLive(): boolean {
  const token = getPlatformToken();
  const expiry = getPlatformExpiry();
  return Boolean(token) && Boolean(expiry) && (expiry as Date).getTime() > Date.now();
}

export function decodePlatformUser(): PlatformUser | null {
  const token = getPlatformToken();
  if (!token) return null;
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return {
      id: payload.sub,
      email: payload.email,
      fullName: payload.fullName || '',
      role: payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] || 'SuperAdmin',
    };
  } catch {
    return null;
  }
}
