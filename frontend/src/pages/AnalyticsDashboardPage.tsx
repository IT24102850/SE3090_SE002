import { Badge, type BadgeTone } from '../ui/Badge';

const kpis = [
  { label: 'Inventory value', value: 'LKR 4.82M', delta: '+12.4%', tone: 'green' as BadgeTone, spark: [34, 41, 38, 47, 52, 58, 64] },
  { label: 'Stock turnover', value: '6.8x', delta: '+8.2%', tone: 'green' as BadgeTone, spark: [22, 28, 25, 34, 31, 38, 42] },
  { label: 'Days of stock', value: '31 days', delta: '+6.9% vs target', tone: 'amber' as BadgeTone, spark: [40, 42, 45, 39, 41, 33, 31] },
  { label: 'Pending orders', value: 'LKR 620K', delta: '14 open', tone: 'blue' as BadgeTone, spark: [18, 22, 27, 25, 30, 34, 28] },
];

const trend = [
  { label: 'Feb', in: 92, out: 64 },
  { label: 'Mar', in: 118, out: 81 },
  { label: 'Apr', in: 101, out: 74 },
  { label: 'May', in: 134, out: 96 },
  { label: 'Jun', in: 121, out: 88 },
  { label: 'Jul', in: 148, out: 107 },
];

const categories = [
  { label: 'Packaging & supplies', value: 38, color: '#3b82f6' },
  { label: 'Coffee & beverages', value: 27, color: '#f59e0b' },
  { label: 'Bakery & desserts', value: 18, color: '#10b981' },
  { label: 'Dairy & chilled', value: 12, color: '#8b5cf6' },
  { label: 'Groceries', value: 5, color: '#64748b' },
];

const topMovers = [
  { name: 'Colombia Supremo Beans 1kg', sku: 'SKU-00128', change: '+38 this week', pct: 24, up: true },
  { name: 'Craft Paper Cups 12oz (x50)', sku: 'SKU-00771', change: '+31 this week', pct: 18, up: true },
  { name: 'Vanilla Syrup 750ml', sku: 'SKU-00324', change: '-26 this week', pct: 21, up: false },
  { name: 'Butter Croissants (x12)', sku: 'SKU-00451', change: '+22 this week', pct: 15, up: true },
];

const lowStock = [
  { item: 'Premium Coffee Beans', sku: 'SKU-00132', category: 'Coffee & beverages', qty: 6, reorder: 40, owner: 'Kavindu', status: 'Low stock' as const, tone: 'amber' as BadgeTone },
  { item: 'Vanilla Syrup', sku: 'SKU-00324', category: 'Coffee & beverages', qty: 0, reorder: 25, owner: 'Kavindu', status: 'Out of stock' as const, tone: 'red' as BadgeTone },
  { item: 'Packaging Boxes — Medium', sku: 'SKU-00598', category: 'Packaging & supplies', qty: 11, reorder: 60, owner: 'Nadeesha', status: 'Low stock' as const, tone: 'amber' as BadgeTone },
  { item: 'Whole Milk 1L', sku: 'SKU-00811', category: 'Dairy & chilled', qty: 18, reorder: 80, owner: 'Nadeesha', status: 'Low stock' as const, tone: 'amber' as BadgeTone },
];

const purchaseOrders = [
  { po: 'PO-2147', supplier: 'Ceylon Coffee Traders', amount: 'LKR 184,500', date: 'Aug 12', status: 'In transit', tone: 'blue' as BadgeTone },
  { po: 'PO-2146', supplier: 'MetroPack Ltd', amount: 'LKR 96,200', date: 'Aug 10', status: 'Received', tone: 'green' as BadgeTone },
  { po: 'PO-2144', supplier: 'Fresh Farms Dairy', amount: 'LKR 72,850', date: 'Aug 08', status: 'Placed', tone: 'violet' as BadgeTone },
  { po: 'PO-2141', supplier: 'Flour & Co Bakery Supply', amount: 'LKR 61,400', date: 'Aug 04', status: 'In review', tone: 'amber' as BadgeTone },
];

