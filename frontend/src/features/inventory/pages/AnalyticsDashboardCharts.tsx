import { useEffect, useMemo, useState } from 'react';
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
type AnalyticsData = {
  revenue: RevenueReport;
  patients: PatientCountReport;
  usage: InventoryUsageReport;
  lowStock: InventoryListResponse;
  usedFallback: boolean;
};

const fallbackRevenue: RevenueReport = {
  totalRevenue: 892000,
  buckets: [
    { date: '2026-08-09', label: 'Aug 09', revenue: 98000 },
    { date: '2026-08-10', label: 'Aug 10', revenue: 116000 },
    { date: '2026-08-11', label: 'Aug 11', revenue: 127500 },
    { date: '2026-08-12', label: 'Aug 12', revenue: 143000 },
    { date: '2026-08-13', label: 'Aug 13', revenue: 131000 },
    { date: '2026-08-14', label: 'Aug 14', revenue: 156500 },
    { date: '2026-08-15', label: 'Aug 15', revenue: 120000 },
  ],
};

const fallbackPatients: PatientCountReport = {
  totalPatients: 1248,
  newPatients: 78,
  buckets: [
    { date: '2026-08-09', label: 'Aug 09', newPatients: 8 },
    { date: '2026-08-10', label: 'Aug 10', newPatients: 13 },
    { date: '2026-08-11', label: 'Aug 11', newPatients: 9 },
    { date: '2026-08-12', label: 'Aug 12', newPatients: 14 },
    { date: '2026-08-13', label: 'Aug 13', newPatients: 11 },
    { date: '2026-08-14', label: 'Aug 14', newPatients: 16 },
    { date: '2026-08-15', label: 'Aug 15', newPatients: 7 },
  ],
};

const fallbackUsage: InventoryUsageReport = {
  totalReceivedQuantity: 592,
  totalIssuedQuantity: 427,
  netQuantity: 165,
  items: [
    { inventoryItemId: 'coffee', itemName: 'Premium Coffee Beans', sku: 'SKU-00132', receivedQuantity: 120, issuedQuantity: 92, netQuantity: 28, movementCount: 16 },
    { inventoryItemId: 'cups', itemName: 'Craft Paper Cups 12oz', sku: 'SKU-00612', receivedQuantity: 180, issuedQuantity: 126, netQuantity: 54, movementCount: 12 },
    { inventoryItemId: 'milk', itemName: 'Whole Milk 1L', sku: 'SKU-00741', receivedQuantity: 160, issuedQuantity: 143, netQuantity: 17, movementCount: 18 },
    { inventoryItemId: 'boxes', itemName: 'Packaging Boxes Medium', sku: 'SKU-00598', receivedQuantity: 82, issuedQuantity: 44, netQuantity: 38, movementCount: 8 },
    { inventoryItemId: 'syrup', itemName: 'Vanilla Syrup 750ml', sku: 'SKU-00324', receivedQuantity: 50, issuedQuantity: 22, netQuantity: 28, movementCount: 7 },
  ],
};

const fallbackLowStock: InventoryListResponse = {
  totalCount: 4,
  items: [
    { id: 'coffee', name: 'Premium Coffee Beans', sku: 'SKU-00132', quantity: 6, reorderLevel: 40, status: 'LowStock' },
    { id: 'syrup', name: 'Vanilla Syrup 750ml', sku: 'SKU-00324', quantity: 0, reorderLevel: 25, status: 'OutOfStock' },
    { id: 'boxes', name: 'Packaging Boxes Medium', sku: 'SKU-00598', quantity: 11, reorderLevel: 60, status: 'LowStock' },
    { id: 'milk', name: 'Whole Milk 1L Small', sku: 'SKU-00811', quantity: 18, reorderLevel: 80, status: 'LowStock' },
  ],
};

const bookingUtilization = [
  { label: 'Mon', booked: 68, available: 32 },
  { label: 'Tue', booked: 74, available: 26 },
  { label: 'Wed', booked: 81, available: 19 },
  { label: 'Thu', booked: 72, available: 28 },
  { label: 'Fri', booked: 88, available: 12 },
  { label: 'Sat', booked: 63, available: 37 },
  { label: 'Sun', booked: 41, available: 59 },
];

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
  if (!response.ok) throw new Error(`Request failed: ${path}`);
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

