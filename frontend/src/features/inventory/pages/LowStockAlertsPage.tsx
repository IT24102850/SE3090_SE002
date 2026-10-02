import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { Badge } from '../ui/Badge';
import { Icon } from '../ui/Icon';
import { useToast } from '../ui/ToastContext';
import { getStoredToken } from '../authToken';
import { scrollToId } from '../../marketing/scroll/useSmoothScroll';
import Modal from '../../../shared/components/Modal';
import type { RootState } from '../../../store/store';

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
  const { user } = useSelector((state: RootState) => state.auth);
  const isStaff = user?.role === 'Staff';
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

  // Interactive controls for report
  const [reorderSearch, setReorderSearch] = useState('');
  const [reorderFilter, setReorderFilter] = useState<'all' | 'critical' | 'high_confidence' | 'priced'>('all');
  const [selectedInsightCategory, setSelectedInsightCategory] = useState<string>('all');
  const [copiedBrief, setCopiedBrief] = useState(false);

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
      if (showSuccess) notify('StockSense workspace refreshed successfully.', 'success');
    } catch {
      setBranches([]);
      setInventoryError('Branch list could not be synchronized.');
      notify('Unable to load authorized branches from the database.', 'error');
    } finally {
      setLoading(false);
    }
  }, [notify, token]);

  async function analyzeInventory(directScope?: 'business' | 'branch', overrideBranchId?: string) {
    setPlan(null);
    setPlanning(true);
    setPlanError('');
    try {
      const activeScope = isStaff ? 'branch' : directScope ?? analysisScope;
      const targetBranchId = isStaff
        ? user?.branchId ?? ''
        : overrideBranchId ?? selectedBranchId;
      const selectedBranch = branches.find((option) => option.id === targetBranchId);
      if (activeScope === 'branch' && !selectedBranch) {
        throw new Error(isStaff
          ? 'Your account needs an assigned branch before StockSense can review its stock. Ask your manager for help.'
          : 'Choose a branch before starting branch-specific analysis.');
      }
      const scopeLabel = activeScope === 'business' ? 'Full business' : selectedBranch?.name ?? 'Selected branch';
      setReportScope(scopeLabel);
      setScopeDialogOpen(false);
      const response = await fetch('/api/inventory/agent/plan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({
          objective: isStaff
            ? 'Help the branch staff prioritize today’s stock work. Clearly list out-of-stock and below-reorder items first, explain the reason for each recommendation in plain language, highlight missing usage or price information that should be checked with a manager, and suggest practical next steps. Do not make changes or place orders.'
            : 'Review overall inventory health, not only low stock. Identify stock coverage risks from recorded issue/sale/consumption, summarize items without recorded outflow and recent waste movements, and explain uncertainty. Do not infer demand from missing history.',
          branchId: activeScope === 'business' ? undefined : selectedBranch?.id,
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

  // Filtered recommendations
  const filteredRecommendations = useMemo(() => {
    return recommendations.filter((item) => {
      if (reorderSearch.trim()) {
        const query = reorderSearch.toLowerCase();
        const matchName = item.item_name.toLowerCase().includes(query);
        const matchSku = item.sku.toLowerCase().includes(query);
        const matchBranch = (item.branch_name ?? '').toLowerCase().includes(query);
        if (!matchName && !matchSku && !matchBranch) return false;
      }
      if (reorderFilter === 'critical') {
        return item.on_hand <= item.reorder_level;
      }
      if (reorderFilter === 'high_confidence') {
        return item.confidence >= 0.7;
      }
      if (reorderFilter === 'priced') {
        return item.estimated_total_cost != null;
      }
      return true;
    });
  }, [recommendations, reorderSearch, reorderFilter]);

  // Filtered insights
  const filteredInsights = useMemo(() => {
    if (!plan?.insights) return [];
    if (selectedInsightCategory === 'all') return plan.insights;
    return plan.insights.filter((insight) => insight.category === selectedInsightCategory);
  }, [plan?.insights, selectedInsightCategory]);

  const insightCategories = useMemo(() => {
    if (!plan?.insights) return [];
    return Array.from(new Set(plan.insights.map((i) => i.category)));
  }, [plan?.insights]);

  const handleCopySummary = () => {
    if (!plan) return;
    const summaryText = `[StockSense AI Report - ${reportScope}]\n\nSummary:\n${plan.planner_summary}\n\nKey Metrics:\n- Insights Found: ${plan.insights.length}\n- Replenishment Suggestions: ${recommendations.length}\n- Estimated Reorder Cost: LKR ${estimatedReorderCost.toLocaleString('en-LK')}\n- Usage-Backed Suggestions: ${usageBackedRecommendations}/${recommendations.length}\n\nEvidence Sources:\n${plan.data_sources.join(', ')}`;
    void navigator.clipboard.writeText(summaryText);
    setCopiedBrief(true);
    notify('Executive brief copied to clipboard!', 'success');
    window.setTimeout(() => setCopiedBrief(false), 2500);
  };

  return (
    <div className={`page stocksense-page${isStaff ? ' is-staff' : ''}`}>
      <header className={`page-head stocksense-hero${isStaff ? ' is-staff' : ''}`}>
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="stocksense-hero-copy">
          <div className="stocksense-brandmark">
            <Icon name="stocksense" size={38} />
          </div>
          <div>
            <div className="stocksense-hero-eyebrow-row">
              <p className="eyebrow">{isStaff ? 'YOUR BRANCH STOCK ASSISTANT' : 'INTELLIGENT INVENTORY OPERATIONS'}</p>
              <span className="stocksense-model-pill">
                <span className="stocksense-status-pulse" aria-hidden="true" />
                {isStaff ? 'Ready to help' : 'Gemini Agent Online'}
              </span>
            </div>
            <h1>StockSense AI</h1>
            <p className="page-sub">{isStaff
              ? 'Get a clear picture of what needs attention at your branch and what to check next.'
              : 'AI-powered insights into stock movement, coverage risks, and replenishment decisions.'}</p>
            <div className="stocksense-capabilities">
              {isStaff ? (
                <>
                  <span>What needs attention</span>
                  <span>Why it matters</span>
                  <span>What to do next</span>
                </>
              ) : (
                <>
                  <span>Stock coverage</span>
                  <span>Movement insights</span>
                  <span>Reorder guidance</span>
                  <span>Safety buffer check</span>
                </>
              )}
            </div>
          </div>
        </div>
        <div className="page-actions stocksense-hero-actions">
          <div className="stocksense-hero-status-row">
            <span className={`live-indicator stocksense-updated${inventoryError ? ' is-stale' : ''}`}>
              <span aria-hidden="true" />
              {inventoryError ? 'Inventory sync needs attention' : 'Inventory data current'} · Updated {lastUpdated.toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}
            </span>
          </div>
          <div className="stocksense-hero-btn-row">
            <button
              className="btn btn-primary stocksense-analyze-button"
              type="button"
              onClick={() => {
                if (isStaff) {
                  void analyzeInventory('branch', user?.branchId);
                } else {
                  setScopeDialogOpen(true);
                }
              }}
              disabled={planning || (isStaff && (loading || !user?.branchId))}
            >
              <span className="stocksense-button-spark" aria-hidden="true">✦</span>
              <span>{planning ? (isStaff ? 'Checking your branch…' : 'Analyzing inventory…') : isStaff ? 'Check my branch stock' : 'Analyze inventory'}</span>
              <span className="stocksense-button-arrow" aria-hidden="true">→</span>
            </button>
            <button
              className="btn btn-secondary stocksense-hero-refresh-btn"
              type="button"
              onClick={() => { void loadInventory(true); }}
              disabled={loading}
              title="Refresh inventory sync now"
            >
              <span className="stocksense-refresh-icon" aria-hidden="true">🔄</span>
              <span>{loading ? 'Refreshing…' : 'Refresh now'}</span>
            </button>
          </div>
          <span className="stocksense-cta-hint">
            <span className="hint-bullet" aria-hidden="true">✦</span>
            {isStaff ? 'Your branch only · No changes are made' : 'Get a clear stock health report'}
          </span>
        </div>
        <div className="stocksense-hero-modes" aria-label="Inventory analysis options">
          {!isStaff && <button
            type="button"
            className="stocksense-hero-mode stocksense-hero-mode-clickable"
            onClick={() => {
              setAnalysisScope('business');
              setScopeDialogOpen(true);
            }}
          >
            <span className="stocksense-hero-mode-icon" aria-hidden="true"><Icon name="inventory" size={20} /></span>
            <div className="stocksense-mode-body">
              <div className="stocksense-mode-headline">
                <strong>Business-wide analysis</strong>
                <span className="stocksense-mode-badge">All branches</span>
              </div>
              <span>Review stock health across all branches together.</span>
            </div>
            <span className="stocksense-mode-arrow-icon" aria-hidden="true">→</span>
          </button>}
          <button
            type="button"
            className="stocksense-hero-mode stocksense-hero-mode-clickable"
            onClick={() => {
              if (isStaff) {
                void analyzeInventory('branch', user?.branchId);
              } else {
                setAnalysisScope('branch');
                setScopeDialogOpen(true);
              }
            }}
            disabled={isStaff && (loading || !user?.branchId || planning)}
          >
            <span className="stocksense-hero-mode-icon" aria-hidden="true"><Icon name="branches" size={20} /></span>
            <div className="stocksense-mode-body">
              <div className="stocksense-mode-headline">
                <strong>{isStaff ? 'Your branch' : 'Branch-specific analysis'}</strong>
                <span className="stocksense-mode-badge">{isStaff ? branches.find((branch) => branch.id === user?.branchId)?.name ?? (loading ? 'Loading…' : 'Branch needed') : `${branches.length} available`}</span>
              </div>
              <span>{isStaff
                ? 'Review stock levels and next steps for the branch you work at.'
                : loading ? 'Loading available branches…' : branches.length > 0 ? `Focus on any of your ${branches.length} available ${branches.length === 1 ? 'branch' : 'branches'}.` : 'Analyze stock health for an individual branch.'}</span>
            </div>
            <span className="stocksense-mode-arrow-icon" aria-hidden="true">→</span>
          </button>
        </div>
        {isStaff && !user?.branchId && (
          <p className="stocksense-staff-branch-help" role="status">
            Your account doesn’t have a branch assigned yet. Ask your manager to update your access.
          </p>
        )}
        <div className="stocksense-hero-orbit" aria-hidden="true"><span /><i /></div>
      </header>

      {/* High-tech AI Intelligence Telemetry Bar when idle */}
      {!plan && !planning && (
        <section className="stocksense-ready-hud" aria-label={isStaff ? 'Your branch stock check' : 'AI Launch Pad'}>
          <div className="stocksense-hud-glow" aria-hidden="true" />
          <div className="stocksense-hud-content">
            <div className="stocksense-hud-left">
              <div className="stocksense-hud-badge">
                <span className="stocksense-hud-dot" />
                <span>{isStaff ? 'READY FOR YOUR BRANCH' : 'INTELLIGENCE ENGINE READY'}</span>
              </div>
              <h3>{isStaff ? 'A helpful heads-up for your shift' : 'Autonomous Depletion & Coverage Guard'}</h3>
              <p>
                {isStaff
                  ? 'See which items may need attention, understand why they were flagged, and share anything unusual with your manager. StockSense only gives guidance—it never changes stock or places an order.'
                  : <>
                    StockSense audits your stock on-hand, recent retail sales velocity, kitchen/clinic consumption, and waste logs.
                    It produces human-in-the-loop purchase orders with deterministic safety buffers — avoiding stockouts before they hit your business.
                  </>}
              </p>
              <div className="stocksense-hud-telemetry">
                <div className="stocksense-hud-item">
                  <span className="hud-metric-label">{isStaff ? 'YOUR BRANCH' : 'CONNECTED SCOPE'}</span>
                  <strong>{isStaff
                    ? branches.find((branch) => branch.id === user?.branchId)?.name ?? (loading ? 'Loading branch…' : 'Not assigned')
                    : branches.length > 0 ? `${branches.length} Authorized Locations` : 'Synchronizing…'}</strong>
                </div>
                <div className="stocksense-hud-divider" />
                <div className="stocksense-hud-item">
                  <span className="hud-metric-label">AI MODEL</span>
                  <strong>{isStaff ? 'Plain-language guidance' : 'StockSense AI Agent'}</strong>
                </div>
                <div className="stocksense-hud-divider" />
                <div className="stocksense-hud-item">
                  <span className="hud-metric-label">{isStaff ? 'YOUR CONTROL' : 'GUARDRAIL'}</span>
                  <strong>{isStaff ? 'You decide what to do' : 'Deterministic Safety Check'}</strong>
                </div>
              </div>
            </div>
            <div className="stocksense-hud-right">
              <div className="stocksense-hud-card">
                <span className="hud-card-kicker">{isStaff ? 'HELPFUL TO KNOW' : 'ENGINE VERIFICATION'}</span>
                <h4>{isStaff ? 'A few things to keep in mind' : 'Continuous Safety Parameters'}</h4>
                <div className="stocksense-hud-safety-list">
                  {isStaff ? (
                    <>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Each suggestion includes a reason to help you review it.</span>
                      </div>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Check unclear stock or pricing details with your manager.</span>
                      </div>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Suggestions never change stock or place an order.</span>
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Zero blind inferences — strictly evidence-led</span>
                      </div>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Safety bounds check prevents over-ordering</span>
                      </div>
                      <div className="hud-safety-item">
                        <span className="hud-check">✓</span>
                        <span>Read-only: never modifies database or places orders</span>
                      </div>
                    </>
                  )}
                </div>
              </div>
            </div>
          </div>
        </section>
      )}

      {!isStaff && <section className="stocksense-guide" aria-labelledby="stocksense-guide-title">
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
      </section>}

      {inventoryError && <p className="page-notice stocksense-sync-notice" role="alert">{inventoryError} The timestamp above shows the last successful snapshot.</p>}

      {planning && (
        <section id="stocksense-analysis-progress" className="stocksense-progress-panel" role="status" aria-live="polite">
          <div className="stocksense-progress-orbit">
            <div className="stocksense-progress-ring" />
            <Icon name="stocksense" size={50} />
            <span className="stocksense-orbit-dot" />
          </div>
          <div className="stocksense-progress-copy">
            <div className="stocksense-progress-heading">
              <p className="eyebrow">LIVE INVENTORY ANALYSIS</p>
              <span>STEP {analysisStep + 1} / {analysisStages.length}</span>
            </div>
            <h2>Building your stock health report</h2>
            <p key={analysisStep} className="stocksense-progress-stage">{analysisStages[analysisStep]}</p>
            <div className="stocksense-stage-pips" aria-hidden="true">
              {analysisStages.map((stage, index) => (
                <span key={stage} className={index === analysisStep ? 'active' : index < analysisStep ? 'done' : ''} />
              ))}
            </div>
            <p className="stocksense-progress-note">Checking stock levels and available movement history. Your inventory is not changed.</p>
          </div>
          <div className="stocksense-progress-meter" aria-label="Analysis in progress"><span /></div>
        </section>
      )}

      {plan && (
        <section id="stocksense-analysis-report" className="panel stocksense-ai-panel">
          <div className="panel-head stocksense-ai-head">
            <div className="stocksense-ai-title">
              <div className="stocksense-ai-orb"><span>✦</span></div>
              <div>
                <p className="eyebrow">STOCKSENSE AI REPORT · {reportScope.toUpperCase()}</p>
                <h2>Inventory health analysis</h2>
                <p className="hint">{plan.planner_summary}</p>
              </div>
            </div>
            <div className="stocksense-ai-head-actions">
              <Badge tone={plan.status === 'NeedsReview' ? 'amber' : 'blue'}>
                {plan.status === 'NeedsReview' ? 'Review recommendations' : plan.insights?.length ? 'Review insights' : 'No action found'}
              </Badge>
              <button
                type="button"
                className="btn btn-secondary btn-sm stocksense-copy-btn"
                onClick={handleCopySummary}
                title="Copy Executive Summary"
              >
                {copiedBrief ? '✓ Copied' : '📋 Copy Brief'}
              </button>
            </div>
          </div>
          <div className="stocksense-ai-body">
            <section className="stocksense-ai-response" aria-label="StockSense AI response">
              <div className="stocksense-ai-response-copy">
                <span className="stocksense-ai-response-kicker"><Icon name="stocksense" size={15} /> YOUR INVENTORY BRIEF</span>
                <h3>Here’s what stands out</h3>
                <p>{plan.planner_summary}</p>
                <div className="stocksense-brief-pills">
                  <span className="brief-pill"><strong>{recommendations.length}</strong> items flag review</span>
                  <span className="brief-pill"><strong>{plan.insights.length}</strong> data signals</span>
                  {pricedRecommendations.length > 0 && (
                    <span className="brief-pill"><strong>{estimatedReorderCost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR', maximumFractionDigits: 0 })}</strong> restock need</span>
                  )}
                </div>
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
                <div className="stocksense-visual-overlay-telemetry">
                  <span>NEURAL SCAN: COMPLETE</span>
                  <span>SAFETY LEVEL: DETERMINISTIC</span>
                </div>
              </div>
            </section>

            <p className="cell-sub stocksense-ai-evidence-note">Read-only analysis using {plan.data_sources.join(' and ').toLowerCase()}. It has not changed stock or created purchase orders.</p>

            <section className="stocksense-report-snapshot" aria-label="AI report summary">
              <div className="stocksense-report-snapshot-heading">
                <div>
                  <p className="eyebrow">THE SIGNAL, AT A GLANCE</p>
                  <h3>What StockSense found</h3>
                </div>
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
                  <strong className="stocksense-report-cost">
                    {pricedRecommendations.length
                      ? estimatedReorderCost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })
                      : 'Not available'}
                  </strong>
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
                {plan.data_sources.map((source) => (
                  <span className="stocksense-source-chip" key={source}>
                    <Icon name="info" size={14} />{source}
                  </span>
                ))}
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

            {plan.insights?.length > 0 && (
              <>
                <div className="stocksense-section-heading">
                  <div>
                    <p className="eyebrow">SIGNALS FROM YOUR DATA</p>
                    <h3>Inventory health insights</h3>
                  </div>
                  <div className="stocksense-category-filters" role="tablist" aria-label="Insight category filter">
                    <button
                      type="button"
                      className={`stocksense-filter-tab ${selectedInsightCategory === 'all' ? 'is-active' : ''}`}
                      onClick={() => setSelectedInsightCategory('all')}
                    >
                      All ({plan.insights.length})
                    </button>
                    {insightCategories.map((cat) => (
                      <button
                        key={cat}
                        type="button"
                        className={`stocksense-filter-tab ${selectedInsightCategory === cat ? 'is-active' : ''}`}
                        onClick={() => setSelectedInsightCategory(cat)}
                      >
                        {cat.replace('_', ' ')}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="stocksense-insights-grid" aria-label="Inventory health insights">
                  {filteredInsights.map((insight, index) => (
                    <article
                      className={`stocksense-insight-card stocksense-insight-${insight.category}`}
                      key={`${insight.category}-${index}`}
                      style={{ animationDelay: `${Math.min(index * 90, 540)}ms` }}
                    >
                      <div className="stocksense-insight-top">
                        <span className="stocksense-insight-icon">
                          <Icon name={insightIcon(insight.category)} size={19} />
                        </span>
                        <p className="stocksense-insight-category">{insight.category.replace('_', ' ')}</p>
                      </div>
                      <h3>{insight.title}</h3>
                      <p className="cell-sub">{insight.detail}</p>
                      {insight.affected_items?.length > 0 && (
                        <div className="stocksense-item-chips" aria-label="Items referenced by this insight">
                          {insight.affected_items.map((itemName, itemIndex) => (
                            <span key={itemName} style={{ animationDelay: `${Math.min(itemIndex * 55, 330)}ms` }}>
                              {itemName}
                            </span>
                          ))}
                        </div>
                      )}
                    </article>
                  ))}
                </div>
              </>
            )}

            {recommendations.length > 0 && (
              <>
                <div className="stocksense-section-heading">
                  <div>
                    <p className="eyebrow">HUMAN REVIEW REQUIRED</p>
                    <h3>Replenishment recommendations</h3>
                    <p className="cell-sub">Compare each suggested quantity with the evidence and supplier notes before opening an order.</p>
                  </div>
                  <span>{recommendations.length} to review</span>
                </div>

                {/* Search & Filter Toolbar */}
                <div className="stocksense-reorder-toolbar">
                  <div className="stocksense-search-wrap">
                    <span className="search-icon" aria-hidden="true">🔍</span>
                    <input
                      type="text"
                      className="stocksense-search-input"
                      placeholder="Search items, SKU or branch…"
                      value={reorderSearch}
                      onChange={(e) => setReorderSearch(e.target.value)}
                      aria-label="Filter recommendations"
                    />
                    {reorderSearch && (
                      <button
                        type="button"
                        className="stocksense-clear-btn"
                        onClick={() => setReorderSearch('')}
                        aria-label="Clear search"
                      >
                        ✕
                      </button>
                    )}
                  </div>
                  <div className="stocksense-filter-chips">
                    <button
                      type="button"
                      className={`stocksense-chip ${reorderFilter === 'all' ? 'is-active' : ''}`}
                      onClick={() => setReorderFilter('all')}
                    >
                      All ({recommendations.length})
                    </button>
                    <button
                      type="button"
                      className={`stocksense-chip chip-critical ${reorderFilter === 'critical' ? 'is-active' : ''}`}
                      onClick={() => setReorderFilter('critical')}
                    >
                      Below Reorder ({recommendations.filter((i) => i.on_hand <= i.reorder_level).length})
                    </button>
                    <button
                      type="button"
                      className={`stocksense-chip ${reorderFilter === 'high_confidence' ? 'is-active' : ''}`}
                      onClick={() => setReorderFilter('high_confidence')}
                    >
                      High Confidence ({recommendations.filter((i) => i.confidence >= 0.7).length})
                    </button>
                    <button
                      type="button"
                      className={`stocksense-chip ${reorderFilter === 'priced' ? 'is-active' : ''}`}
                      onClick={() => setReorderFilter('priced')}
                    >
                      Priced ({pricedRecommendations.length})
                    </button>
                  </div>
                </div>

                <div className="stocksense-recommendations" aria-label="Replenishment recommendations">
                  {filteredRecommendations.length === 0 ? (
                    <div className="stocksense-empty-filter">
                      <p>No recommendations match your search criteria.</p>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        onClick={() => { setReorderSearch(''); setReorderFilter('all'); }}
                      >
                        Reset filters
                      </button>
                    </div>
                  ) : (
                    filteredRecommendations.map((item, index) => {
                      const confidence = Math.max(0, Math.min(100, Math.round(item.confidence * 100)));
                      const confidenceLabel = confidence >= 70 ? 'Strong movement evidence' : confidence >= 50 ? 'Some movement evidence' : 'Limited movement evidence';
                      const isOutOfStock = item.on_hand <= 0;
                      const isBelowReorder = item.on_hand <= item.reorder_level;

                      // Stock gauge calculation
                      const maxCapacity = Math.max(item.reorder_level * 2, item.on_hand + item.recommended_quantity, 10);
                      const currentPct = Math.min(100, Math.round((item.on_hand / maxCapacity) * 100));
                      const reorderPct = Math.min(100, Math.round((item.reorder_level / maxCapacity) * 100));
                      const suggestedPct = Math.min(100 - currentPct, Math.round((item.recommended_quantity / maxCapacity) * 100));

                      return (
                        <article
                          className={`stocksense-recommendation-card ${isOutOfStock ? 'is-out-of-stock' : isBelowReorder ? 'is-below-reorder' : ''}`}
                          key={item.inventory_item_id}
                          style={{ animationDelay: `${Math.min(index * 100, 600)}ms` }}
                        >
                          <div className="stocksense-card-status-strip" aria-hidden="true" />
                          <div className="stocksense-recommendation-head">
                            <div>
                              <div className="stocksense-item-badge-row">
                                <p className="eyebrow">REPLENISHMENT REVIEW</p>
                                {isOutOfStock ? (
                                  <span className="stocksense-urgency-badge urgency-danger">OUT OF STOCK</span>
                                ) : isBelowReorder ? (
                                  <span className="stocksense-urgency-badge urgency-warning">BELOW SAFETY LEVEL</span>
                                ) : (
                                  <span className="stocksense-urgency-badge urgency-info">MONITOR COVERAGE</span>
                                )}
                              </div>
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

                          {/* Visual Stock Level Gauge */}
                          <div className="stocksense-stock-gauge-wrap" aria-label="Stock level visualization">
                            <div className="stocksense-gauge-labels">
                              <span className="gauge-label-current">Current: <strong>{item.on_hand}</strong></span>
                              <span className="gauge-label-reorder">Safety Point: <strong>{item.reorder_level}</strong></span>
                              <span className="gauge-label-suggested">+ Suggested: <strong>{item.recommended_quantity}</strong></span>
                            </div>
                            <div className="stocksense-gauge-bar">
                              <div
                                className={`gauge-fill-current ${isOutOfStock ? 'is-zero' : isBelowReorder ? 'is-low' : 'is-good'}`}
                                style={{ width: `${currentPct}%` }}
                                title={`On hand: ${item.on_hand}`}
                              />
                              <div
                                className="gauge-fill-suggested"
                                style={{ width: `${suggestedPct}%` }}
                                title={`Recommended addition: ${item.recommended_quantity}`}
                              />
                              <div
                                className="gauge-marker-reorder"
                                style={{ left: `${reorderPct}%` }}
                                title={`Reorder point: ${item.reorder_level}`}
                              />
                            </div>
                          </div>

                          <div className="stocksense-recommendation-metrics">
                            <div>
                              <span>On hand / reorder point</span>
                              <strong>{item.on_hand} / {item.reorder_level}</strong>
                            </div>
                            <div>
                              <span>Recorded outflow</span>
                              <strong>{item.avg_daily_outflow == null ? 'No usage history' : `${item.avg_daily_outflow} / day`}</strong>
                            </div>
                            <div>
                              <span>Suggested quantity</span>
                              <strong className="stocksense-suggested-highlight">{item.recommended_quantity}</strong>
                            </div>
                            <div>
                              <span>Estimated cost</span>
                              <strong>{item.estimated_total_cost == null ? 'Unit cost not set' : item.estimated_total_cost.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' })}</strong>
                            </div>
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
                            {item.validation_notes.length > 0 && (
                              <ul>
                                {item.validation_notes.map((note, noteIdx) => (
                                  <li key={`${item.inventory_item_id}-note-${noteIdx}`}>{note}</li>
                                ))}
                              </ul>
                            )}
                          </details>

                          <div className="stocksense-recommendation-action">
                            <span>Review the evidence before creating an order.</span>
                            <Link
                              className="link-button stocksense-po-link"
                              to={`/purchase-orders?reorderItemId=${encodeURIComponent(item.inventory_item_id)}&branchId=${encodeURIComponent(item.branch_id ?? '')}&quantity=${encodeURIComponent(item.recommended_quantity)}`}
                            >
                              <span>Review order</span>
                              <span aria-hidden="true">→</span>
                            </Link>
                          </div>
                        </article>
                      );
                    })
                  )}
                </div>
              </>
            )}
          </div>
        </section>
      )}

      {planError && <p id="stocksense-analysis-error" className="page-notice" role="alert" style={{ marginTop: 12 }}>{planError}</p>}

      <p className="ai-disclaimer">Coverage and movement insights use the returned inventory snapshot and recent movement sample. Recommendations use explicit outflow history when available; where history is missing, reorder quantities fall back to reorder levels. Review supplier, lead time and budget before ordering.</p>

      {scopeDialogOpen && !isStaff && (
        <Modal
          title="Choose AI analysis scope"
          onClose={() => setScopeDialogOpen(false)}
          className="stocksense-scope-modal"
          footer={
            <>
              <button className="btn btn-secondary" type="button" onClick={() => setScopeDialogOpen(false)}>Cancel</button>
              <button
                className="btn btn-primary"
                type="button"
                onClick={() => { void analyzeInventory(); }}
                disabled={analysisScope === 'branch' && (!selectedBranchId || branches.length === 0)}
              >
                {analysisScope === 'business' ? 'Analyze full business' : 'Analyze selected branch'}
              </button>
            </>
          }
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
          {analysisScope === 'branch' && (
            <label className="form-field">
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
            </label>
          )}
        </Modal>
      )}
    </div>
  );
}
