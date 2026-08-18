import { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';

export function AppLayout() {
  const { user, logout, hasAnyRole } = useAuth();
  const navigate = useNavigate();
  const { notify } = useToast();
  const [showSignOutDialog, setShowSignOutDialog] = useState(false);

  function confirmSignOut() {
    logout();
    notify('You have been safely signed out. See you next time!', 'success');
    navigate('/login');
  }

  // WebSocket connection to agent service for real-time toasts
  useEffect(() => {
    let ws: WebSocket | null = null;
    try {
      ws = new WebSocket((window.location.protocol === 'https:' ? 'wss' : 'ws') + '://' + (window.location.hostname || 'localhost') + ':8000/ws/workflows');
      ws.onmessage = (ev) => {
        try {
          const data = JSON.parse(ev.data || '{}');
          if (data?.type === 'workflow_update') {
            const act = data.actionType || data.action || 'workflow';
            const status = data.status || 'updated';
            const qty = data.tool_result?.quantity ?? data.tool_result?.qty;
            const backend = data.backend_result || data.tool_result?.backend_response;
            const msg = backend ? `PO placed (${backend?.number ?? backend?.id ?? 'id'})` : `${act} ${status}${qty ? ` · qty ${qty}` : ''}`;
            notify(msg, backend ? 'success' : (status === 'blocked' ? 'error' : 'info'));
          } else if (data?.type === 'workflow_approved') {
            const backend = data.backend_result;
            const msg = backend ? `PO ${backend?.number ?? backend?.id ?? 'placed'}` : 'Workflow approved';
            notify(msg, 'success');
          }
        } catch (e) {
          // ignore
        }
      };
      ws.onopen = () => {
        // optionally send a ping/subscribe
      };
      ws.onclose = () => { /* reconnect logic could be added here */ };
    } catch (e) {
      // ignore
    }
    return () => { try { ws?.close(); } catch (e) {} };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="app-shell">
      <header className="topbar">
        <NavLink className="brand" to="/inventory">
          <span className="brand-mark">SM</span>
          <span className="brand-text">SME Platform <small style={{display:'block', fontSize:12, fontWeight:600, color:'rgba(255,255,255,.85)'}}>Inventory • Analytics • Intelligence</small></span>
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
          <button className="btn btn-secondary" type="button" onClick={() => setShowSignOutDialog(true)}>Sign out</button>
        </div>
      </header>
      <main className="container"><Outlet /></main>
      {showSignOutDialog && (
        <div className="modal-overlay" onClick={() => setShowSignOutDialog(false)} role="presentation">
          <section className="modal modal-sm signout-modal" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="signout-title">
            <div className="signout-icon" aria-hidden="true">↗</div>
            <h2 id="signout-title">Ready to sign out?</h2>
            <p>Your work is saved. You can sign back in whenever you’re ready.</p>
            <div className="modal-actions">
              <button className="btn btn-secondary" type="button" onClick={() => setShowSignOutDialog(false)}>Stay signed in</button>
              <button className="btn btn-primary" type="button" onClick={confirmSignOut}>Sign out</button>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
