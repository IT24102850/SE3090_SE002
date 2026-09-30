import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
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

type DateRange = '7d' | '30d' | '90d';
type Branch = { id: string; name: string };
type InventoryItem = {
  id: string;
  branchId?: string | null;
  quantity: number;
  reorderLevel: number;
  unitCost?: number | null;
};
type InventoryResponse = { items: InventoryItem[]; totalCount: number; totalPages: number };
type SalesReport = {
  salesCount: number;
  totalRevenue: number;
  averageSale: number;
  costOfGoodsSold: number | null;
  grossProfit: number | null;
};
type BranchPerformance = Branch & SalesReport & {
  itemCount: number;
  unitsOnHand: number;
  stockValue: number;
  attentionItems: number;
  profitMargin: number | null;
};
type PerformanceState =
  | { status: 'loading' }
  | { status: 'ready'; branches: BranchPerformance[] }
  | { status: 'failed'; error: string };

const INITIAL_STATE: PerformanceState = { status: 'loading' };
const RANGES: DateRange[] = ['7d', '30d', '90d'];

function rangeLabel(range: DateRange) {
  return range === '7d' ? 'Last 7 days' : range === '30d' ? 'Last 30 days' : 'Last 90 days';
}

function dateParams(range: DateRange) {
  const to = new Date();
  const from = new Date(to);
  from.setDate(from.getDate() - (range === '7d' ? 7 : range === '30d' ? 30 : 90));
  return new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
}

function money(value: number) {
  return new Intl.NumberFormat('en-LK', {
    style: 'currency',
    currency: 'LKR',
    maximumFractionDigits: 0,
  }).format(value);
}

function compactMoney(value: number) {
  return `LKR ${new Intl.NumberFormat('en-LK', {
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(value)}`;
}

function count(value: number) {
  return new Intl.NumberFormat('en-LK', { maximumFractionDigits: 0 }).format(value);
}

async function getJson<T>(path: string, token: string | null): Promise<T> {
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) throw new Error(`${response.status} from ${path.split('?')[0]}`);
  return response.json() as Promise<T>;
}

