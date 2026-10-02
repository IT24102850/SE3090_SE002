import { configureStore } from '@reduxjs/toolkit';
import { render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
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
      <Provider store={store}>
        <AppToastProvider>
          <ToastProvider>
            <BranchOverviewPage />
          </ToastProvider>
        </AppToastProvider>
      </Provider>,
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
      <Provider store={store}>
        <AppToastProvider>
          <ToastProvider><BranchOverviewPage /></ToastProvider>
        </AppToastProvider>
      </Provider>,
    );

    expect(await screen.findByText('Main item')).toBeInTheDocument();
    expect(screen.queryByText('Kandy item')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Assigned branch')).toHaveTextContent('Main branch');
    expect(requestedUrls.some((url) => url.includes('branchId=branch-1'))).toBe(true);
    expect(screen.getByText('1 locations · 1 products tracked')).toBeInTheDocument();
  });
});
