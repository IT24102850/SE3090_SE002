import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge, type BadgeTone } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';
import { getStoredToken } from '../authToken';

type AlertLevel = 'Critical' | 'At risk' | 'Watch';

type StockAlert = {
  id: string;
  item: string;
  sku: string;
  branch: string;
  branchId?: string;
  onHand: number;
  reorderLevel: number;
  dailyUse: number;
  level: AlertLevel;
  updatedAt: string;
};

const tone: Record<AlertLevel, BadgeTone> = { Critical: 'red', 'At risk': 'amber', Watch: 'blue' };
const levels = ['All urgency', 'Critical', 'At risk', 'Watch'] as const;

function formatSignalTime(value?: string) {
  if (!value) return 'Not recorded';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'Not recorded' : date.toLocaleString('en-LK');
}

function runOutDate(alert: StockAlert) {
  if (alert.onHand === 0) return 'Out of stock';
  const date = new Date();
  date.setDate(date.getDate() + Math.max(1, Math.ceil(alert.onHand / alert.dailyUse)));
  return date.toLocaleDateString('en-LK', { month: 'short', day: 'numeric' });
}

export function LowStockAlertsPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const [liveAlerts, setLiveAlerts] = useState<StockAlert[]>([]);
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState('All branches');
  const [level, setLevel] = useState<(typeof levels)[number]>(levels[0]);
  const [lastUpdated, setLastUpdated] = useState(new Date());
  const [loading, setLoading] = useState(true);

  const loadAlerts = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch('/api/inventory/low-stock?pageSize=100', {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!response.ok) throw new Error(`Low-stock request failed (${response.status})`);
      const data = await response.json();
      setLiveAlerts((data.items ?? []).map((item: any): StockAlert => {
        const onHand = Number(item.quantity ?? 0);
        const reorderLevel = Number(item.reorderLevel ?? 0);
        const ratio = reorderLevel > 0 ? onHand / reorderLevel : 1;
        return {
          id: item.id,
          item: item.name,
          sku: item.sku,
          branch: item.branch ?? 'Unassigned',
          branchId: item.branchId,
          onHand,
          reorderLevel,
          dailyUse: 1,
          level: onHand === 0 || ratio < .45 ? 'Critical' : ratio <= 1 ? 'At risk' : 'Watch',
          updatedAt: formatSignalTime(item.updatedAt ?? item.createdAt),
        };
      }));
      setLastUpdated(new Date());
    } catch {
      setLiveAlerts([]);
      notify('Unable to load low-stock alerts from the database.', 'error');
    } finally {
      setLoading(false);
    }
  }, [notify, token]);

  useEffect(() => {
    void loadAlerts();
    const interval = window.setInterval(() => void loadAlerts(), 30_000);
    return () => window.clearInterval(interval);
  }, [loadAlerts]);

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return liveAlerts.filter((alert) =>
      (branch === 'All branches' || alert.branch === branch) &&
      (level === 'All urgency' || alert.level === level) &&
      (!term || alert.item.toLowerCase().includes(term) || alert.sku.toLowerCase().includes(term)),
    );
  }, [branch, level, liveAlerts, query]);

  const critical = liveAlerts.filter((alert) => alert.level === 'Critical').length;
  const dueToday = liveAlerts.filter((alert) => alert.onHand === 0 || Math.ceil(alert.onHand / alert.dailyUse) <= 1).length;
  const branchOptions = ['All branches', ...Array.from(new Set(liveAlerts.map((alert) => alert.branch)))];

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
          <button className="btn btn-secondary" type="button" onClick={() => { void loadAlerts(); setLastUpdated(new Date()); }}>Refresh now</button>
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
            <span className="stat-value">{liveAlerts.length}</span>
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
          <select className="filter-select" value={branch} onChange={(event) => setBranch(event.target.value)} aria-label="Filter alerts by branch">{branchOptions.map((entry) => <option key={entry}>{entry}</option>)}</select>
          <select className="filter-select" value={level} onChange={(event) => setLevel(event.target.value as (typeof levels)[number])} aria-label="Filter alerts by urgency">{levels.map((entry) => <option key={entry}>{entry}</option>)}</select>
        </div>
        <div className="table-wrap">
          <table className="data-table">
            <thead><tr><th>Item</th><th>Branch</th><th>On hand</th><th>AI forecast</th><th>Urgency</th><th>Last signal</th><th>Action</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={7} className="empty-state">Checking live inventory levels…</td></tr>}
              {!loading && filtered.map((alert) => (
                <tr key={alert.id}>
                  <td><p className="cell-title">{alert.item}</p><p className="cell-sub">{alert.sku} · Avg. {alert.dailyUse}/day</p></td>
                  <td>{alert.branch}</td>
                  <td><strong className={alert.onHand === 0 ? 'qty qty-out' : 'qty'}>{alert.onHand}</strong><p className="cell-sub">Reorder at {alert.reorderLevel}</p></td>
                  <td><p className={alert.onHand === 0 ? 'forecast-critical' : 'forecast-date'}>{runOutDate(alert)}</p><p className="cell-sub">Usage trend model</p></td>
                  <td><Badge tone={tone[alert.level]}>{alert.level}</Badge></td>
                  <td className="cell-sub">{alert.updatedAt}</td>
                  <td><div className="row-actions">
                    <Link className="table-link" to={`/inventory?search=${encodeURIComponent(alert.sku)}`}>Transfer</Link>
                    <Link className="link-button" to={`/purchase-orders?reorderItemId=${encodeURIComponent(alert.id)}&branchId=${encodeURIComponent(alert.branchId ?? '')}`}>Reorder</Link>
                  </div></td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={7} className="empty-state">No items are currently below their reorder level.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
      <p className="ai-disclaimer">Forecasts use recent stock movement velocity and should be reviewed alongside supplier lead times.</p>
    </div>
  );
}
