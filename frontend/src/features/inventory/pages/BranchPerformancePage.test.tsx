import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { BranchPerformancePage } from './BranchPerformancePage';

describe('branch performance report', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal('matchMedia', vi.fn(() => ({
      matches: false,
      media: '(prefers-color-scheme: dark)',
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(() => false),
    })));
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it('compares sales, profit and current stock for each accessible branch', async () => {
    const requestedBranchIds: string[] = [];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path === '/api/inventory/branches') {
        return {
          ok: true,
          json: async () => [
            { id: 'branch-1', name: 'Main branch' },
            { id: 'branch-2', name: 'North branch' },
          ],
        } as Response;
      }
      if (path.startsWith('/api/inventory?')) {
        return {
          ok: true,
          json: async () => ({
            items: [
              { id: 'stock-1', branchId: 'branch-1', quantity: 20, reorderLevel: 5, unitCost: 100 },
              { id: 'stock-2', branchId: 'branch-1', quantity: 1, reorderLevel: 2, unitCost: 200 },
              { id: 'stock-3', branchId: 'branch-2', quantity: 0, reorderLevel: 3, unitCost: 50 },
            ],
            totalCount: 3,
            totalPages: 1,
          }),
        } as Response;
      }
      if (path.startsWith('/api/reports/sales-activity?')) {
        const params = new URL(path, 'http://localhost').searchParams;
        const branchId = params.get('branchId') ?? '';
        requestedBranchIds.push(branchId);
        const northBranch = branchId === 'branch-2';
        return {
          ok: true,
          json: async () => ({
            salesCount: northBranch ? 3 : 5,
            totalRevenue: northBranch ? 9000 : 15000,
            averageSale: 3000,
            costOfGoodsSold: northBranch ? 5400 : 9000,
            grossProfit: northBranch ? 3600 : 6000,
          }),
        } as Response;
      }
      if (path.startsWith('/api/reports/branch-commerce?')) {
        return {
          ok: true,
          json: async () => ({
            manualSalesCount: 5,
            manualSalesRevenue: 11000,
            customerOrderSalesCount: 3,
            customerOrderSalesRevenue: 13000,
            customerOrderCount: 6,
            customerOrderValue: 18000,
            pendingOrders: 2,
            confirmedOrders: 1,
            preparingOrders: 0,
            readyForPickupOrders: 0,
            outForDeliveryOrders: 0,
            completedOrders: 3,
            cancelledOrders: 0,
            branches: [
              {
                branchId: 'branch-1',
                manualSalesCount: 3,
                manualSalesRevenue: 5000,
                customerOrderSalesCount: 2,
                customerOrderSalesRevenue: 10000,
                customerOrderCount: 4,
                customerOrderValue: 13000,
                pendingOrders: 1,
                confirmedOrders: 1,
                preparingOrders: 0,
                readyForPickupOrders: 0,
                outForDeliveryOrders: 0,
                completedOrders: 2,
                cancelledOrders: 0,
              },
              {
                branchId: 'branch-2',
                manualSalesCount: 2,
                manualSalesRevenue: 6000,
                customerOrderSalesCount: 1,
                customerOrderSalesRevenue: 3000,
                customerOrderCount: 2,
                customerOrderValue: 5000,
                pendingOrders: 1,
                confirmedOrders: 0,
                preparingOrders: 0,
                readyForPickupOrders: 0,
                outForDeliveryOrders: 0,
                completedOrders: 1,
                cancelledOrders: 0,
              },
            ],
          }),
        } as Response;
      }
      throw new Error(`Unexpected request: ${path}`);
    });
    vi.stubGlobal('fetch', fetchMock);

    render(
      <MemoryRouter>
        <AppToastProvider>
          <ToastProvider><BranchPerformancePage /></ToastProvider>
        </AppToastProvider>
      </MemoryRouter>,
    );

    const scorecard = await screen.findByRole('heading', { name: 'Detailed comparison' });
    expect(screen.getByRole('heading', { name: 'Revenue by branch' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Stock value by branch' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Manual sales & customer orders' })).toBeInTheDocument();
    expect(screen.getByText('LKR 11,000')).toBeInTheDocument();
    expect(screen.getByText('LKR 13,000')).toBeInTheDocument();
    expect(screen.getByText('LKR 18,000 order value')).toBeInTheDocument();
    const table = scorecard.closest('section');
    expect(table).not.toBeNull();
    expect(within(table as HTMLElement).getByText('Main branch')).toBeInTheDocument();
    expect(within(table as HTMLElement).getByText('North branch')).toBeInTheDocument();
    expect(within(table as HTMLElement).getByRole('columnheader', { name: 'Manual sales' })).toBeInTheDocument();
    expect(within(table as HTMLElement).getByRole('columnheader', { name: 'Customer-order sales' })).toBeInTheDocument();
    expect(within(table as HTMLElement).getAllByText('40.0%')).toHaveLength(2);
    expect(screen.getByText('LKR 24,000')).toBeInTheDocument();
    expect(screen.getAllByText('LKR 2,200')).toHaveLength(2);
    expect(requestedBranchIds.sort()).toEqual(['branch-1', 'branch-2']);

    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    expect(await screen.findByText('Branch performance refreshed successfully.')).toBeInTheDocument();
  });

  it('shows an explicit error and offers retry when branch data cannot load', async () => {
    const fetchMock = vi.fn(async () => ({ ok: false, status: 503 }) as Response);
    vi.stubGlobal('fetch', fetchMock);

    render(
      <MemoryRouter>
        <AppToastProvider>
          <ToastProvider><BranchPerformancePage /></ToastProvider>
        </AppToastProvider>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('503 from /api/inventory/branches');
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument();
    expect(screen.queryByText('Branch performance refreshed successfully.')).not.toBeInTheDocument();
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3));
  });
});
