import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  LineChart,
  Line,
  PieChart,
  Pie,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { Link } from 'react-router-dom';
import { getStoredToken } from '../authToken';
import { useChartTheme } from '../../../shared/useChartTheme';
import { Badge, type BadgeTone } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';

/* ── types ─────────────────────────────────────────────────────────────── */
type InventoryUsageItem = {
  inventoryItemId: string;
  itemName?: string;
  sku?: string;
  receivedQuantity: number;
  issuedQuantity: number;
  netQuantity: number;
  movementCount: number;
};
type InventoryUsageReport = {
  totalReceivedQuantity: number;
  totalIssuedQuantity: number;
  netQuantity: number;
  items: InventoryUsageItem[];
};
type SalesActivityItem = {
  id: string;
  reference: string;
  occurredAt: string;
  amount: number;
  quantity: number;
  items: string[];
  costOfGoodsSold: number | null;
  grossProfit: number | null;
};
type SalesActivityReport = {
  salesCount: number;
  totalRevenue: number;
  averageSale: number;
  costOfGoodsSold: number | null;
  grossProfit: number | null;
  page: number;
  pageSize: number;
  totalPages: number;
  recentSales: SalesActivityItem[];
};
type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  quantity: number;
  reorderLevel: number;
  unitCost?: number;
  category?: string;
  categoryId?: string;
  description?: string;
  status: string;
};
type InventoryListResponse = { items: InventoryItem[]; totalCount: number; totalPages: number };

type Slot<T> = { status: 'loading' } | { status: 'ready'; value: T } | { status: 'failed'; error: string };
const loading = { status: 'loading' } as const;

type DateRange = '7d' | '30d' | '90d';
const SALES_PAGE_SIZE = 5;

/* ── helpers ────────────────────────────────────────────────────────────── */
function settle<T>(result: PromiseSettledResult<T>): Slot<T> {
  return result.status === 'fulfilled'
    ? { status: 'ready', value: result.value }
    : { status: 'failed', error: result.reason instanceof Error ? result.reason.message : 'Request failed' };
}

async function apiGet<T>(path: string, token: string | null): Promise<T> {
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) throw new Error(`${response.status} from ${path.split('?')[0]}`);
  return response.json() as Promise<T>;
}

function compact(value: number) {
  return new Intl.NumberFormat('en-LK', { notation: 'compact', maximumFractionDigits: 1 }).format(value);
}

function lkr(value: number) {
  return new Intl.NumberFormat('en-LK', { style: 'currency', currency: 'LKR', maximumFractionDigits: 0 }).format(value);
}

function statusTone(status: string): BadgeTone {
  if (status === 'OutOfStock') return 'red';
  if (status === 'LowStock') return 'amber';
  return 'green';
}

function dateRangeLabel(r: DateRange) {
  return r === '7d' ? 'Last 7 days' : r === '30d' ? 'Last 30 days' : 'Last 90 days';
}

function saleDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? 'Date unavailable'
    : date.toLocaleString('en-LK', {
        day: 'numeric',
        month: 'short',
        hour: 'numeric',
        minute: '2-digit',
      });
}

function buildDateParams(range: DateRange): string {
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - (range === '7d' ? 7 : range === '30d' ? 30 : 90));
  return `from=${from.toISOString()}&to=${to.toISOString()}`;
}

function pageButtons(currentPage: number, totalPages: number): Array<number | 'ellipsis-start' | 'ellipsis-end'> {
  if (totalPages <= 7) return Array.from({ length: totalPages }, (_, index) => index + 1);
  if (currentPage <= 4) return [1, 2, 3, 4, 5, 'ellipsis-end', totalPages];
  if (currentPage >= totalPages - 3) {
    return [1, 'ellipsis-start', ...Array.from({ length: 5 }, (_, index) => totalPages - 4 + index)];
  }
  return [1, 'ellipsis-start', currentPage - 1, currentPage, currentPage + 1, 'ellipsis-end', totalPages];
}

function exportCsv(rows: ReturnType<typeof buildTableRows>, filename: string) {
  const header = 'Item,SKU,Received,Issued,Net Movement,Movement Records';
  const lines = rows.map(r =>
    [r.name, r.sku, r.received, r.issued, r.net, r.movements].map(v => `"${v}"`).join(',')
  );
  const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}

function buildTableRows(report: InventoryUsageReport) {
  return report.items.map(item => ({
    id: item.inventoryItemId,
    name: item.itemName ?? item.sku ?? 'Inventory item',
    sku: item.sku ?? 'No SKU',
    received: item.receivedQuantity,
    issued: item.issuedQuantity,
    net: item.netQuantity,
    movements: item.movementCount,
  }));
}

