import { NavLink, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import { NAV_SECTIONS } from '../../../shared/components/AppLayout';
import { Icon } from './Icon';

const inventoryDestinations = NAV_SECTIONS.find((section) => section.id === 'inventory')?.items ?? [];

export default function InventoryWorkspaceNav() {
  const { pathname } = useLocation();
  const role = useSelector((state: RootState) => state.auth.user?.role);
  // InventoryShell also hosts user management; keep this navigation on inventory routes.
  if (!role || !inventoryDestinations.some((item) => item.path === pathname)) return null;
  const destinations = inventoryDestinations.filter((item) => item.roles.includes(role));

  return (
    <div className="inventory-workspace-nav">
      <div className="inventory-workspace-label"><Icon name="box" size={18} /><span>Inventory workspace</span></div>
      <nav aria-label="Inventory workspace" className="inventory-workspace-links">
        {destinations.map((item) => <NavLink key={item.path} to={item.path} end className={({ isActive }) => `inventory-workspace-link${isActive ? ' is-current' : ''}`}>{item.label}</NavLink>)}
      </nav>
    </div>
  );
}