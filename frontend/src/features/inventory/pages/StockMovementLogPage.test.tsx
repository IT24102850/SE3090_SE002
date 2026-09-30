import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { StockMovementLogPage } from './StockMovementLogPage';

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
          <MemoryRouter><StockMovementLogPage /></MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

function movement(id: string, movementType: string, quantity: number, item: string) {
  return {
    id,
    occurredAt: '2026-09-29T10:00:00Z',
    item,
    sku: `${id}-SKU`,
    movementType,
    quantity,
    reference: `REF-${id}`,
    notes: null,
    supplierId: null,
    supplierName: null,
    supplierLeadTimeDays: null,
    performedBy: 'Test Manager',
  };
}

function emptyPhysicalCounts() {
  return new Response(JSON.stringify({
    items: [],
    page: 1,
    pageSize: 100,
    totalCount: 0,
    totalPages: 0,
  }), { status: 200 });
}

describe('StockMovementLogPage', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('loads every movement page and classifies receipt and consumption types correctly', async () => {
    const requestedUrls: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      requestedUrls.push(url);
      if (url.includes('/physical-counts')) return emptyPhysicalCounts();
      if (url.includes('page=1')) {
        return new Response(JSON.stringify({
          items: [
            movement('consumption', 'Consumption', -3, 'Used ingredient'),
            movement('receipt', 'PurchaseReceived', 5, 'Received item'),
          ],
          page: 1,
          pageSize: 100,
          totalCount: 3,
          totalPages: 2,
        }), { status: 200 });
      }
      if (url.includes('page=2')) {
        return new Response(JSON.stringify({
          items: [movement('sale', 'Sale', -2, 'Sold item')],
          page: 2,
          pageSize: 100,
          totalCount: 3,
          totalPages: 2,
        }), { status: 200 });
      }
      return new Response('Unexpected request', { status: 404 });
    }));

    renderPage();

    expect(screen.getByRole('heading', { name: 'Physical counts & stock activity' })).toBeInTheDocument();
    expect(await screen.findByText('Used ingredient')).toBeInTheDocument();
    expect(screen.getByText('Sold item')).toBeInTheDocument();
    const table = screen.getByRole('table');
    expect(within(table).getByText('Receive')).toBeInTheDocument();
    expect(within(table).getByText('Consumption')).toBeInTheDocument();
    expect(requestedUrls).toHaveLength(3);
    expect(requestedUrls.some((url) => url.includes('/movements?page=2'))).toBe(true);

    fireEvent.click(screen.getByRole('button', { name: /Issued \/ consumed/ }));
    expect(within(table).getByText('Used ingredient')).toBeInTheDocument();
    expect(within(table).getByText('Sold item')).toBeInTheDocument();
    expect(within(table).queryByText('Received item')).not.toBeInTheDocument();
    expect(screen.getByText('−5')).toBeInTheDocument();
  });

  it('keeps unknown movement types visible rather than disguising them as adjustments', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes('/physical-counts')) return emptyPhysicalCounts();
      return new Response(JSON.stringify({
        items: [movement('transfer', 'Transfer', -1, 'Transferred item')],
        page: 1,
        pageSize: 100,
        totalCount: 1,
        totalPages: 1,
      }), { status: 200 });
    }));

    renderPage();

    const table = screen.getByRole('table');
    await waitFor(() => expect(within(table).getByText('Transfer')).toBeInTheDocument());
    expect(within(table).queryByText('Adjustment')).not.toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Transfer' })).toBeInTheDocument();
  });

  it('includes the complete selected end date without including the next day', async () => {
    const endOfDay = new Date(2026, 8, 29, 23, 59, 59, 999).toISOString();
    const nextDay = new Date(2026, 8, 30, 0, 0, 0, 0).toISOString();
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes('/physical-counts')) return emptyPhysicalCounts();
      return new Response(JSON.stringify({
        items: [
          { ...movement('last-moment', 'Receive', 1, 'Last moment item'), occurredAt: endOfDay },
          { ...movement('tomorrow', 'Receive', 1, 'Tomorrow item'), occurredAt: nextDay },
        ],
        page: 1,
        pageSize: 100,
        totalCount: 2,
        totalPages: 1,
      }), { status: 200 });
    }));

    renderPage();
    const table = screen.getByRole('table');
    await waitFor(() => expect(within(table).getByText('Tomorrow item')).toBeInTheDocument());
    fireEvent.change(screen.getByLabelText('To date'), { target: { value: '2026-09-29' } });

    expect(within(table).getByText('Last moment item')).toBeInTheDocument();
    expect(within(table).queryByText('Tomorrow item')).not.toBeInTheDocument();
  });

  it('accepts the legacy API array response during backend rollout', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes('/physical-counts')) return emptyPhysicalCounts();
      return new Response(JSON.stringify([
        movement('legacy', 'Receive', 2, 'Legacy API item'),
      ]), { status: 200 });
    });
    vi.stubGlobal('fetch', fetchMock);

    renderPage();

    const table = screen.getByRole('table');
    await waitFor(() => expect(within(table).getByText('Legacy API item')).toBeInTheDocument());
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(screen.queryByText('Movement request returned an invalid response.')).not.toBeInTheDocument();
  });

  it('shows mobile physical counts in activity and does not duplicate applied adjustments', async () => {
    const count = (
      id: string,
      status: string,
      variance: number,
      reference: string,
    ) => ({
      id,
      inventoryItemId: `item-${id}`,
      itemName: `Counted ${id}`,
      sku: `SKU-${id}`,
      systemQuantityAtCount: 10,
      countedQuantity: 10 + variance,
      variance,
      reason: variance === 0 ? 'NoDiscrepancy' : 'LostOrMissing',
      reasonNotes: null,
      countedAt: '2026-09-29T12:00:00Z',
      countedBy: 'Mobile Counter',
      branchId: 'branch-1',
      reference,
      status,
      photoUrls: [],
      reviewedBy: null,
      reviewedAt: null,
      reviewNotes: null,
    });
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes('/physical-counts')) {
        return new Response(JSON.stringify({
          items: [
            count('applied', 'Applied', -2, 'MOBILE-AUDIT-applied'),
            count('pending', 'PendingApproval', 7, 'MOBILE-AUDIT-pending'),
            count('matched', 'Matched', 0, 'MOBILE-AUDIT-matched'),
          ],
          page: 1,
          pageSize: 100,
          totalCount: 3,
          totalPages: 1,
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        items: [
          {
            ...movement('adjustment-applied', 'Adjustment', -2, 'Counted applied'),
            reference: 'MOBILE-AUDIT-applied',
          },
          movement('normal-adjustment', 'Adjustment', 3, 'Manual adjustment'),
        ],
        page: 1,
        pageSize: 100,
        totalCount: 2,
        totalPages: 1,
      }), { status: 200 });
    }));

    renderPage();

    const table = screen.getByRole('table');
    expect(await within(table).findByText('Counted applied')).toBeInTheDocument();
    expect(within(table).getByText('Counted pending')).toBeInTheDocument();
    expect(within(table).getByText('Counted matched')).toBeInTheDocument();
    expect(within(table).getByText('Manual adjustment')).toBeInTheDocument();
    expect(within(table).queryByText('Counted applied', { selector: 'p.cell-title' })).toBeInTheDocument();
    expect(within(table).getAllByText('MOBILE-AUDIT-applied')).toHaveLength(1);
    expect(within(table).getByText(/Pending approval physical count/)).toBeInTheDocument();
    expect(within(table).getByText('Variance +7')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Physical counts 3/ })).toBeInTheDocument();
    expect(within(table).getByText('-2')).toBeInTheDocument();
  });
});
