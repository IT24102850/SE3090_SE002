import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { PurchaseOrderManagerPage } from './PurchaseOrderManagerPage';

function renderPage() {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: {
        user: {
          id: 'user-1',
          email: 'manager@example.test',
          fullName: 'Test Manager',
          role: 'Manager' as const,
          tenantId: 'tenant-1',
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
          <MemoryRouter><PurchaseOrderManagerPage /></MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

describe('PurchaseOrderManagerPage catalog-linked order items', () => {
  beforeEach(() => localStorage.setItem('token', 'test-token'));

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('filters linked items by supplier and locks catalog unit cost', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/purchase-orders?page=')) {
        return new Response(JSON.stringify({ items: [], totalCount: 0, totalPages: 0 }), { status: 200 });
      }
      if (url.endsWith('/api/purchase-orders/options')) {
        return new Response(JSON.stringify({
          branches: [
            { id: 'branch-1', name: 'Main branch' },
            { id: 'branch-2', name: 'North branch' },
          ],
          suppliers: [
            { id: 'supplier-1', name: 'Supplier One' },
            { id: 'supplier-2', name: 'Supplier Two' },
          ],
          items: [
            { id: 'item-1', name: 'Tea', sku: 'TEA-1', unitCost: 50, branchId: 'branch-1', supplierId: 'supplier-1' },
            { id: 'item-2', name: 'Coffee', sku: 'COF-1', unitCost: 90, branchId: 'branch-1', supplierId: 'supplier-2' },
            { id: 'item-3', name: 'Oolong', sku: 'OOL-1', unitCost: 70, branchId: 'branch-2', branchName: 'North branch', supplierId: 'supplier-1' },
          ],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    expect(document.querySelector('.purchase-orders-register-wrap .purchase-orders-register-table')).toBeInTheDocument();
    fireEvent.click(await screen.findByRole('button', { name: /Create order/ }));
    const itemSelect = screen.getByLabelText('Inventory item for line 1');
    expect(within(itemSelect).getByRole('option', { name: 'Tea (TEA-1)' })).toBeInTheDocument();
    expect(within(itemSelect).getByRole('option', { name: 'Oolong (OOL-1) · from North branch' })).toBeInTheDocument();
    expect(within(itemSelect).queryByRole('option', { name: 'Coffee (COF-1)' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveValue(50);
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveAttribute('readonly');

    fireEvent.change(screen.getByLabelText('Supplier'), { target: { value: 'supplier-2' } });
    expect(within(itemSelect).getByRole('option', { name: 'Coffee (COF-1)' })).toBeInTheDocument();
    expect(within(itemSelect).queryByRole('option', { name: 'Tea (TEA-1)' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveValue(90);
  });

  it('creates a separate order with branch-specific quantities for each selected branch', async () => {
    let batchRequest: { number: string; supplierId: string; branchOrders: Array<{ branchId: string; items: Array<{ quantity: number }> }> } | undefined;
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes('/api/purchase-orders?page=')) {
        return new Response(JSON.stringify({ items: [], totalCount: 0, totalPages: 0 }), { status: 200 });
      }
      if (url.endsWith('/api/purchase-orders/options')) {
        return new Response(JSON.stringify({
          branches: [
            { id: 'branch-1', name: 'Main branch' },
            { id: 'branch-2', name: 'North branch' },
          ],
          suppliers: [{ id: 'supplier-1', name: 'Supplier One' }],
          items: [
            { id: 'item-1', name: 'Tea', sku: 'TEA-1', unitCost: 50, branchId: 'branch-1', supplierId: 'supplier-1' },
          ],
        }), { status: 200 });
      }
      if (url.endsWith('/api/purchase-orders/batch')) {
        batchRequest = JSON.parse(String(init?.body));
        return new Response(JSON.stringify([
          {
            id: 'po-main', number: 'PO-2026-001-01', branchId: 'branch-1', branch: 'Main branch',
            supplierId: 'supplier-1', supplier: 'Supplier One', status: 'Draft', totalAmount: 50,
            lineItems: 1, createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z', items: [],
          },
          {
            id: 'po-north', number: 'PO-2026-001-02', branchId: 'branch-2', branch: 'North branch',
            supplierId: 'supplier-1', supplier: 'Supplier One', status: 'Draft', totalAmount: 200,
            lineItems: 1, createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z', items: [],
          },
        ]), { status: 201 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    fireEvent.click(await screen.findByRole('button', { name: /Create order/ }));
    fireEvent.click(screen.getByLabelText('Order for North branch'));
    const northBranchQuantity = screen.getByLabelText('Quantity for North branch, line 1');
    expect(northBranchQuantity).toHaveAttribute('step', '1');
    fireEvent.change(northBranchQuantity, { target: { value: '9.982' } });
    expect(northBranchQuantity).toHaveValue(0);
    fireEvent.change(northBranchQuantity, { target: { value: '4' } });
    fireEvent.click(screen.getByRole('button', { name: 'Create purchase order' }));
    fireEvent.click(screen.getByRole('button', { name: 'Create 2 orders' }));

    await screen.findByText(/2 purchase orders created successfully/);
    const groupedRequest = await screen.findByRole('region', {
      name: 'Grouped purchase request PO-2026-001',
    });
    expect(groupedRequest).toHaveTextContent('Each branch order has its own status and receipt');
    const northBranchOrder = within(groupedRequest).getByRole('button', { name: /North branch/ });
    expect(northBranchOrder).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(northBranchOrder);
    expect(northBranchOrder).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByText('Branch', { selector: 'dt' }).nextElementSibling).toHaveTextContent('North branch');
    expect(batchRequest).toEqual({
      number: expect.any(String),
      supplierId: 'supplier-1',
      branchOrders: [
        { branchId: 'branch-1', items: [{ inventoryItemId: 'item-1', description: 'Tea', quantity: 1, unitPrice: 50 }] },
        { branchId: 'branch-2', items: [{ inventoryItemId: 'item-1', description: 'Tea', quantity: 4, unitPrice: 50 }] },
      ],
    });
  });

  it('updates remaining quantity live as accepted and damaged units are entered', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/purchase-orders?page=')) {
        return new Response(JSON.stringify({
          items: [{
            id: 'po-receiving',
            number: 'PO-RECEIVING-1',
            branchId: 'branch-1',
            branch: 'Main branch',
            supplierId: 'supplier-1',
            supplier: 'Supplier One',
            status: 'InTransit',
            totalAmount: 100,
            lineItems: 1,
            createdAt: '2026-01-01T00:00:00Z',
            updatedAt: '2026-01-01T00:00:00Z',
            items: [{
              id: 'po-item-1',
              inventoryItemId: 'item-1',
              itemName: 'Fantech Keyboard',
              quantity: 2,
              unitPrice: 50,
              lineTotal: 100,
              receivedQuantity: 0,
              damagedQuantity: 0,
              shortageQuantity: 0,
              receivingClosed: false,
            }],
          }],
          totalCount: 1,
          totalPages: 1,
        }), { status: 200 });
      }
      if (url.endsWith('/api/purchase-orders/options')) {
        return new Response(JSON.stringify({
          branches: [{ id: 'branch-1', name: 'Main branch' }],
          suppliers: [{ id: 'supplier-1', name: 'Supplier One' }],
          items: [{ id: 'item-1', name: 'Fantech Keyboard', sku: 'KEY-1', unitCost: 50, branchId: 'branch-1', supplierId: 'supplier-1' }],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    await screen.findByRole('heading', { name: 'PO-RECEIVING-1', level: 2 });
    fireEvent.click(screen.getByRole('button', { name: 'Receive items' }));

    const remaining = screen.getByLabelText('Remaining after this delivery for Fantech Keyboard');
    const accepted = screen.getByLabelText('Accepted now Fantech Keyboard');
    const damaged = screen.getByLabelText('Damaged now Fantech Keyboard');
    expect(remaining).toHaveTextContent('2');
    fireEvent.change(accepted, { target: { value: '1' } });
    expect(remaining).toHaveTextContent('1');
    fireEvent.change(damaged, { target: { value: '1' } });
    expect(remaining).toHaveTextContent('0');
    expect(remaining).toHaveTextContent('of 2 remaining before this delivery');
  });
});
