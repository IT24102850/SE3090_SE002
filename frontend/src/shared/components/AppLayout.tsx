import { NavLink, useNavigate } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { useState, type ReactNode } from 'react';
import { RootState } from '../../store/store';
import { logout } from '../../store/authSlice';
import NotificationBell from './NotificationBell';

interface NavItem {
  path: string;
  label: string;
  icon: string;
  roles: string[];
}

const NAV_ITEMS: NavItem[] = [
  { path: '/dashboard', label: 'Dashboard', icon: '📊', roles: ['Admin', 'Manager', 'Staff', 'Customer'] },
  { path: '/bookings', label: 'Booking Manager', icon: '📅', roles: ['Admin', 'Manager', 'Staff'] },
  { path: '/my-schedule', label: 'My Schedule', icon: '🩺', roles: ['Staff'] },
  { path: '/resources', label: 'Resource Manager', icon: '🏢', roles: ['Admin', 'Manager'] },
  { path: '/multi-branch', label: 'Multi-Branch Schedule', icon: '🗂️', roles: ['Admin', 'Manager'] },
  { path: '/reports', label: 'Reports', icon: '📈', roles: ['Admin', 'Manager'] },
  { path: '/planner', label: 'AI Planner', icon: '🤖', roles: ['Admin', 'Manager'] },
  { path: '/booking-types', label: 'Booking Types', icon: '🏷️', roles: ['Admin', 'Manager'] },
  { path: '/staff', label: 'Staff', icon: '🧑‍💼', roles: ['Admin', 'Manager'] },
  { path: '/branches', label: 'Branches', icon: '📍', roles: ['Admin'] },
  { path: '/business-profile', label: 'Business Profile', icon: '🏪', roles: ['Admin', 'Manager'] },
  { path: '/settings', label: 'Business Settings', icon: '⚙️', roles: ['Admin'] },
];

export default function AppLayout({ children }: { children: ReactNode }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  const items = NAV_ITEMS.filter((item) => !user || item.roles.includes(user.role));

  const handleLogout = () => {
    dispatch(logout());
    navigate('/login');
  };

  return (
    <div className="app-shell">
      <button
        type="button"
        className="mobile-menu-toggle"
        aria-label={mobileNavOpen ? 'Close menu' : 'Open menu'}
        aria-expanded={mobileNavOpen}
        onClick={() => setMobileNavOpen((open) => !open)}
      >
        <span className={`hamburger-icon${mobileNavOpen ? ' open' : ''}`}>
          <span />
          <span />
          <span />
        </span>
      </button>
      {mobileNavOpen && (
        <div className="sidebar-overlay" onClick={() => setMobileNavOpen(false)} />
      )}
      <aside className={`sidebar${mobileNavOpen ? ' open' : ''}`}>
        <div className="sidebar-brand">
          <span className="sidebar-brand-mark">⬢</span>
          SME Platform
        </div>
        <nav className="sidebar-nav">
          {items.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => `sidebar-link${isActive ? ' active' : ''}`}
              onClick={() => setMobileNavOpen(false)}
            >
              <span>{item.icon}</span>
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        {user && (
          <div className="sidebar-footer">
            <NavLink
              to="/profile"
              onClick={() => setMobileNavOpen(false)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, textDecoration: 'none', color: 'inherit', marginBottom: 10 }}
            >
              <span
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: '50%',
                  overflow: 'hidden',
                  flexShrink: 0,
                  background: 'rgba(255,255,255,0.12)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 13,
                  fontWeight: 700,
                }}
              >
                {user.profilePictureUrl ? (
                  <img src={user.profilePictureUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                ) : (
                  (user.fullName || user.email || '?')
                    .trim()
                    .split(/\s+/)
                    .slice(0, 2)
                    .map((p) => p[0]?.toUpperCase())
                    .join('')
                )}
              </span>
              <span>
                <div className="sidebar-user">{user.fullName}</div>
                <div className="sidebar-role">{user.role}</div>
              </span>
            </NavLink>
            <button className="sidebar-logout" onClick={handleLogout}>Log out</button>
          </div>
        )}
      </aside>
      <div className="app-main">
        {user && (
          <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '12px 24px 0' }}>
            <NotificationBell />
          </div>
        )}
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}
