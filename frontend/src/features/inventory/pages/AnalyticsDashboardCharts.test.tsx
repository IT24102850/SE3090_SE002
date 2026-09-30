import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { AnalyticsDashboardPage } from './AnalyticsDashboardCharts';
import { ToastProvider } from '../ui/ToastContext';
import { MemoryRouter } from 'react-router-dom';

describe('inventory sales activity', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it('loads and displays sales totals and recent sale activity', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      const body = path.startsWith('/api/reports/sales-activity')
        ? {
            salesCount: 2,
            totalRevenue: 12500,
            averageSale: 6250,
            costOfGoodsSold: 8000,
            grossProfit: 4500,
            page: 1,
            pageSize: 5,
            totalPages: 1,
            recentSales: [
              {
                id: 'sale-1',
                reference: 'SALE-20260929-001',
                occurredAt: '2026-09-29T07:00:00Z',
                amount: 7500,
                quantity: 3,
                items: ['Coffee Beans'],
                costOfGoodsSold: 6000,
                grossProfit: 1500,
              },
            ],
          }
        : path.startsWith('/api/reports/inventory-usage')
          ? {
              totalReceivedQuantity: 0,
              totalIssuedQuantity: 0,
              netQuantity: 0,
              items: [],
            }
          : {
              items: [
                {
                  id: 'item-1',
                  name: 'Coffee Beans',
                  sku: 'COF-01',
                  quantity: 10,
                  reorderLevel: 2,
                  unitCost: 80,
                  status: 'InStock',
                },
              ],
              totalCount: 1,
              totalPages: 1,
            };
      return {
        ok: true,
        json: async () => body,
      } as Response;
    });
    vi.stubGlobal('fetch', fetchMock);
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({
        matches: false,
        media: '(prefers-color-scheme: dark)',
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(() => false),
      })),
    );

    render(
      <MemoryRouter><AppToastProvider>
        <ToastProvider>
          <AnalyticsDashboardPage />
        </ToastProvider>
      </AppToastProvider></MemoryRouter>,
    );

    expect(await screen.findByText('What’s happening in sales')).toBeInTheDocument();
    expect(screen.getByText('SALE-20260929-001')).toBeInTheDocument();
    expect(screen.getByText('Coffee Beans')).toBeInTheDocument();
    expect(screen.getByText('SALE-20260929-001').closest('.inventory-sales-reference')).toBeInTheDocument();
    expect(screen.getByText('SALE REF')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getAllByText('Gross profit')).toHaveLength(2);
    const revenueMetric = screen.getByText('Sales revenue').closest('article');
    expect(revenueMetric).toHaveClass('inventory-analytics-metric');
    expect(revenueMetric?.querySelector('.inventory-analytics-metric-main')).not.toBeNull();
    expect(revenueMetric?.querySelector('.inventory-analytics-metric-detail')).toHaveTextContent('Revenue from recorded sales');
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringMatching(/^\/api\/reports\/sales-activity\?/),
      expect.anything(),
    );
    await waitFor(() => expect(screen.getByText('Recent sales')).toBeInTheDocument());
  });

  it('links to the dedicated branch performance report', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      const body = path.startsWith('/api/reports/sales-activity')
        ? { salesCount: 0, totalRevenue: 0, averageSale: 0, costOfGoodsSold: 0, grossProfit: 0, page: 1, pageSize: 5, totalPages: 0, recentSales: [] }
        : path.startsWith('/api/reports/inventory-usage')
          ? { totalReceivedQuantity: 0, totalIssuedQuantity: 0, netQuantity: 0, items: [] }
          : { items: [], totalCount: 0, totalPages: 0 };
      return { ok: true, json: async () => body } as Response;
    });
    vi.stubGlobal('fetch', fetchMock);
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

    render(
      <MemoryRouter><AppToastProvider>
        <ToastProvider>
          <AnalyticsDashboardPage />
        </ToastProvider>
      </AppToastProvider></MemoryRouter>,
    );

    const branchLink = await screen.findByRole('link', { name: 'View branch performance' });
    expect(branchLink).toHaveAttribute('href', '/branch-performance');
    expect(fetchMock).not.toHaveBeenCalledWith('/api/inventory/branches', expect.anything());
  });

  it('opens a printable receipt from recent sales', async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      const body = path.startsWith('/api/reports/sales-activity')
        ? {
            salesCount: 1,
            totalRevenue: 7500,
            averageSale: 7500,
            costOfGoodsSold: 6000,
            grossProfit: 1500,
            page: 1,
            pageSize: 5,
            totalPages: 1,
            recentSales: [
              {
                id: 'sale-1',
                reference: 'SALE-20260929-001',
                occurredAt: '2026-09-29T07:00:00Z',
                amount: 7500,
                quantity: 3,
                items: ['Coffee Beans'],
                costOfGoodsSold: 6000,
                grossProfit: 1500,
              },
            ],
          }
        : path.startsWith('/api/reports/inventory-usage')
          ? {
              totalReceivedQuantity: 0,
              totalIssuedQuantity: 0,
              netQuantity: 0,
              items: [],
            }
          : { items: [], totalCount: 0, totalPages: 1 };
      return { ok: true, json: async () => body } as Response;
    });
    vi.stubGlobal('fetch', fetchMock);
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({
        matches: false,
        media: '(prefers-color-scheme: dark)',
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(() => false),
      })),
    );

    render(
      <MemoryRouter><AppToastProvider>
        <ToastProvider>
          <AnalyticsDashboardPage />
        </ToastProvider>
      </AppToastProvider></MemoryRouter>,
    );

    fireEvent.click(await screen.findByRole('button', {
      name: 'View receipt for SALE-20260929-001',
    }));

    const dialog = screen.getByRole('dialog', { name: 'Sales receipt' });
    expect(dialog).toBeInTheDocument();
    expect(within(dialog).getByText('Coffee Beans')).toBeInTheDocument();
    expect(within(dialog).getByText('SALE-20260929-001')).toBeInTheDocument();
    expect(within(dialog).getByText(/7,500\.00/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Print / Save PDF' })).toBeInTheDocument();
    expect(within(dialog).getByText(/not included in the sales activity data/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Close receipt' }));
    expect(screen.queryByRole('dialog', { name: 'Sales receipt' })).not.toBeInTheDocument();
  });

  it('pages through every sale in the selected date range', async () => {
    const requestedPages: number[] = [];
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input);
      if (path.startsWith('/api/reports/sales-activity')) {
        const page = Number(new URL(path, 'http://localhost').searchParams.get('page'));
        requestedPages.push(page);
        return {
          ok: true,
          json: async () => ({
            salesCount: 11,
            totalRevenue: 11000,
            averageSale: 1000,
            costOfGoodsSold: null,
            grossProfit: null,
            page,
            pageSize: 5,
            totalPages: 3,
            recentSales: Array.from({ length: 5 }, (_, index) => {
              const saleNumber = (page - 1) * 5 + index + 1;
              return {
                id: `sale-${saleNumber}`,
                reference: `SALE-${saleNumber}`,
                occurredAt: '2026-09-29T07:00:00Z',
                amount: 1000,
                quantity: 1,
                items: ['Coffee Beans'],
                costOfGoodsSold: null,
                grossProfit: null,
              };
            }),
          }),
        } as Response;
      }

      const body = path.startsWith('/api/reports/inventory-usage')
        ? { totalReceivedQuantity: 0, totalIssuedQuantity: 0, netQuantity: 0, items: [] }
        : { items: [], totalCount: 0, totalPages: 1 };
      return { ok: true, json: async () => body } as Response;
    });
    vi.stubGlobal('fetch', fetchMock);
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({
        matches: false,
        media: '(prefers-color-scheme: dark)',
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(() => false),
      })),
    );

    render(
      <MemoryRouter><AppToastProvider>
        <ToastProvider>
          <AnalyticsDashboardPage />
        </ToastProvider>
      </AppToastProvider></MemoryRouter>,
    );

    expect(await screen.findByText('SALE-1')).toBeInTheDocument();
    expect(screen.getByText('SALE-5')).toBeInTheDocument();
    expect(screen.getByText('Showing 1–5 of 11 sales')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '2' }));

    expect(await screen.findByText('SALE-6')).toBeInTheDocument();
    expect(screen.getByText('SALE-10')).toBeInTheDocument();
    expect(screen.getByText('Showing 6–10 of 11 sales')).toBeInTheDocument();
    expect(requestedPages).toEqual([1, 2]);
    expect(screen.queryByText('SALE-1')).not.toBeInTheDocument();
  });
});