function Sparkline({ points, color }: { points: number[]; color: string }) {
  const max = Math.max(...points);
  const min = Math.min(...points);
  const step = 100 / (points.length - 1);
  const coords = points.map((value, index) => {
    const x = index * step;
    const y = 34 - ((value - min) / (max - min || 1)) * 28;
    return `${x},${y}`;
  });
  const area = `0,34 ${coords.join(' ')} 100,34`;
  return (
    <svg className="sparkline" viewBox="0 0 100 36" preserveAspectRatio="none" aria-hidden="true">
      <defs>
        <linearGradient id={`spark-fill-${color.replace('#', '')}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity=".28" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={area} fill={`url(#spark-fill-${color.replace('#', '')})`} />
      <polyline points={coords.join(' ')} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function StockChart() {
  const max = Math.max(...trend.flatMap((month) => [month.in, month.out]));
  const toY = (value: number) => 168 - (value / max) * 128;
  const toX = (index: number) => 34 + index * (520 / (trend.length - 1));
  const steps = [50, 100, 150, 200];
  const gridLines = steps.map((value) => {
    const y = toY(value);
    return (
      <g key={value}>
        <line x1="34" x2="560" y1={y} y2={y} stroke="#eef2f7" strokeWidth="1" />
        <text x="6" y={y + 4} className="chart-label">{value}</text>
      </g>
    );
  });
  const incoming = trend.map((month, index) => `${toX(index)},${toY(month.in)}`).join(' ');
  const outgoing = trend.map((month, index) => `${toX(index)},${toY(month.out)}`).join(' ');
  return (
    <div className="panel">
      <div className="panel-head">
        <div>
          <h2>Stock movement</h2>
          <p>Incoming and outgoing stock, last 6 months (units ×100)</p>
        </div>
        <select className="range-select" defaultValue="6m" aria-label="Chart period">
          <option value="6m">Last 6 months</option>
          <option value="3m">Last 3 months</option>
          <option value="12m">Last 12 months</option>
        </select>
      </div>
      <div className="chart-legend">
        <span className="legend-key legend-incoming">Incoming</span>
        <span className="legend-key legend-outgoing">Outgoing</span>
      </div>
      <svg className="stock-chart" viewBox="0 0 600 200" role="img" aria-label="Bar chart of incoming and outgoing stock over the last six months">
        {gridLines}
        {trend.map((month, index) => (
          <g key={month.label}>
            <rect x={toX(index) - 10} y={toY(month.in)} width="12" height={168 - toY(month.in)} rx="4" fill="#3b82f6" opacity=".85" />
            <rect x={toX(index) + 4} y={toY(month.out)} width="12" height={168 - toY(month.out)} rx="4" fill="#94a3b8" opacity=".85" />
          </g>
        ))}
        <polyline points={incoming} fill="none" stroke="#2563eb" strokeWidth="2.5" strokeLinecap="round" strokeDasharray="6 4" />
        <polyline points={outgoing} fill="none" stroke="#64748b" strokeWidth="2.5" strokeLinecap="round" strokeDasharray="6 4" />
        {trend.map((month, index) => (
          <text key={month.label} x={toX(index)} y="194" textAnchor="middle" className="chart-label">{month.label}</text>
        ))}
      </svg>
    </div>
  );
}

function CategoryDonut() {
  const total = categories.reduce((sum, category) => sum + category.value, 0);
  let accumulated = 0;
  return (
    <div className="panel">
      <div className="panel-head">
        <div>
          <h2>Inventory by category</h2>
          <p>Share of total stock value</p>
        </div>
      </div>
      <div className="donut-wrap">
        <svg viewBox="0 0 200 200" className="donut" aria-label="Donut chart of inventory by category">
          <circle cx="100" cy="100" r="78" fill="none" stroke="#eef2f7" strokeWidth="30" />
          {categories.map((category) => {
            const fraction = category.value / total;
            const dash = fraction * 2 * Math.PI * 78;
            const offset = accumulated * 2 * Math.PI * 78;
            accumulated += fraction;
            return (
              <circle
                key={category.label}
                cx="100"
                cy="100"
                r="78"
                fill="none"
                stroke={category.color}
                strokeWidth="30"
                strokeDasharray={`${dash} ${2 * Math.PI * 78 - dash}`}
                strokeDashoffset={-offset}
                transform="rotate(-90 100 100)"
              />
            );
          })}
          <text x="100" y="94" textAnchor="middle" className="donut-total">LKR 4.8M</text>
          <text x="100" y="114" textAnchor="middle" className="donut-sub">total value</text>
        </svg>
        <ul className="donut-legend">
          {categories.map((category) => (
            <li key={category.label}>
              <span className="donut-dot" style={{ background: category.color }} />
              <span className="donut-label">{category.label}</span>
              <span className="donut-value">{category.value}%</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function StockLevelBar({ qty, reorder }: { qty: number; reorder: number }) {
  const pct = Math.min(100, (qty / reorder) * 100);
  const tone = qty === 0 ? 'red' : pct < 35 ? 'amber' : 'green';
  return (
    <div className="stock-level">
      <div className={`stock-level-fill stock-level-${tone}`} style={{ width: `${Math.max(4, pct)}%` }} />
    </div>
  );
}

export function AnalyticsDashboardPage() {
  return (
    <div className="page dashboard-page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / ANALYTICS</p>
          <h1>Inventory intelligence</h1>
          <p className="page-sub">Use these signals to make confident stocking decisions.</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-secondary">Export report</button>
          <button className="btn btn-primary">Schedule report</button>
        </div>
      </header>

      <section className="kpi-grid" aria-label="Key metrics">
        {kpis.map((kpi) => (
          <article className="kpi-card" key={kpi.label}>
            <div className="kpi-top">
              <span className="kpi-label">{kpi.label}</span>
              <Badge tone={kpi.tone}>{kpi.delta}</Badge>
            </div>
            <div className="kpi-value">{kpi.value}</div>
            <Sparkline points={kpi.spark} color={kpi.tone === 'amber' ? '#d97706' : kpi.tone === 'blue' ? '#3b82f6' : '#10b981'} />
          </article>
        ))}
      </section>

      <section className="dashboard-grid">
        <StockChart />
        <CategoryDonut />
      </section>

      <section className="dashboard-grid dashboard-grid-bottom">
        <div className="panel">
          <div className="panel-head">
            <div>
              <h2>Top movers</h2>
              <p>Biggest week-over-week changes in unit movement</p>
            </div>
          </div>
          <ul className="movers-list">
            {topMovers.map((mover) => (
              <li className="mover" key={mover.sku}>
                <div className="mover-name">
                  <span className={`mover-arrow mover-${mover.up ? 'up' : 'down'}`}>{mover.up ? '▲' : '▼'}</span>
                  <div>
                    <p className="mover-title">{mover.name}</p>
                    <p className="mover-sku">{mover.sku}</p>
                  </div>
                </div>
                <span className={`mover-change mover-${mover.up ? 'up' : 'down'}`}>{mover.change}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="panel">
          <div className="panel-head">
            <div>
              <h2>Low stock alerts</h2>
              <p>Items that will need reordering soon</p>
            </div>
            <button className="link-button">View all</button>
          </div>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>Item</th><th>On hand</th><th>Stock level</th><th>Status</th></tr>
              </thead>
              <tbody>
                {lowStock.map((row) => (
                  <tr key={row.sku}>
                    <td>
                      <p className="cell-title">{row.item}</p>
                      <p className="cell-sub">{row.sku} · {row.category} · {row.owner}</p>
                    </td>
                    <td><span className="qty">{row.qty}</span> <span className="cell-sub">/{row.reorder}</span></td>
                    <td><StockLevelBar qty={row.qty} reorder={row.reorder} /></td>
                    <td><Badge tone={row.tone}>{row.status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section className="panel purchase-panel">
        <div className="panel-head">
          <div>
            <h2>Purchase order pipeline</h2>
            <p>Orders across all suppliers, most recent first</p>
          </div>
          <button className="link-button">Create purchase order</button>
        </div>
        <div className="table-wrap">
          <table className="data-table purchase-table">
            <thead>
              <tr><th>PO number</th><th>Supplier</th><th>Amount</th><th>Placed</th><th>Status</th><th></th></tr>
            </thead>
            <tbody>
              {purchaseOrders.map((order) => (
                <tr key={order.po}>
                  <td className="po-number">{order.po}</td>
                  <td>{order.supplier}</td>
                  <td className="amount">{order.amount}</td>
                  <td className="cell-sub">{order.date}</td>
                  <td><Badge tone={order.tone}>{order.status}</Badge></td>
                  <td><button className="row-action" aria-label={`Open ${order.po}`}>⋯</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
