import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from './AuthContext';
import type { Role } from './roles';

export function ProtectedRoute({ allowedRoles }: { allowedRoles: readonly Role[] }) {
  const { token, user, hasAnyRole } = useAuth();
  const location = useLocation();

  if (!token || !user) return <Navigate to="/login" replace state={{ from: location }} />;
  if (!hasAnyRole(allowedRoles)) return <Navigate to="/forbidden" replace />;
  return <Outlet />;
}
