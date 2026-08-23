import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement } from 'react';
import { AuthProvider, createDemoToken } from '../auth/AuthContext';
import { ToastProvider } from '../ui/ToastContext';
import { AnalyticsDashboardPage } from './AnalyticsDashboardCharts';
import { InventoryManagerPage } from './InventoryManagerPage';
import { PurchaseOrderManagerPage } from './PurchaseOrderManagerPage';

function renderWithAuth(ui: ReactElement) {
  localStorage.setItem('sme.access-token', createDemoToken('Admin'));
  return render(
    <AuthProvider>
      <ToastProvider>{ui}</ToastProvider>
    </AuthProvider>
  );
}

describe('frontend dashboard and workflow components', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal('fetch', vi.fn(() => Promise.reject(new Error('offline'))));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('renders the analytics dashboard with fallback KPI cards and chart summary', async () => {
    renderWithAuth(<AnalyticsDashboardPage />);

    expect(await screen.findByRole('heading', { name: /analytics dashboard/i })).toBeInTheDocument();
    expect(screen.getByText('Revenue')).toBeInTheDocument();
    expect(await screen.findByText(/using sample fallback/i)).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText(/LKR\s*892,000/i)).toBeInTheDocument());
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
    await user.click(screen.getByRole('button', { name: /create draft/i }));

    expect((await screen.findAllByText('PO-2148')).length).toBeGreaterThan(0);

    const [advanceButton] = await screen.findAllByRole('button', { name: /advance to in review/i });
    await user.click(advanceButton);

    expect((await screen.findAllByText(/PO-2148 moved to in review/i)).length).toBeGreaterThan(0);
  });
});