export function AnalyticsDashboardPage() {
  const token = getStoredToken();
  const [data, setData] = useState<AnalyticsData>({
    revenue: fallbackRevenue,
    patients: fallbackPatients,
    usage: fallbackUsage,
    lowStock: fallbackLowStock,
    usedFallback: true,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      const [revenue, patients, usage, lowStock] = await Promise.allSettled([
        apiGet<RevenueReport>('/api/reports/revenue', token),
        apiGet<PatientCountReport>('/api/reports/patient-count', token),
        apiGet<InventoryUsageReport>('/api/reports/inventory-usage', token),
        apiGet<InventoryListResponse>('/api/inventory/low-stock?pageSize=8', token),
      ]);

      if (cancelled) return;

      setData({
        revenue: revenue.status === 'fulfilled' ? revenue.value : fallbackRevenue,
        patients: patients.status === 'fulfilled' ? patients.value : fallbackPatients,
        usage: usage.status === 'fulfilled' ? usage.value : fallbackUsage,
        lowStock: lowStock.status === 'fulfilled' ? lowStock.value : fallbackLowStock,
        usedFallback: [revenue, patients, usage, lowStock].some((result) => result.status === 'rejected'),
      });
      setLoading(false);
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [token]);

  const stockLevels = useMemo(() => (
    data.lowStock.items.map((item) => ({
      name: item.name.length > 18 ? `${item.name.slice(0, 18)}...` : item.name,
      sku: item.sku,
      quantity: item.quantity,
      reorderLevel: item.reorderLevel,
      fillRate: item.reorderLevel > 0 ? Math.round((item.quantity / item.reorderLevel) * 100) : 0,
      status: item.status,
    }))
  ), [data.lowStock.items]);

  const usageRows = useMemo(() => (
    data.usage.items.slice(0, 6).map((item) => ({
      name: item.itemName ?? item.sku ?? 'Inventory item',
      sku: item.sku ?? 'No SKU',
      received: item.receivedQuantity,
      issued: item.issuedQuantity,
      net: item.netQuantity,
    }))
  ), [data.usage.items]);

  const averageBooking = Math.round(
    bookingUtilization.reduce((sum, day) => sum + day.booked, 0) / bookingUtilization.length
  );

  return (
    <div className="page dashboard-page analytics-page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / ANALYTICS</p>
          <h1>Analytics dashboard</h1>
          <p className="page-sub">Revenue trends, inventory pressure, patient growth, and booking capacity in one view.</p>
        </div>
        <div className="page-actions">
          {loading && <Badge tone="blue">Loading live data</Badge>}
          {!loading && data.usedFallback && <Badge tone="amber">Using sample fallback</Badge>}
        </div>
      </header>

      <section className="kpi-grid" aria-label="Key metrics">
        <KpiCard label="Revenue" value={currency(data.revenue.totalRevenue)} detail="30 days" tone="green" />
        <KpiCard label="Patients" value={compact(data.patients.totalPatients)} detail={`+${data.patients.newPatients} new`} tone="blue" />
        <KpiCard label="Stock issued" value={compact(data.usage.totalIssuedQuantity)} detail={`${compact(data.usage.netQuantity)} net`} tone="amber" />
        <KpiCard label="Booking utilization" value={`${averageBooking}%`} detail="weekly avg" tone="violet" />
      </section>

      <section className="analytics-grid analytics-grid-primary">
        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Revenue trends</h2>
              <p>Daily revenue across the selected reporting window</p>
            </div>
          </div>
          <div className="chart-box">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={data.revenue.buckets} margin={{ top: 8, right: 20, left: 8, bottom: 8 }}>
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
          {data.revenue.dataSourceNote && <p className="analytics-note">{data.revenue.dataSourceNote}</p>}
        </article>

        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Stock levels</h2>
              <p>Low-stock items compared with reorder thresholds</p>
            </div>
          </div>
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
          <div className="chart-box chart-box-sm">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={data.patients.buckets} margin={{ top: 8, right: 20, left: 0, bottom: 8 }}>
                <CartesianGrid stroke={gridStroke} vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} tick={axisTick} />
                <YAxis tickLine={false} axisLine={false} tick={axisTick} width={36} />
                <Tooltip contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                <Line type="monotone" dataKey="newPatients" name="New patients" stroke={chartColors.blue} strokeWidth={3} dot={{ r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </article>

        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Booking utilization</h2>
              <p>Booked capacity versus available appointment slots</p>
            </div>
            <Badge tone="slate">Sample</Badge>
          </div>
          <div className="chart-box chart-box-sm">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={bookingUtilization} margin={{ top: 8, right: 20, left: 0, bottom: 8 }}>
                <CartesianGrid stroke={gridStroke} vertical={false} />
                <XAxis dataKey="label" tickLine={false} axisLine={false} tick={axisTick} />
                <YAxis tickFormatter={(value: any) => `${value}%`} tickLine={false} axisLine={false} tick={axisTick} width={42} />
                <Tooltip formatter={(value: any) => `${value}%`} contentStyle={tooltipStyle} itemStyle={tooltipItem} labelStyle={tooltipItem} />
                <Legend />
                <Bar dataKey="booked" stackId="slots" name="Booked" fill={chartColors.sky} radius={[6, 6, 0, 0]} />
                <Bar dataKey="available" stackId="slots" name="Available" fill="rgba(255,255,255,0.14)" radius={[6, 6, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
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
        </article>

        <article className="panel analytics-panel">
          <div className="panel-head">
            <div>
              <h2>Stock risk split</h2>
              <p>Fill-rate distribution among watched items</p>
            </div>
          </div>
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
        </article>
      </section>
    </div>
  );
}
