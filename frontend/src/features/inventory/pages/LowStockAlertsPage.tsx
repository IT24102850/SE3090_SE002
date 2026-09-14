import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge, type BadgeTone } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';

type AlertLevel = 'Critical' | 'At risk' | 'Watch';

type StockAlert = {
  id: string;
  item: string;
  sku: string;
  branch: string;
  onHand: number;
  reorderLevel: number;
  dailyUse: number;
  level: AlertLevel;
  updatedAt: string;
};

const alerts: StockAlert[] = [
  { id: 'a1', item: 'Vanilla Syrup 750ml', sku: 'SKU-00324', branch: 'Main branch', onHand: 0, reorderLevel: 25, dailyUse: 3.8, level: 'Critical', updatedAt: 'Just now' },
  { id: 'a2', item: 'Premium Coffee Beans', sku: 'SKU-00132', branch: 'Main branch', onHand: 6, reorderLevel: 40, dailyUse: 4.1, level: 'Critical', updatedAt: '2 min ago' },
  { id: 'a3', item: 'Whole Milk 1L (Small)', sku: 'SKU-00811', branch: 'Main branch', onHand: 18, reorderLevel: 80, dailyUse: 12.4, level: 'Critical', updatedAt: '4 min ago' },
  { id: 'a4', item: 'Packaging Boxes — Medium', sku: 'SKU-00598', branch: 'Colombo outlet', onHand: 11, reorderLevel: 60, dailyUse: 3.2, level: 'At risk', updatedAt: '6 min ago' },
  { id: 'a5', item: 'Craft Paper Cups 12oz (x50)', sku: 'SKU-00612', branch: 'Kandy outlet', onHand: 24, reorderLevel: 40, dailyUse: 2.6, level: 'At risk', updatedAt: '8 min ago' },
  { id: 'a6', item: 'Brown Sugar 500g', sku: 'SKU-00902', branch: 'Galle outlet', onHand: 17, reorderLevel: 30, dailyUse: 1.5, level: 'Watch', updatedAt: '12 min ago' },
];

const tone: Record<AlertLevel, BadgeTone> = { Critical: 'red', 'At risk': 'amber', Watch: 'blue' };
const branches = ['All branches', 'Main branch', 'Colombo outlet', 'Kandy outlet', 'Galle outlet'];
const levels = ['All urgency', 'Critical', 'At risk', 'Watch'] as const;

function runOutDate(alert: StockAlert) {
  if (alert.onHand === 0) return 'Out of stock';
  const date = new Date();
  date.setDate(date.getDate() + Math.max(1, Math.ceil(alert.onHand / alert.dailyUse)));
  return date.toLocaleDateString('en-LK', { month: 'short', day: 'numeric' });
}

