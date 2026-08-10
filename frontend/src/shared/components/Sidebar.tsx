import React from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

interface NavItem {
  path: string;
  label: string;
  icon: string;
  roles: string[];
}

export const Sidebar: React.FC = () => {
  const { hasRole } = useAuth();

  const navItems: NavItem[] = [
    { path: '/dashboard', label: 'Dashboard', icon: '📊', roles: ['Admin', 'Manager', 'Staff', 'Customer'] },
    { path: '/bookings', label: 'Bookings', icon: '📅', roles: ['Admin', 'Manager', 'Staff'] },
    { path: '/resources', label: 'Resources', icon: '🏢', roles: ['Admin', 'Manager'] },
    { path: '/bulk-schedule', label: 'Bulk Schedule', icon: '⚡', roles: ['Admin', 'Manager'] },
    { path: '/agent-workflows', label: 'AI Workflows', icon: '🤖', roles: ['Admin', 'Manager', 'Staff'] },
    { path: '/my-bookings', label: 'My Bookings', icon: '🎫', roles: ['Customer'] },
    { path: '/settings', label: 'Settings', icon: '⚙️', roles: ['Admin', 'Manager', 'Staff', 'Customer'] },
  ];

  const filteredItems = navItems.filter(item => hasRole(item.roles));

  return (
    <nav className="sidebar" style={{ padding: '1rem', background: '#f5f5f5', minHeight: '100vh', width: '220px' }}>
      <h3 style={{ marginBottom: '1rem' }}>Menu</h3>
      {filteredItems.map(item => (
        <NavLink
          key={item.path}
          to={item.path}
          style={({ isActive }) => ({
            display: 'block',
            padding: '0.6rem 0.5rem',
            textDecoration: 'none',
            color: isActive ? '#1976d2' : '#333',
            fontWeight: isActive ? 'bold' : 'normal',
            borderRadius: '4px',
            marginBottom: '0.25rem',
          })}
        >
          {item.icon} {item.label}
        </NavLink>
      ))}
    </nav>
  );
};