import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';

// ─── Types ──────────────────────────────────────────────────────────

export interface User {
  id: string;
  email: string;
  fullName: string;
  role: 'Admin' | 'Manager' | 'Staff' | 'Customer';
  tenantId: string;
  branchId?: string;
}

interface AuthContextType {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (token: string) => void;
  logout: () => void;
  hasRole: (roles: string[]) => boolean;
  getToken: () => string | null;
}

// ─── Context ────────────────────────────────────────────────────────

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// ─── Provider ───────────────────────────────────────────────────────

interface AuthProviderProps {
  children: ReactNode;
}

export const AuthProvider: React.FC<AuthProviderProps> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const parseToken = (token: string): User => {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    const payload = JSON.parse(jsonPayload);

    return {
      id: payload.sub,
      email: payload.email,
      fullName: payload.fullName || payload.name || '',
      role: payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'],
      tenantId: payload.tenantId,
      branchId: payload.branchId || undefined,
    };
  };

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      try {
        const parsedUser = parseToken(token);
        setUser(parsedUser);
      } catch (e) {
        console.error('Invalid token:', e);
        localStorage.removeItem('token');
      }
    }
    setIsLoading(false);
  }, []);

  const login = (token: string) => {
    localStorage.setItem('token', token);
    const parsedUser = parseToken(token);
    setUser(parsedUser);
  };

  const logout = () => {
    localStorage.removeItem('token');
    setUser(null);
    window.location.href = '/login';
  };

  const hasRole = (roles: string[]): boolean => {
    if (!user) return false;
    return roles.includes(user.role);
  };

  const getToken = (): string | null => {
    return localStorage.getItem('token');
  };

  const value: AuthContextType = {
    user,
    isAuthenticated: !!user,
    isLoading,
    login,
    logout,
    hasRole,
    getToken,
  };

  return React.createElement(AuthContext.Provider, { value }, children);
};

// ─── Hook ───────────────────────────────────────────────────────────

export const useAuth = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};