async function apiGetAllInventory(token: string | null): Promise<InventoryListResponse> {
  const items: InventoryItem[] = [];
  const itemIds = new Set<string>();
  let page = 1;
  let expectedCount: number | undefined;
  let expectedPages: number | undefined;
  do {
    const result = await apiGet<InventoryListResponse>(
      `/api/inventory?page=${page}&pageSize=100`,
      token,
    );
    if (
      !Array.isArray(result.items) ||
      !Number.isSafeInteger(result.totalCount) ||
      result.totalCount < 0 ||
      !Number.isSafeInteger(result.totalPages) ||
      result.totalPages < 0 ||
      result.totalPages !== Math.ceil(result.totalCount / 100)
    ) {
      throw new Error('Inventory response has invalid items or pagination totals.');
    }
    if (
      (expectedCount !== undefined && expectedCount !== result.totalCount) ||
      (expectedPages !== undefined && expectedPages !== result.totalPages)
    ) {
      throw new Error('Inventory changed while loading. Refresh to capture a complete snapshot.');
    }
    expectedCount ??= result.totalCount;
    expectedPages ??= result.totalPages;
    for (const item of result.items) {
      if (!item || typeof item.id !== 'string' || !item.id.trim()) {
        throw new Error('Inventory response contains an item without a valid ID.');
      }
      if (itemIds.has(item.id)) {
        throw new Error('Inventory pages contain duplicate items. Refresh to capture a complete snapshot.');
      }
      itemIds.add(item.id);
    }
    items.push(...result.items);
    page += 1;
  } while (page <= (expectedPages ?? 0));

  if (items.length !== expectedCount) {
    throw new Error(`Loaded ${items.length} of ${expectedCount} inventory items. Refresh to capture the complete snapshot.`);
  }

  return { items, totalCount: expectedCount ?? 0, totalPages: expectedPages ?? 0 };
}

/* ── sub-components ─────────────────────────────────────────────────────── */
function PanelError({ error, onRetry }: { error: string; onRetry: () => void }) {
  return (
    <div className="analytics-panel-error" role="alert">
      <span className="analytics-panel-error-icon"><Icon name="alert" size={18} /></span>
      <div>
        <p>Could not load this data.</p>
        <small>{error}</small>
      </div>
      <button type="button" className="btn btn-ghost" onClick={onRetry}>Retry</button>
    </div>
  );
}

function PanelEmpty({ children }: { children: React.ReactNode }) {
  return (
    <div className="analytics-panel-empty">
      <Icon name="inventory" size={28} />
      <p>{children}</p>
    </div>
  );
}

function PanelSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div className="analytics-skeleton">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="analytics-skeleton-row" style={{ animationDelay: `${i * 0.07}s` }} />
      ))}
    </div>
  );
}

function Metric({ label, value, detail, tone, icon }: {
  label: string; value: string; detail: string; tone: string; icon: string;
}) {
  return (
    <article className={`inventory-analytics-metric metric-${tone}`}>
      <div className="inventory-analytics-metric-main">
        <span className="inventory-analytics-metric-icon" aria-hidden="true"><Icon name={icon} size={19} /></span>
        <span className="inventory-analytics-metric-copy">
          <span className="inventory-analytics-metric-label">{label}</span>
          <strong>{value}</strong>
        </span>
      </div>
      <div className="inventory-analytics-metric-detail">
        <span aria-hidden="true" />
        <small>{detail}</small>
      </div>
    </article>
  );
}

function SaleReceiptModal({
  sale,
  onClose,
}: {
  sale: SalesActivityItem;
  onClose: () => void;
}) {
  const date = new Date(sale.occurredAt);
  const formattedDate = Number.isNaN(date.getTime())
    ? 'Date unavailable'
    : date.toLocaleString('en-LK', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });

  return (
    <div
      className="modal-overlay inventory-sale-receipt-overlay"
      onClick={onClose}
      role="presentation"
    >
      <article
        className="inventory-sale-receipt-paper"
        onClick={event => event.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="inventory-sale-receipt-title"
      >
        <div className="inventory-sale-receipt-actions">
          <button type="button" className="btn btn-secondary" onClick={() => window.print()}>
            Print / Save PDF
          </button>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={onClose}
            aria-label="Close receipt"
          >
            Close
          </button>
        </div>
        <header className="inventory-sale-receipt-header">
          <p>INVENTORY SALES</p>
          <h2 id="inventory-sale-receipt-title">Sales receipt</h2>
          <span>Recorded transaction</span>
        </header>
        <div className="inventory-sale-receipt-meta">
          <div>
            <span>REFERENCE</span>
            <strong>{sale.reference}</strong>
          </div>
          <div>
            <span>DATE &amp; TIME</span>
            <strong>{formattedDate}</strong>
          </div>
        </div>
        <div className="inventory-sale-receipt-items">
          <div className="inventory-sale-receipt-items-head">
            <span>ITEMS SOLD</span>
            <span>QUANTITY</span>
          </div>
          <div className="inventory-sale-receipt-items-body">
            <strong>{sale.items.length ? sale.items.join(', ') : 'Recorded sale'}</strong>
            <span>{sale.quantity > 0 ? compact(sale.quantity) : '—'}</span>
          </div>
        </div>
        <div className="inventory-sale-receipt-totals">
          {sale.costOfGoodsSold != null && (
            <div><span>Cost of goods sold</span><strong>{lkr(sale.costOfGoodsSold)}</strong></div>
          )}
          {sale.grossProfit != null && (
            <div><span>Gross profit</span><strong>{lkr(sale.grossProfit)}</strong></div>
          )}
          <div className="inventory-sale-receipt-total">
            <span>SALE TOTAL</span>
            <strong>{new Intl.NumberFormat('en-LK', {
              style: 'currency',
              currency: 'LKR',
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            }).format(sale.amount)}</strong>
          </div>
        </div>
        <footer className="inventory-sale-receipt-note">
          This receipt confirms an inventory sale record only. Payment collection,
          customer details, branch, and unit prices are not included in the sales
          activity data.
        </footer>
      </article>
    </div>
  );
}

