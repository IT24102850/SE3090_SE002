import { Fragment, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import { useToast } from '../../../shared/components/Toast';
import {
  billingApi, errorMessage,
  type BillingAnalysis, type BillingPlannedAnalysis, type BillingWorkflow, type ThresholdConfig,
} from '../billingApi';
import { addDays, dateTime, humanize, isoDay, money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

type Tab = 'queue' | 'copilot' | 'run' | 'history';

/** Starting points, so the objective box is not a blank stare. */
const EXAMPLE_OBJECTIVES = [
  'Check last quarter for discount abuse',
  'Why is revenue down this month?',
  'Review the open insurance claims',
  'Are we overcharging for anything?',
];

const ANALYSIS_TYPES: { id: string; label: string }[] = [
  { id: 'full', label: 'Full review' },
  { id: 'anomalies', label: 'Billing anomalies' },
  { id: 'revenue', label: 'Revenue trends' },
  { id: 'insurance', label: 'Insurance claims' },
  { id: 'pricing', label: 'Pricing benchmarks' },
  { id: 'commission', label: 'Commission split' },
];

const THRESHOLD_LABELS: Partial<Record<keyof ThresholdConfig, string>> = {
  maxDiscountPercent: 'Max discount %',
  adjustmentApprovalAmount: 'Adjustment approval above',
  claimApprovalAmount: 'Claim approval above',
  maxTaxPercent: 'Max tax %',
  revenueDropPercent: 'Revenue drop alert %',
  priceDeviationPercent: 'Price deviation alert %',
  duplicateWindowMinutes: 'Duplicate window (min)',
};

export default function BillingAgentMonitorPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const isAdmin = user?.role === 'Admin';
  const toast = useToast();
  const [tab, setTab] = useState<Tab>('queue');

  const queue = useAsync(() => billingApi.workflows({ kind: 'approval', status: 'Pending' }), []);
  const history = useAsync(() => billingApi.workflows({ take: 100 }), []);
  const tools = useAsync(() => billingApi.agentTools(), []);

  const [type, setType] = useState('full');
  const [from, setFrom] = useState(isoDay(addDays(new Date(), -30)));
  const [to, setTo] = useState(isoDay());
  const [dealAmount, setDealAmount] = useState('');
  const [thresholds, setThresholds] = useState<Partial<ThresholdConfig>>({});
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<BillingAnalysis | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  const [objective, setObjective] = useState('');
  const [planning, setPlanning] = useState(false);
  const [planned, setPlanned] = useState<BillingPlannedAnalysis | null>(null);
  const [planError, setPlanError] = useState<string | null>(null);

  const refresh = () => { queue.reload(); history.reload(); };

  const thresholdOverrides = () =>
    (Object.keys(thresholds).length ? { ...tools.data?.defaultThresholds, ...thresholds } : undefined);

  const askCopilot = async () => {
    setPlanning(true);
    setPlanError(null);
    try {
      const r = await billingApi.planAnalysis({ objective: objective.trim(), thresholds: thresholdOverrides() });
      setPlanned(r);
      refresh();
      toast.show(
        `${r.analysis.anomalies.length} anomalies · ${r.analysis.approvalWorkflowIds.length} items in the approval queue.`,
        r.analysis.anomalies.length ? 'warning' : 'success',
      );
    } catch (err) {
      // The copilot needs the agent service; the form below never does, which
      // is worth saying rather than leaving the manager stuck.
      setPlanError(errorMessage(err, 'The copilot could not plan this analysis.'));
    } finally {
      setPlanning(false);
    }
  };

  const run = async () => {
    setRunning(true);
    try {
      const r = await billingApi.analyze({
        analysisType: type,
        dataRange: { from: new Date(`${from}T00:00:00`).toISOString(), to: new Date(`${to}T23:59:59`).toISOString() },
        thresholds: thresholdOverrides(),
        dealAmount: type === 'commission' ? Number(dealAmount) : undefined,
      });
      setResult(r);
      refresh();
      toast.show(`${r.anomalies.length} anomalies · ${r.approvalWorkflowIds.length} items in the approval queue.`, r.anomalies.length ? 'warning' : 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'The analysis failed.'), 'error');
    } finally {
      setRunning(false);
    }
  };

  const decide = async (wf: BillingWorkflow, approve: boolean) => {
    try {
      const reason = approve ? undefined : window.prompt('Reason for rejecting?') ?? undefined;
      if (!approve && reason === undefined) return;
      const r = approve ? await billingApi.approveWorkflow(wf.id) : await billingApi.rejectWorkflow(wf.id, reason);
      toast.show(r.message, 'success');
      refresh();
    } catch (err) {
      toast.show(errorMessage(err, 'That did not work.'), 'error');
    }
  };

  const pending = queue.data ?? [];

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Billing agent</h1>
          <p className="page-subtitle">
            The domain analysis agent watches invoices, payments and claims, flags anomalies and proposes fixes. Anything above the thresholds waits for a human.
          </p>
        </div>
      </div>

      <div className="bl-tabs" role="tablist">
        <button role="tab" className="bl-tab" aria-selected={tab === 'queue'} onClick={() => setTab('queue')}>
          Approval queue<span className="bl-tab-count">{pending.length}</span>
        </button>
        <button role="tab" className="bl-tab" aria-selected={tab === 'copilot'} onClick={() => setTab('copilot')}>Ask the copilot</button>
        <button role="tab" className="bl-tab" aria-selected={tab === 'run'} onClick={() => setTab('run')}>Run analysis</button>
        <button role="tab" className="bl-tab" aria-selected={tab === 'history'} onClick={() => setTab('history')}>Audit trail</button>
      </div>

      {tab === 'queue' && (
        <div className="bl-stack">
          <div className="bl-notice bl-small">
            Needs an Admin: invoice adjustments over 100, insurance claims over 500, and cancellations with a refund.
            {!isAdmin && ' You can approve the rest.'}
          </div>
          {queue.loading && !queue.data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}
          {pending.length === 0 && queue.data && <div className="bl-empty">Nothing is waiting for approval.</div>}
          <ul className="bl-list">
            {pending.map((wf) => {
              const adminOnly = planRequiresAdmin(wf);
              return (
                <li key={wf.id} className="bl-list-item">
                  <div className="bl-spread">
                    <strong>{wf.objective}</strong>
                    <div className="bl-row">
                      {wf.amount != null && <span className="bl-num">{money(wf.amount)}</span>}
                      {adminOnly && <span className="bl-badge bl-badge-warning">Admin</span>}
                      <span className="bl-badge bl-badge-primary">{humanize(wf.actionType ?? 'action')}</span>
                    </div>
                  </div>
                  {wf.reason && <span className="bl-small bl-muted">{wf.reason}</span>}
                  <span className="bl-small bl-muted">Raised {dateTime(wf.createdAt)} · {sourceOf(wf)}</span>
                  {wf.errorLog && <span className="bl-field-error">{wf.errorLog}</span>}
                  <div className="bl-row">
                    <button className="btn btn-primary btn-sm" disabled={adminOnly && !isAdmin} title={adminOnly && !isAdmin ? 'Only an Admin can approve this' : undefined}
                      onClick={() => decide(wf, true)}>Approve</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => decide(wf, false)}>Reject</button>
                  </div>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      {tab === 'copilot' && (
        <div className="bl-stack">
          <div className="card bl-stack" style={{ padding: 16 }}>
            <label className="bl-field">
              <span>What should the agent look at?</span>
              <textarea
                className="input"
                rows={3}
                maxLength={500}
                placeholder="Check last quarter for discount abuse"
                value={objective}
                onChange={(e) => setObjective(e.target.value)}
              />
              <span className="bl-field-hint">
                A planner turns this into the same analysis the form below runs. It can narrow the request - a shorter
                period, a stricter discount cap - and it cannot loosen a threshold, approve anything, or reach a tool
                outside the five on the allow-list.
              </span>
            </label>
            <div className="bl-row">
              {EXAMPLE_OBJECTIVES.map((example) => (
                <button key={example} type="button" className="btn btn-ghost btn-sm" onClick={() => setObjective(example)}>
                  {example}
                </button>
              ))}
            </div>
            <div>
              <button className="btn btn-primary" disabled={planning || objective.trim().length < 3} onClick={askCopilot}>
                {planning ? 'Planning…' : 'Plan and run'}
              </button>
            </div>
          </div>

          {planError && (
            <div className="bl-notice bl-notice-critical">
              {planError}
              <div className="bl-small bl-muted" style={{ marginTop: 6 }}>
                The analysis itself does not need the copilot - use <strong>Run analysis</strong> to pick the type and
                period yourself.
              </div>
            </div>
          )}

          {planned && <PlanPanel planned={planned} />}
          {planned && <AnalysisResult result={planned.analysis} />}
        </div>
      )}

      {tab === 'run' && (
        <div className="bl-stack">
          <div className="card bl-stack" style={{ padding: 16 }}>
            <div className="bl-grid-3">
              <label className="bl-field"><span>Analysis</span>
                <select className="input" value={type} onChange={(e) => setType(e.target.value)}>
                  {ANALYSIS_TYPES.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
                </select>
              </label>
              <label className="bl-field"><span>From</span><input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
              <label className="bl-field"><span>To</span><input className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
            </div>
            {type === 'commission' && (
              <label className="bl-field"><span>Deal amount</span><input className="input" type="number" min={0} value={dealAmount} onChange={(e) => setDealAmount(e.target.value)} /></label>
            )}
            {tools.data && (
              <details>
                <summary className="bl-label" style={{ cursor: 'pointer' }}>Thresholds</summary>
                <div className="bl-grid-3" style={{ marginTop: 10 }}>
                  {(Object.keys(THRESHOLD_LABELS) as (keyof ThresholdConfig)[]).map((k) => (
                    <label key={k} className="bl-field"><span>{THRESHOLD_LABELS[k]}</span>
                      <input className="input" type="number" min={0} value={thresholds[k] ?? tools.data!.defaultThresholds[k]}
                        onChange={(e) => setThresholds({ ...thresholds, [k]: Number(e.target.value) })} />
                    </label>
                  ))}
                </div>
                <p className="bl-small bl-muted">Tools: {tools.data.tools.join(', ')} - the agent can call nothing else.</p>
              </details>
            )}
            <div><button className="btn btn-primary" disabled={running || (type === 'commission' && !(Number(dealAmount) > 0))} onClick={run}>{running ? 'Analysing…' : 'Run analysis'}</button></div>
          </div>

          {result && <AnalysisResult result={result} />}
        </div>
      )}

      {tab === 'history' && (
        <div className="bl-table-wrap">
          <table className="bl-table">
            <thead><tr><th>When</th><th>What</th><th>Kind</th><th>Status</th><th>Outcome</th></tr></thead>
            <tbody>
              {(history.data ?? []).map((wf) => (
                <Fragment key={wf.id}>
                  <tr className="bl-clickable" onClick={() => setExpanded(expanded === wf.id ? null : wf.id)}>
                    <td className="bl-small">{dateTime(wf.createdAt)}</td>
                    <td>{wf.objective}</td>
                    <td>{wf.kind === 'analysis' ? 'Analysis' : humanize(wf.actionType ?? 'approval')}</td>
                    <td><StatusBadge status={wf.approvalStatus === 'NotRequired' ? wf.status : wf.approvalStatus} /></td>
                    <td className="bl-small">{wf.finalOutcome ?? wf.errorLog ?? '—'}</td>
                  </tr>
                  {expanded === wf.id && (
                    <tr>
                      <td colSpan={5}>
                        <pre className="bl-code">{pretty(wf.kind === 'analysis' ? wf.toolResultsJson : wf.planJson)}</pre>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
              {history.data && history.data.length === 0 && <tr><td colSpan={5}><div className="bl-empty">The agent has not run yet.</div></td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/** The plan the copilot produced, what it expected to find, and - separately -
 *  everything it asked for that it was not allowed to have. */
function PlanPanel({ planned }: { planned: BillingPlannedAnalysis }) {
  const { planner, plannerWarnings, effectiveThresholds, narrative, narrativeError } = planned;
  const { intent } = planner;
  const pct = Math.round(planner.confidenceScore * 100);
  const raised = new Set(planned.analysis.anomalies.map((a) => a.type));

  return (
    <div className="bl-stack">
      {planner.usedFallback && (
        <div className="bl-notice bl-notice-warning">
          The language model was unavailable, so the objective was read from keywords instead. Detection, thresholds and
          approvals are unaffected - only the reading of the sentence is simpler.
        </div>
      )}

      {plannerWarnings.length > 0 && (
        <div className="bl-notice bl-notice-warning">
          <strong>The planner asked for something it was not allowed:</strong>
          <ul>{plannerWarnings.map((w) => <li key={w}>{w}</li>)}</ul>
        </div>
      )}

      <div className="card chart-card bl-stack">
        <div className="bl-spread">
          <p className="chart-title" style={{ margin: 0 }}>Plan</p>
          <div className="bl-row">
            <span className="bl-badge bl-badge-primary">{humanize(intent.analysisType)}</span>
            <span className="bl-badge">Last {intent.daysBack} days</span>
            {intent.tightenDiscountCapTo != null && (
              <span className="bl-badge bl-badge-warning">
                Discount cap tightened to {intent.tightenDiscountCapTo}%
              </span>
            )}
            {intent.dealAmount != null && <span className="bl-badge">Deal {money(intent.dealAmount)}</span>}
            {planner.usedFallback && <span className="bl-badge bl-badge-warning">No model</span>}
          </div>
        </div>

        {intent.focus && <span>{intent.focus}</span>}
        {planner.summary && <span className="bl-small bl-muted">{planner.summary}</span>}

        <ol className="bl-list" style={{ listStyle: 'none' }}>
          {planner.plan.map((step) => (
            <li key={step.order} className="bl-list-item">
              <div className="bl-spread">
                <strong>{step.order}. {step.action}</strong>
                <span className={`bl-badge ${step.assignedAgent === 'BillingApprovalGate' ? 'bl-badge-warning' : 'bl-badge-primary'}`}>
                  {step.assignedAgent === 'BillingApprovalGate' ? 'Human approval' : 'Domain analysis'}
                </span>
              </div>
              <span className="bl-small">{step.description}</span>
              {step.tools.length > 0 && <span className="bl-evidence bl-mono">{step.tools.join(' · ')}</span>}
            </li>
          ))}
        </ol>

        <div className="bl-row">
          <span className="bl-label">Planner confidence</span>
          <span className="bl-num">{pct}%</span>
          <div className="bl-meter"><span style={{ width: `${pct}%` }} /></div>
        </div>
        <span className="bl-small bl-muted">
          Thresholds this run used: discount cap {effectiveThresholds.maxDiscountPercent}%, adjustments over{' '}
          {money(effectiveThresholds.adjustmentApprovalAmount)} and claims over{' '}
          {money(effectiveThresholds.claimApprovalAmount)} wait for a person.
        </span>
      </div>

      <div className="bl-grid-2" style={{ alignItems: 'start' }}>
        <div className="card chart-card">
          <p className="chart-title">Expected before the data was read</p>
          {planner.predictedFindings.length === 0 && <div className="bl-empty">The planner made no prediction.</div>}
          <ul className="bl-list">
            {planner.predictedFindings.map((f) => (
              <li key={f.kind} className="bl-list-item">
                <div className="bl-spread">
                  <strong>{humanize(f.kind)}</strong>
                  {/* Predicted, then checked against what the detector actually
                      raised - a mismatch is the interesting case, not a bug. */}
                  <span className={`bl-badge ${raised.has(f.kind) ? 'bl-badge-good' : ''}`}>
                    {raised.has(f.kind) ? 'Found' : 'Not found'}
                  </span>
                </div>
                <span className="bl-small">{f.description}</span>
                <span className="bl-evidence">Likelihood {Math.round(f.likelihood * 100)}%</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="card chart-card">
          <p className="chart-title">What the findings add up to</p>
          {narrativeError && <div className="bl-small bl-muted">No summary this time: {narrativeError}</div>}
          {narrative && (
            <div className="bl-stack">
              <strong>{narrative.headline}</strong>
              {narrative.usedFallback && (
                <span className="bl-small bl-muted">Grouped by type, without the model.</span>
              )}
              <ul className="bl-list">
                {narrative.themes.map((t) => (
                  <li key={t.title} className="bl-list-item">
                    <div className="bl-spread">
                      <strong>{t.title}</strong>
                      <StatusBadge status={t.severity} label={t.severity} />
                    </div>
                    <span>{t.detail}</span>
                    <span className="bl-evidence bl-mono">{t.anomalyIds.join(' · ')}</span>
                  </li>
                ))}
              </ul>
              {narrative.suggestedNextSteps.length > 0 && (
                <>
                  <span className="bl-label">Where to start</span>
                  <ul className="bl-list">
                    {narrative.suggestedNextSteps.map((s) => (
                      <li key={s} className="bl-list-item">{s}</li>
                    ))}
                  </ul>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function AnalysisResult({ result }: { result: BillingAnalysis }) {
  const pct = Math.round(result.confidenceScore * 100);
  return (
    <div className="bl-stack">
      <div className="bl-kpis">
        <div className="bl-kpi"><div className="bl-kpi-label">Anomalies</div><div className="bl-kpi-value">{result.anomalies.length}</div></div>
        <div className="bl-kpi"><div className="bl-kpi-label">Recommended actions</div><div className="bl-kpi-value">{result.recommendedActions.length}</div></div>
        <div className="bl-kpi">
          <div className="bl-kpi-label">Confidence</div>
          <div className="bl-kpi-value">{pct}%</div>
          <div className="bl-meter"><span style={{ width: `${pct}%` }} /></div>
        </div>
      </div>

      <div className="bl-grid-2" style={{ alignItems: 'start' }}>
        <div className="card chart-card">
          <p className="chart-title">Anomalies</p>
          {result.anomalies.length === 0 && <div className="bl-empty">Nothing suspicious found.</div>}
          <ul className="bl-list">
            {result.anomalies.map((a) => (
              <li key={a.id} className="bl-list-item">
                <div className="bl-spread"><strong>{humanize(a.type)}</strong><StatusBadge status={a.severity} label={a.severity} /></div>
                <span>{a.description}</span>
                <span className="bl-evidence">{Object.entries(a.evidence).map(([k, v]) => `${humanize(k)}: ${String(v)}`).join(' · ')}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="bl-stack">
          <div className="card chart-card">
            <p className="chart-title">Insights</p>
            <ul className="bl-list">
              {result.insights.map((i, idx) => (
                <li key={idx} className="bl-list-item"><strong>{i.title}</strong><span>{i.detail}</span></li>
              ))}
            </ul>
          </div>
          <div className="card chart-card">
            <p className="chart-title">Recommended actions</p>
            {result.recommendedActions.length === 0 && <div className="bl-empty">No action needed.</div>}
            <ul className="bl-list">
              {result.recommendedActions.map((a) => (
                <li key={a.id} className="bl-list-item">
                  <div className="bl-spread">
                    <span className="bl-badge bl-badge-primary">{humanize(a.actionType)}</span>
                    {a.requiresApproval && <span className="bl-badge bl-badge-warning">Needs Admin</span>}
                  </div>
                  <span>{a.description}</span>
                  {a.approvalReason && <span className="bl-small bl-muted">{a.approvalReason}</span>}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>

      <div className="card chart-card">
        <p className="chart-title">Tool calls</p>
        <div className="bl-table-wrap">
          <table className="bl-table">
            <thead><tr><th>Tool</th><th>Result</th><th className="bl-num">Examined</th><th className="bl-num">ms</th></tr></thead>
            <tbody>
              {result.toolCalls.map((t) => (
                <tr key={t.tool}><td className="bl-mono">{t.tool}</td><td>{t.summary}</td><td className="bl-num">{t.itemsExamined}</td><td className="bl-num">{t.durationMs}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function planRequiresAdmin(wf: BillingWorkflow): boolean {
  try {
    return Boolean(JSON.parse(wf.planJson ?? '{}').requiresAdmin);
  } catch {
    return false;
  }
}

function sourceOf(wf: BillingWorkflow): string {
  try {
    return JSON.parse(wf.planJson ?? '{}').source === 'agent' ? 'raised by the billing agent' : 'requested by staff';
  } catch {
    return '';
  }
}

function pretty(json: string | null): string {
  if (!json) return '—';
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch {
    return json;
  }
}
