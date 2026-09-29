import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { SalesPage } from './SalesPage';

const inventoryItem = {
  id: 'item-1',
  name: 'Tea Leaves',
  sku: 'TEA-001',
  category: 'Tea',
  unit: 'kg',
  branch: 'Main branch',
  branchId: 'branch-1',
  quantity: 8,
  unitCost: 50,
  sellingPrice: 75,
};

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
          <MemoryRouter><SalesPage /></MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

describe('SalesPage', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
    vi.stubGlobal('crypto', { randomUUID: () => 'sale-reference-id' });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('locks catalog prices and submits the exact expected values after confirmation', async () => {
    let saleRequest: Record<string, unknown> | undefined;
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items: [inventoryItem], totalPages: 1 }), { status: 200 });
      }
      if (url.includes('/api/reports/sales-activity?')) {
        return new Response(JSON.stringify({
          salesCount: 0,
          totalRevenue: 0,
          averageSale: 0,
          costOfGoodsSold: 0,
          grossProfit: 0,
          recentSales: [],
        }), { status: 200 });
      }
      if (url.endsWith('/api/inventory/item-1/sell')) {
        saleRequest = JSON.parse(String(init?.body)) as Record<string, unknown>;
        return new Response(JSON.stringify({
          reference: 'SALE-WEB-sale-reference-id',
          itemName: 'Tea Leaves',
          quantity: 2,
          unitPrice: 75,
          amount: 150,
          costOfGoodsSold: 100,
          grossProfit: 50,
          remainingQuantity: 6,
          occurredAt: '2026-05-20T10:00:00Z',
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    const itemSelect = await screen.findByLabelText('Inventory item');
    fireEvent.change(itemSelect, { target: { value: 'item-1' } });
    fireEvent.change(screen.getByLabelText('Quantity to sell'), { target: { value: '2' } });

    expect(screen.getByLabelText('Unit selling price')).toHaveValue('LKR 75.00');
    expect(screen.getByLabelText('Unit selling price')).toHaveAttribute('readonly');
    expect(screen.getByLabelText('Unit cost')).toHaveAttribute('readonly');
    fireEvent.click(screen.getByRole('button', { name: 'Review sale' }));
    fireEvent.click(screen.getByRole('button', { name: 'Record sale' }));

    await waitFor(() => expect(saleRequest).toEqual({
      quantity: 2,
      expectedSellingPrice: 75,
      expectedUnitCost: 50,
      reference: 'SALE-WEB-sale-reference-id',
    }));
    expect(await screen.findByRole('heading', { name: 'Sale receipt' })).toBeInTheDocument();
    expect(screen.getByText('LKR 150.00')).toBeInTheDocument();
  });
});