async function getAllInventory(token: string | null) {
  const items: InventoryItem[] = [];
  const itemIds = new Set<string>();
  let page = 1;
  let totalPages = 1;
  let totalCount = 0;

  do {
    const result = await getJson<InventoryResponse>(
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
    for (const item of result.items) {
      if (!item || typeof item.id !== 'string' || !item.id.trim()) {
        throw new Error('Inventory response contains an item without a valid ID.');
      }
      if (itemIds.has(item.id)) {
        throw new Error('Inventory pages contain duplicate items. Refresh to capture a complete snapshot.');
      }
      itemIds.add(item.id);
    }
    if (page > 1 && (result.totalCount !== totalCount || result.totalPages !== totalPages)) {
      throw new Error('Inventory changed while loading. Refresh to capture a complete snapshot.');
    }
    totalCount = result.totalCount;
    totalPages = result.totalPages;
    items.push(...result.items);
    page += 1;
  } while (page <= totalPages);

  if (items.length !== totalCount) {
    throw new Error(`Loaded ${items.length} of ${totalCount} inventory items.`);
  }
  return items;
}

function Metric({
  label,
  value,
  detail,
  tone,
  icon,
}: {
  label: string;
  value: string;
  detail: string;
  tone: string;
  icon: string;
}) {
  return (
    <article className={`inventory-analytics-metric metric-${tone}`}>
      <span className="inventory-analytics-metric-icon" aria-hidden="true">{icon}</span>
      <span className="inventory-analytics-metric-label">{label}</span>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}

export function BranchPerformancePage() {
  const token = getStoredToken();
  const chart = useChartTheme();
  const [range, setRange] = useState<DateRange>('30d');
  const [data, setData] = useState<PerformanceState>(INITIAL_STATE);
  const requestId = useRef(0);

  const load = useCallback(async () => {
    const currentRequest = ++requestId.current;
    setData({ status: 'loading' });
    try {
      const [branches, inventory] = await Promise.all([
        getJson<Branch[]>('/api/inventory/branches', token),
        getAllInventory(token),
      ]);
      if (!Array.isArray(branches)) throw new Error('Branch response is invalid.');
      const params = dateParams(range);
      const performances = await Promise.all(branches.map(async (branch) => {
        const query = new URLSearchParams(params);
        query.set('branchId', branch.id);
        query.set('page', '1');
        query.set('pageSize', '1');
        const report = await getJson<SalesReport>(
          `/api/reports/sales-activity?${query.toString()}`,
          token,
        );
        const stock = inventory.filter((item) => item.branchId === branch.id);
        const stockValue = stock.reduce(
          (total, item) => total + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0),
          0,
        );
        const grossProfit = report.grossProfit;
        return {
          ...branch,
          ...report,
          itemCount: stock.length,
          unitsOnHand: stock.reduce((total, item) => total + Number(item.quantity ?? 0), 0),
          stockValue,
          attentionItems: stock.filter(
            (item) => item.quantity <= 0 || item.quantity <= item.reorderLevel,
          ).length,
          profitMargin: grossProfit == null || report.totalRevenue <= 0
            ? null
            : grossProfit / report.totalRevenue * 100,
        };
      }));
      if (currentRequest === requestId.current) setData({ status: 'ready', branches: performances });
    } catch (error) {
      if (currentRequest === requestId.current) {
        setData({
          status: 'failed',
          error: error instanceof Error ? error.message : 'Branch performance could not be loaded.',
        });
      }
    }
  }, [range, token]);

  useEffect(() => {
    void load();
    return () => { requestId.current += 1; };
  }, [load]);

  const rankedBranches = useMemo(
    () => data.status === 'ready'
      ? [...data.branches].sort((a, b) => b.totalRevenue - a.totalRevenue)
      : [],
    [data],
  );
  const totals = useMemo(() => rankedBranches.reduce((sum, branch) => ({
    sales: sum.sales + branch.salesCount,
    revenue: sum.revenue + branch.totalRevenue,
    profit: sum.profit + (branch.grossProfit ?? 0),
    stockValue: sum.stockValue + branch.stockValue,
    items: sum.items + branch.itemCount,
    attention: sum.attention + branch.attentionItems,
    profitDataComplete: sum.profitDataComplete && branch.grossProfit != null,
  }), {
    sales: 0,
    revenue: 0,
    profit: 0,
    stockValue: 0,
    items: 0,
    attention: 0,
    profitDataComplete: rankedBranches.length > 0,
  }), [rankedBranches]);

  const chartData = useMemo(() => rankedBranches.map((branch) => ({
    name: branch.name,
    revenue: branch.totalRevenue,
    grossProfit: branch.grossProfit,
    stockValue: branch.stockValue,
  })), [rankedBranches]);

  return (
    <div className="page inventory-analytics-page branch-performance-page">
      <header className="inventory-analytics-hero panel">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="inventory-analytics-hero-top">
          <span className="inventory-analytics-mark" aria-hidden="true">⌖</span>
          <span className="inventory-analytics-period">{rangeLabel(range).toUpperCase()}</span>
        </div>
        <div className="inventory-analytics-hero-content">
          <div>
            <p className="eyebrow">INVENTORY INTELLIGENCE / NETWORK</p>
            <h1>Branch performance</h1>
            <p>Compare sales, profitability and stock health across every branch you can access.</p>
          </div>
          <div className="inventory-analytics-hero-actions branch-performance-controls">
            <div className="inventory-analytics-range-tabs" role="group" aria-label="Date range">
              {RANGES.map((value) => (
                <button
                  key={value}
                  type="button"
                  className={`inventory-analytics-range-tab${range === value ? ' is-active' : ''}`}
                  onClick={() => setRange(value)}
                  disabled={data.status === 'loading'}
                >
                  {value === '7d' ? '7 days' : value === '30d' ? '30 days' : '90 days'}
                </button>
              ))}
            </div>
            <button
              type="button"
              className="btn inventory-analytics-refresh"
              onClick={() => void load()}
              disabled={data.status === 'loading'}
            >
              {data.status === 'loading' ? 'Updating…' : 'Refresh'}
            </button>
          </div>
        </div>
        <div className="inventory-analytics-hero-foot">
          <span><i className={data.status === 'loading' ? 'is-loading' : data.status === 'failed' ? 'is-warning' : 'is-ready'} />
            {data.status === 'loading' ? 'Loading branch reports' : data.status === 'failed' ? 'Branch data needs attention' : `${rankedBranches.length} branches compared`}
          </span>
          <span>Sales use the selected period · stock values are current snapshots</span>
        </div>
      </header>

      <div className="branch-performance-links">
        <Link to="/inventory-analytics">← Inventory analytics</Link>
        <Link to="/branch-overview">View branch stock overview →</Link>
      </div>

      {data.status === 'failed' ? (
        <section className="panel branch-performance-state" role="alert">
          <div>
            <strong>Branch comparison could not be loaded.</strong>
            <p>{data.error}</p>
          </div>
          <button type="button" className="btn btn-secondary" onClick={() => void load()}>Retry</button>
        </section>
      ) : data.status === 'loading' ? (
        <section className="panel branch-performance-state" role="status">Loading sales and stock data for each branch…</section>
      ) : rankedBranches.length === 0 ? (
        <section className="panel branch-performance-state">
          <strong>No branches are available for comparison.</strong>
          <p>Create or authorize a branch, then refresh this report.</p>
        </section>
      ) : (
        <>
          <section className="inventory-analytics-metrics branch-performance-metrics" aria-label="Combined branch performance">
            <Metric label="Sales recorded" value={count(totals.sales)} detail={`${rangeLabel(range)} · all branches`} tone="blue" icon="#" />
            <Metric label="Sales revenue" value={money(totals.revenue)} detail="Revenue during selected period" tone="teal" icon="LKR" />
            <Metric label="Gross profit" value={totals.profitDataComplete ? money(totals.profit) : 'Partial data'} detail={totals.profitDataComplete ? 'Revenue less cost of sold stock' : 'One or more branches have incomplete cost data'} tone="green" icon="Σ" />
            <Metric label="Current stock value" value={money(totals.stockValue)} detail={`${count(totals.items)} branch item records`} tone="violet" icon="▦" />
          </section>

          <section className="branch-performance-highlights" aria-label="Performance highlights">
            <article className="panel branch-performance-highlight">
              <span className="branch-performance-highlight-icon" aria-hidden="true">↗</span>
              <div><small>REVENUE LEADER</small><strong>{rankedBranches[0].name}</strong><span>{money(rankedBranches[0].totalRevenue)} sales revenue</span></div>
              <b>#1</b>
            </article>
            <article className="panel branch-performance-highlight">
              <span className="branch-performance-highlight-icon is-stock" aria-hidden="true">▦</span>
              <div><small>STOCK NEEDING ATTENTION</small><strong>{count(totals.attention)} items</strong><span>At or below reorder levels across the network</span></div>
              <b aria-hidden="true">!</b>
            </article>
          </section>

          <section className="branch-performance-charts" aria-label="Branch comparison charts">
            <article className="panel inventory-analytics-panel branch-performance-chart-panel">
              <div className="inventory-analytics-panel-head">
                <div><p className="eyebrow">SALES &amp; PROFIT</p><h2>Revenue by branch</h2><p>{rangeLabel(range)} · compare total revenue and gross profit</p></div>
              </div>
              <div className="branch-performance-chart">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartData} margin={{ top: 12, right: 12, left: 12, bottom: 8 }}>
                    <CartesianGrid stroke={chart.grid} vertical={false} />
                    <XAxis dataKey="name" tick={{ fill: chart.tick, fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis tickFormatter={compactMoney} tick={{ fill: chart.tick, fontSize: 10 }} axisLine={false} tickLine={false} width={92} />
                    <Tooltip
                      contentStyle={chart.tooltip}
                      formatter={(value, name) => [money(Number(value)), name === 'grossProfit' ? 'Gross profit' : 'Revenue']}
                    />
                    <Legend formatter={(value) => value === 'grossProfit' ? 'Gross profit' : 'Revenue'} />
                    <Bar dataKey="revenue" name="revenue" fill={chart.series.blue} radius={[5, 5, 0, 0]} />
                    <Bar dataKey="grossProfit" name="grossProfit" fill={chart.series.green} radius={[5, 5, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </article>
            <article className="panel inventory-analytics-panel branch-performance-chart-panel">
              <div className="inventory-analytics-panel-head">
                <div><p className="eyebrow">CURRENT INVENTORY</p><h2>Stock value by branch</h2><p>On-hand quantity × unit cost · current snapshot</p></div>
              </div>
              <div className="branch-performance-chart">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartData} margin={{ top: 12, right: 12, left: 12, bottom: 8 }}>
                    <CartesianGrid stroke={chart.grid} vertical={false} />
                    <XAxis dataKey="name" tick={{ fill: chart.tick, fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis tickFormatter={compactMoney} tick={{ fill: chart.tick, fontSize: 10 }} axisLine={false} tickLine={false} width={92} />
                    <Tooltip contentStyle={chart.tooltip} formatter={(value) => [money(Number(value)), 'Stock value']} />
                    <Bar dataKey="stockValue" name="Stock value" fill={chart.series.teal} radius={[5, 5, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </article>
          </section>

          <section className="panel branch-performance-table-panel">
            <div className="inventory-analytics-panel-head">
              <div><p className="eyebrow">BRANCH SCORECARD</p><h2>Detailed comparison</h2><p>Sales metrics follow the selected range; inventory and stock health reflect current records.</p></div>
            </div>
            <div className="table-wrap">
              <table className="data-table">
                <thead><tr><th>Branch</th><th>Sales</th><th>Revenue</th><th>Avg. sale</th><th>Cost of goods</th><th>Gross profit</th><th>Margin</th><th>Stock value</th><th>Items at risk</th></tr></thead>
                <tbody>
                  {rankedBranches.map((branch, index) => (
                    <tr key={branch.id}>
                      <td><strong>{branch.name}</strong><small className="branch-performance-rank">Revenue rank #{index + 1}</small></td>
                      <td>{count(branch.salesCount)}</td>
                      <td><strong>{money(branch.totalRevenue)}</strong></td>
                      <td>{money(branch.averageSale)}</td>
                      <td>{branch.costOfGoodsSold == null ? 'Incomplete data' : money(branch.costOfGoodsSold)}</td>
                      <td>{branch.grossProfit == null ? 'Incomplete data' : money(branch.grossProfit)}</td>
                      <td>{branch.profitMargin == null ? '—' : `${branch.profitMargin.toFixed(1)}%`}</td>
                      <td>{money(branch.stockValue)}</td>
                      <td><span className={branch.attentionItems ? 'branch-performance-risk' : 'branch-performance-healthy'}>{count(branch.attentionItems)}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
