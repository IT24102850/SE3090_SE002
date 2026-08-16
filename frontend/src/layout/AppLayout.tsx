import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { useToast } from '../ui/ToastContext';

export function AppLayout() {
  const { user, logout, hasAnyRole } = useAuth();
  const navigate = useNavigate();
  const { notify } = useToast();

  function signOut() {
    if (!window.confirm('Are you sure you want to sign out?')) return;
    logout();
    notify('You have been signed out.', 'info');
    navigate('/login');
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <NavLink className="brand" to="/inventory">SME Platform</NavLink>
        <nav aria-label="Main navigation">
          {hasAnyRole(['Admin', 'Manager']) && <NavLink to="/analytics">Analytics Dashboard</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/inventory">Inventory</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/stock-movements">Stock Log</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/purchase-orders">Purchase Orders</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/low-stock-alerts">Low Stock Alerts</NavLink>}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && <NavLink to="/branch-overview">Branches</NavLink>}
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
