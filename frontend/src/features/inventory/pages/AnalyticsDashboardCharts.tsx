import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ComposedChart,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { getStoredToken } from '../authToken';
import { Badge, type BadgeTone } from '../ui/Badge';

type RevenueBucket = { date: string; label: string; revenue: number };
type RevenueReport = { totalRevenue: number; buckets: RevenueBucket[]; dataSourceNote?: string };
type PatientBucket = { date: string; label: string; newPatients: number };
type PatientCountReport = { totalPatients: number; newPatients: number; buckets: PatientBucket[] };
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
type BookingStats = {
  total: number;
  noShows: number;
  completed: number;
  cancelled: number;
  noShowRate: number;
  utilizationRate: number;
};

/* One slot per data source. Each panel reads its own slot and renders
 * either the chart or an error with a retry - never a stand-in.
 *
 * This file used to carry four hard-coded fallback datasets (a fictional
 * 892k of revenue, 1,248 patients, a coffee shop's stock) that any failed
 * request was silently replaced with, plus a booking chart that was never
 * fetched at all. A dashboard that shows invented numbers when the real ones
 * are unavailable is not degraded, it is wrong, and it is wrong in the way
 * that is hardest to notice. */
type Slot<T> = { status: 'loading' } | { status: 'ready'; value: T } | { status: 'failed'; error: string };
const loading = { status: 'loading' } as const;

function settle<T>(result: PromiseSettledResult<T>): Slot<T> {
  return result.status === 'fulfilled'
    ? { status: 'ready', value: result.value }
    : { status: 'failed', error: result.reason instanceof Error ? result.reason.message : 'Request failed' };
}

const chartColors = {
  blue: '#8B5CF6',
  green: '#4ADE80',
  amber: '#FBBF24',
  red: '#F87171',
  slate: '#9A9A9F',
  sky: '#22D3EE',
};

// Recharts paints its own chrome; without these it renders a white tooltip
// and near-black axis text on the dark canvas.
const axisTick = { fill: '#9A9A9F', fontSize: 12 };
const gridStroke = 'rgba(255,255,255,0.07)';
const tooltipStyle = {
  background: '#231E33',
  border: '1px solid rgba(255,255,255,0.16)',
  borderRadius: 10,
  color: '#FFFFFF',
};
const tooltipItem = { color: '#C4C4C8' };

async function apiGet<T>(path: string, token: string | null): Promise<T> {
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) throw new Error(`${response.status} from ${path.split('?')[0]}`);
  return response.json() as Promise<T>;
}

function currency(value: number) {
  return new Intl.NumberFormat('en-LK', {
    style: 'currency',
    currency: 'LKR',
    maximumFractionDigits: 0,
  }).format(value);
}

function compact(value: number) {
  return new Intl.NumberFormat('en-LK', { notation: 'compact', maximumFractionDigits: 1 }).format(value);
}

function statusTone(status: string): BadgeTone {
  if (status === 'OutOfStock') return 'red';
  if (status === 'LowStock') return 'amber';
  return 'green';
}

function KpiCard({ label, value, detail, tone }: { label: string; value: string; detail: string; tone: BadgeTone }) {
  return (
    <article className="kpi-card analytics-kpi">
      <div className="kpi-top">
        <span className="kpi-label">{label}</span>
        <Badge tone={tone}>{detail}</Badge>
      </div>
      <div className="kpi-value">{value}</div>
    </article>
  );
}

/** What a panel shows in place of its chart when its request failed. */
function PanelError({ error, onRetry }: { error: string; onRetry: () => void }) {
  return (
    <div className="analytics-panel-error" role="alert">
      <p>Could not load this data.</p>
      <span>{error}</span>
      <button type="button" className="btn btn-ghost" onClick={onRetry}>Retry</button>
    </div>
  );
}

/** What a panel shows when the request succeeded and there is nothing in it. */
function PanelEmpty({ children }: { children: React.ReactNode }) {
  return <div className="analytics-panel-empty"><p>{children}</p></div>;
}

