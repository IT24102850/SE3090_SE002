import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';
import { getStoredToken } from '../authToken';
import { scrollToId } from '../../marketing/scroll/useSmoothScroll';

type InventoryBranch = {
  branch: string;
  branchId?: string;
};

const analysisStages = [
  'Reading your authorized inventory snapshot…',
  'Matching recent issues, sales and usage…',
  'Checking stock coverage and reorder risks…',
  'Reviewing waste and movement gaps…',
  'Preparing clear findings for your review…',
];

type InventoryRecommendation = {
  inventory_item_id: string; item_name: string; sku: string; branch_id?: string; branch_name?: string;
  on_hand: number; reorder_level: number; avg_daily_outflow?: number | null; recommended_quantity: number;
  days_until_reorder?: number | null; estimated_total_cost?: number | null;
  confidence: number; reason: string; validation_notes: string[];
};
type InventoryInsight = { category: string; title: string; detail: string; affected_items: string[] };
type InventoryPlan = { workflow_id: string; status: string; planner_summary: string; data_sources: string[]; recommendations: InventoryRecommendation[]; insights: InventoryInsight[]; warnings: string[] };

function insightIcon(category: string) {
  switch (category) {
    case 'coverage': return 'predict';
    case 'movement': return 'workflow';
    case 'trend': return 'chart';
    case 'excess': return 'inventory';
    case 'risk': return 'alert';
    case 'data_quality': return 'info';
    case 'cost': return 'chart';
    default: return 'inventory';
  }
}

