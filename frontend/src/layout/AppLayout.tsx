import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';

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
        <NavLink className="brand" to="/inventory">
          <span className="brand-mark">SM</span>
          <span className="brand-text">SME Platform</span>
        </NavLink>
        <nav aria-label="Main navigation" className="nav-links">
          {hasAnyRole(['Admin', 'Manager']) && (
            <NavLink to="/analytics" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="predict" />
              <span>Analytics</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/inventory" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="info" />
              <span>Inventory</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/stock-movements" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="info" />
              <span>Stock Log</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/purchase-orders" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="po" />
              <span>Purchase Orders</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/low-stock-alerts" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="info" />
              <span>Low Stock</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/branch-overview" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="info" />
              <span>Branches</span>
            </NavLink>
          )}
          {hasAnyRole(['Admin', 'Manager']) && (
            <NavLink to="/agent-workflows" className={({isActive})=> isActive? 'active nav-item':'nav-item'}>
              <Icon name="predict" />
              <span>Agent Workflows</span>
            </NavLink>
          )}
        </nav>

        <div className="account">
          <div className="account-info">
            <div className="avatar">{(user?.id ?? user?.roles?.[0] ?? 'A').toString()[0]?.toUpperCase()}</div>
            <div className="account-meta">
                <div className="account-name">{user?.id ?? user?.roles?.[0] ?? 'Admin'}</div>
              <div className="account-roles">{user?.roles.join(', ')}</div>
            </div>
          </div>
          <button className="btn btn-ghost" onClick={signOut}>Sign out</button>
        </div>
      </header>
      <main className="container"><Outlet /></main>
    </div>
  );
}
