import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import InventoryWorkspaceNav from './InventoryWorkspaceNav';

let role = 'Admin';
vi.mock('react-redux', async (importOriginal) => ({
  ...await importOriginal<typeof import('react-redux')>(),
  useSelector: (selector: (state: unknown) => unknown) => selector({ auth: { user: { role } } }),
}));

function renderNav(path = '/inventory') {
  return render(<MemoryRouter initialEntries={[path]}><InventoryWorkspaceNav /></MemoryRouter>);
}

describe('Inventory workspace navigation', () => {
  it('marks the current inventory destination', () => {
    role = 'Admin';
    renderNav('/purchase-orders');
    expect(screen.getByRole('link', { name: 'Purchase Orders' })).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: 'Inventory Manager' })).not.toHaveAttribute('aria-current');
  });

  it('hides analytics from staff while keeping supplier access', () => {
    role = 'Staff';
    renderNav();
    expect(screen.queryByRole('link', { name: 'Inventory Analytics' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Branch Performance' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Suppliers' })).toBeInTheDocument();
  });

  it('hides suppliers from managers while keeping analytics access', () => {
    role = 'Manager';
    renderNav();
    expect(screen.queryByRole('link', { name: 'Suppliers' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Inventory Analytics' })).toBeInTheDocument();
  });

  it('does not show inventory navigation on user management', () => {
    role = 'Admin';
    renderNav('/manage-users');
    expect(screen.queryByRole('navigation', { name: 'Inventory workspace' })).not.toBeInTheDocument();
  });
});