export function LowStockAlertsPage() {
  const { notify } = useToast();
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState(branches[0]);
  const [level, setLevel] = useState<(typeof levels)[number]>(levels[0]);
  const [lastUpdated, setLastUpdated] = useState(new Date());
  const [actionMessage, setActionMessage] = useState('');

  useEffect(() => {
    const interval = window.setInterval(() => setLastUpdated(new Date()), 30_000);
    return () => window.clearInterval(interval);
  }, []);

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return alerts.filter((alert) =>
      (branch === 'All branches' || alert.branch === branch) &&
      (level === 'All urgency' || alert.level === level) &&
      (!term || alert.item.toLowerCase().includes(term) || alert.sku.toLowerCase().includes(term)),
    );
  }, [branch, level, query]);

  const critical = alerts.filter((alert) => alert.level === 'Critical').length;
  const dueToday = alerts.filter((alert) => alert.onHand === 0 || Math.ceil(alert.onHand / alert.dailyUse) <= 1).length;

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / INVENTORY HEALTH</p>
          <h1>Low-stock alerts</h1>
          <p className="page-sub">Live inventory risk signals with AI-predicted run-out dates based on recent usage.</p>
        </div>
        <div className="page-actions">
          <span className="live-indicator"><span aria-hidden="true" /> Live · updated {lastUpdated.toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}</span>
          <button className="btn btn-secondary" type="button" onClick={() => { setLastUpdated(new Date()); notify('Low-stock signals refreshed.', 'success'); }}>Refresh now</button>
        </div>
      </header>

      <section className="stat-strip" aria-label="Low stock alert summary">
        <div className="stat">
          <div className="metric-icon-bubble metric-amber"><Icon name="alert" /></div>
          <div>
            <span className="stat-value stat-value-out">{critical}</span>
            <span className="stat-label">Critical alerts</span>
          </div>
        </div>
        <div className="stat">
          <div className="metric-icon-bubble metric-purple"><Icon name="clock" /></div>
          <div>
            <span className="stat-value">{dueToday}</span>
            <span className="stat-label">Run out today / tomorrow</span>
          </div>
        </div>
        <div className="stat">
          <div className="metric-icon-bubble metric-cyan"><Icon name="inventory" /></div>
          <div>
            <span className="stat-value">{alerts.length}</span>
            <span className="stat-label">Items being watched</span>
          </div>
        </div>
        <div className="stat">
          <div className="metric-icon-bubble metric-emerald"><Icon name="workflow" /></div>
          <div>
            <span className="stat-value">30s</span>
            <span className="stat-label">Refresh interval</span>
          </div>
        </div>
      </section>

      <section className="panel">
        <div className="toolbar toolbar-wrap">
          <div className="search-field"><span className="search-icon" aria-hidden="true">⌕</span><input type="search" placeholder="Search item or SKU…" value={query} onChange={(event) => setQuery(event.target.value)} aria-label="Search alerts" /></div>
          <select className="filter-select" value={branch} onChange={(event) => setBranch(event.target.value)} aria-label="Filter alerts by branch">{branches.map((entry) => <option key={entry}>{entry}</option>)}</select>
          <select className="filter-select" value={level} onChange={(event) => setLevel(event.target.value as (typeof levels)[number])} aria-label="Filter alerts by urgency">{levels.map((entry) => <option key={entry}>{entry}</option>)}</select>
        </div>
        {actionMessage && <p className="alert-action-message" role="status">{actionMessage}</p>}
        <div className="table-wrap">
          <table className="data-table">
            <thead><tr><th>Item</th><th>Branch</th><th>On hand</th><th>AI forecast</th><th>Urgency</th><th>Last signal</th><th>Action</th></tr></thead>
            <tbody>
              {filtered.map((alert) => (
                <tr key={alert.id}>
                  <td><p className="cell-title">{alert.item}</p><p className="cell-sub">{alert.sku} · Avg. {alert.dailyUse}/day</p></td>
                  <td>{alert.branch}</td>
                  <td><strong className={alert.onHand === 0 ? 'qty qty-out' : 'qty'}>{alert.onHand}</strong><p className="cell-sub">Reorder at {alert.reorderLevel}</p></td>
                  <td><p className={alert.onHand === 0 ? 'forecast-critical' : 'forecast-date'}>{runOutDate(alert)}</p><p className="cell-sub">Usage trend model</p></td>
                  <td><Badge tone={tone[alert.level]}>{alert.level}</Badge></td>
                  <td className="cell-sub">{alert.updatedAt}</td>
                  <td><div className="row-actions"><Link className="table-link" to="/branch-overview">Transfer</Link><button type="button" className="link-button" onClick={() => { setActionMessage(`Reorder draft opened for ${alert.item}.`); notify(`${alert.item} needs a reorder review.`, alert.level === 'Critical' ? 'warning' : 'info'); }}>Reorder</button></div></td>
                </tr>
              ))}
              {filtered.length === 0 && <tr><td colSpan={7} className="empty-state">No alerts match the selected filters.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
      <p className="ai-disclaimer">Forecasts use recent stock movement velocity and should be reviewed alongside supplier lead times.</p>
    </div>
  );
}
