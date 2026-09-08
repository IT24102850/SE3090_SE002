import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';

export function AppLayout() {
  const { user, logout, hasAnyRole } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const { notify } = useToast();
  const [showSignOutDialog, setShowSignOutDialog] = useState(false);
  const [theme, setTheme] = useState<'dark' | 'light'>(() => {
    return (localStorage.getItem('upgradehub-theme') as 'dark' | 'light') || 'dark';
  });
  const [currentTime, setCurrentTime] = useState(new Date());

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    if (theme === 'light') {
      document.documentElement.classList.add('theme-light');
      document.documentElement.classList.remove('theme-dark');
      document.body.classList.add('theme-light');
      document.body.classList.remove('theme-dark');
    } else {
      document.documentElement.classList.add('theme-dark');
      document.documentElement.classList.remove('theme-light');
      document.body.classList.add('theme-dark');
      document.body.classList.remove('theme-light');
    }
    localStorage.setItem('upgradehub-theme', theme);
  }, [theme]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setCurrentTime(new Date());
    }, 1000);
    return () => window.clearInterval(timer);
  }, []);

  function toggleTheme() {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  }

  function confirmSignOut() {
    logout();
    notify('You have been safely signed out. See you next time!', 'success');
    navigate('/login');
  }

  // WebSocket connection to agent service for real-time toasts
  useEffect(() => {
    let ws: WebSocket | null = null;
    try {
      ws = new WebSocket(
        (window.location.protocol === 'https:' ? 'wss' : 'ws') +
          '://' +
          (window.location.hostname || 'localhost') +
          ':8000/ws/workflows'
      );
      ws.onmessage = (ev) => {
        try {
          const data = JSON.parse(ev.data || '{}');
          if (data?.type === 'workflow_update') {
            const act = data.actionType || data.action || 'workflow';
            const status = data.status || 'updated';
            const qty = data.tool_result?.quantity ?? data.tool_result?.qty;
            const backend = data.backend_result || data.tool_result?.backend_response;
            const msg = backend
              ? `PO placed (${backend?.number ?? backend?.id ?? 'id'})`
              : `${act} ${status}${qty ? ` · qty ${qty}` : ''}`;
            notify(msg, backend ? 'success' : status === 'blocked' ? 'error' : 'info');
          } else if (data?.type === 'workflow_approved') {
            const backend = data.backend_result;
            const msg = backend ? `PO ${backend?.number ?? backend?.id ?? 'placed'}` : 'Workflow approved';
            notify(msg, 'success');
          }
        } catch (e) {
          // ignore
        }
      };
      ws.onopen = () => {};
      ws.onclose = () => {};
    } catch (e) {
      // ignore
    }
    return () => {
      try {
        ws?.close();
      } catch (e) {}
    };
  }, []);

  const getPageEyebrow = () => {
    const path = location.pathname;
    if (path.startsWith('/analytics')) return 'SME INVENTORY // ENTERPRISE ANALYTICS';
    if (path.startsWith('/inventory')) return 'SME INVENTORY // STOCK MANAGEMENT';
    if (path.startsWith('/stock-movements')) return 'SME INVENTORY // INVENTORY AUDIT LOG';
    if (path.startsWith('/purchase-orders')) return 'SME INVENTORY // PROCUREMENT & POs';
    if (path.startsWith('/low-stock-alerts')) return 'SME INVENTORY // REAL-TIME RISK SIGNALS';
    if (path.startsWith('/branch-overview')) return 'SME INVENTORY // MULTI-OUTLET NETWORK';
    if (path.startsWith('/agent-workflows')) return 'SME INVENTORY // AGENTIC AI AUTOMATION';
    return 'SME INVENTORY // OPERATIONS';
  };

  const roleName = user?.roles?.[0] ?? 'Admin';
  const roleInitial = (user?.id ?? roleName ?? 'A').toString()[0]?.toUpperCase();

  return (
    <div className="app-shell">
      {/* Sleek Vertical Sidebar */}
      <aside className="sidebar" aria-label="Sidebar navigation">
        <NavLink className="brand" to="/inventory">
          <div className="brand-mark" aria-hidden="true">SME</div>
          <div className="brand-meta">
            <span className="brand-name">SME Inventory</span>
            <span className="brand-tagline">Stock • Procurement • Analytics</span>
          </div>
        </NavLink>

        <nav aria-label="Main navigation" className="nav-list">
          {hasAnyRole(['Admin', 'Manager']) && (
            <>
              <div className="sidebar-section-title">Overview & Intelligence</div>
              <NavLink to="/analytics" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
                <div className="nav-icon"><Icon name="chart" /></div>
                <span>Analytics</span>
              </NavLink>
            </>
          )}

          <div className="sidebar-section-title">Operations</div>
          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/inventory" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
              <div className="nav-icon"><Icon name="inventory" /></div>
              <span>Inventory</span>
            </NavLink>
          )}

          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/stock-movements" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
              <div className="nav-icon"><Icon name="history" /></div>
              <span>Stock Log</span>
            </NavLink>
          )}

          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/purchase-orders" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
              <div className="nav-icon"><Icon name="po" /></div>
              <span>Purchase Orders</span>
            </NavLink>
          )}

          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/low-stock-alerts" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
              <div className="nav-icon"><Icon name="alert" /></div>
              <span>Low Stock</span>
            </NavLink>
          )}

          {hasAnyRole(['Admin', 'Manager', 'Staff']) && (
            <NavLink to="/branch-overview" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
              <div className="nav-icon"><Icon name="branch" /></div>
              <span>Branches</span>
            </NavLink>
          )}

          {hasAnyRole(['Admin', 'Manager']) && (
            <>
              <div className="sidebar-section-title">Automation & AI</div>
              <NavLink to="/agent-workflows" className={({ isActive }) => (isActive ? 'active nav-item' : 'nav-item')}>
                <div className="nav-icon"><Icon name="workflow" /></div>
                <span>Agent Workflows</span>
              </NavLink>
            </>
          )}
        </nav>

        <div className="sidebar-footer">
          <div className="status-indicator">
            <span className="status-pulse-dot" aria-hidden="true" />
            <span>Real-time Sync Active</span>
          </div>

          <button
            type="button"
            className="theme-toggle-btn"
            onClick={toggleTheme}
            aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
          >
            <span>{theme === 'dark' ? 'Dark Mode' : 'Light Mode'}</span>
            <div className="theme-switch-icon">
              <Icon name={theme === 'dark' ? 'moon' : 'sun'} size={14} />
            </div>
          </button>

          <div className="sidebar-user-card">
            <div className="sidebar-user-avatar">{roleInitial}</div>
            <div className="sidebar-user-info">
              <span className="sidebar-user-name">{user?.id ?? 'Administrator'}</span>
              <span className="sidebar-user-role">{user?.roles?.join(', ') ?? 'Admin'}</span>
            </div>
            <button
              type="button"
              className="icon-btn-action"
              style={{ width: 30, height: 30, borderRadius: 8 }}
              title="Sign out"
              onClick={() => setShowSignOutDialog(true)}
            >
              <Icon name="logout" size={14} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="main-content">
        <header className="topbar">
          <div className="topbar-titles">
            <div className="topbar-eyebrow">
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--brand-primary)' }} />
              {getPageEyebrow()}
            </div>
          </div>

          <div className="topbar-actions">
            <div className="live-clock-badge" title="Live System Time">
              <Icon name="clock" size={15} />
              <span>{currentTime.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</span>
            </div>

            <div className="user-profile-badge">
              <div className="user-avatar">{roleInitial}</div>
              <span className="user-name">{user?.id ?? roleName}</span>
              <span className="badge badge-violet" style={{ fontSize: 10, padding: '2px 8px' }}>{roleName}</span>
            </div>

            <button
              className="btn btn-secondary"
              type="button"
              onClick={() => setShowSignOutDialog(true)}
              style={{ padding: '7px 14px', fontSize: 12.5 }}
            >
              Sign out
            </button>
          </div>
        </header>

        <main className="container">
          <Outlet />
        </main>
      </div>

      {showSignOutDialog && (
        <div className="modal-overlay" onClick={() => setShowSignOutDialog(false)} role="presentation">
          <section
            className="modal modal-sm signout-modal"
            onClick={(event) => event.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-labelledby="signout-title"
          >
            <div className="signout-icon" aria-hidden="true">
              <Icon name="logout" size={24} />
            </div>
            <h2 id="signout-title">Ready to sign out?</h2>
            <p>Your work and session cache are safely synchronized. You can sign back in whenever you’re ready.</p>
            <div className="modal-actions">
              <button className="btn btn-secondary" type="button" onClick={() => setShowSignOutDialog(false)}>
                Stay signed in
              </button>
              <button className="btn btn-primary" type="button" onClick={confirmSignOut}>
                Sign out
              </button>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