export function LowStockAlertsPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const [inventory, setInventory] = useState<InventoryBranch[]>([]);
  const [branch, setBranch] = useState('All branches');
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
      const firstPage = await response.json();
      const totalPages = Math.max(1, Number(firstPage.totalPages) || 1);
      const remainingPages = await Promise.all(
        Array.from({ length: totalPages - 1 }, async (_, index) => {
          const page = index + 2;
          const pageResponse = await fetch(`/api/inventory?page=${page}&pageSize=100`, {
            headers: token ? { Authorization: `Bearer ${token}` } : undefined,
          });
          if (!pageResponse.ok) throw new Error(`Inventory page ${page} failed (${pageResponse.status})`);
          return pageResponse.json();
        }),
      );
      const pages = [firstPage, ...remainingPages];
      const allItems = pages.flatMap((page) => page.items ?? []);
      setInventory(allItems.map((item: any): InventoryBranch => ({
        branch: item.branch ?? 'Unassigned',
        branchId: item.branchId,
      })));
      setLastUpdated(new Date());
      setInventoryError('');
      if (showSuccess) notify('Inventory refreshed successfully. The stock health summary is up to date.', 'success');
    } catch {
      setInventory([]);
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

  useEffect(() => {
    if (planning) scrollToId('stocksense-analysis-progress');
  }, [planning]);

  useEffect(() => {
    if (plan) {
      scrollToId('stocksense-analysis-report');
    } else if (planError) {
      scrollToId('stocksense-analysis-error');
    }
  }, [plan, planError]);

  const branchOptions = ['All branches', ...Array.from(new Set(inventory.map((item) => item.branch)))];

  return (
    <div className="page stocksense-page">
      <header className="page-head stocksense-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="stocksense-hero-copy">
          <div className="stocksense-brandmark"><Icon name="stocksense" size={38} /></div>
          <div>
            <p className="eyebrow">INTELLIGENT INVENTORY OPERATIONS</p>
            <h1>StockSense AI</h1>
            <p className="page-sub">AI-powered insights into stock movement, coverage risks, and replenishment decisions.</p>
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

      <section className="stocksense-guide" aria-labelledby="stocksense-guide-title">
        <div className="stocksense-guide-heading">
          <div>
            <p className="eyebrow">A SMARTER WAY TO MANAGE STOCK</p>
            <h2 id="stocksense-guide-title">Know what needs attention—and what to do next.</h2>
            <p>StockSense turns your inventory snapshot and recorded activity into practical guidance your team can review.</p>
          </div>
          <div className="stocksense-guide-visual" aria-hidden="true">
            <span className="stocksense-visual-orbit" />
            <div className="stocksense-visual-health">
              <span className="stocksense-visual-label"><i /> STOCK HEALTH</span>
              <strong>In focus</strong>
              <span className="stocksense-visual-bars"><i /><i /><i /><i /><i /><i /><i /></span>
            </div>
            <div className="stocksense-visual-insight"><Icon name="stocksense" size={18} /><span>Insights ready</span><b>✦</b></div>
          </div>
          <span className="stocksense-guide-badge"><Icon name="stocksense" size={19} /> Your inventory co-pilot</span>
        </div>
        <div className="stocksense-guide-grid">
          <article className="stocksense-guide-card" style={{ animationDelay: '40ms' }}>
            <span className="stocksense-guide-icon guide-risk"><Icon name="alert" size={21} /></span>
            <span className="stocksense-guide-step">01 · SPOT RISKS</span>
            <h3>Catch stock problems earlier</h3>
            <p>See out-of-stock and below-reorder items, check stock health by branch, and focus attention where it is needed.</p>
          </article>
          <article className="stocksense-guide-card" style={{ animationDelay: '130ms' }}>
            <span className="stocksense-guide-icon guide-movement"><Icon name="chart" size={21} /></span>
            <span className="stocksense-guide-step">02 · UNDERSTAND ACTIVITY</span>
            <h3>Know what is moving</h3>
            <p>Use recorded sales, issues, consumption and waste to understand outflow. Missing history is called out—not guessed.</p>
          </article>
          <article className="stocksense-guide-card" style={{ animationDelay: '220ms' }}>
            <span className="stocksense-guide-icon guide-plan"><Icon name="predict" size={21} /></span>
            <span className="stocksense-guide-step">03 · PLAN WITH CONFIDENCE</span>
            <h3>Review useful next steps</h3>
            <p>Get reorder suggestions with reasons, estimated cost and confidence, then decide what fits your suppliers and budget.</p>
          </article>
        </div>
        <div className="stocksense-guide-footer">
          <span><strong>Simple workflow</strong> Refresh stock <i aria-hidden="true">→</i> Analyze inventory <i aria-hidden="true">→</i> Review suggestions</span>
          <span className="stocksense-readonly-note"><Icon name="info" size={15} /> Read-only: StockSense never changes stock or creates orders.</span>
        </div>
      </section>

      {inventoryError && <p className="page-notice stocksense-sync-notice" role="alert">{inventoryError} The timestamp above shows the last successful snapshot.</p>}

      <section className="panel stocksense-scope-panel" aria-label="Inventory analysis scope">
        <div className="panel-head">
          <div>
            <p className="eyebrow">ANALYSIS SCOPE</p>
            <h2>Choose what StockSense reviews</h2>
            <p className="hint">Stock details and editing stay in Inventory Manager; this page focuses on analysis and recommendations.</p>
          </div>
        </div>
        <div className="toolbar toolbar-wrap">
          <label className="stocksense-scope-label" htmlFor="stocksense-analysis-branch">Branch</label>
          <select
            id="stocksense-analysis-branch"
            className="filter-select"
            value={branch}
            onChange={(event) => setBranch(event.target.value)}
            aria-label="Select branch for analysis"
          >
            {branchOptions.map((entry) => <option key={entry}>{entry}</option>)}
          </select>
          <Link className="btn btn-secondary" to="/inventory">Open Inventory Manager</Link>
        </div>
      </section>

      {planning && <section id="stocksense-analysis-progress" className="stocksense-progress-panel" role="status" aria-live="polite">
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

      {plan && <section id="stocksense-analysis-report" className="panel stocksense-ai-panel">
        <div className="panel-head stocksense-ai-head">
          <div className="stocksense-ai-title"><div className="stocksense-ai-orb"><span>✦</span></div><div><p className="eyebrow">STOCKSENSE AI REPORT</p><h2>Inventory health analysis</h2><p className="hint">{plan.planner_summary}</p></div></div>
          <Badge tone={plan.status === 'NeedsReview' ? 'amber' : 'blue'}>{plan.status === 'NeedsReview' ? 'Review recommendations' : plan.insights?.length ? 'Review insights' : 'No action found'}</Badge>
        </div>
        <div className="stocksense-ai-body">
          <p className="cell-sub">Read-only analysis using {plan.data_sources.join(' and ').toLowerCase()}. It has not changed stock or created purchase orders.</p>
          {plan.warnings.map((warning, index) => {
            const isDeterministic = warning.toLowerCase().includes('deterministic') || warning.toLowerCase().includes('gemini is unavailable');
            return (
              <div
                className={`stocksense-status-notice ${isDeterministic ? 'notice-info' : 'notice-neutral'}`}
                key={index}
                role="status"
              >
                <span className="stocksense-notice-icon">
                  <Icon name={isDeterministic ? 'workflow' : 'info'} size={16} />
                </span>
                <div className="stocksense-notice-content">
                  <strong>{isDeterministic ? 'Operational Notice' : 'Planning Parameter'}</strong>
                  <p>{warning}</p>
                </div>
              </div>
            );
          })}
          {plan.insights?.length > 0 && <><div className="stocksense-section-heading"><div><p className="eyebrow">SIGNALS FROM YOUR DATA</p><h3>Inventory health insights</h3></div><span>{plan.insights.length} insights</span></div><div className="stocksense-insights-grid" aria-label="Inventory health insights">{plan.insights.map((insight, index) => <article className={`stocksense-insight-card stocksense-insight-${insight.category}`} key={`${insight.category}-${index}`} style={{ animationDelay: `${Math.min(index * 75, 450)}ms` }}>
            <div className="stocksense-insight-top"><span className="stocksense-insight-icon"><Icon name={insightIcon(insight.category)} size={19} /></span><p className="stocksense-insight-category">{insight.category.replace('_', ' ')}</p></div><h3>{insight.title}</h3><p className="cell-sub">{insight.detail}</p>
            {insight.affected_items?.length > 0 && <div className="stocksense-item-chips">{insight.affected_items.map((itemName) => <span key={itemName}>{itemName}</span>)}</div>}
          </article>)}</div></>}
          {plan.recommendations.length > 0 && <>
            <div className="stocksense-section-heading">
              <div><p className="eyebrow">HUMAN REVIEW REQUIRED</p><h3>Replenishment recommendations</h3></div>
              <span>{plan.recommendations.length} to review</span>
            </div>
            <div className="stocksense-recommendations" aria-label="Replenishment recommendations">
              {plan.recommendations.map((item) => {
                const confidence = Math.max(0, Math.min(100, Math.round(item.confidence * 100)));
                const confidenceLabel = confidence >= 70 ? 'Strong movement evidence' : confidence >= 50 ? 'Some movement evidence' : 'Limited movement evidence';
                return (
                  <article className="stocksense-recommendation-card" key={item.inventory_item_id}>
                    <div className="stocksense-recommendation-head">
                      <div>
                        <p className="eyebrow">REPLENISHMENT REVIEW</p>
                        <h4>{item.item_name}</h4>
                        <p className="cell-sub">{item.sku} · {item.branch_name ?? 'No branch'}</p>
                      </div>
                      <div className="stocksense-recommendation-confidence">
                        <strong>{confidence}%</strong>
                        <span>{confidenceLabel}</span>
                        <div
                          className="stocksense-confidence-track"
                          role="progressbar"
                          aria-label={`Confidence: ${confidence}%`}
                          aria-valuemin={0}
                          aria-valuemax={100}
                          aria-valuenow={confidence}
                        >
                          <span style={{ width: `${confidence}%` }} />
                        </div>
                      </div>
                    </div>
                    <div className="stocksense-recommendation-metrics">
                      <div><span>On hand / reorder point</span><strong>{item.on_hand} / {item.reorder_level}</strong></div>
                      <div><span>Recorded outflow</span><strong>{item.avg_daily_outflow == null ? 'No usage history' : `${item.avg_daily_outflow} / day`}</strong></div>
                      <div><span>Suggested quantity</span><strong>{item.recommended_quantity}</strong></div>
                      <div><span>Estimated cost</span><strong>{item.estimated_total_cost == null ? 'Unit cost not set' : item.estimated_total_cost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })}</strong></div>
                    </div>
                    {item.days_until_reorder != null && <p className="stocksense-recommendation-timing">Estimated to reach reorder point in about <strong>{item.days_until_reorder} days</strong>.</p>}
                    <details className="stocksense-recommendation-details">
                      <summary>Why this was suggested and what to verify</summary>
                      <p>{item.reason}</p>
                      {item.validation_notes.length > 0 && <ul>{item.validation_notes.map((note, index) => <li key={`${item.inventory_item_id}-note-${index}`}>{note}</li>)}</ul>}
                    </details>
                    <div className="stocksense-recommendation-action">
                      <span>Review the evidence before creating an order.</span>
                      <Link className="link-button" to={`/purchase-orders?reorderItemId=${encodeURIComponent(item.inventory_item_id)}&branchId=${encodeURIComponent(item.branch_id ?? '')}&quantity=${encodeURIComponent(item.recommended_quantity)}`}>Review order</Link>
                    </div>
                  </article>
                );
              })}
            </div>
          </>}
        </div>
      </section>}
      {planError && <p id="stocksense-analysis-error" className="page-notice" role="alert" style={{ marginTop: 12 }}>{planError}</p>}


      <p className="ai-disclaimer">Coverage and movement insights use the returned inventory snapshot and recent movement sample. Recommendations use explicit outflow history when available; where history is missing, reorder quantities fall back to reorder levels. Review supplier, lead time and budget before ordering.</p>
    </div>
  );
}