/* ── main component ─────────────────────────────────────────────────────── */
export function AnalyticsDashboardPage() {
  const token = getStoredToken();
  const chart = useChartTheme();
  const { notify } = useToast();
  const axisTick = { fill: chart.tick, fontSize: 12 };

  const [range, setRange] = useState<DateRange>('30d');
  const [usage, setUsage] = useState<Slot<InventoryUsageReport>>(loading);
  const [inventory, setInventory] = useState<Slot<InventoryListResponse>>(loading);
  const [sales, setSales] = useState<Slot<SalesActivityReport>>(loading);
  const [receiptSale, setReceiptSale] = useState<SalesActivityItem | null>(null);
  const [salesPageLoading, setSalesPageLoading] = useState(false);
  const [salesPageError, setSalesPageError] = useState<string | null>(null);
  const [salesPage, setSalesPage] = useState(1);
  const salesRequestId = useRef(0);

  const load = useCallback(async (showMsg = false) => {
    const requestId = ++salesRequestId.current;
    setUsage(loading);
    setInventory(loading);
    setSales(loading);
    setSalesPageLoading(false);
    setSalesPage(1);
    setSalesPageError(null);
    const dateParams = buildDateParams(range);
    const [movementResult, inventoryResult, salesResult] = await Promise.allSettled([
      apiGet<InventoryUsageReport>(`/api/reports/inventory-usage?${dateParams}`, token),
      apiGetAllInventory(token),
      apiGet<SalesActivityReport>(`/api/reports/sales-activity?${dateParams}&page=1&pageSize=${SALES_PAGE_SIZE}`, token),
    ]);
    const movementSlot = settle(movementResult);
    const inventorySlot = settle(inventoryResult);
    const salesSlot = settle(salesResult);
    if (requestId !== salesRequestId.current) return;
    setUsage(movementSlot);
    setInventory(inventorySlot);
    setSales(salesSlot);
    if (showMsg) {
      if (
        movementSlot.status === 'ready' &&
        inventorySlot.status === 'ready' &&
        salesSlot.status === 'ready'
      ) {
        notify(`Analytics refreshed — ${dateRangeLabel(range)}.`, 'success');
      } else {
        notify('Some data could not be refreshed. Check the panels below.', 'warning');
      }
    }
  }, [notify, token, range]);

  const loadSalesPage = useCallback(async (page: number) => {
    const requestId = ++salesRequestId.current;
    setSalesPageLoading(true);
    setSalesPageError(null);
    try {
      const dateParams = buildDateParams(range);
      const report = await apiGet<SalesActivityReport>(
        `/api/reports/sales-activity?${dateParams}&page=${page}&pageSize=${SALES_PAGE_SIZE}`,
        token,
      );
      if (requestId === salesRequestId.current) {
        setSales({ status: 'ready', value: report });
        setSalesPage(page);
      }
    } catch (error) {
      if (requestId === salesRequestId.current) {
        setSalesPageError(error instanceof Error ? error.message : 'Request failed');
      }
    } finally {
      if (requestId === salesRequestId.current) setSalesPageLoading(false);
    }
  }, [range, token]);

  useEffect(() => { void load(); }, [load]);

  /* derived */
  const anyLoading = usage.status === 'loading' || inventory.status === 'loading' || sales.status === 'loading';
  const failedCount = [usage, inventory, sales].filter(s => s.status === 'failed').length;

  const allRows = useMemo(() =>
    usage.status === 'ready' ? buildTableRows(usage.value) : [], [usage]);

  const chartRows = useMemo(() => allRows.slice(0, 8), [allRows]);

  const stockItems = inventory.status === 'ready'
    ? inventory.value.items.filter(item => item.quantity <= 0 || item.quantity <= item.reorderLevel)
    : [];
  const reorderCount = inventory.status === 'ready' ? stockItems.length : null;
  const inventoryItems = inventory.status === 'ready' ? inventory.value.items : [];

  const inventoryStats = useMemo(() => {
    const categoryLabels = new Set<string>();
    let inStock = 0;
    let low = 0;
    let out = 0;
    let units = 0;
    let value = 0;
    let costedItems = 0;
    for (const item of inventoryItems) {
      units += item.quantity;
      if (item.quantity <= 0) out += 1;
      else if (item.quantity <= item.reorderLevel) low += 1;
      else inStock += 1;
      if (item.category?.trim()) categoryLabels.add(item.category.trim().toLowerCase());
      if (typeof item.unitCost === 'number') {
        value += item.quantity * item.unitCost;
        costedItems += 1;
      }
    }
    return {
      items: inventory.status === 'ready' ? inventory.value.totalCount : 0,
      units,
      value,
      costedItems,
      categoryCount: categoryLabels.size,
      uncategorized: inventoryItems.filter(item => !item.category?.trim()).length,
      inStock,
      low,
      out,
    };
  }, [inventory]);

  const categoryValueData = useMemo(() => {
    const groups = new Map<string, number>();
    for (const item of inventoryItems) {
      const category = item.category?.trim() || 'Uncategorised';
      if (typeof item.unitCost !== 'number') continue;
      groups.set(category, (groups.get(category) ?? 0) + item.quantity * item.unitCost);
    }
    return [...groups.entries()]
      .map(([name, categoryValue]) => ({ name, value: categoryValue }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 6);
  }, [inventory]);

  const movementCount = usage.status === 'ready'
    ? usage.value.items.reduce((t, i) => t + i.movementCount, 0) : null;

  /* stock health pie */
  const healthData = useMemo(() => {
    if (inventory.status !== 'ready') return [];
    return [
      { name: 'In stock', value: inventoryStats.inStock, color: '#17ae83' },
      { name: 'Low stock', value: inventoryStats.low, color: '#e2a126' },
      { name: 'Out of stock', value: inventoryStats.out, color: '#e44e63' },
    ].filter(d => d.value > 0);
  }, [inventory.status, inventoryStats]);

  /* net movement trend (top 5 items) */
  const trendData = useMemo(() => chartRows.slice(0, 5).map(r => ({
    name: r.sku.length > 8 ? r.sku.slice(0, 8) + '…' : r.sku,
    net: r.net,
  })), [chartRows]);

  const sortedStockItems = useMemo(() => [...stockItems].sort((a, b) => {
    if (a.quantity <= 0 && b.quantity > 0) return -1;
    if (b.quantity <= 0 && a.quantity > 0) return 1;
    const aCoverage = a.reorderLevel > 0 ? a.quantity / a.reorderLevel : 1;
    const bCoverage = b.reorderLevel > 0 ? b.quantity / b.reorderLevel : 1;
    return aCoverage - bCoverage;
  }), [stockItems]);

  const healthyShare = inventory.status === 'ready' && inventoryStats.items > 0
    ? inventoryStats.inStock / inventoryStats.items
    : 0;

  return (
    <div className="page inventory-analytics-page">

      {/* ── HERO ── */}
      <header className="inventory-analytics-hero panel">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="inventory-analytics-orbit" aria-hidden="true">
          <span className="inventory-analytics-orbit-inner" />
          <span className="inventory-analytics-orbit-dot" />
          <i><Icon name="chart" size={24} /></i>
        </div>
        <div className="inventory-analytics-hero-top">
          <span className="inventory-analytics-mark btn btn-ghost"><Icon name="chart" size={16} /></span>
          <span className="inventory-analytics-period badge badge-blue">{dateRangeLabel(range).toUpperCase()}</span>
        </div>
        <div className="inventory-analytics-hero-content">
          <div>
            <p className="eyebrow">INVENTORY INTELLIGENCE / ANALYTICS</p>
            <h1>Your stock, in focus</h1>
            <p>One complete view of stock on hand, value, movement and items needing attention.</p>
          </div>
          <div className="inventory-analytics-hero-actions">
            {/* Date range picker */}
            <div className="inventory-analytics-range-tabs" role="group" aria-label="Date range">
              {(['7d', '30d', '90d'] as DateRange[]).map(r => (
                <button
                  key={r}
                  type="button"
                  className={`inventory-analytics-range-tab${range === r ? ' is-active' : ''}`}
                  onClick={() => setRange(r)}
                  disabled={anyLoading}
                >
                  {r === '7d' ? '7 days' : r === '30d' ? '30 days' : '90 days'}
                </button>
              ))}
            </div>
            <button
              type="button"
              className={`btn inventory-analytics-refresh${anyLoading ? ' is-refreshing' : ''}`}
              onClick={() => void load(true)}
              disabled={anyLoading}
            >
              <Icon name="workflow" size={16} />
              <span>{anyLoading ? 'Updating…' : 'Refresh'}</span>
            </button>
          </div>
        </div>
        <div className="inventory-analytics-hero-foot">
          <span>
            <i className={anyLoading ? 'is-loading' : failedCount ? 'is-warning' : 'is-ready'} />
            {anyLoading
              ? 'Syncing inventory records'
              : failedCount
                ? `${failedCount} data source${failedCount > 1 ? 's' : ''} need attention`
                : 'Live inventory data'}
          </span>
          <span>Snapshot covers all accessible items · date range filters activity only</span>
        </div>
      </header>

      <section className="inventory-analytics-overview" aria-label="Whole inventory snapshot">
        <div className="inventory-analytics-section-heading">
          <div>
            <p className="eyebrow">WHOLE INVENTORY</p>
            <h2>Stock at a glance</h2>
          </div>
          <span>Current stock · all accessible items</span>
        </div>
        <div className="inventory-analytics-metrics inventory-analytics-snapshot">
          <Metric
            label="Items tracked"
            value={inventory.status === 'ready' ? compact(inventoryStats.items) : '—'}
            detail={`${compact(inventoryStats.categoryCount)} categories represented`}
            tone="blue"
            icon="inventory"
          />
          <Metric
            label="Units on hand"
            value={inventory.status === 'ready' ? compact(inventoryStats.units) : '—'}
            detail="Across all loaded items"
            tone="teal"
            icon="workflow"
          />
          <Metric
            label="Estimated stock value"
            value={inventory.status === 'ready' ? lkr(inventoryStats.value) : '—'}
            detail={`${compact(inventoryStats.costedItems)} items with unit cost`}
            tone="violet"
            icon="chart"
          />
          <Metric
            label="Reorder alerts"
            value={inventory.status === 'ready' ? compact(reorderCount ?? 0) : '—'}
            detail={`${compact(inventoryStats.low)} low · ${compact(inventoryStats.out)} out of stock`}
            tone="amber"
            icon="alert"
          />
        </div>
        <div className="inventory-analytics-health">
          <div className="inventory-analytics-health-copy">
            <span className="inventory-analytics-health-icon"><Icon name="workflow" size={17} /></span>
            <span><strong>Healthy stock</strong><small>Above reorder level</small></span>
          </div>
          <div
            className="inventory-analytics-health-track"
            role="progressbar"
            aria-label="Items above reorder level"
            aria-valuemin={0}
            aria-valuemax={inventory.status === 'ready' ? inventoryStats.items : 0}
            aria-valuenow={inventory.status === 'ready' ? inventoryStats.inStock : 0}
          >
            <span style={{ width: `${healthyShare * 100}%` }} />
          </div>
          <strong className="inventory-analytics-health-count">
            {inventory.status === 'ready'
              ? `${compact(inventoryStats.inStock)} / ${compact(inventoryStats.items)}`
              : '—'}
          </strong>
        </div>
      </section>

      {/* ── PERIOD MOVEMENT METRICS ── */}
      <section className="inventory-analytics-movement-summary" aria-label={`Inventory movement summary for ${dateRangeLabel(range)}`}>
        <div className="inventory-analytics-section-heading">
          <div>
            <p className="eyebrow">PERIOD ACTIVITY</p>
            <h2>Movement summary</h2>
          </div>
          <span>{dateRangeLabel(range)} · changes during this period</span>
        </div>
        <div className="inventory-analytics-metrics">
          <Metric
            label="Units issued"
            value={usage.status === 'ready' ? compact(usage.value.totalIssuedQuantity) : '—'}
            detail="Used or transferred out"
            tone="violet"
            icon="movement"
          />
          <Metric
            label="Units received"
            value={usage.status === 'ready' ? compact(usage.value.totalReceivedQuantity) : '—'}
            detail="Added to inventory"
            tone="teal"
            icon="inventory"
          />
          <Metric
            label="Net stock movement"
            value={usage.status === 'ready'
              ? `${usage.value.netQuantity > 0 ? '+' : ''}${compact(usage.value.netQuantity)}`
              : '—'}
            detail="Received minus issued"
            tone="blue"
            icon="workflow"
          />
          <Metric
            label="Movement records"
            value={movementCount == null ? '—' : compact(movementCount)}
            detail="Recorded events in this period"
            tone="amber"
            icon="movement"
          />
        </div>
      </section>

      <section
        className="inventory-analytics-sales-summary"
        aria-label={`Sales summary for ${dateRangeLabel(range)}`}
      >
        <div className="inventory-analytics-section-heading">
          <div>
            <p className="eyebrow">SALES ACTIVITY</p>
            <h2>What’s happening in sales</h2>
          </div>
          <span>{dateRangeLabel(range)} · recorded sales</span>
        </div>
        <div className="inventory-sales-branch-action">
          <div>
            <strong>Compare branch performance</strong>
            <span>Explore branch sales, profit, stock value and health side by side.</span>
          </div>
          <Link to="/branch-performance" className="btn btn-secondary">View branch performance</Link>
        </div>
        <div className="inventory-analytics-metrics">
          <Metric
            label="Sales recorded"
            value={sales.status === 'ready' ? compact(sales.value.salesCount) : '—'}
            detail="Completed sales in this period"
            tone="blue"
            icon="chart"
          />
          <Metric
            label="Sales revenue"
            value={sales.status === 'ready' ? lkr(sales.value.totalRevenue) : '—'}
            detail="Revenue from recorded sales"
            tone="teal"
            icon="workflow"
          />
          <Metric
            label="Cost of goods sold"
            value={sales.status === 'ready' && sales.value.costOfGoodsSold != null
              ? lkr(sales.value.costOfGoodsSold)
              : '—'}
            detail={sales.status === 'ready' && sales.value.costOfGoodsSold == null
              ? 'Set unit costs to calculate'
              : 'Recorded cost of sold stock'}
            tone="amber"
            icon="inventory"
          />
          <Metric
            label="Gross profit"
            value={sales.status === 'ready' && sales.value.grossProfit != null
              ? lkr(sales.value.grossProfit)
              : '—'}
            detail={sales.status === 'ready' && sales.value.grossProfit == null
              ? 'Cost data is incomplete'
              : 'Sales revenue minus stock cost'}
            tone="green"
            icon="chart"
          />
          <Metric
            label="Average sale"
            value={sales.status === 'ready' ? lkr(sales.value.averageSale) : '—'}
            detail="Average value per sale"
            tone="violet"
            icon="inventory"
          />
        </div>
        <article className="panel inventory-analytics-panel inventory-sales-activity-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">RECENTLY RECORDED</p>
              <h2>Recent sales</h2>
              <p>All completed sales within the selected date range, shown page by page.</p>
            </div>
            <span className="inventory-analytics-panel-icon">
              <Icon name="chart" size={18} />
            </span>
          </div>
          {sales.status === 'failed' ? (
            <PanelError error={sales.error} onRetry={() => void load()} />
          ) : sales.status === 'loading' ? (
            <PanelSkeleton rows={4} />
          ) : sales.value.recentSales.length === 0 ? (
            <PanelEmpty>No sales have been recorded in this period.</PanelEmpty>
          ) : (
            <>
              <div className="table-wrap inventory-sales-activity-table-wrap">
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>When</th>
                      <th>Items sold</th>
                      <th>Quantity</th>
                      <th>Reference</th>
                      <th className="inventory-sales-profit-heading">Gross profit</th>
                      <th className="inventory-sales-amount-heading">Sale total</th>
                      <th>Receipt</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sales.value.recentSales.map(sale => (
                      <tr key={sale.id}>
                        <td>{saleDate(sale.occurredAt)}</td>
                        <td>
                          <strong>{sale.items.length ? sale.items.join(', ') : 'Recorded sale'}</strong>
                        </td>
                        <td>{sale.quantity > 0 ? compact(sale.quantity) : '—'}</td>
                        <td>
                          <span className="inventory-sales-reference">
                            <span className="inventory-sales-reference-mark" aria-hidden="true">#</span>
                            <span className="inventory-sales-reference-copy">
                              <small>SALE REF</small>
                              <strong>{sale.reference}</strong>
                            </span>
                          </span>
                        </td>
                        <td className="inventory-sales-profit">
                          {sale.grossProfit == null ? 'Cost data missing' : lkr(sale.grossProfit)}
                        </td>
                        <td className="inventory-sales-amount">{lkr(sale.amount)}</td>
                        <td>
                          <button
                            type="button"
                            className="link-button inventory-sale-receipt-action"
                            onClick={() => setReceiptSale(sale)}
                            aria-label={`View receipt for ${sale.reference}`}
                          >
                            View receipt
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="table-footer inventory-sales-activity-footer">
                <p className="table-caption">
                  {`Showing ${(salesPage - 1) * SALES_PAGE_SIZE + 1}–${Math.min(salesPage * SALES_PAGE_SIZE, sales.value.salesCount)} of ${sales.value.salesCount} sales`}
                </p>
                {sales.value.totalPages > 1 && (
                  <nav className="pagination" aria-label="Sales activity pagination">
                    <button
                      type="button"
                      className="pagination-btn"
                      disabled={salesPage <= 1 || salesPageLoading}
                      onClick={() => void loadSalesPage(salesPage - 1)}
                    >
                      Previous
                    </button>
                    {pageButtons(salesPage, sales.value.totalPages).map((pageNum, index) =>
                      typeof pageNum === 'number' ? (
                        <button
                          key={pageNum}
                          type="button"
                          className={`pagination-btn${pageNum === salesPage ? ' pagination-btn-active' : ''}`}
                          aria-current={pageNum === salesPage ? 'page' : undefined}
                          disabled={salesPageLoading}
                          onClick={() => void loadSalesPage(pageNum)}
                        >
                          {pageNum}
                        </button>
                      ) : (
                        <span key={`${pageNum}-${index}`} className="pagination-ellipsis" aria-hidden="true">…</span>
                      ),
                    )}
                    <button
                      type="button"
                      className="pagination-btn"
                      disabled={salesPage >= sales.value.totalPages || salesPageLoading}
                      onClick={() => void loadSalesPage(salesPage + 1)}
                    >
                      Next
                    </button>
                  </nav>
                )}
                {salesPageError && (
                  <div className="inventory-sales-page-error" role="alert">
                    <span>{salesPageError}</span>
                    <button type="button" className="link-button" onClick={() => void loadSalesPage(salesPage)}>
                      Retry
                    </button>
                  </div>
                )}
              </div>
            </>
          )}
        </article>
      </section>
      {receiptSale && (
        <SaleReceiptModal
          sale={receiptSale}
          onClose={() => setReceiptSale(null)}
        />
      )}

      {/* ── MAIN CHARTS GRID ── */}
      <section className="inventory-analytics-grid">

        {/* Stock flow bar chart */}
        <article className="panel inventory-analytics-panel inventory-flow-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">STOCK FLOW</p>
              <h2>Received vs. Issued</h2>
              <p>Top items by recorded stock movement in the selected period.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="movement" size={18} /></span>
          </div>
          {usage.status === 'failed' ? (
            <PanelError error={usage.error} onRetry={() => void load()} />
          ) : usage.status === 'loading' ? (
            <PanelSkeleton rows={5} />
          ) : chartRows.length === 0 ? (
            <PanelEmpty>No stock movements were recorded in this period.</PanelEmpty>
          ) : (
            <div className="inventory-flow-chart">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartRows} margin={{ top: 12, right: 18, left: 0, bottom: 4 }} barGap={8}>
                  <CartesianGrid stroke={chart.grid} vertical={false} />
                  <XAxis dataKey="sku" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick} width={44} />
                  <Tooltip contentStyle={chart.tooltip} itemStyle={chart.tooltipItem} labelStyle={chart.tooltipItem} />
                  <Legend />
                  <Bar dataKey="received" name="Received" fill={chart.series.green} radius={[6, 6, 0, 0]} />
                  <Bar dataKey="issued" name="Issued" fill={chart.series.amber} radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
          {movementCount != null && (
            <div className="inventory-analytics-panel-foot">
              Based on {compact(movementCount)} recorded stock movements.
            </div>
          )}
        </article>

        {/* Reorder watch */}
        <article className="panel inventory-analytics-panel reorder-watch-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">REORDER WATCH</p>
              <h2>Needs Attention</h2>
              <p>
                {reorderCount == null
                  ? 'Current stock against reorder levels.'
                  : `${reorderCount} item${reorderCount === 1 ? '' : 's'} at or below reorder level.`}
              </p>
            </div>
            <span className="inventory-analytics-panel-icon warning"><Icon name="alert" size={18} /></span>
          </div>
          {inventory.status === 'failed' ? (
            <PanelError error={inventory.error} onRetry={() => void load()} />
          ) : inventory.status === 'loading' ? (
            <PanelSkeleton rows={5} />
          ) : stockItems.length === 0 ? (
            <PanelEmpty>All listed inventory is above its reorder level.</PanelEmpty>
          ) : (
            <div className="inventory-reorder-list">
              {sortedStockItems.slice(0, 7).map(item => {
                const fill = item.reorderLevel > 0
                  ? Math.min(100, Math.round((item.quantity / item.reorderLevel) * 100))
                  : 0;
                const status = item.quantity <= 0 ? 'OutOfStock' : 'LowStock';
                return (
                  <div className="inventory-reorder-item" key={item.id}>
                    <div className="inventory-reorder-copy">
                      <div>
                        <strong>{item.name}</strong>
                        <small>{item.sku}</small>
                      </div>
                      <Badge tone={statusTone(status)}>
                        {item.quantity} / {item.reorderLevel}
                      </Badge>
                    </div>
                    <div
                      className="inventory-reorder-track"
                      aria-label={`${item.name}: ${fill}% of reorder level`}
                    >
                      <span
                        style={{ width: `${fill}%` }}
                        className={item.quantity <= 0 ? 'is-empty' : 'is-low'}
                      />
                    </div>
                  </div>
                );
              })}
              {reorderCount != null && reorderCount > 7 && (
                <p className="inventory-reorder-more">+{reorderCount - 7} more items need review</p>
              )}
            </div>
          )}
        </article>
      </section>

      {/* ── SECONDARY CHARTS ROW ── */}
      <section className="inventory-analytics-grid inventory-analytics-grid-secondary">

        {/* Net movement trend line chart */}
        <article className="panel inventory-analytics-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">NET MOVEMENT TREND</p>
              <h2>Top 5 Items — Net Stock</h2>
              <p>Positive net = more received than issued. Negative = drawdown.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="chart" size={18} /></span>
          </div>
          {usage.status === 'failed' ? (
            <PanelError error={usage.error} onRetry={() => void load()} />
          ) : usage.status === 'loading' ? (
            <PanelSkeleton rows={4} />
          ) : trendData.length === 0 ? (
            <PanelEmpty>No trend data available for this period.</PanelEmpty>
          ) : (
            <div className="inventory-flow-chart">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={trendData} margin={{ top: 12, right: 18, left: 0, bottom: 4 }}>
                  <CartesianGrid stroke={chart.grid} vertical={false} />
                  <XAxis dataKey="name" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick} width={44} />
                  <Tooltip contentStyle={chart.tooltip} itemStyle={chart.tooltipItem} labelStyle={chart.tooltipItem} />
                  <Line
                    type="monotone"
                    dataKey="net"
                    name="Net movement"
                    stroke={chart.series.blue ?? '#4b73dc'}
                    strokeWidth={2.5}
                    dot={{ r: 4 }}
                    activeDot={{ r: 6 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>

        {/* Stock health pie chart */}
        <article className="panel inventory-analytics-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">STOCK HEALTH</p>
              <h2>Status Distribution</h2>
              <p>Distribution across the complete accessible inventory.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="chart" size={18} /></span>
          </div>
          {inventory.status === 'failed' ? (
            <PanelError error={inventory.error} onRetry={() => void load()} />
          ) : inventory.status === 'loading' ? (
            <PanelSkeleton rows={3} />
          ) : healthData.length === 0 ? (
            <PanelEmpty>No stock health data available.</PanelEmpty>
          ) : (
            <div className="inventory-health-chart">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={healthData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="48%"
                    outerRadius={84}
                    innerRadius={58}
                    paddingAngle={3}
                  >
                    {healthData.map((entry, idx) => (
                      <Cell key={idx} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip contentStyle={chart.tooltip} itemStyle={chart.tooltipItem} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>

        <article className="panel inventory-analytics-panel inventory-category-value-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">CATEGORY VALUE</p>
              <h2>Where stock value sits</h2>
              <p>On-hand value by saved category, for items with unit cost.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="inventory" size={18} /></span>
          </div>
          {inventory.status === 'failed' ? (
            <PanelError error={inventory.error} onRetry={() => void load()} />
          ) : inventory.status === 'loading' ? (
            <PanelSkeleton rows={4} />
          ) : categoryValueData.length === 0 ? (
            <PanelEmpty>No category valuation is available yet.</PanelEmpty>
          ) : (
            <div className="inventory-category-value-chart">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={categoryValueData} layout="vertical" margin={{ top: 4, right: 18, left: 8, bottom: 4 }}>
                  <CartesianGrid stroke={chart.grid} horizontal={false} />
                  <XAxis type="number" tickLine={false} axisLine={false} tick={axisTick} tickFormatter={compact} />
                  <YAxis type="category" dataKey="name" tickLine={false} axisLine={false} tick={axisTick} width={104} />
                  <Tooltip
                    contentStyle={chart.tooltip}
                    itemStyle={chart.tooltipItem}
                    formatter={(value) => lkr(Number(value))}
                  />
                  <Bar dataKey="value" name="On-hand value" fill={chart.series.blue ?? '#4b73dc'} radius={[0, 7, 7, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
          {inventory.status === 'ready' && inventoryStats.uncategorized > 0 && (
            <div className="inventory-category-value-note">
              {compact(inventoryStats.uncategorized)} items have no saved category and are grouped as Uncategorised.
            </div>
          )}
        </article>
      </section>

      {/* ── MOVEMENT DETAIL TABLE ── */}
      <section className="panel inventory-analytics-panel inventory-movers-panel">
        <div className="inventory-analytics-panel-head">
          <div>
            <p className="eyebrow">MOVEMENT DETAIL</p>
            <h2>Most Active Inventory</h2>
            <p>Receipts and issues grouped by item. Net movement reveals stock build-up or drawdown.</p>
          </div>
          <div className="inventory-analytics-panel-head-actions">
            {usage.status === 'ready' && (
              <Badge tone="blue">{usage.value.items.length} items moved</Badge>
            )}
            {usage.status === 'ready' && allRows.length > 0 && (
              <button
                type="button"
                className="btn btn-ghost inventory-analytics-export-btn"
                onClick={() => exportCsv(allRows, `inventory-movement-${range}.csv`)}
                title="Export to CSV"
              >
                <Icon name="workflow" size={15} /> Export CSV
              </button>
            )}
          </div>
        </div>
        {usage.status === 'failed' ? (
          <PanelError error={usage.error} onRetry={() => void load()} />
        ) : usage.status === 'loading' ? (
          <PanelSkeleton rows={6} />
        ) : allRows.length === 0 ? (
          <PanelEmpty>No item-level movement detail is available yet.</PanelEmpty>
        ) : (
          <div className="table-wrap inventory-movers-table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>SKU</th>
                  <th>Received</th>
                  <th>Issued</th>
                  <th>Net Movement</th>
                  <th>Records</th>
                </tr>
              </thead>
              <tbody>
                {allRows.map(item => (
                  <tr key={item.id}>
                    <td><strong>{item.name}</strong></td>
                    <td><span className="cell-sub">{item.sku}</span></td>
                    <td><span className="inventory-value-positive">+{compact(item.received)}</span></td>
                    <td><span className="inventory-value-negative">−{compact(item.issued)}</span></td>
                    <td>
                      <strong className={item.net < 0 ? 'inventory-value-negative' : 'inventory-value-positive'}>
                        {item.net > 0 ? '+' : ''}{compact(item.net)}
                      </strong>
                    </td>
                    <td>{item.movements}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <p className="inventory-analytics-disclaimer">
        Analytics reflect recorded inventory movements and current reorder settings for the selected period.
        Missing or unrecorded movements are not estimated.
      </p>
    </div>
  );
}
