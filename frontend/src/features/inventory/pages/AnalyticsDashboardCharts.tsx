import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
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
  status: string;
};
type InventoryListResponse = { items: InventoryItem[]; totalCount: number };

type Slot<T> = { status: 'loading' } | { status: 'ready'; value: T } | { status: 'failed'; error: string };
const loading = { status: 'loading' } as const;

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

function statusTone(status: string): BadgeTone {
  if (status === 'OutOfStock') return 'red';
  if (status === 'LowStock') return 'amber';
  return 'green';
}

function PanelError({ error, onRetry }: { error: string; onRetry: () => void }) {
  return (
    <div className="analytics-panel-error" role="alert">
      <p>Could not load this data.</p>
      <span>{error}</span>
      <button type="button" className="btn btn-ghost" onClick={onRetry}>Retry</button>
    </div>
  );
}

function PanelEmpty({ children }: { children: React.ReactNode }) {
  return <div className="analytics-panel-empty"><p>{children}</p></div>;
}

function Metric({ label, value, detail, tone, icon }: { label: string; value: string; detail: string; tone: string; icon: string }) {
  return (
    <article className={`inventory-analytics-metric metric-${tone}`}>
      <span className="inventory-analytics-metric-icon"><Icon name={icon} size={19} /></span>
      <span className="inventory-analytics-metric-label">{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}

export function AnalyticsDashboardPage() {
  const token = getStoredToken();
  const chart = useChartTheme();
  const { notify } = useToast();
  const axisTick = { fill: chart.tick, fontSize: 12 };
  const [usage, setUsage] = useState<Slot<InventoryUsageReport>>(loading);
  const [lowStock, setLowStock] = useState<Slot<InventoryListResponse>>(loading);

  const load = useCallback(async (showRefreshMessage = false) => {
    setUsage(loading);
    setLowStock(loading);
    const [movementResult, stockResult] = await Promise.allSettled([
      apiGet<InventoryUsageReport>('/api/reports/inventory-usage', token),
      apiGet<InventoryListResponse>('/api/inventory/low-stock?pageSize=100', token),
    ]);
    const movementSlot = settle(movementResult);
    const stockSlot = settle(stockResult);
    setUsage(movementSlot);
    setLowStock(stockSlot);

    if (showRefreshMessage) {
      if (movementSlot.status === 'ready' && stockSlot.status === 'ready') {
        notify('Inventory analytics refreshed with the latest movement and stock data.', 'success');
      } else {
        notify('Some inventory data could not be refreshed. Check the panels for details.', 'warning');
      }
    }
  }, [notify, token]);

  useEffect(() => {
    void load();
  }, [load]);

  const anyLoading = usage.status === 'loading' || lowStock.status === 'loading';
  const failedCount = [usage, lowStock].filter((slot) => slot.status === 'failed').length;
  const usageRows = useMemo(() => (
    usage.status === 'ready'
      ? usage.value.items.slice(0, 8).map((item) => ({
          id: item.inventoryItemId,
          name: item.itemName ?? item.sku ?? 'Inventory item',
          sku: item.sku ?? 'No SKU',
          received: item.receivedQuantity,
          issued: item.issuedQuantity,
          net: item.netQuantity,
          movements: item.movementCount,
        }))
      : []
  ), [usage]);

  const stockItems = lowStock.status === 'ready' ? lowStock.value.items : [];
  const reorderCount = lowStock.status === 'ready' ? lowStock.value.totalCount : null;
  const movementCount = usage.status === 'ready'
    ? usage.value.items.reduce((total, item) => total + item.movementCount, 0)
    : null;

  return (
    <div className="page inventory-analytics-page">
      <header className="inventory-analytics-hero">
        <div className="inventory-analytics-orbit" aria-hidden="true"><span className="inventory-analytics-orbit-inner" /><span className="inventory-analytics-orbit-dot" /><i><Icon name="chart" size={24} /></i></div>
        <div className="inventory-analytics-hero-top">
          <span className="inventory-analytics-mark"><Icon name="chart" size={23} /></span>
          <span className="inventory-analytics-period">LAST 30 DAYS</span>
        </div>
        <div className="inventory-analytics-hero-content">
          <div>
            <p className="eyebrow">INVENTORY INTELLIGENCE / 30-DAY VIEW</p>
            <h1>Inventory analytics</h1>
            <p>See what moved, what needs replenishing, and where stock is building up.</p>
          </div>
          <button type="button" className={`btn inventory-analytics-refresh${anyLoading ? ' is-refreshing' : ''}`} onClick={() => void load(true)} disabled={anyLoading}>
            <Icon name="workflow" size={17} /> <span>{anyLoading ? 'Updating analytics…' : 'Refresh data'}</span>
          </button>
        </div>
        <div className="inventory-analytics-hero-foot">
          <span><i className={anyLoading ? 'is-loading' : failedCount ? 'is-warning' : 'is-ready'} />{anyLoading ? 'Syncing inventory records' : failedCount ? `${failedCount} data source${failedCount > 1 ? 's' : ''} need attention` : 'Live inventory data'}</span>
          <span>Movements and reorder levels · Read only</span>
        </div>
      </header>

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
          value={usage.status === 'ready' ? `${usage.value.netQuantity > 0 ? '+' : ''}${compact(usage.value.netQuantity)}` : '—'}
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

      <section className="inventory-analytics-grid">
        <article className="panel inventory-analytics-panel inventory-flow-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">STOCK FLOW</p>
              <h2>Received vs. issued</h2>
              <p>Top items by recorded stock movement over the last 30 days.</p>
            </div>
            <span className="inventory-analytics-panel-icon"><Icon name="movement" size={18} /></span>
          </div>
          {usage.status === 'failed' ? (
            <PanelError error={usage.error} onRetry={() => void load()} />
          ) : usage.status === 'ready' && usageRows.length === 0 ? (
            <PanelEmpty>No stock movements were recorded in this period.</PanelEmpty>
          ) : (
            <div className="inventory-flow-chart">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={usageRows} margin={{ top: 12, right: 18, left: 0, bottom: 4 }} barGap={8}>
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
          {movementCount != null && <div className="inventory-analytics-panel-foot">Based on {compact(movementCount)} recorded stock movements.</div>}
        </article>

        <article className="panel inventory-analytics-panel reorder-watch-panel">
          <div className="inventory-analytics-panel-head">
            <div>
              <p className="eyebrow">REORDER WATCH</p>
              <h2>Needs attention</h2>
              <p>{reorderCount == null ? 'Current stock against reorder levels.' : `${reorderCount} item${reorderCount === 1 ? '' : 's'} at or below reorder level.`}</p>
            </div>
            <span className="inventory-analytics-panel-icon warning"><Icon name="alert" size={18} /></span>
          </div>
          {lowStock.status === 'failed' ? (
            <PanelError error={lowStock.error} onRetry={() => void load()} />
          ) : lowStock.status === 'ready' && stockItems.length === 0 ? (
            <PanelEmpty>All listed inventory is above its reorder level.</PanelEmpty>
          ) : (
            <div className="inventory-reorder-list">
              {stockItems.slice(0, 7).map((item) => {
                const fill = item.reorderLevel > 0 ? Math.min(100, Math.round((item.quantity / item.reorderLevel) * 100)) : 0;
                return (
                  <div className="inventory-reorder-item" key={item.id}>
                    <div className="inventory-reorder-copy">
                      <div><strong>{item.name}</strong><small>{item.sku}</small></div>
                      <Badge tone={statusTone(item.status)}>{item.quantity} / {item.reorderLevel}</Badge>
                    </div>
                    <div className="inventory-reorder-track" aria-label={`${item.name}: ${fill}% of reorder level`}>
                      <span style={{ width: `${fill}%` }} className={item.quantity === 0 ? 'is-empty' : 'is-low'} />
                    </div>
                  </div>
                );
              })}
              {reorderCount != null && reorderCount > stockItems.length && <p className="inventory-reorder-more">+{reorderCount - stockItems.length} more items need review</p>}
            </div>
          )}
        </article>
      </section>

      <section className="panel inventory-analytics-panel inventory-movers-panel">
        <div className="inventory-analytics-panel-head">
          <div>
            <p className="eyebrow">MOVEMENT DETAIL</p>
            <h2>Most active inventory</h2>
            <p>Receipts and issues grouped by item. Net movement helps reveal stock build-up or drawdown.</p>
          </div>
          {usage.status === 'ready' && <Badge tone="blue">{usage.value.items.length} items moved</Badge>}
        </div>
        {usage.status === 'failed' ? (
          <PanelError error={usage.error} onRetry={() => void load()} />
        ) : usage.status === 'ready' && usageRows.length === 0 ? (
          <PanelEmpty>No item-level movement detail is available yet.</PanelEmpty>
        ) : (
          <div className="table-wrap inventory-movers-table-wrap">
            <table className="data-table">
              <thead><tr><th>Item</th><th>Received</th><th>Issued</th><th>Net movement</th><th>Movement records</th></tr></thead>
              <tbody>{usageRows.map((item) => (
                <tr key={item.id}>
                  <td><strong>{item.name}</strong><div className="cell-sub">{item.sku}</div></td>
                  <td><span className="inventory-value-positive">+{compact(item.received)}</span></td>
                  <td><span className="inventory-value-negative">−{compact(item.issued)}</span></td>
                  <td><strong className={item.net < 0 ? 'inventory-value-negative' : 'inventory-value-positive'}>{item.net > 0 ? '+' : ''}{compact(item.net)}</strong></td>
                  <td>{item.movements}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </section>
      <p className="inventory-analytics-disclaimer">Analytics reflect recorded inventory movements and current reorder settings. Missing or unrecorded movements are not estimated.</p>
    </div>
  );
}
