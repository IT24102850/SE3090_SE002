import { configureStore } from '@reduxjs/toolkit';
import { render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { BranchOverviewPage } from './BranchOverviewPage';

vi.mock('../../../api/bookingApi', () => ({
  useGetBranchesQuery: () => ({
    data: [
      { id: 'branch-1', name: 'Main branch' },
      { id: 'branch-2', name: 'Kandy branch' },
    ],
  }),
}));

describe('BranchOverviewPage product stock directory', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({
          items: [
            {
              id: 'main-item',
              name: 'Wireless Mouse',
              sku: 'MOUSE-001',
              category: 'Technology',
              branch: 'Main branch',
              branchId: 'branch-1',
              quantity: 8,
              reorderLevel: 2,
              unit: 'piece',
              unitCost: 50,
            },
            {
              id: 'kandy-item',
              name: 'Wireless Mouse',
              sku: 'MOUSE-001',
              category: 'Technology',
              branch: 'Kandy branch',
              branchId: 'branch-2',
              quantity: 4,
              reorderLevel: 5,
              unit: 'piece',
              unitCost: 50,
            },
          ],
          totalPages: 1,
        }), { status: 200 });
      }
      if (url === '/api/inventory/categories') {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (url.startsWith('/api/reports/branch-commerce?')) {
        return new Response(JSON.stringify({
          salesCount: 3,
          salesRevenue: 10000,
          manualSalesCount: 2,
          manualSalesRevenue: 7500,
          customerOrderSalesCount: 1,
          customerOrderSalesRevenue: 2500,
          customerOrderCount: 4,
          customerOrderValue: 14000,
          pendingOrders: 1,
          confirmedOrders: 0,
          preparingOrders: 1,
          readyForPickupOrders: 1,
          outForDeliveryOrders: 0,
          completedOrders: 1,
          cancelledOrders: 0,
          branches: [
            {
              branchId: 'branch-1', branchName: 'Main branch',
              salesCount: 2, salesRevenue: 7000,
              manualSalesCount: 1, manualSalesRevenue: 4500,
              customerOrderSalesCount: 1, customerOrderSalesRevenue: 2500,
              customerOrderCount: 3, customerOrderValue: 8200,
              pendingOrders: 1, confirmedOrders: 0, preparingOrders: 1,
              readyForPickupOrders: 1, outForDeliveryOrders: 0,
              completedOrders: 0, cancelledOrders: 0,
            },
            {
              branchId: 'branch-2', branchName: 'Kandy branch',
              salesCount: 1, salesRevenue: 3000,
              manualSalesCount: 1, manualSalesRevenue: 3000,
              customerOrderSalesCount: 0, customerOrderSalesRevenue: 0,
              customerOrderCount: 1, customerOrderValue: 5800,
              pendingOrders: 0, confirmedOrders: 0, preparingOrders: 0,
              readyForPickupOrders: 0, outForDeliveryOrders: 0,
              completedOrders: 1, cancelledOrders: 0,
            },
          ],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('shows one product row with separate branch stock and aggregate totals', async () => {
    const store = configureStore({
      reducer: { auth: authReducer },
      preloadedState: {
        auth: {
          user: {
            id: 'user-1',
            email: 'admin@example.test',
            fullName: 'Test Admin',
            role: 'Admin' as const,
            tenantId: 'tenant-1',
          },
          token: 'test-token',
          isAuthenticated: true,
          loading: false,
          error: null,
        },
      },
    });

    render(
      <MemoryRouter>
        <Provider store={store}>
          <AppToastProvider>
            <ToastProvider>
              <BranchOverviewPage />
            </ToastProvider>
          </AppToastProvider>
        </Provider>
      </MemoryRouter>,
    );

    await screen.findByText('Kandy branch');
    const table = screen.getByRole('table');
    const rows = within(table).getAllByRole('row');
    expect(rows).toHaveLength(2);
    expect(within(rows[1]).getByText('Wireless Mouse')).toBeInTheDocument();
    expect(within(rows[1]).getByText('MOUSE-001').closest('td')).not.toHaveClass('branch-stock-cell');
    expect(within(rows[1]).getByText('Main branch').closest('td')).toHaveClass('branch-stock-cell');
    expect(within(rows[1]).getByText('Main branch')).toBeInTheDocument();
    expect(within(rows[1]).getByText('Kandy branch')).toBeInTheDocument();
    expect(within(rows[1]).getByText('Main branch').parentElement).toHaveClass('branch-stock-allocation');
    expect(within(rows[1]).getByText('12 piece')).toBeInTheDocument();
    expect(within(rows[1]).getByText('LKR 600')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText('1 of 1 products · 2 branch stocks · 1 categories')).toBeInTheDocument());
    expect(await screen.findByRole('heading', { name: 'Sales & customer orders' })).toBeInTheDocument();
    expect(screen.getByText('LKR 10,000')).toBeInTheDocument();
    const commerceSection = screen.getByLabelText('Sales and customer orders for the last 30 days');
    expect(within(commerceSection).getByText('Manual sales')).toBeInTheDocument();
    expect(within(commerceSection).getByText('Customer-order sales')).toBeInTheDocument();
    expect(within(commerceSection).getByText('LKR 7,500')).toBeInTheDocument();
    expect(within(commerceSection).getByText('LKR 2,500')).toBeInTheDocument();
    const customerOrderMetric = within(commerceSection).getByText('Customer orders').closest('article');
    expect(customerOrderMetric).not.toBeNull();
    expect(within(customerOrderMetric!).getByText(/LKR 14,000/)).toBeInTheDocument();
    expect(within(customerOrderMetric!).getByText(/order value · excludes cancelled/)).toBeInTheDocument();
    expect(screen.getByLabelText('Main branch sales and order activity')).toHaveTextContent('LKR 7,000');
    expect(screen.getByLabelText('Main branch sales and order activity')).toHaveTextContent('LKR 4,500');
    expect(screen.getByLabelText('Main branch sales and order activity')).toHaveTextContent('LKR 2,500');
    expect(screen.getByLabelText('Kandy branch sales and order activity')).toHaveTextContent('0 pending');
  });

  it('limits a Manager to their assigned branch', async () => {
    const requestedUrls: string[] = [];
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      requestedUrls.push(url);
      if (url === '/api/inventory/branches') {
        return new Response(JSON.stringify([
          { id: 'branch-1', name: 'Main branch' },
          { id: 'branch-2', name: 'Kandy branch' },
        ]), { status: 200 });
      }
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({
          items: [
            {
              id: 'main-item', name: 'Main item', sku: 'MAIN-001',
              branch: 'Main branch', branchId: 'branch-1', quantity: 8,
              reorderLevel: 2, unitCost: 50,
            },
            {
              id: 'kandy-item', name: 'Kandy item', sku: 'KANDY-001',
              branch: 'Kandy branch', branchId: 'branch-2', quantity: 4,
              reorderLevel: 5, unitCost: 50,
            },
          ],
          totalPages: 1,
        }), { status: 200 });
      }
      if (url === '/api/inventory/categories') return new Response(JSON.stringify([]), { status: 200 });
      if (url.startsWith('/api/reports/branch-commerce?')) {
        return new Response(JSON.stringify({
          salesCount: 0, salesRevenue: 0, customerOrderCount: 0,
          manualSalesCount: 0, manualSalesRevenue: 0,
          customerOrderSalesCount: 0, customerOrderSalesRevenue: 0,
          customerOrderValue: 0,
          pendingOrders: 0, confirmedOrders: 0, preparingOrders: 0,
          readyForPickupOrders: 0, outForDeliveryOrders: 0,
          completedOrders: 0, cancelledOrders: 0,
          branches: [{
            branchId: 'branch-1', branchName: 'Main branch',
            salesCount: 0, salesRevenue: 0, customerOrderCount: 0,
            manualSalesCount: 0, manualSalesRevenue: 0,
            customerOrderSalesCount: 0, customerOrderSalesRevenue: 0,
            customerOrderValue: 0,
            pendingOrders: 0, confirmedOrders: 0, preparingOrders: 0,
            readyForPickupOrders: 0, outForDeliveryOrders: 0,
            completedOrders: 0, cancelledOrders: 0,
          }],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

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
            branchId: 'branch-1',
          },
          token: 'test-token',
          isAuthenticated: true,
          loading: false,
          error: null,
        },
      },
    });

    render(
      <MemoryRouter>
        <Provider store={store}>
          <AppToastProvider>
            <ToastProvider><BranchOverviewPage /></ToastProvider>
          </AppToastProvider>
        </Provider>
      </MemoryRouter>,
    );

    expect(await screen.findByText('Main item')).toBeInTheDocument();
    expect(screen.queryByText('Kandy item')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Assigned branch')).toHaveTextContent('Main branch');
    expect(requestedUrls.some((url) => url.includes('branchId=branch-1'))).toBe(true);
    expect(screen.getByText('1 locations · 1 products tracked')).toBeInTheDocument();
  });
});
