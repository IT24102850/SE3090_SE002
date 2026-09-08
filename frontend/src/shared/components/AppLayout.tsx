import { NavLink, useNavigate, useLocation } from 'react-router-dom';
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

interface NavSection {
  id: string;
  label: string;
  items: NavItem[];
}

/* Sections are the ONLY nav definition — there is no separate flat list to
   fall out of sync with, so an item cannot be dropped by regrouping. All 19
   destinations that had a sidebar entry still have one; nothing was removed,
   merged or hidden behind a "more" affordance. scripts/check-nav-parity.mjs
   asserts that against the router's own paths and runs as part of the build. */
const NAV_SECTIONS: NavSection[] = [
  {
    id: 'overview',
    label: 'Overview',
    items: [
      { path: '/dashboard', label: 'Dashboard', icon: '📊', roles: ['Admin', 'Manager', 'Staff', 'Customer'] },
      { path: '/reports', label: 'Reports', icon: '📈', roles: ['Admin', 'Manager'] },
    ],
  },
  {
    id: 'scheduling',
    label: 'Scheduling',
    items: [
      { path: '/bookings', label: 'Booking Manager', icon: '📅', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/my-schedule', label: 'My Schedule', icon: '🩺', roles: ['Staff'] },
      { path: '/multi-branch', label: 'Multi-Branch Schedule', icon: '🗂️', roles: ['Admin', 'Manager'] },
      { path: '/booking-types', label: 'Booking Types', icon: '🏷️', roles: ['Admin', 'Manager'] },
    ],
  },
  {
    id: 'resources',
    label: 'Resources',
    items: [
      { path: '/resources', label: 'Resource Manager', icon: '🏢', roles: ['Admin', 'Manager'] },
      { path: '/staff', label: 'Staff', icon: '🧑‍💼', roles: ['Admin', 'Manager'] },
      { path: '/branches', label: 'Branches', icon: '📍', roles: ['Admin'] },
    ],
  },
  {
    id: 'inventory',
    label: 'Inventory',
    items: [
      { path: '/inventory', label: 'Inventory Manager', icon: '📦', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/stock-movements', label: 'Stock Movements', icon: '🔄', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/purchase-orders', label: 'Purchase Orders', icon: '🧾', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/low-stock-alerts', label: 'Low Stock Alerts', icon: '⚠️', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/branch-overview', label: 'Branch Overview', icon: '🏬', roles: ['Admin', 'Manager', 'Staff'] },
      { path: '/inventory-analytics', label: 'Inventory Analytics', icon: '📉', roles: ['Admin', 'Manager'] },
    ],
  },
  {
    id: 'automation',
    label: 'Automation',
    items: [
      { path: '/planner', label: 'AI Planner', icon: '🤖', roles: ['Admin', 'Manager'] },
      { path: '/agent-workflows', label: 'Agent Workflows', icon: '🛰️', roles: ['Admin', 'Manager', 'Staff'] },
    ],
  },
  {
    id: 'business',
    label: 'Business',
    items: [
      { path: '/business-profile', label: 'Business Profile', icon: '🏪', roles: ['Admin', 'Manager'] },
      { path: '/settings', label: 'Business Settings', icon: '⚙️', roles: ['Admin'] },
    ],
  },
];

/** Every nav path, in sidebar order. Exported for the parity test. */
export const ALL_NAV_PATHS = NAV_SECTIONS.flatMap((s) => s.items.map((i) => i.path));

export default function AppLayout({ children }: { children: ReactNode }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  // Role filtering happens inside each section; a section whose items are all
  // filtered out disappears rather than leaving an empty heading.
  const sections = NAV_SECTIONS
    .map((section) => ({
      ...section,
      items: section.items.filter((item) => !user || item.roles.includes(user.role)),
    }))
    .filter((section) => section.items.length > 0);

  const activeSectionId = sections.find((s) => s.items.some((i) => i.path === location.pathname))?.id;

  // Collapsed by default except the section you are in, so the list stays
  // short without putting anything more than one click away. Once the user
  // opens a section it stays open while they navigate — `null` means
  // "untouched", so the active section keeps auto-following the route.
  const [openIds, setOpenIds] = useState<Set<string> | null>(null);
  const isOpen = (id: string) => (openIds ? openIds.has(id) : id === activeSectionId);
  const toggleSection = (id: string) => {
    setOpenIds((prev) => {
      const next = new Set(prev ?? (activeSectionId ? [activeSectionId] : []));
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

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
          <img className="sidebar-brand-mark" src="/unify-logo.svg" alt="" width={32} height={32} />
          Unify
        </div>
        <nav className="sidebar-nav">
          {sections.map((section) => {
            const open = isOpen(section.id);
            const hasActive = section.id === activeSectionId;
            return (
              <div key={section.id} className="sidebar-section">
                <button
                  type="button"
                  className={`sidebar-section-header${hasActive ? ' has-active' : ''}`}
                  aria-expanded={open}
                  aria-controls={`nav-section-${section.id}`}
                  onClick={() => toggleSection(section.id)}
                >
                  <span className="sidebar-section-label">{section.label}</span>
                  <span className="sidebar-section-count">{section.items.length}</span>
                  <span className={`sidebar-section-chevron${open ? ' open' : ''}`} aria-hidden="true">›</span>
                </button>
                {open && (
                  <div className="sidebar-section-items" id={`nav-section-${section.id}`}>
                    {section.items.map((item) => (
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
                  </div>
                )}
              </div>
            );
          })}
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