export function AnalyticsDashboardPage() {
  const token = getStoredToken();
  const { user } = useSelector((state: RootState) => state.auth);

  const [revenue, setRevenue] = useState<Slot<RevenueReport>>(loading);
  const [patients, setPatients] = useState<Slot<PatientCountReport>>(loading);
  const [usage, setUsage] = useState<Slot<InventoryUsageReport>>(loading);
  const [lowStock, setLowStock] = useState<Slot<InventoryListResponse>>(loading);
  const [bookings, setBookings] = useState<Slot<BookingStats>>(loading);

  const load = useCallback(async () => {
    setRevenue(loading);
    setPatients(loading);
    setUsage(loading);
    setLowStock(loading);
    setBookings(loading);

    // The bookings report wants an explicit tenant and window. Thirty days,
    // to match the revenue card beside it.
    const to = new Date();
    const from = new Date(to);
    from.setDate(from.getDate() - 30);
    const bookingsQuery = user
      ? `/api/bookings/reports/no-shows?tenantId=${user.tenantId}&from=${from.toISOString()}&to=${to.toISOString()}`
      : null;

    const [rev, pat, use, low, book] = await Promise.allSettled([
      apiGet<RevenueReport>('/api/reports/revenue', token),
      apiGet<PatientCountReport>('/api/reports/patient-count', token),
      apiGet<InventoryUsageReport>('/api/reports/inventory-usage', token),
      apiGet<InventoryListResponse>('/api/inventory/low-stock?pageSize=8', token),
      bookingsQuery
        ? apiGet<BookingStats>(bookingsQuery, token)
        : Promise.reject(new Error('No signed-in tenant')),
    ]);

    setRevenue(settle(rev));
    setPatients(settle(pat));
    setUsage(settle(use));
    setLowStock(settle(low));
    setBookings(settle(book));
  }, [token, user]);

  useEffect(() => {
    void load();
  }, [load]);

  const anyLoading = [revenue, patients, usage, lowStock, bookings].some((s) => s.status === 'loading');
  const failedCount = [revenue, patients, usage, lowStock, bookings].filter((s) => s.status === 'failed').length;

  const stockLevels = useMemo(() => (
    lowStock.status === 'ready'
      ? lowStock.value.items.map((item) => ({
          name: item.name.length > 18 ? `${item.name.slice(0, 18)}...` : item.name,
          sku: item.sku,
          quantity: item.quantity,
          reorderLevel: item.reorderLevel,
          fillRate: item.reorderLevel > 0 ? Math.round((item.quantity / item.reorderLevel) * 100) : 0,
          status: item.status,
        }))
      : []
  ), [lowStock]);

  const usageRows = useMemo(() => (
    usage.status === 'ready'
      ? usage.value.items.slice(0, 6).map((item) => ({
          name: item.itemName ?? item.sku ?? 'Inventory item',
          sku: item.sku ?? 'No SKU',
          received: item.receivedQuantity,
          issued: item.issuedQuantity,
          net: item.netQuantity,
        }))
      : []
  ), [usage]);

  // The three outcomes of a booking over the window, for the bar chart.
  const bookingRows = useMemo(() => (
    bookings.status === 'ready'
      ? [
          { label: 'Completed', count: bookings.value.completed },
          { label: 'No-shows', count: bookings.value.noShows },
          { label: 'Cancelled', count: bookings.value.cancelled },
        ]
      : []
  ), [bookings]);

  return (
    <div className="page dashboard-page analytics-page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / ANALYTICS</p>
          <h1>Analytics dashboard</h1>
          <p className="page-sub">Revenue trends, inventory pressure, patient growth, and booking outcomes in one view.</p>
        </div>
        <div className="page-actions">
          {anyLoading && <Badge tone="blue">Loading live data</Badge>}
          {!anyLoading && failedCount > 0 && (
            <Badge tone="red">{failedCount} of 5 sources unavailable</Badge>
          )}
          <button type="button" className="btn btn-ghost" onClick={() => void load()} disabled={anyLoading}>
            Refresh
          </button>
        </div>
      </header>

      {/* A card whose source failed shows a dash, not a number. */}
      <section className="kpi-grid" aria-label="Key metrics">
        <KpiCard
          label="Revenue"
          value={revenue.status === 'ready' ? currency(revenue.value.totalRevenue) : '—'}
          detail="30 days"
          tone={revenue.status === 'failed' ? 'red' : 'green'}
        />
        <KpiCard
          label="Patients"
          value={patients.status === 'ready' ? compact(patients.value.totalPatients) : '—'}
          detail={patients.status === 'ready' ? `+${patients.value.newPatients} new` : 'unavailable'}
          tone={patients.status === 'failed' ? 'red' : 'blue'}
        />
        <KpiCard
          label="Stock issued"
          value={usage.status === 'ready' ? compact(usage.value.totalIssuedQuantity) : '—'}
          detail={usage.status === 'ready' ? `${compact(usage.value.netQuantity)} net` : 'unavailable'}
          tone={usage.status === 'failed' ? 'red' : 'amber'}
        />
        <KpiCard
          label="Booking completion"
          value={bookings.status === 'ready' ? `${Math.round(bookings.value.utilizationRate)}%` : '—'}
          detail={bookings.status === 'ready' ? `${bookings.value.total} bookings` : 'unavailable'}
          tone={bookings.status === 'failed' ? 'red' : 'violet'}
        />
      </section>

      <section className="analytics-grid analytics-grid-primary">
        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Revenue trends</h2>
              <p>Daily revenue across the selected reporting window</p>
            </div>
          </div>
          {revenue.status === 'failed' ? (
            <PanelError error={revenue.error} onRetry={() => void load()} />
          ) : revenue.status === 'ready' && revenue.value.buckets.length === 0 ? (
            <PanelEmpty>No revenue recorded in this window.</PanelEmpty>
          ) : (
            <div className="chart-box">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={revenue.status === 'ready' ? revenue.value.buckets : []} margin={{ top: 8, right: 20, left: 8, bottom: 8 }}>
                  <defs>
                    <linearGradient id="revenue-fill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={chartColors.green} stopOpacity={0.28} />
                      <stop offset="100%" stopColor={chartColors.green} stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke={gridStroke} vertical={false} />
                  <XAxis dataKey="label" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis tickFormatter={compact} tickLine={false} axisLine={false} tick={axisTick} width={54} />
                  <Tooltip formatter={(value: any) => currency(Number(value))} contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  <Area type="monotone" dataKey="revenue" stroke={chartColors.green} strokeWidth={3} fill="url(#revenue-fill)" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
          {revenue.status === 'ready' && revenue.value.dataSourceNote && (
            <p className="analytics-note">{revenue.value.dataSourceNote}</p>
          )}
        </article>

        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Stock levels</h2>
              <p>Low-stock items compared with reorder thresholds</p>
            </div>
          </div>
          {lowStock.status === 'failed' ? (
            <PanelError error={lowStock.error} onRetry={() => void load()} />
          ) : lowStock.status === 'ready' && stockLevels.length === 0 ? (
            <PanelEmpty>Nothing is below its reorder level.</PanelEmpty>
          ) : (
            <div className="chart-box">
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={stockLevels} layout="vertical" margin={{ top: 8, right: 20, left: 12, bottom: 8 }}>
                  <CartesianGrid stroke={gridStroke} horizontal={false} />
                  <XAxis type="number" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis type="category" dataKey="name" width={112} tickLine={false} axisLine={false} tick={{ fill: '#C4C4C8', fontSize: 12 }} />
                  <Tooltip contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  <Legend />
                  <Bar dataKey="quantity" name="On hand" radius={[0, 6, 6, 0]} fill={chartColors.amber} />
                  <Line dataKey="reorderLevel" name="Reorder" stroke={chartColors.red} strokeWidth={2} dot={false} />
                </ComposedChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>
      </section>

      <section className="analytics-grid analytics-grid-secondary">
        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Patient counts</h2>
              <p>New patient registrations by day</p>
            </div>
          </div>
          {patients.status === 'failed' ? (
            <PanelError error={patients.error} onRetry={() => void load()} />
          ) : patients.status === 'ready' && patients.value.buckets.length === 0 ? (
            <PanelEmpty>No patient registrations in this window.</PanelEmpty>
          ) : (
            <div className="chart-box chart-box-sm">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={patients.status === 'ready' ? patients.value.buckets : []} margin={{ top: 8, right: 20, left: 0, bottom: 8 }}>
                  <CartesianGrid stroke={gridStroke} vertical={false} />
                  <XAxis dataKey="label" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis tickLine={false} axisLine={false} tick={axisTick} width={36} />
                  <Tooltip contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  <Line type="monotone" dataKey="newPatients" name="New patients" stroke={chartColors.blue} strokeWidth={3} dot={{ r: 4 }} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>

        {/* Real outcomes from /api/bookings/reports/no-shows. The previous
            chart here was a hard-coded Mon-Sun "booked vs available" series
            labelled Sample - never fetched from anywhere. The backend has no
            per-day capacity figure to replace it with, so this shows what
            it does have: how the window's bookings actually ended. */}
        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Booking outcomes</h2>
              <p>How bookings in the last 30 days ended</p>
            </div>
          </div>
          {bookings.status === 'failed' ? (
            <PanelError error={bookings.error} onRetry={() => void load()} />
          ) : bookings.status === 'ready' && bookings.value.total === 0 ? (
            <PanelEmpty>No bookings in the last 30 days.</PanelEmpty>
          ) : (
            <div className="chart-box chart-box-sm">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={bookingRows} margin={{ top: 8, right: 20, left: 0, bottom: 8 }}>
                  <CartesianGrid stroke={gridStroke} vertical={false} />
                  <XAxis dataKey="label" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={axisTick} width={42} />
                  <Tooltip contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  <Bar dataKey="count" name="Bookings" radius={[6, 6, 0, 0]}>
                    {bookingRows.map((row) => (
                      <Cell
                        key={row.label}
                        fill={row.label === 'Completed' ? chartColors.green : row.label === 'No-shows' ? chartColors.red : chartColors.slate}
                      />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>
      </section>

      <section className="analytics-grid analytics-grid-bottom">
        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Inventory movement mix</h2>
              <p>Received versus issued quantities by top-moving item</p>
            </div>
          </div>
          {usage.status === 'failed' ? (
            <PanelError error={usage.error} onRetry={() => void load()} />
          ) : usage.status === 'ready' && usageRows.length === 0 ? (
            <PanelEmpty>No stock movements recorded in this window.</PanelEmpty>
          ) : (
            <div className="chart-box chart-box-sm">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={usageRows} margin={{ top: 8, right: 20, left: 0, bottom: 8 }}>
                  <CartesianGrid stroke={gridStroke} vertical={false} />
                  <XAxis dataKey="sku" tickLine={false} axisLine={false} tick={axisTick} />
                  <YAxis tickLine={false} axisLine={false} tick={axisTick} width={42} />
                  <Tooltip contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  <Legend />
                  <Bar dataKey="received" name="Received" fill={chartColors.green} radius={[6, 6, 0, 0]} />
                  <Bar dataKey="issued" name="Issued" fill={chartColors.amber} radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </article>

        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Stock risk split</h2>
              <p>Fill-rate distribution among watched items</p>
            </div>
          </div>
          {lowStock.status === 'failed' ? (
            <PanelError error={lowStock.error} onRetry={() => void load()} />
          ) : lowStock.status === 'ready' && stockLevels.length === 0 ? (
            <PanelEmpty>Nothing is below its reorder level.</PanelEmpty>
          ) : (
            <div className="analytics-split">
              <div className="chart-box chart-box-donut">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={stockLevels}
                      dataKey="fillRate"
                      nameKey="sku"
                      innerRadius="58%"
                      outerRadius="82%"
                      paddingAngle={3}
                    >
                      {stockLevels.map((item) => (
                        <Cell key={item.sku} fill={item.status === 'OutOfStock' ? chartColors.red : item.fillRate < 35 ? chartColors.amber : chartColors.green} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value: any) => `${value}%`} contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              <div className="risk-list">
                {stockLevels.map((item) => (
                  <div className="risk-row" key={item.sku}>
                    <div>
                      <p>{item.name}</p>
                      <span>{item.sku}</span>
                    </div>
                    <Badge tone={statusTone(item.status)}>{item.fillRate}%</Badge>
                  </div>
                ))}
              </div>
            </div>
          )}
        </article>
      </section>
    </div>
  );
}
