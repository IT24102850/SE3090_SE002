import { NavLink, useNavigate, useLocation } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { useEffect, useState, type ReactNode } from 'react';
import { RootState } from '../../store/store';
import { logout } from '../../store/authSlice';
import NotificationBell from './NotificationBell';
import { bookingApi, useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import { resetSubtypeCache } from '../../features/dashboard/subtype';
import { useSubtypeConfig } from '../../features/dashboard/useSubtypeConfig';
import { useToast } from './Toast';
import WorkspaceAssistant from './WorkspaceAssistant';
import UserAvatar from './UserAvatar';
import BusinessAvatar from './BusinessAvatar';

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
  // The top-bar chip carries the business's identity - its logo from
  // Settings -> Business Profile - rather than the person's photo, which
  // stays on the sidebar profile link. Skipped until someone is signed in.
  const chipTenantId = user?.tenantId ?? '';
  const { data: chipTenant } = useGetTenantQuery({ tenantId: chipTenantId }, { skip: !chipTenantId });
  const { data: chipProfile } = useGetTenantProfileQuery({ tenantId: chipTenantId }, { skip: !chipTenantId });
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [theme, setTheme] = useState(() => localStorage.getItem('unify-theme') || 'light');
  const [themeMenuOpen, setThemeMenuOpen] = useState(false);
  const [logoutConfirmOpen, setLogoutConfirmOpen] = useState(false);
  // The rail is viewport-height, so below the nav there is room for one
  // useful card. Dismissed once, it stays dismissed on this browser.
  const [tipDismissed, setTipDismissed] = useState(() => {
    try { return localStorage.getItem('unify-sidebar-tip-widget') === '1'; } catch { return false; }
  });
  const dismissTip = () => {
    setTipDismissed(true);
    try { localStorage.setItem('unify-sidebar-tip-widget', '1'); } catch { /* private mode */ }
  };
  const { show } = useToast();

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem('unify-theme', theme);
  }, [theme]);

  // Role filtering happens inside each section; a section whose items are all
  // filtered out disappears rather than leaving an empty heading.
  // Destinations are renamed to the tenant's own vocabulary - "Resources"
  // becomes "Vessels & Crew" for a whale-watching operator, "Rooms" for a
  // homestay. A sub-type's explicit navOverrides win; otherwise the generic
  // resource/booking/equipment terms are used. Only labels and icons change,
  // never paths, so scripts/check-nav-parity.mjs still matches every route.
  const subtype = useSubtypeConfig();
  const termLabels: Record<string, string> = {
    '/resources': subtype.resourceTermPlural,
    '/bookings': subtype.bookingTermPlural,
    '/inventory': subtype.equipmentTerm,
  };
  const overrides = subtype.navOverrides ?? {};

  const sections = NAV_SECTIONS
    .map((section) => ({
      ...section,
      items: section.items
        .filter((item) => !user || item.roles.includes(user.role))
        .map((item) => {
          const override = overrides[item.path];
          return {
            ...item,
            label: override?.label ?? termLabels[item.path] ?? item.label,
            icon: override?.icon ?? item.icon,
          };
        }),
    }))
    .filter((section) => section.items.length > 0);

  const activeSectionId = sections.find((s) => s.items.some((i) => i.path === location.pathname))?.id;
  // A small thumb-zone nav gives phone users the three places they use most
  // without asking them to open the full drawer for every move. The drawer
  // remains the source of truth for all destinations.
  const mobileQuickLinks = [
    sections.flatMap((section) => section.items).find((item) => item.path === '/dashboard'),
    sections.find((section) => section.id === 'scheduling')?.items[0],
    sections.find((section) => section.id === 'inventory')?.items[0],
  ].filter((item): item is NavItem => Boolean(item));
  const pageName = location.pathname === '/inventory-analytics'
    ? 'ENTERPRISE ANALYTICS'
    : location.pathname === '/inventory'
      ? 'STOCK MANAGEMENT'
      : location.pathname.replace('/', '').replace(/-/g, ' ').toUpperCase() || 'OPERATIONS';
  const pageCategory = location.pathname.startsWith('/inventory') || location.pathname === '/purchase-orders' || location.pathname === '/stock-movements' || location.pathname === '/low-stock-alerts' || location.pathname === '/branch-overview'
    ? 'inventory'
    : location.pathname === '/planner' || location.pathname === '/agent-workflows'
      ? 'automation'
      : location.pathname === '/resources' || location.pathname === '/staff' || location.pathname === '/branches'
        ? 'resources'
        : location.pathname === '/bookings' || location.pathname === '/my-schedule' || location.pathname === '/multi-branch' || location.pathname === '/booking-types'
          ? 'scheduling'
          : location.pathname === '/business-profile' || location.pathname === '/settings'
            ? 'business'
            : 'overview';

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
    // Both caches are keyed to the tenant that just logged out. RTK Query
    // keeps its store across a logout, and the sub-type is memoised in a
    // module variable, so without these two the next tenant to sign in on
    // this browser sees the previous tenant's dashboard, sidebar labels and
    // list data until a hard refresh.
    dispatch(bookingApi.util.resetApiState());
    resetSubtypeCache();
    show('You have been signed out safely. See you next time!', 'success');
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
          <img className="sidebar-brand-mark" src="/unify-logo.svg" alt="" width={46} height={46} />
          <span>
            <strong>Unify</strong>
            <small>Innovate · Adapt · Operate</small>
          </span>
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
                        <span className="sidebar-link-icon" aria-hidden="true">{item.icon}</span>
                        <span>{item.label}</span>
                      </NavLink>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </nav>
        {user && !tipDismissed && (user.role === 'Admin' || user.role === 'Manager') && (
          <div className="sidebar-tip" role="note">
            <button type="button" className="sidebar-tip-close" aria-label="Dismiss" onClick={dismissTip}>×</button>
            <div className="sidebar-tip-eyebrow">Website bookings</div>
            <div className="sidebar-tip-title">Take reservations on your own site</div>
            <p className="sidebar-tip-body">Paste a two-line snippet and bookings land here, pending your approval.</p>
            <NavLink to="/settings" className="sidebar-tip-cta" onClick={() => setMobileNavOpen(false)}>Get the snippet →</NavLink>
          </div>
        )}
        {user && (
          <div className="sidebar-footer">
            <NavLink
              to="/profile"
              onClick={() => setMobileNavOpen(false)}
              style={{ display: 'flex', alignItems: 'center', gap: 10, textDecoration: 'none', color: 'inherit', marginBottom: 10 }}
            >
              <UserAvatar
                name={user.fullName}
                email={user.email}
                src={user.profilePictureUrl}
                size={36}
                className="sidebar-avatar"
              />
              <span>
                <div className="sidebar-user">{user.fullName}</div>
                <div className="sidebar-role">{user.role}</div>
              </span>
            </NavLink>
            <button className="sidebar-logout" onClick={() => setLogoutConfirmOpen(true)}>Log out</button>
          </div>
        )}
      </aside>
      <div className="app-main">
        {user && <header className="app-topbar">
          <div className="app-breadcrumb">
            <span className="app-breadcrumb-dot" />
            <strong>UNIFY</strong>
            <span>//</span>
            <span>{pageName}</span>
          </div>
          <div className="app-topbar-actions">
            <NavLink to="/dashboard" className="app-home" title="Go to dashboard">
              <span aria-hidden="true">⌂</span>
              <span>Home</span>
            </NavLink>
            <label className="theme-select" title="Choose theme">
              <span className="theme-select-icon" aria-hidden="true">◐</span>
              <span className="theme-select-label">Theme</span>
              <button type="button" className="theme-select-trigger" aria-haspopup="listbox" aria-expanded={themeMenuOpen} onClick={() => setThemeMenuOpen((open) => !open)}>
                {theme === 'dark' ? 'Dark theme' : theme === 'light' ? 'Light theme' : 'System theme'}
                <span className="theme-select-chevron" aria-hidden="true" />
              </button>
              {themeMenuOpen && <div className="theme-menu" role="listbox" aria-label="Choose theme">
                {[
                  ['light', 'Light theme'],
                  ['dark', 'Dark theme'],
                  ['system', 'System theme'],
                ].map(([value, label]) => (
                  <button type="button" role="option" aria-selected={theme === value} className={`theme-menu-option${theme === value ? ' selected' : ''}`} key={value} onClick={() => { setTheme(value); setThemeMenuOpen(false); }}>
                    <span>{theme === value ? '✓' : ''}</span>{label}
                  </button>
                ))}
              </div>}
            </label>
            <span className="app-clock" aria-label="Current time">◷ {new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
            <NavLink to="/profile" className="app-user-chip" title={chipTenant?.name ? `${chipTenant.name} · ${user.fullName || user.email}` : undefined}>
              <BusinessAvatar name={chipTenant?.name} src={chipProfile?.logoUrl} size={27} className="app-user-avatar" />
              <strong>{user.fullName || user.email}</strong>
              <span className="app-role-chip">{user.role}</span>
            </NavLink>
            <button className="app-signout" onClick={() => setLogoutConfirmOpen(true)}>Sign out</button>
            <NotificationBell />
          </div>
        </header>}
        <div className={`app-content page-category-${pageCategory}`}>{children}</div>
        {user && <footer className="app-footer">
          <span><b>UNIFY</b> · Your work, in flow</span>
          <span className="app-footer-status"><i /> Workspace synced</span>
          <nav aria-label="Footer navigation"><NavLink to="/dashboard">Home</NavLink><NavLink to="/profile">Profile</NavLink><button type="button" onClick={() => setLogoutConfirmOpen(true)}>Sign out</button></nav>
        </footer>}
        {user && (
          <nav className="mobile-quick-nav" aria-label="Quick navigation">
            {mobileQuickLinks.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                className={({ isActive }) => `mobile-quick-link${isActive ? ' active' : ''}`}
              >
                <span aria-hidden="true">{item.icon}</span>
                <small>{item.label.replace(' Manager', '')}</small>
              </NavLink>
            ))}
            <button type="button" className="mobile-quick-link mobile-quick-more" onClick={() => setMobileNavOpen(true)}>
              <span aria-hidden="true">•••</span>
              <small>More</small>
            </button>
          </nav>
        )}
      </div>
      {user && <WorkspaceAssistant />}
      {logoutConfirmOpen && (
        <div className="confirm-backdrop" role="presentation" onMouseDown={() => setLogoutConfirmOpen(false)}>
          <section className="confirm-dialog" role="dialog" aria-modal="true" aria-labelledby="logout-title" onMouseDown={(event) => event.stopPropagation()}>
            <div className="confirm-dialog-icon" aria-hidden="true">↗</div>
            <p className="confirm-dialog-kicker">READY TO WRAP UP?</p>
            <h2 id="logout-title">Sign out of your workspace?</h2>
            <p>Your session will be closed on this device. Your work and updates are already saved.</p>
            <div className="confirm-dialog-actions"><button type="button" className="btn btn-secondary" onClick={() => setLogoutConfirmOpen(false)}>Stay signed in</button><button type="button" className="btn btn-primary" onClick={handleLogout}>Yes, sign me out</button></div>
          </section>
        </div>
      )}
    </div>
  );
}
