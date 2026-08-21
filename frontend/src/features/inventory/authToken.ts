// Inventory pages were ported from a standalone app with its own auth
// context; they now read the JWT the same way the shared axios client does
// (see ../../api/axiosConfig.ts) instead of a separate token store.
export function getStoredToken(): string | null {
  return localStorage.getItem('token');
}
