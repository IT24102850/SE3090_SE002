import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';

export function AppLayout() {
  const { user, logout, hasAnyRole } = useAuth();
  const navigate = useNavigate();

  function signOut() {
    logout();
    navigate('/login');
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <NavLink className="brand" to="/inventory">SME Platform</NavLink>
        <nav aria-label="Main navigation">
          {hasAnyRole(['Admin', 'Manager']) && <NavLink to="/analytics">Analytics Dashboard</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/inventory">Inventory Manager</NavLink>}
        </nav>
        <div className="account">
          <span>{user?.roles.join(', ')}</span>
          <button onClick={signOut}>Sign out</button>
        </div>
      </header>
      <main><Outlet /></main>
    </div>
  );
}
