import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';
import { getStoredToken } from '../authToken';
import { scrollToId } from '../../marketing/scroll/useSmoothScroll';
import Modal from '../../../shared/components/Modal';

type BranchOption = { id: string; name: string };

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
type InventoryPlan = { workflow_id: string; status: string; planner_summary: string; data_sources: string[]; recommendations: InventoryRecommendation[]; insights: InventoryInsight[]; warnings: string[]; created_at?: string };

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
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [scopeDialogOpen, setScopeDialogOpen] = useState(false);
  const [analysisScope, setAnalysisScope] = useState<'business' | 'branch'>('business');
  const [selectedBranchId, setSelectedBranchId] = useState('');
  const [reportScope, setReportScope] = useState('Full business');
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
      const response = await fetch('/api/inventory/branches', {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!response.ok) throw new Error(`Branch list request failed (${response.status})`);
      const branchData: unknown = await response.json();
      if (!Array.isArray(branchData) || !branchData.every((entry) =>
        typeof entry?.id === 'string' && typeof entry?.name === 'string',
      )) {
        throw new Error('Branch list response is invalid.');
      }
      setBranches(branchData as BranchOption[]);
      setLastUpdated(new Date());
      setInventoryError('');
      if (showSuccess) notify('Branch list refreshed successfully.', 'success');
    } catch {
      setBranches([]);
      setInventoryError('Branch list could not be synchronized.');
      notify('Unable to load authorized branches from the database.', 'error');
    } finally {
      setLoading(false);
    }
  }, [notify, token]);

  async function analyzeInventory() {
    setPlan(null);
    setPlanning(true);
    setPlanError('');
    try {
      const selectedBranch = branches.find((option) => option.id === selectedBranchId);
      if (analysisScope === 'branch' && !selectedBranch) {
        throw new Error('Choose a branch before starting branch-specific analysis.');
      }
      const scopeLabel = analysisScope === 'business' ? 'Full business' : selectedBranch?.name ?? 'Selected branch';
      setReportScope(scopeLabel);
      setScopeDialogOpen(false);
      const response = await fetch('/api/inventory/agent/plan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({
          objective: 'Review overall inventory health, not only low stock. Identify stock coverage risks from recorded issue/sale/consumption, summarize items without recorded outflow and recent waste movements, and explain uncertainty. Do not infer demand from missing history.',
          branchId: analysisScope === 'business' ? undefined : selectedBranch?.id,
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

  const recommendations = plan?.recommendations ?? [];
  const pricedRecommendations = recommendations.filter((item) => item.estimated_total_cost != null);
  const estimatedReorderCost = pricedRecommendations.reduce((sum, item) => sum + (item.estimated_total_cost ?? 0), 0);
  const usageBackedRecommendations = recommendations.filter((item) => item.avg_daily_outflow != null).length;
  const reportTime = plan?.created_at ? new Date(plan.created_at) : null;
  const formattedReportTime = reportTime && !Number.isNaN(reportTime.getTime())
    ? reportTime.toLocaleString('en-LK', { dateStyle: 'medium', timeStyle: 'short' })
    : null;

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
          <button className="btn btn-primary stocksense-analyze-button" type="button" onClick={() => setScopeDialogOpen(true)} disabled={planning}><span className="stocksense-button-spark" aria-hidden="true">✦</span><span>{planning ? 'Analyzing inventory…' : 'Analyze inventory'}</span><span className="stocksense-button-arrow" aria-hidden="true">→</span></button>
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
          <div className="stocksense-ai-title"><div className="stocksense-ai-orb"><span>✦</span></div><div><p className="eyebrow">STOCKSENSE AI REPORT · {reportScope.toUpperCase()}</p><h2>Inventory health analysis</h2><p className="hint">{plan.planner_summary}</p></div></div>
          <Badge tone={plan.status === 'NeedsReview' ? 'amber' : 'blue'}>{plan.status === 'NeedsReview' ? 'Review recommendations' : plan.insights?.length ? 'Review insights' : 'No action found'}</Badge>
        </div>
        <div className="stocksense-ai-body">
          <section className="stocksense-ai-response" aria-label="StockSense AI response">
            <div className="stocksense-ai-response-copy">
              <span className="stocksense-ai-response-kicker"><Icon name="stocksense" size={15} /> YOUR INVENTORY BRIEF</span>
              <h3>Here’s what stands out</h3>
              <p>{plan.planner_summary}</p>
              <span className="stocksense-ai-response-foot"><i /> Evidence-led · Ready for your review</span>
            </div>
            <div className="stocksense-ai-response-visual" aria-hidden="true">
              <img
                src="https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?auto=format&fit=crop&w=900&q=80"
                alt=""
                loading="lazy"
                referrerPolicy="no-referrer"
                onError={(event) => { event.currentTarget.style.visibility = 'hidden'; }}
              />
              <span className="stocksense-ai-response-orbit" />
              <span className="stocksense-ai-response-spark stocksense-ai-response-spark-one">✦</span>
              <span className="stocksense-ai-response-spark stocksense-ai-response-spark-two">✧</span>
              <span className="stocksense-ai-response-image-label"><Icon name="inventory" size={14} /> INVENTORY IN FOCUS</span>
            </div>
          </section>
          <p className="cell-sub stocksense-ai-evidence-note">Read-only analysis using {plan.data_sources.join(' and ').toLowerCase()}. It has not changed stock or created purchase orders.</p>
          <section className="stocksense-report-snapshot" aria-label="AI report summary">
            <div className="stocksense-report-snapshot-heading">
              <div><p className="eyebrow">THE SIGNAL, AT A GLANCE</p><h3>What StockSense found</h3></div>
              {formattedReportTime && <span>Report started {formattedReportTime}</span>}
            </div>
            <div className="stocksense-report-metrics">
              <article className="stocksense-report-metric" style={{ animationDelay: '40ms' }}>
                <span className="stocksense-report-metric-icon"><Icon name="chart" size={18} /></span>
                <span className="stocksense-report-metric-label">Data signals</span>
                <strong>{plan.insights.length}</strong>
                <small>Insight{plan.insights.length === 1 ? '' : 's'} from available stock and movement data</small>
              </article>
              <article className="stocksense-report-metric" style={{ animationDelay: '110ms' }}>
                <span className="stocksense-report-metric-icon"><Icon name="alert" size={18} /></span>
                <span className="stocksense-report-metric-label">Needs your review</span>
                <strong>{recommendations.length}</strong>
                <small>Replenishment suggestion{recommendations.length === 1 ? '' : 's'}; nothing is ordered automatically</small>
              </article>
              <article className="stocksense-report-metric" style={{ animationDelay: '180ms' }}>
                <span className="stocksense-report-metric-icon"><Icon name="workflow" size={18} /></span>
                <span className="stocksense-report-metric-label">Estimated reorder cost</span>
                <strong className="stocksense-report-cost">{pricedRecommendations.length
                  ? estimatedReorderCost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })
                  : 'Not available'}</strong>
                <small>{pricedRecommendations.length} of {recommendations.length} suggestions have a recorded unit cost</small>
              </article>
              <article className="stocksense-report-metric" style={{ animationDelay: '250ms' }}>
                <span className="stocksense-report-metric-icon"><Icon name="predict" size={18} /></span>
                <span className="stocksense-report-metric-label">Usage-backed suggestions</span>
                <strong>{usageBackedRecommendations} / {recommendations.length}</strong>
                <small>Suggestions with a rate from recorded outflow history</small>
              </article>
            </div>
            <div className="stocksense-report-sources">
              <span>Evidence used</span>
              {plan.data_sources.map((source) => <span className="stocksense-source-chip" key={source}><Icon name="info" size={14} />{source}</span>)}
            </div>
          </section>
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
          {plan.insights?.length > 0 && <><div className="stocksense-section-heading"><div><p className="eyebrow">SIGNALS FROM YOUR DATA</p><h3>Inventory health insights</h3></div><span>{plan.insights.length} insights</span></div><div className="stocksense-insights-grid" aria-label="Inventory health insights">{plan.insights.map((insight, index) => <article className={`stocksense-insight-card stocksense-insight-${insight.category}`} key={`${insight.category}-${index}`} style={{ animationDelay: `${Math.min(index * 90, 540)}ms` }}>
            <div className="stocksense-insight-top"><span className="stocksense-insight-icon"><Icon name={insightIcon(insight.category)} size={19} /></span><p className="stocksense-insight-category">{insight.category.replace('_', ' ')}</p></div><h3>{insight.title}</h3><p className="cell-sub">{insight.detail}</p>
            {insight.affected_items?.length > 0 && <div className="stocksense-item-chips" aria-label="Items referenced by this insight">{insight.affected_items.map((itemName, itemIndex) => <span key={itemName} style={{ animationDelay: `${Math.min(itemIndex * 55, 330)}ms` }}>{itemName}</span>)}</div>}
          </article>)}</div></>}
          {recommendations.length > 0 && <>
            <div className="stocksense-section-heading">
              <div><p className="eyebrow">HUMAN REVIEW REQUIRED</p><h3>Replenishment recommendations</h3><p className="cell-sub">Compare each suggested quantity with the evidence and supplier notes before opening an order.</p></div>
              <span>{recommendations.length} to review</span>
            </div>
            <div className="stocksense-recommendations" aria-label="Replenishment recommendations">
              {recommendations.map((item, index) => {
                const confidence = Math.max(0, Math.min(100, Math.round(item.confidence * 100)));
                const confidenceLabel = confidence >= 70 ? 'Strong movement evidence' : confidence >= 50 ? 'Some movement evidence' : 'Limited movement evidence';
                return (
                  <article className="stocksense-recommendation-card" key={item.inventory_item_id} style={{ animationDelay: `${Math.min(index * 100, 600)}ms` }}>
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
                    {(item.on_hand <= item.reorder_level || item.days_until_reorder != null) && (
                      <p className="stocksense-recommendation-timing">
                        {item.on_hand < item.reorder_level
                          ? <>Already below the reorder point <strong>({item.on_hand} on hand; reorder at {item.reorder_level})</strong>.</>
                          : item.on_hand === item.reorder_level
                            ? <>At the reorder point now <strong>({item.on_hand} on hand)</strong>.</>
                            : item.days_until_reorder === 0
                              ? <>Projected to reach the reorder point in <strong>less than 0.1 days</strong>.</>
                              : <>Projected to reach the reorder point in about <strong>{item.days_until_reorder} days</strong>.</>}
                      </p>
                    )}
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
      {scopeDialogOpen && <Modal
        title="Choose AI analysis scope"
        onClose={() => setScopeDialogOpen(false)}
        className="stocksense-scope-modal"
        footer={<>
          <button className="btn btn-secondary" type="button" onClick={() => setScopeDialogOpen(false)}>Cancel</button>
          <button
            className="btn btn-primary"
            type="button"
            onClick={() => { void analyzeInventory(); }}
            disabled={analysisScope === 'branch' && (!selectedBranchId || branches.length === 0)}
          >
            {analysisScope === 'business' ? 'Analyze full business' : 'Analyze selected branch'}
          </button>
        </>}
      >
        <p>Would you like recommendations for the full business or for one specific branch?</p>
        <fieldset className="stocksense-scope-options">
          <legend>Choose a scope</legend>
          <label>
            <input
              type="radio"
              name="stocksense-analysis-scope"
              value="business"
              checked={analysisScope === 'business'}
              onChange={() => setAnalysisScope('business')}
            />
            <span><strong>Full business</strong><small>Review all authorized branches together.</small></span>
          </label>
          <label>
            <input
              type="radio"
              name="stocksense-analysis-scope"
              value="branch"
              checked={analysisScope === 'branch'}
              onChange={() => setAnalysisScope('branch')}
            />
            <span><strong>Specific branch</strong><small>Focus on one branch's stock and recommendations.</small></span>
          </label>
        </fieldset>
        {analysisScope === 'branch' && <label className="form-field">
          Branch
          <select
            aria-label="Select branch for analysis"
            value={selectedBranchId}
            onChange={(event) => setSelectedBranchId(event.target.value)}
            disabled={loading || branches.length === 0}
          >
            <option value="">Select a branch</option>
            {branches.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
          </select>
          {branches.length === 0 && <small>No authorized branches are available to analyze.</small>}
        </label>}
      </Modal>}
    </div>
  );
}
