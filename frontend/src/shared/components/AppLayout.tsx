import { NavLink, useNavigate } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import type { ReactNode } from 'react';
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
  { path: '/settings', label: 'Business Settings', icon: '⚙️', roles: ['Admin'] },
];

export default function AppLayout({ children }: { children: ReactNode }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();
  const navigate = useNavigate();

  const items = NAV_ITEMS.filter((item) => !user || item.roles.includes(user.role));

  const handleLogout = () => {
    dispatch(logout());
    navigate('/login');
  };

  return (
    <div className="app-shell">
      <aside className="sidebar">
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
            >
              <span>{item.icon}</span>
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        {user && (
          <div className="sidebar-footer">
            <div className="sidebar-user">{user.fullName}</div>
            <div className="sidebar-role">{user.role}</div>
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
