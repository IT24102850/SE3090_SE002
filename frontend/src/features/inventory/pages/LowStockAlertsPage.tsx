import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge, type BadgeTone } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';
import { getStoredToken } from '../authToken';

type HealthStatus = 'Out of stock' | 'Below reorder' | 'Healthy';

type InventoryHealthRow = {
  id: string;
  item: string;
  sku: string;
  branch: string;
  branchId?: string;
  onHand: number;
  reorderLevel: number;
  unitCost?: number;
  health: HealthStatus;
  updatedAt: string;
};

const tone: Record<HealthStatus, BadgeTone> = { 'Out of stock': 'red', 'Below reorder': 'amber', Healthy: 'green' };
const healthFilters = ['All inventory', 'Out of stock', 'Below reorder', 'Healthy'] as const;
const analysisStages = [
  'Reading your authorized inventory snapshot…',
  'Matching recent issues, sales and usage…',
  'Checking stock coverage and reorder risks…',
  'Reviewing waste and movement gaps…',
  'Preparing clear findings for your review…',
];

function formatSignalTime(value?: string) {
  if (!value) return 'Not recorded';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'Not recorded' : date.toLocaleString('en-LK');
}

type InventoryRecommendation = {
  inventory_item_id: string; item_name: string; sku: string; branch_id?: string; branch_name?: string;
  on_hand: number; reorder_level: number; avg_daily_outflow?: number | null; recommended_quantity: number;
  estimated_total_cost?: number | null; confidence: number; reason: string;
};
type InventoryInsight = { category: string; title: string; detail: string; affected_items: string[] };
type InventoryPlan = { workflow_id: string; status: string; planner_summary: string; data_sources: string[]; recommendations: InventoryRecommendation[]; insights: InventoryInsight[]; warnings: string[] };

function insightIcon(category: string) {
  switch (category) {
    case 'coverage': return 'predict';
    case 'movement': return 'workflow';
    case 'data_quality': return 'info';
    case 'cost': return 'chart';
    default: return 'inventory';
  }
}

