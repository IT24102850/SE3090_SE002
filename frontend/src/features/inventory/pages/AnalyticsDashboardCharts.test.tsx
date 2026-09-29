import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { AnalyticsDashboardPage } from './AnalyticsDashboardCharts';
import { ToastProvider } from '../ui/ToastContext';

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
      <AppToastProvider>
        <ToastProvider>
          <AnalyticsDashboardPage />
        </ToastProvider>
      </AppToastProvider>,
    );

    expect(await screen.findByText('What’s happening in sales')).toBeInTheDocument();
    expect(screen.getByText('SALE-20260929-001')).toBeInTheDocument();
    expect(screen.getByText('Coffee Beans')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getAllByText('Gross profit')).toHaveLength(2);
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringMatching(/^\/api\/reports\/sales-activity\?/),
      expect.anything(),
    );
    await waitFor(() => expect(screen.getByText('Recent sales')).toBeInTheDocument());
  });
});
