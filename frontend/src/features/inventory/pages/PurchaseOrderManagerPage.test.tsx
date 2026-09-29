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
          branches: [{ id: 'branch-1', name: 'Main branch' }],
          suppliers: [
            { id: 'supplier-1', name: 'Supplier One' },
            { id: 'supplier-2', name: 'Supplier Two' },
          ],
          items: [
            { id: 'item-1', name: 'Tea', sku: 'TEA-1', unitCost: 50, branchId: 'branch-1', supplierId: 'supplier-1' },
            { id: 'item-2', name: 'Coffee', sku: 'COF-1', unitCost: 90, branchId: 'branch-1', supplierId: 'supplier-2' },
          ],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    fireEvent.click(await screen.findByRole('button', { name: /Create order/ }));
    const itemSelect = screen.getByLabelText('Inventory item for line 1');
    expect(within(itemSelect).getByRole('option', { name: 'Tea (TEA-1)' })).toBeInTheDocument();
    expect(within(itemSelect).queryByRole('option', { name: 'Coffee (COF-1)' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveValue(50);
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveAttribute('readonly');

    fireEvent.change(screen.getByLabelText('Supplier'), { target: { value: 'supplier-2' } });
    expect(within(itemSelect).getByRole('option', { name: 'Coffee (COF-1)' })).toBeInTheDocument();
    expect(within(itemSelect).queryByRole('option', { name: 'Tea (TEA-1)' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Unit price for line 1 (catalog locked)')).toHaveValue(90);
  });
});
