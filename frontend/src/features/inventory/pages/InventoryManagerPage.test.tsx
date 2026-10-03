import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { ConfirmationProvider } from '../../../shared/components/ConfirmationProvider';
import { InventoryManagerPage } from './InventoryManagerPage';

const itemId = '6aa6b7bd-32d6-44be-9382-fb2e790375f2';

function renderPage(userOverrides: { role?: 'Admin' | 'Manager' | 'Staff'; branchId?: string } = {}) {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: {
        user: {
          id: 'user-1',
          email: 'manager@example.test',
          fullName: 'Test Manager',
          role: userOverrides.role ?? 'Manager' as const,
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          ...userOverrides,
        },
        token: 'test-token',
        isAuthenticated: true,
        loading: false,
        error: null,
      },
    },
  });

  return render(
    <Provider store={store}>
      <AppToastProvider>
        <ToastProvider>
          <MemoryRouter>
            <ConfirmationProvider><InventoryManagerPage /></ConfirmationProvider>
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

describe('InventoryManagerPage price editing', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('saves a selling price for an existing uncategorized item', async () => {
    let item: Record<string, unknown> = {
      id: itemId,
      name: 'Tea Leaves',
      sku: 'TEA-001',
      categoryId: null,
      category: null,
      unitId: null,
      unit: null,
      branchId: 'branch-1',
      branch: 'Main branch',
      quantity: 12,
      reorderLevel: 2,
      unitCost: 50,
      sellingPrice: null,
    };
    let updateBody: Record<string, unknown> | undefined;

    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === '/api/inventory/categories') {
        return new Response(JSON.stringify([{ id: 'category-1', name: 'Tea' }]), { status: 200 });
      }
      if (url === '/api/inventory/branches') {
        return new Response(JSON.stringify([{ id: 'branch-1', name: 'Main branch' }]), { status: 200 });
      }
      if (url === '/api/suppliers') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items: [item], totalPages: 1 }), { status: 200 });
      }
      if (url.startsWith('/api/inventory/') && init?.method === 'PUT') {
        updateBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        item = { ...item, sellingPrice: Number(updateBody.sellingPrice) };
        return new Response(JSON.stringify(item), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    await screen.findByText('Tea Leaves');

    fireEvent.click(screen.getByRole('button', { name: 'Edit Tea Leaves across branches' }));
    fireEvent.change(screen.getByLabelText('Selling price (LKR)'), {
      target: { value: '75' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Save item' }));

    expect(screen.queryByText('Choose a category for this inventory item.'))
      .not.toBeInTheDocument();
    fireEvent.click(await screen.findByRole('button', { name: 'Save changes' }));

    await waitFor(() => {
      expect(updateBody?.sellingPrice).toBe(75);
      expect(screen.getByText('LKR 75')).toBeInTheDocument();
    });
  });

  it('creates the same catalog item with separate starting stock for selected branches', async () => {
    let createBody: Record<string, unknown> | undefined;
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === '/api/inventory/categories') {
        return new Response(JSON.stringify([{ id: 'category-1', name: 'Technology' }]), { status: 200 });
      }
      if (url === '/api/inventory/branches') {
        return new Response(JSON.stringify([
          { id: 'branch-1', name: 'Main branch' },
          { id: 'branch-2', name: 'Kandy branch' },
        ]), { status: 200 });
      }
      if (url === '/api/suppliers') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items: [], totalPages: 1 }), { status: 200 });
      }
      if (url === '/api/inventory' && init?.method === 'POST') {
        createBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        return new Response(JSON.stringify({ id: 'created-item' }), { status: 201 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage({ role: 'Admin' });
    await screen.findByRole('button', { name: /Add item/ });
    fireEvent.click(screen.getByRole('button', { name: /Add item/ }));
    expect(screen.getByRole('dialog', { name: 'Add inventory item' })).toBeInTheDocument();
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByRole('dialog', { name: 'Add inventory item' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Add item/ }));
    fireEvent.change(screen.getByLabelText('Item name'), { target: { value: 'Wireless Mouse' } });
    fireEvent.change(screen.getByLabelText('Picture link'), {
      target: { value: 'https://images.example.test/mouse.jpg' },
    });
    fireEvent.change(screen.getByLabelText('Unit'), { target: { value: 'piece' } });
    fireEvent.change(screen.getByLabelText('Starting stock for Main branch'), { target: { value: '8' } });
    fireEvent.click(screen.getByLabelText('Kandy branch'));
    fireEvent.change(screen.getByLabelText('Starting stock for Kandy branch'), { target: { value: '4' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save item' }));
    const confirmation = await screen.findByRole('alertdialog');
    fireEvent.click(within(confirmation).getByRole('button', { name: 'Add item' }));

    await waitFor(() => {
      expect(createBody?.branchStocks).toEqual([
        { branchId: 'branch-1', quantity: 8 },
        { branchId: 'branch-2', quantity: 4 },
      ]);
      expect(createBody?.imageUrl).toBe('https://images.example.test/mouse.jpg');
      expect(createBody?.branchId).toBeNull();
    });
  });

  it('locks Staff to their assigned branch and hides catalogue management controls', async () => {
    const items = [
      {
        id: itemId, name: 'Main tea', sku: 'TEA-001', category: 'Tea',
        branchId: 'branch-1', branch: 'Main branch', quantity: 12,
        reorderLevel: 2, unitCost: 50, sellingPrice: 75,
      },
      {
        id: 'other-branch-item', name: 'North tea', sku: 'TEA-002', category: 'Tea',
        branchId: 'branch-2', branch: 'Kandy branch', quantity: 9,
        reorderLevel: 2, unitCost: 50, sellingPrice: 75,
      },
    ];
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url === '/api/inventory/categories') return new Response(JSON.stringify([]), { status: 200 });
      if (url === '/api/inventory/branches') {
        return new Response(JSON.stringify([
          { id: 'branch-1', name: 'Main branch' },
          { id: 'branch-2', name: 'Kandy branch' },
        ]), { status: 200 });
      }
      if (url === '/api/suppliers') return new Response(JSON.stringify({ items: [] }), { status: 200 });
      if (url.startsWith('/api/inventory?')) {
        return new Response(JSON.stringify({ items, totalPages: 1 }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage({ role: 'Staff', branchId: 'branch-1' });

    expect(await screen.findByText('Main tea')).toBeInTheDocument();
    expect(screen.queryByText('North tea')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Assigned branch')).toHaveTextContent('Main branch');
    expect(screen.queryByRole('button', { name: 'Add item' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Import CSV' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Edit Main tea across branches' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Suppliers' })).not.toBeInTheDocument();
  });

  it('updates selected branch stock and adds another branch while leaving other branches untouched', async () => {
    const items = [
      {
        id: itemId,
        name: 'Wireless Mouse',
        sku: 'MOUSE-001',
        categoryId: 'category-1',
        category: 'Technology',
        unitId: null,
        unit: 'piece',
        branchId: 'branch-1',
        branch: 'Main branch',
        quantity: 8,
        reorderLevel: 2,
        unitCost: 50,
        sellingPrice: 75,
      },
      {
        id: 'kandy-item',
        name: 'Wireless Mouse',
        sku: 'MOUSE-001',
        categoryId: 'category-1',
        category: 'Technology',
        unitId: null,
        unit: 'piece',
        branchId: 'branch-2',
        branch: 'Kandy branch',
        quantity: 4,
        reorderLevel: 2,
        unitCost: 50,
        sellingPrice: 75,
      },
    ];
    let updateBody: Record<string, unknown> | undefined;
    const adjustmentRequest = vi.fn();
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === '/api/inventory/categories') {
        return new Response(JSON.stringify([{ id: 'category-1', name: 'Technology' }]), { status: 200 });
      }
      if (url === '/api/inventory/branches') {
        return new Response(JSON.stringify([
          { id: 'branch-1', name: 'Main branch' },
          { id: 'branch-2', name: 'Kandy branch' },
          { id: 'branch-3', name: 'Galle branch' },
        ]), { status: 200 });
      }
      if (url === '/api/suppliers') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items, totalPages: 1 }), { status: 200 });
      }
      if (url.startsWith('/api/inventory/') && init?.method === 'PUT') {
        updateBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        return new Response(JSON.stringify(items[0]), { status: 200 });
      }
      if (url.endsWith('/adjust')) adjustmentRequest();
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage({ role: 'Admin' });
    await screen.findAllByText('Wireless Mouse');
    expect(screen.getAllByRole('row')).toHaveLength(2);
    expect(screen.getAllByText('Main branch')).toHaveLength(2);
    expect(screen.getAllByText('Kandy branch')).toHaveLength(2);
    fireEvent.click(screen.getByRole('button', { name: 'Edit Wireless Mouse across branches' }));
    fireEvent.change(screen.getByLabelText('On-hand stock for Main branch'), { target: { value: '7' } });
    fireEvent.change(screen.getByLabelText('On-hand stock for Kandy branch'), { target: { value: '5' } });
    fireEvent.click(screen.getByLabelText('Galle branch'));
    fireEvent.change(screen.getByLabelText('On-hand stock for Galle branch'), { target: { value: '3' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save item' }));
    const confirmation = await screen.findByRole('alertdialog');
    fireEvent.click(within(confirmation).getByRole('button', { name: 'Save changes' }));

    await waitFor(() => {
      expect(updateBody?.branchStocks).toEqual([
        { branchId: 'branch-1', quantity: 7 },
        { branchId: 'branch-2', quantity: 5 },
        { branchId: 'branch-3', quantity: 3 },
      ]);
      expect(updateBody?.branchId).toBeNull();
      expect(adjustmentRequest).not.toHaveBeenCalled();
    });
  });
});
