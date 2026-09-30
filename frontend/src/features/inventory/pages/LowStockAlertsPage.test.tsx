import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { LowStockAlertsPage } from './LowStockAlertsPage';

const scrollIntoView = vi.fn();
const originalScrollIntoView = HTMLElement.prototype.scrollIntoView;

describe('LowStockAlertsPage inventory scope', () => {
  beforeEach(() => {
    scrollIntoView.mockClear();
    Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', {
      configurable: true,
      value: scrollIntoView,
    });
    vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false })));
    localStorage.setItem('token', 'test-token');
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({
      items: [{
        id: 'item-1',
        name: 'Tea Leaves',
        sku: 'TEA-001',
        branch: 'Main branch',
        branchId: 'branch-1',
        quantity: 12,
        reorderLevel: 2,
        unitCost: 50,
      }],
      totalPages: 1,
      totalCount: 1,
    }), { status: 200 })));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    if (originalScrollIntoView) {
      Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', {
        configurable: true,
        value: originalScrollIntoView,
      });
    } else {
      Reflect.deleteProperty(HTMLElement.prototype, 'scrollIntoView');
    }
    localStorage.clear();
  });

  it('keeps catalogue details in Inventory Manager instead of repeating them', async () => {
    render(
      <AppToastProvider>
        <ToastProvider>
          <MemoryRouter>
            <LowStockAlertsPage />
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>,
    );

    await screen.findByRole('option', { name: 'Main branch' });

    expect(screen.queryByRole('heading', { name: 'Inventory status' })).not.toBeInTheDocument();
    expect(screen.queryByText('Tea Leaves')).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Open Inventory Manager' })).toHaveAttribute('href', '/inventory');
  });

  it('explains recommendation confidence and assumptions for review', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === '/api/inventory/agent/plan') {
        return new Response(JSON.stringify({
          workflow_id: 'workflow-1',
          status: 'NeedsReview',
          planner_summary: 'Review stock coverage for Tea Leaves.',
          data_sources: ['Authorized inventory snapshot', 'Recent stock movements'],
          created_at: '2026-09-30T06:00:00Z',
          recommendations: [{
            inventory_item_id: 'item-1',
            item_name: 'Tea Leaves',
            sku: 'TEA-001',
            branch_id: 'branch-1',
            branch_name: 'Main branch',
            on_hand: 1,
            reorder_level: 3,
            avg_daily_outflow: 0.5,
            days_until_reorder: 0,
            recommended_quantity: 10,
            estimated_total_cost: 500,
            confidence: 0.55,
            reason: 'Stock is below the reorder level.',
            validation_notes: ['Uses recent recorded outflow.', 'Review supplier availability before ordering.'],
          }],
          insights: [{
            category: 'coverage',
            title: 'Short stock cover',
            detail: 'Tea Leaves are projected to reach the reorder point soon.',
            affected_items: ['Tea Leaves'],
          }],
          warnings: [],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        items: [{
          id: 'item-1',
          name: 'Tea Leaves',
          sku: 'TEA-001',
          branch: 'Main branch',
          branchId: 'branch-1',
          quantity: 1,
          reorderLevel: 3,
          unitCost: 50,
        }],
        totalPages: 1,
        totalCount: 1,
      }), { status: 200 });
    }));

    render(
      <AppToastProvider>
        <ToastProvider>
          <MemoryRouter>
            <LowStockAlertsPage />
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: /Analyze inventory/i }));

    expect(await screen.findByText('55%')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'What StockSense found' })).toBeInTheDocument();
    expect(screen.getByText('Estimated reorder cost')).toBeInTheDocument();
    expect(screen.getByText('1 of 1 suggestions have a recorded unit cost')).toBeInTheDocument();
    expect(screen.getByText('Usage-backed suggestions')).toBeInTheDocument();
    expect(screen.getByText('Authorized inventory snapshot')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Short stock cover' })).toBeInTheDocument();
    expect(screen.getByText((_, element) =>
      element?.classList.contains('stocksense-recommendation-timing') === true
      && element.textContent?.includes('Already below the reorder point (1 on hand; reorder at 3).') === true,
    )).toBeInTheDocument();
    expect(screen.getByText('Some movement evidence')).toBeInTheDocument();
    expect(screen.getByText('Stock is below the reorder level.')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Why this was suggested and what to verify'));
    expect(screen.getByText('Review supplier availability before ordering.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Review order' })).toHaveAttribute(
      'href',
      '/purchase-orders?reorderItemId=item-1&branchId=branch-1&quantity=10',
    );
    expect(scrollIntoView.mock.contexts.map((element) => (element as HTMLElement).id)).toEqual([
      'stocksense-analysis-progress',
      'stocksense-analysis-report',
    ]);
  });

  it('does not display a rounded near-zero estimate as zero days', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === '/api/inventory/agent/plan') {
        return new Response(JSON.stringify({
          workflow_id: 'workflow-2',
          status: 'NeedsReview',
          planner_summary: 'Review stock coverage.',
          data_sources: [],
          recommendations: [{
            inventory_item_id: 'item-2',
            item_name: 'Syringes',
            sku: 'SURG-003',
            on_hand: 48,
            reorder_level: 50,
            avg_daily_outflow: 0.29,
            days_until_reorder: 0,
            recommended_quantity: 2,
            confidence: 0.4,
            reason: 'Stock is below the reorder level.',
            validation_notes: [],
          }],
          insights: [],
          warnings: [],
        }), { status: 200 });
      }
      return new Response(JSON.stringify({
        items: [{
          id: 'item-2',
          name: 'Syringes',
          sku: 'SURG-003',
          branch: 'Main branch',
          branchId: 'branch-1',
          quantity: 48,
          reorderLevel: 50,
        }],
        totalPages: 1,
        totalCount: 1,
      }), { status: 200 });
    }));

    render(
      <AppToastProvider>
        <ToastProvider>
          <MemoryRouter>
            <LowStockAlertsPage />
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>,
    );

    fireEvent.click(await screen.findByRole('button', { name: /Analyze inventory/i }));

    expect(await screen.findByText((_, element) =>
      element?.classList.contains('stocksense-recommendation-timing') === true
      && element.textContent?.includes('Already below the reorder point (48 on hand; reorder at 50).') === true,
    )).toBeInTheDocument();
    expect(screen.queryByText(/0 days/)).not.toBeInTheDocument();
  });
});
