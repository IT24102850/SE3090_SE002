import { useAuth } from './context/AuthContext';

export const RoleTest = () => {
  const { user, isAuthenticated, hasRole, logout } = useAuth();

  if (!isAuthenticated) return <div>Please log in</div>;

  return (
    <div style={{ padding: 20 }}>
      <h2>Welcome, {user?.fullName}</h2>
      <p>Role: <strong>{user?.role}</strong></p>
      <p>Tenant: {user?.tenantId}</p>

      {hasRole(['Admin', 'Manager']) && (
        <div style={{ color: 'green' }}>✅ You can see Manager/Admin content</div>
      )}

      {hasRole(['Customer']) && (
        <div style={{ color: 'blue' }}>✅ You can see Customer content</div>
      )}

      <button onClick={logout}>Logout</button>
    </div>
  );
};