export function LowStockAlertsPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const [inventory, setInventory] = useState<InventoryHealthRow[]>([]);
  const [inventoryTotalCount, setInventoryTotalCount] = useState(0);
  const [query, setQuery] = useState('');
  const [branch, setBranch] = useState('All branches');
  const [healthFilter, setHealthFilter] = useState<(typeof healthFilters)[number]>(healthFilters[0]);
  const [lastUpdated, setLastUpdated] = useState(new Date());
  const [loading, setLoading] = useState(true);
  const [inventoryError, setInventoryError] = useState('');
  const [planning, setPlanning] = useState(false);
  const [analysisStep, setAnalysisStep] = useState(0);
  const [plan, setPlan] = useState<InventoryPlan | null>(null);
  const [planError, setPlanError] = useState('');

  const loadInventory = useCallback(async (showSuccess = false) => {
    setLoading(true);
    try {
      const response = await fetch('/api/inventory?page=1&pageSize=100', {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!response.ok) throw new Error(`Inventory request failed (${response.status})`);
      const data = await response.json();
      setInventoryTotalCount(Number(data.totalCount ?? data.items?.length ?? 0));
      setInventory((data.items ?? []).map((item: any): InventoryHealthRow => {
        const onHand = Number(item.quantity ?? 0);
        const reorderLevel = Number(item.reorderLevel ?? 0);
        return {
          id: item.id,
          item: item.name,
          sku: item.sku,
          branch: item.branch ?? 'Unassigned',
          branchId: item.branchId,
          onHand,
          reorderLevel,
          unitCost: item.unitCost == null ? undefined : Number(item.unitCost),
          health: onHand <= 0 ? 'Out of stock' : onHand <= reorderLevel ? 'Below reorder' : 'Healthy',
          updatedAt: formatSignalTime(item.updatedAt ?? item.createdAt),
        };
      }));
      setLastUpdated(new Date());
      setInventoryError('');
      if (showSuccess) notify('Inventory refreshed successfully. The stock health summary is up to date.', 'success');
    } catch {
      setInventory([]);
      setInventoryTotalCount(0);
      setInventoryError('Inventory data could not be synchronized.');
      notify('Unable to load inventory health from the database.', 'error');
    } finally {
      setLoading(false);
    }
  }, [notify, token]);

  async function analyzeInventory() {
    setPlan(null);
    setPlanning(true);
    setPlanError('');
    try {
      const selectedBranch = inventory.find((item) => item.branch === branch)?.branchId;
      const response = await fetch('/api/inventory/agent/plan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({
          objective: 'Review overall inventory health, not only low stock. Identify stock coverage risks from recorded issue/sale/consumption, summarize items without recorded outflow and recent waste movements, and explain uncertainty. Do not infer demand from missing history.',
          branchId: branch === 'All branches' ? undefined : selectedBranch,
        }),
      });
      const responseBody = await response.text();
      let result: any = {};
      if (responseBody.trim()) {
        try {
          result = JSON.parse(responseBody);
        } catch {
          const preview = responseBody.replace(/\s+/g, ' ').slice(0, 180);
          throw new Error(`Inventory analysis API returned a non-JSON response (HTTP ${response.status}): ${preview || 'empty response'}`);
        }
      }
      if (!responseBody.trim()) {
        if (response.status === 401) throw new Error('Your session has expired. Sign in again and retry inventory analysis.');
        if (response.status === 403) throw new Error('Your account does not have permission to read inventory for this branch.');
        if (response.status === 404) throw new Error('The backend does not have the inventory AI endpoint yet. Restart the ASP.NET backend and retry.');
        throw new Error(`Inventory analysis API returned an empty response (HTTP ${response.status}). Check that the backend has restarted with the inventory agent endpoint and that the agent service is configured.`);
      }
      if (!response.ok) throw new Error(result.message ?? result.warnings?.[0] ?? `Inventory analysis failed (${response.status}).`);
      setPlan(result as InventoryPlan);
    } catch (error) {
      setPlanError(error instanceof Error ? error.message : 'Inventory analysis failed.');
    } finally {
      setPlanning(false);
    }
  }

  useEffect(() => {
    void loadInventory();
    const interval = window.setInterval(() => void loadInventory(), 30_000);
    return () => window.clearInterval(interval);
  }, [loadInventory]);

  useEffect(() => {
    if (!planning) {
      setAnalysisStep(0);
      return;
    }
    const timer = window.setInterval(() => {
      setAnalysisStep((step) => (step + 1) % analysisStages.length);
    }, 2200);
    return () => window.clearInterval(timer);
  }, [planning]);

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return inventory.filter((alert) =>
      (branch === 'All branches' || alert.branch === branch) &&
      (healthFilter === 'All inventory' || alert.health === healthFilter) &&
      (!term || alert.item.toLowerCase().includes(term) || alert.sku.toLowerCase().includes(term)),
    );
  }, [branch, healthFilter, inventory, query]);

  const outOfStock = inventory.filter((item) => item.health === 'Out of stock').length;
  const belowReorder = inventory.filter((item) => item.health === 'Below reorder').length;
  const healthy = inventory.filter((item) => item.health === 'Healthy').length;
  const pricedItems = inventory.filter((item) => item.unitCost != null);
  const estimatedValue = pricedItems.reduce((sum, item) => sum + item.onHand * (item.unitCost ?? 0), 0);
  const branchOptions = ['All branches', ...Array.from(new Set(inventory.map((item) => item.branch)))];

  return (
    <div className="page stocksense-page">
      <header className="page-head stocksense-hero">
        <div className="stocksense-hero-copy">
          <div className="stocksense-brandmark"><Icon name="stocksense" size={38} /></div>
          <div>
            <p className="eyebrow">INTELLIGENT INVENTORY OPERATIONS</p>
            <h1>StockSense AI</h1>
            <p className="page-sub">A clear view of stock health, movement patterns, coverage risks and replenishment decisions.</p>
            <div className="stocksense-capabilities"><span>Stock coverage</span><span>Movement insights</span><span>Reorder guidance</span></div>
          </div>
        </div>
        <div className="page-actions stocksense-hero-actions">
          <span className={`live-indicator stocksense-updated${inventoryError ? ' is-stale' : ''}`}><span aria-hidden="true" />{inventoryError ? 'Inventory sync needs attention' : 'Inventory data current'} · Updated {lastUpdated.toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}</span>
          <button className="btn btn-primary stocksense-analyze-button" type="button" onClick={analyzeInventory} disabled={planning}><span className="stocksense-button-spark" aria-hidden="true">✦</span><span>{planning ? 'Analyzing inventory…' : 'Analyze inventory'}</span><span className="stocksense-button-arrow" aria-hidden="true">→</span></button>
          <span className="stocksense-cta-hint">Get a clear stock health report</span>
          <button className="btn btn-secondary" type="button" onClick={() => { void loadInventory(true); }} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh now'}</button>
        </div>
        <div className="stocksense-hero-orbit" aria-hidden="true"><span /><i /></div>
      </header>

      {inventoryError && <p className="page-notice stocksense-sync-notice" role="alert">{inventoryError} The timestamp above shows the last successful snapshot.</p>}

      {planning && <section className="stocksense-progress-panel" role="status" aria-live="polite">
        <div className="stocksense-progress-orbit"><div className="stocksense-progress-ring" /><Icon name="stocksense" size={50} /><span className="stocksense-orbit-dot" /></div>
        <div className="stocksense-progress-copy">
          <div className="stocksense-progress-heading"><p className="eyebrow">LIVE INVENTORY ANALYSIS</p><span>STEP {analysisStep + 1} / {analysisStages.length}</span></div>
          <h2>Building your stock health report</h2>
          <p key={analysisStep} className="stocksense-progress-stage">{analysisStages[analysisStep]}</p>
          <div className="stocksense-stage-pips" aria-hidden="true">{analysisStages.map((stage, index) => <span key={stage} className={index === analysisStep ? 'active' : index < analysisStep ? 'done' : ''} />)}</div>
          <p className="stocksense-progress-note">Checking stock levels and available movement history. Your inventory is not changed.</p>
        </div>
        <div className="stocksense-progress-meter" aria-label="Analysis in progress"><span /></div>
      </section>}

      {plan && <section className="panel stocksense-ai-panel">
        <div className="panel-head stocksense-ai-head">
          <div className="stocksense-ai-title"><div className="stocksense-ai-orb"><span>✦</span></div><div><p className="eyebrow">STOCKSENSE AI REPORT</p><h2>Inventory health analysis</h2><p className="hint">{plan.planner_summary}</p></div></div>
          <Badge tone={plan.status === 'NeedsReview' ? 'amber' : 'blue'}>{plan.status === 'NeedsReview' ? 'Review recommendations' : plan.insights?.length ? 'Review insights' : 'No action found'}</Badge>
        </div>
        <div className="stocksense-ai-body">
          <p className="cell-sub">Read-only analysis using {plan.data_sources.join(' and ').toLowerCase()}. It has not changed stock or created purchase orders.</p>
          {plan.warnings.map((warning, index) => <p className="page-notice" key={index}>{warning}</p>)}
          {plan.insights?.length > 0 && <><div className="stocksense-section-heading"><div><p className="eyebrow">SIGNALS FROM YOUR DATA</p><h3>Inventory health insights</h3></div><span>{plan.insights.length} insights</span></div><div className="stocksense-insights-grid" aria-label="Inventory health insights">{plan.insights.map((insight, index) => <article className={`stocksense-insight-card stocksense-insight-${insight.category}`} key={`${insight.category}-${index}`} style={{ animationDelay: `${Math.min(index * 75, 450)}ms` }}>
            <div className="stocksense-insight-top"><span className="stocksense-insight-icon"><Icon name={insightIcon(insight.category)} size={19} /></span><p className="stocksense-insight-category">{insight.category.replace('_', ' ')}</p></div><h3>{insight.title}</h3><p className="cell-sub">{insight.detail}</p>
            {insight.affected_items?.length > 0 && <div className="stocksense-item-chips">{insight.affected_items.map((itemName) => <span key={itemName}>{itemName}</span>)}</div>}
          </article>)}</div></>}
          {plan.recommendations.length > 0 && <><div className="stocksense-section-heading"><div><p className="eyebrow">HUMAN REVIEW REQUIRED</p><h3>Replenishment recommendations</h3></div><span>{plan.recommendations.length} to review</span></div><div className="table-wrap"><table className="data-table"><thead><tr><th>Item</th><th>On hand</th><th>Avg. daily outflow</th><th>Suggested reorder</th><th>Est. cost</th><th>Reason</th><th>Review</th></tr></thead><tbody>
            {plan.recommendations.map((item) => <tr key={item.inventory_item_id}>
              <td><strong>{item.item_name}</strong><div className="cell-sub">{item.sku} · {item.branch_name ?? 'No branch'}</div></td>
              <td>{item.on_hand} / {item.reorder_level} reorder level</td>
              <td>{item.avg_daily_outflow == null ? 'No usage history' : `${item.avg_daily_outflow}/day`}</td>
              <td><strong>{item.recommended_quantity}</strong><div className="cell-sub">Confidence {Math.round(item.confidence * 100)}%</div></td>
              <td>{item.estimated_total_cost == null ? 'Unit cost not set' : item.estimated_total_cost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })}</td>
              <td>{item.reason}</td>
              <td><Link className="link-button" to={`/purchase-orders?reorderItemId=${encodeURIComponent(item.inventory_item_id)}&branchId=${encodeURIComponent(item.branch_id ?? '')}&quantity=${encodeURIComponent(item.recommended_quantity)}`}>Review order</Link></td>
            </tr>)}
          </tbody></table></div></>}
        </div>
      </section>}
      {planError && <p className="page-notice" role="alert" style={{ marginTop: 12 }}>{planError}</p>}


      <section className="stat-strip movement-stat-strip stocksense-kpis" aria-label="Inventory health summary">
        <article className="stat metric-card movement-stat movement-stat-activity stocksense-kpi stocksense-kpi-total"><div className="movement-stat-main"><span className="movement-stat-icon"><Icon name="inventory" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">INVENTORY</span><strong className="movement-stat-value">{inventory.length}{inventoryTotalCount > inventory.length ? ` / ${inventoryTotalCount}` : ''}</strong><span className="movement-stat-label">Items loaded</span></div><span className="movement-stat-index">01</span></div><div className="movement-stat-detail">{inventoryTotalCount} items in the current snapshot</div></article>
        <article className="stat metric-card movement-stat movement-stat-out stocksense-kpi stocksense-kpi-out"><div className="movement-stat-main"><span className="movement-stat-icon"><Icon name="alert" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">OUT OF STOCK</span><strong className="movement-stat-value">{outOfStock}</strong><span className="movement-stat-label">Items requiring attention</span></div><span className="movement-stat-glyph">OUT</span></div><div className="movement-stat-detail">{outOfStock ? 'Replenishment review required' : 'No empty stock records'}</div></article>
        <article className="stat metric-card movement-stat movement-stat-in stocksense-kpi stocksense-kpi-reorder"><div className="movement-stat-main"><span className="movement-stat-icon"><Icon name="alert" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">REORDER WATCH</span><strong className="movement-stat-value">{belowReorder}</strong><span className="movement-stat-label">Below reorder level</span></div><span className="movement-stat-glyph">LOW</span></div><div className="movement-stat-detail">{belowReorder} items need review</div></article>
        <article className="stat metric-card movement-stat movement-stat-net stocksense-kpi stocksense-kpi-value"><div className="movement-stat-main"><span className="movement-stat-icon"><Icon name="workflow" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">STOCK VALUE</span><strong className="movement-stat-value stocksense-stock-value" title={pricedItems.length ? `LKR ${estimatedValue.toLocaleString('en-LK')}` : 'No item costs recorded'}>{pricedItems.length ? `LKR ${new Intl.NumberFormat('en-LK', { notation: 'compact', maximumFractionDigits: 1 }).format(estimatedValue)}` : 'Not set'}</strong><span className="movement-stat-label">Estimated · {healthy} healthy</span></div><span className="movement-stat-glyph">LKR</span></div><div className="movement-stat-detail">Based on {pricedItems.length} priced items</div></article>
      </section>

      <section className="panel stocksense-inventory-panel">
        <div className="panel-head"><div><h2>Inventory status</h2><p className="hint">Health is based on current quantity and configured reorder level.{inventoryTotalCount > inventory.length ? ` Showing the first ${inventory.length} of ${inventoryTotalCount} items.` : ''}</p></div></div>
        <div className="toolbar toolbar-wrap">
          <div className="search-field"><span className="search-icon" aria-hidden="true">⌕</span><input type="search" placeholder="Search item or SKU…" value={query} onChange={(event) => setQuery(event.target.value)} aria-label="Search inventory" /></div>
          <select className="filter-select" value={branch} onChange={(event) => setBranch(event.target.value)} aria-label="Filter inventory by branch">{branchOptions.map((entry) => <option key={entry}>{entry}</option>)}</select>
          <select className="filter-select" value={healthFilter} onChange={(event) => setHealthFilter(event.target.value as (typeof healthFilters)[number])} aria-label="Filter inventory by health">{healthFilters.map((entry) => <option key={entry}>{entry}</option>)}</select>
        </div>
        <div className="table-wrap">
          <table className="data-table">
            <thead><tr><th>Item</th><th>Branch</th><th>On hand</th><th>Unit cost</th><th>Health</th><th>Last updated</th><th>Action</th></tr></thead>
            <tbody>
              {loading && <tr><td colSpan={7} className="empty-state">Loading inventory health…</td></tr>}
              {!loading && filtered.map((alert) => (
                <tr key={alert.id}>
                  <td><p className="cell-title">{alert.item}</p><p className="cell-sub">{alert.sku}</p></td>
                  <td>{alert.branch}</td>
                  <td><strong className={alert.onHand === 0 ? 'qty qty-out' : 'qty'}>{alert.onHand}</strong><p className="cell-sub">Reorder at {alert.reorderLevel}</p></td>
                  <td>{alert.unitCost == null ? 'Not set' : alert.unitCost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })}</td>
                  <td><Badge tone={tone[alert.health]}>{alert.health}</Badge></td>
                  <td className="cell-sub">{alert.updatedAt}</td>
                  <td><div className="row-actions">
                    <Link className="table-link" to={`/inventory?search=${encodeURIComponent(alert.sku)}`}>View item</Link>
                    {alert.health !== 'Healthy' && <Link className="link-button" to={`/purchase-orders?reorderItemId=${encodeURIComponent(alert.id)}&branchId=${encodeURIComponent(alert.branchId ?? '')}`}>Review order</Link>}
                  </div></td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={7} className="empty-state">{inventory.length ? 'No inventory items match these filters.' : 'No inventory items are available.'}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
      <p className="ai-disclaimer">Coverage and movement insights use the returned inventory snapshot and recent movement sample. Recommendations use explicit outflow history when available; where history is missing, reorder quantities fall back to reorder levels. Review supplier, lead time and budget before ordering.</p>
    </div>
  );
}
