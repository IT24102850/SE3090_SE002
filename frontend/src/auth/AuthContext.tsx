import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import { isRole, type Role } from './roles';

const tokenStorageKey = 'sme.access-token';

type JwtPayload = {
  sub?: string;
  exp?: number;
  'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'?: string;
  role?: string | string[];
  roles?: string | string[];
  Role?: string | string[];
  'http://schemas.microsoft.com/ws/2008/06/identity/claims/role'?: string | string[];
  tenant_id?: string;
};

export type AuthUser = { id?: string; roles: Role[]; tenantId?: string };

type AuthContextValue = {
  token: string | null;
  user: AuthUser | null;
  setToken: (token: string) => void;
  logout: () => void;
  hasAnyRole: (allowedRoles: readonly Role[]) => boolean;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

function decodeToken(token: string): JwtPayload | null {
  try {
    const encodedPayload = token.split('.')[1];
    if (!encodedPayload) return null;
    const payload = encodedPayload.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(payload));
  } catch {
    return null;
  }
}

function userFromToken(token: string | null): AuthUser | null {
  if (!token) return null;
  const payload = decodeToken(token);
  if (!payload || (payload.exp !== undefined && payload.exp * 1000 <= Date.now())) return null;
  const rawRoles = payload.role ?? payload.roles ?? payload.Role ?? payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'];
  const roles = (Array.isArray(rawRoles) ? rawRoles : [rawRoles])
    .filter(isRole)
    .map((role) => (role.charAt(0).toUpperCase() + role.slice(1).toLowerCase()) as Role);
  return { id: payload.sub ?? payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'], roles, tenantId: payload.tenant_id };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setStoredToken] = useState<string | null>(() => localStorage.getItem(tokenStorageKey));
  const user = useMemo(() => userFromToken(token), [token]);

  const setToken = useCallback((newToken: string) => {
    localStorage.setItem(tokenStorageKey, newToken);
    setStoredToken(newToken);
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem(tokenStorageKey);
    setStoredToken(null);
  }, []);

  const value = useMemo(() => ({
    token,
    user,
    setToken,
    logout,
    hasAnyRole: (allowedRoles: readonly Role[]) => !!user && user.roles.some((role) => allowedRoles.includes(role))
  }), [logout, setToken, token, user]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
}

export function createDemoToken(role: Role): string {
  const encode = (value: object) => btoa(JSON.stringify(value))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  const header = encode({ alg: 'none', typ: 'JWT' });
  const payload = encode({
    sub: 'demo-user',
    role,
    tenant_id: '00000000-0000-0000-0000-000000000001',
    exp: Math.floor(Date.now() / 1000) + 60 * 60
  });

  return `${header}.${payload}.demo`;
}
