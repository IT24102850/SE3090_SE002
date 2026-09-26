import { useCallback, useEffect, useMemo, useState } from 'react';
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
type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  quantity: number;
  reorderLevel: number;
  unitCost?: number;
  status: string;
};
type InventoryListResponse = { items: InventoryItem[]; totalCount: number };

type Slot<T> = { status: 'loading' } | { status: 'ready'; value: T } | { status: 'failed'; error: string };
const loading = { status: 'loading' } as const;

type DateRange = '7d' | '30d' | '90d';

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

function buildDateParams(range: DateRange): string {
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - (range === '7d' ? 7 : range === '30d' ? 30 : 90));
  return `from=${from.toISOString()}&to=${to.toISOString()}`;
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
      <span className="inventory-analytics-metric-icon"><Icon name={icon} size={19} /></span>
      <span className="inventory-analytics-metric-label">{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
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
  const [lowStock, setLowStock] = useState<Slot<InventoryListResponse>>(loading);

  const load = useCallback(async (showMsg = false) => {
    setUsage(loading);
    setLowStock(loading);
    const dateParams = buildDateParams(range);
    const [movementResult, stockResult] = await Promise.allSettled([
      apiGet<InventoryUsageReport>(`/api/reports/inventory-usage?${dateParams}`, token),
      apiGet<InventoryListResponse>('/api/inventory/low-stock?pageSize=100', token),
    ]);
    const movementSlot = settle(movementResult);
    const stockSlot = settle(stockResult);
    setUsage(movementSlot);
    setLowStock(stockSlot);
    if (showMsg) {
      if (movementSlot.status === 'ready' && stockSlot.status === 'ready') {
        notify(`Analytics refreshed — ${dateRangeLabel(range)}.`, 'success');
      } else {
        notify('Some data could not be refreshed. Check the panels below.', 'warning');
      }
    }
  }, [notify, token, range]);

  useEffect(() => { void load(); }, [load]);

  /* derived */
  const anyLoading = usage.status === 'loading' || lowStock.status === 'loading';
  const failedCount = [usage, lowStock].filter(s => s.status === 'failed').length;

  const allRows = useMemo(() =>
    usage.status === 'ready' ? buildTableRows(usage.value) : [], [usage]);

  const chartRows = useMemo(() => allRows.slice(0, 8), [allRows]);

  const stockItems = lowStock.status === 'ready' ? lowStock.value.items : [];
  const reorderCount = lowStock.status === 'ready' ? lowStock.value.totalCount : null;

  const movementCount = usage.status === 'ready'
    ? usage.value.items.reduce((t, i) => t + i.movementCount, 0) : null;

  /* stock health pie */
  const healthData = useMemo(() => {
    if (lowStock.status !== 'ready') return [];
    const inStock = Math.max(0, (lowStock.value.totalCount > 0 ? 0 : 1));
    const low = stockItems.filter(i => i.status === 'LowStock').length;
    const out = stockItems.filter(i => i.status === 'OutOfStock').length;
    const ok = stockItems.length - low - out;
    return [
      { name: 'Healthy', value: ok, color: '#17ae83' },
      { name: 'Low stock', value: low, color: '#e2a126' },
      { name: 'Out of stock', value: out, color: '#e44e63' },
    ].filter(d => d.value > 0);
    void inStock;
  }, [lowStock, stockItems]);

  /* net movement trend (top 5 items) */
  const trendData = useMemo(() => chartRows.slice(0, 5).map(r => ({
    name: r.sku.length > 8 ? r.sku.slice(0, 8) + '…' : r.sku,
    net: r.net,
  })), [chartRows]);

  /* LKR cost estimate */
  const totalCostEstimate = useMemo(() => {
    if (lowStock.status !== 'ready') return null;
    return stockItems.reduce((sum, i) => sum + (i.quantity * (i.unitCost ?? 0)), 0);
  }, [lowStock, stockItems]);

  return (
    <div className="page inventory-analytics-page">

      {/* ── HERO ── */}
      <header className="inventory-analytics-hero panel">
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
            <h1>Inventory Analytics</h1>
            <p>See what moved, what needs replenishing, and where stock is building up.</p>
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
          <span>Movements and reorder levels · Read only</span>
        </div>
      </header>

      {/* ── KPI METRICS ── */}
      <section className="inventory-analytics-metrics" aria-label="Inventory movement summary">
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
          label="Below reorder level"
          value={reorderCount == null ? '—' : compact(reorderCount)}
          detail="Items to review"
          tone="amber"
          icon="alert"
        />
      </section>

      {/* ── COST HIGHLIGHT (when data available) ── */}
      {totalCostEstimate != null && totalCostEstimate > 0 && (
        <div className="inventory-analytics-cost-banner panel">
          <span className="inventory-analytics-cost-icon"><Icon name="inventory" size={17} /></span>
          <span>
            Estimated on-hand stock value: <strong>{lkr(totalCostEstimate)}</strong>
          </span>
          <span className="inventory-analytics-cost-note">Based on items with unit cost recorded</span>
        </div>
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
          {lowStock.status === 'failed' ? (
            <PanelError error={lowStock.error} onRetry={() => void load()} />
          ) : lowStock.status === 'loading' ? (
            <PanelSkeleton rows={5} />
          ) : stockItems.length === 0 ? (
            <PanelEmpty>All listed inventory is above its reorder level.</PanelEmpty>
          ) : (
            <div className="inventory-reorder-list">
              {stockItems.slice(0, 7).map(item => {
                const fill = item.reorderLevel > 0
                  ? Math.min(100, Math.round((item.quantity / item.reorderLevel) * 100))
                  : 0;
                return (
                  <div className="inventory-reorder-item" key={item.id}>
                    <div className="inventory-reorder-copy">
                      <div>
                        <strong>{item.name}</strong>
                        <small>{item.sku}</small>
                      </div>
                      <Badge tone={statusTone(item.status)}>
                        {item.quantity} / {item.reorderLevel}
                      </Badge>
                    </div>
                    <div
                      className="inventory-reorder-track"
                      aria-label={`${item.name}: ${fill}% of reorder level`}
                    >
                      <span
                        style={{ width: `${fill}%` }}
                        className={item.quantity === 0 ? 'is-empty' : 'is-low'}
                      />
                    </div>
                  </div>
                );
              })}
              {reorderCount != null && reorderCount > stockItems.length && (
                <p className="inventory-reorder-more">+{reorderCount - stockItems.length} more items need review</p>
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
              <p>Low-stock items that need reorder attention.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="chart" size={18} /></span>
          </div>
          {lowStock.status === 'failed' ? (
            <PanelError error={lowStock.error} onRetry={() => void load()} />
          ) : lowStock.status === 'loading' ? (
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
                    cy="50%"
                    outerRadius={80}
                    innerRadius={48}
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
