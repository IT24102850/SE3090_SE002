import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
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
  reorderLevel: 6,
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
    expect(await screen.findByRole('article', { name: '7-day revenue' })).toHaveTextContent('LKR 0.00');
    expect(screen.getByRole('article', { name: 'Gross profit' })).toHaveTextContent('LKR 0.00');
    expect(screen.getByRole('article', { name: 'Sales recorded' })).toHaveTextContent('0');
    expect(screen.getByRole('article', { name: 'Average sale' })).toHaveTextContent('LKR 0.00');
    const itemSearch = await screen.findByRole('combobox', { name: 'Search in-stock item' });
    fireEvent.change(itemSearch, { target: { value: 'tea-001' } });
    fireEvent.click(await screen.findByRole('option', { name: /Tea Leaves/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Clear selected item' }));
    expect(itemSearch).toHaveValue('');
    expect(screen.getByLabelText('Unit selling price')).toHaveValue('Select an item');
    expect(screen.getByRole('button', { name: 'Review sale' })).toBeDisabled();
    fireEvent.click(await screen.findByRole('option', { name: /Tea Leaves/ }));
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
    expect(await screen.findByRole('heading', { name: 'Sale recorded' })).toBeInTheDocument();
    expect(screen.getAllByText('LKR 150.00')).toHaveLength(2);
    expect(screen.getByText('UNIFY · SALES RECEIPT')).toBeInTheDocument();
    expect(screen.getByText('SALE RECORDED')).toBeInTheDocument();
    expect(screen.getByText('INVENTORY UPDATE')).toBeInTheDocument();
    expect(screen.getByText('Stock remaining: 6 kg')).toBeInTheDocument();
    expect(screen.getByText(/Payment collection is not recorded by this receipt/i)).toBeInTheDocument();
    expect(screen.getByText('Generated by Unify')).toBeInTheDocument();
    expect(screen.getByText(/LOW STOCK/)).toBeInTheDocument();
    const receiptDialog = screen.getByRole('dialog');
    expect(within(receiptDialog).queryByText('Cost of goods')).not.toBeInTheDocument();
    expect(within(receiptDialog).queryByText('Gross profit')).not.toBeInTheDocument();
  });

  it('shows matching items while typing and explains when there are no matches', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
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
      return new Response('Unexpected request', { status: 404 });
    }));

    renderPage();
    const itemSearch = await screen.findByRole('combobox', { name: 'Search in-stock item' });
    fireEvent.change(itemSearch, { target: { value: 'main branch' } });
    expect(await screen.findByRole('option', { name: /Tea Leaves.*Main branch/ })).toBeInTheDocument();

    fireEvent.change(itemSearch, { target: { value: 'not in catalog' } });
    expect(await screen.findByText('No in-stock item matches this search.')).toBeInTheDocument();
  });

  it('omits unavailable branch details from historical receipts', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items: [], totalPages: 1 }), { status: 200 });
      }
      if (url.includes('/api/reports/sales-activity?')) {
        return new Response(JSON.stringify({
          salesCount: 1,
          totalRevenue: 750,
          averageSale: 750,
          costOfGoodsSold: null,
          grossProfit: null,
          recentSales: [{
            id: 'sale-1',
            reference: 'SALE-001',
            occurredAt: '2026-09-29T10:00:00Z',
            amount: 750,
            quantity: 1,
            items: ['Paper'],
            costOfGoodsSold: null,
            grossProfit: null,
          }],
        }), { status: 200 });
      }
      return new Response('Unexpected request', { status: 404 });
    }));

    renderPage();
    const receiptButton = await screen.findByRole('button', { name: 'View receipt' });
    expect(screen.getByRole('heading', { name: 'Recent sales & receipts' })).toBeInTheDocument();
    expect(screen.getByText('1 sale')).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Sale reference' })).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Date & time' })).toBeInTheDocument();
    const saleRow = screen.getByText('SALE-001').closest('tr');
    expect(saleRow).not.toBeNull();
    expect(within(saleRow!).getByText('Paper')).toBeInTheDocument();
    expect(receiptButton).toHaveClass('sales-receipt-button');
    fireEvent.click(receiptButton);

    const receipt = screen.getByRole('dialog');
    expect(within(receipt).getByText('UNIFY · SALES RECEIPT')).toBeInTheDocument();
    expect(within(receipt).queryByText('BRANCH')).not.toBeInTheDocument();
    expect(within(receipt).queryByText('Not included in the sales report')).not.toBeInTheDocument();
    expect(within(receipt).getByText('Generated by Unify')).toBeInTheDocument();
  });
});
