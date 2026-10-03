import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { Navigate, NavLink, useLocation, useNavigate } from 'react-router-dom';
import { useDispatch } from 'react-redux';
import { platformApi, useLogoutMutation } from './platformApi';
import { clearPlatformSession, decodePlatformUser, getIdleMinutes, getPlatformExpiry, getPlatformToken, isPlatformSessionLive } from './platformSession';
import './platform.css';

/* Shell for every platform console page. Also the client half of the
 * session rules: it redirects to sign-in when there is no live token,
 * counts the hard expiry down in the rail, and signs out on its own after
 * the idle timeout - the server enforces both anyway; this just means the
 * owner is never surprised by a dead request. */

const NAV = [
  { path: '/platform', label: 'Overview', icon: '◎', end: true },
  { path: '/platform/tenants', label: 'Tenants', icon: '🏢' },
  { path: '/platform/users', label: 'Users', icon: '👥' },
  { path: '/platform/audit', label: 'Audit log', icon: '🧾' },
  { path: '/platform/security', label: 'Security', icon: '🔐' },
];

function useCountdown(target: Date | null) {
  const [left, setLeft] = useState(() => (target ? target.getTime() - Date.now() : 0));
  useEffect(() => {
    if (!target) return;
    const id = window.setInterval(() => setLeft(target.getTime() - Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [target]);
  return Math.max(0, left);
}

const fmt = (ms: number) => {
  const s = Math.floor(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

export default function PlatformLayout({ children, title }: { children: ReactNode; title: string }) {
  const navigate = useNavigate();
  const location = useLocation();
  const dispatch = useDispatch();
  const [logout] = useLogoutMutation();
  const live = isPlatformSessionLive();
  const user = decodePlatformUser();
  const expiry = getPlatformExpiry();
  const idleMinutes = getIdleMinutes();
  const remaining = useCountdown(live ? expiry : null);
  const [idleLeft, setIdleLeft] = useState(idleMinutes * 60 * 1000);
  const lastActivity = useRef(Date.now());

  useEffect(() => {
    document.documentElement.dataset.theme = localStorage.getItem('unify-theme') || 'light';
  }, []);

  const signOut = useCallback(async (reason?: string) => {
    try { await logout().unwrap(); } catch { /* the session may already be gone; leaving is the point */ }
    clearPlatformSession();
    dispatch(platformApi.util.resetApiState());
    navigate(reason ? `/platform/login?reason=${reason}` : '/platform/login', { replace: true });
  }, [dispatch, logout, navigate]);

  // Idle timer: any interaction resets it; hitting zero signs out.
  useEffect(() => {
    if (!live) return;
    const bump = () => { lastActivity.current = Date.now(); };
    const events: (keyof WindowEventMap)[] = ['mousemove', 'keydown', 'click', 'scroll', 'touchstart'];
    events.forEach((e) => window.addEventListener(e, bump, { passive: true }));
    const id = window.setInterval(() => {
      const left = idleMinutes * 60 * 1000 - (Date.now() - lastActivity.current);
      setIdleLeft(Math.max(0, left));
      if (left <= 0) void signOut('expired');
    }, 1000);
    return () => { events.forEach((e) => window.removeEventListener(e, bump)); window.clearInterval(id); };
  }, [live, idleMinutes, signOut]);

  // Hard expiry reached while the tab sat open.
  useEffect(() => {
    if (live && expiry && remaining === 0) void signOut('expired');
  }, [live, expiry, remaining, signOut]);

  // No token at all means they simply have not signed in; a dead token
  // means the session ended, which is worth saying.
  if (!live) return <Navigate to={getPlatformToken() ? '/platform/login?reason=expired' : '/platform/login'} replace />;

  const total = 60 * 60 * 1000;
  const pct = Math.min(100, Math.max(0, (remaining / total) * 100));
  const idleWarn = idleLeft < 2 * 60 * 1000;

  return (
    <div className="pf-shell">
      <aside className="pf-rail">
        <NavLink to="/platform" className="pf-brand">
          <span className="pf-brand-mark" aria-hidden="true">🛡️</span>
          <span><strong>Unify</strong><small>Platform console</small></span>
        </NavLink>
        <nav className="pf-nav" aria-label="Platform console">
          <div className="pf-nav-label">Console</div>
          {NAV.map((item) => (
            <NavLink key={item.path} to={item.path} end={item.end} className={({ isActive }) => `pf-link${isActive ? ' active' : ''}`}>
              <span className="pf-link-icon" aria-hidden="true">{item.icon}</span>
              <span>{item.label}</span>
            </NavLink>
          ))}
          <div className="pf-nav-label">Elsewhere</div>
          <NavLink to="/login" className="pf-link"><span className="pf-link-icon" aria-hidden="true">↗</span><span>Workspace sign-in</span></NavLink>
        </nav>
        <div className="pf-rail-foot">
          <div className="pf-session" aria-live="polite">
            <div className="pf-session-row"><span>Session ends in</span><b>{fmt(remaining)}</b></div>
            <div className={`pf-session-row${idleWarn ? ' warn' : ''}`}><span>Idle sign-out in</span><b>{fmt(idleLeft)}</b></div>
            <div className="pf-session-bar"><i style={{ width: `${pct}%` }} /></div>
          </div>
          <strong>{user?.fullName || 'Platform owner'}</strong>
          <span className="pf-muted">{user?.email}</span>
          <button type="button" className="pf-signout" onClick={() => void signOut()}>Sign out</button>
        </div>
      </aside>
      <div className="pf-main">
        <header className="pf-topbar">
          <div className="pf-crumb"><b>Platform</b><span>//</span><span>{title}</span></div>
          <div className="pf-topbar-actions">
            <span className={`pf-chip${idleWarn ? ' warn' : ''}`}><i aria-hidden="true" />{idleWarn ? 'Idle - signing out soon' : 'MFA session · encrypted'}</span>
            <span className="pf-chip" title={location.pathname}>{user?.role}</span>
          </div>
        </header>
        <div className="pf-content">{children}</div>
      </div>
    </div>
  );
}
