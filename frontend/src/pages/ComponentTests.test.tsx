import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement } from 'react';
import { AuthProvider } from '../auth/AuthContext';
import { ToastProvider } from '../ui/ToastContext';
import { AnalyticsDashboardPage } from './AnalyticsDashboardCharts';
import { InventoryManagerPage } from './InventoryManagerPage';
import { PurchaseOrderManagerPage } from './PurchaseOrderManagerPage';

function renderWithAuth(ui: ReactElement) {
  const encode = (value: object) => btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  localStorage.setItem('sme.access-token', `${encode({ alg: 'none' })}.${encode({ sub: 'test-user', role: 'Admin', tenant_id: '00000000-0000-0000-0000-000000000001', branch_id: '00000000-0000-0000-0000-000000000002', exp: Math.floor(Date.now() / 1000) + 3600 })}.test`);
  return render(
    <AuthProvider>
      <ToastProvider>{ui}</ToastProvider>
    </AuthProvider>
  );
}

describe('frontend dashboard and workflow components', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      const body = init?.body ? JSON.parse(String(init.body)) : null;
      if (url.includes('/api/inventory?')) {
        return Promise.resolve(new Response(JSON.stringify({
          items: [
            { id: 'item-1', name: 'Vanilla Syrup 750ml', sku: 'SKU-00324', quantity: 0, reorderLevel: 25, unitCost: 1000, status: 'OutOfStock' },
            { id: 'item-2', name: 'Premium Coffee Beans', sku: 'SKU-00132', quantity: 6, reorderLevel: 40, unitCost: 2000, status: 'LowStock' },
          ],
          totalCount: 2,
        }), { status: 200 }));
      }
      if (url.includes('/api/inventory/low-stock')) {
        return Promise.resolve(new Response(JSON.stringify({
          items: [{ id: 'item-1', name: 'Vanilla Syrup 750ml', sku: 'SKU-00324', quantity: 0, reorderLevel: 25, unitCost: 1000, status: 'OutOfStock' }],
          totalCount: 1,
        }), { status: 200 }));
      }
      if (url.includes('/api/reports/revenue')) {
        return Promise.resolve(new Response(JSON.stringify({ totalRevenue: 1000, buckets: [] }), { status: 200 }));
      }
      if (url.includes('/api/reports/inventory-usage')) {
        return Promise.resolve(new Response(JSON.stringify({ totalReceivedQuantity: 0, totalIssuedQuantity: 0, netQuantity: 0, items: [] }), { status: 200 }));
      }
      if (url.includes('/api/suppliers')) {
        return Promise.resolve(new Response(JSON.stringify({ items: [{ id: 'supplier-1', name: 'Ceylon Coffee Traders' }] }), { status: 200 }));
      }
      if (url.includes('/api/purchase-orders') && init?.method === 'POST') {
        return Promise.resolve(new Response(JSON.stringify({ id: 'po-2148-id', number: body.number, branchId: body.branchId, branch: 'Main Branch', supplierId: body.supplierId, supplier: 'Ceylon Coffee Traders', status: 'Draft', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }), { status: 201 }));
      }
      if (url.includes('/api/purchase-orders')) {
        return Promise.resolve(new Response(JSON.stringify({ items: [], page: 1, pageSize: 50, totalCount: 0, totalPages: 0 }), { status: 200 }));
      }
      return Promise.reject(new Error(`Unhandled request: ${url}`));
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('renders the analytics dashboard from live API data', async () => {
    renderWithAuth(<AnalyticsDashboardPage />);

    expect(await screen.findByRole('heading', { name: /analytics dashboard/i })).toBeInTheDocument();
    expect(screen.getByText('Revenue')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText(/LKR\s*1,000/i)).toBeInTheDocument());
  });

  it('filters inventory rows by search and stock status', async () => {
    const user = userEvent.setup();
    renderWithAuth(<InventoryManagerPage />);

    const search = screen.getByLabelText(/search stock/i);
    await user.type(search, 'syrup');

    expect(await screen.findByText(/Vanilla Syrup 750ml/i)).toBeInTheDocument();
    expect(screen.queryByText(/Premium Coffee Beans/i)).not.toBeInTheDocument();

    await user.clear(search);
    await user.selectOptions(screen.getByLabelText(/filter by status/i), 'Low stock');

    expect(await screen.findByText(/Premium Coffee Beans/i)).toBeInTheDocument();
  });

  it('creates a draft purchase order and advances it through the lifecycle', async () => {
    const user = userEvent.setup();
    renderWithAuth(<PurchaseOrderManagerPage />);

    expect(await screen.findByRole('heading', { name: /purchase order manager/i })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /create po/i }));
    await screen.findAllByRole('option', { name: /Ceylon Coffee Traders/i });
    await user.click(screen.getByRole('button', { name: /create draft/i }));

    expect((await screen.findAllByText('PO-2141')).length).toBeGreaterThan(0);

    const [advanceButton] = await screen.findAllByRole('button', { name: /advance to in review/i });
    await user.click(advanceButton);

    expect((await screen.findAllByText(/PO-2141 moved to in review/i)).length).toBeGreaterThan(0);
  });
});
