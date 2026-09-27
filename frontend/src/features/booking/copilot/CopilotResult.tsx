import { useMemo, useState } from 'react';
import {
  useApplyWorkflowMutation,
  useApproveWorkflowMutation,
  useRejectWorkflowMutation,
  useReviseWorkflowMutation,
} from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDayLabel, formatTime } from '../../../shared/dateUtils';
import type { AgentWorkflow } from '../types';
import { AgentPipeline } from './AgentPipeline';
import {
  AGENT_META,
  CHECK_LABELS,
  RULE_LABELS,
  type AgentName,
  type CopilotTrace,
  type ScheduleProposal,
} from './copilotTypes';

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function pct(value: number) {
  return `${Math.round(value)}%`;
}

function money(value: number | null | undefined, currency: string) {
  if (value == null) return '—';
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency, maximumFractionDigits: 0 }).format(value);
  } catch {
    return `${currency} ${Math.round(value).toLocaleString()}`;
  }
}

type Tone = 'good' | 'warn' | 'bad' | 'info';

/* What the manager is being asked to do right now. Derived from the stored
 * workflow rather than the trace, because the workflow moves on (approved,
 * applied) while the trace is a fixed record of the run. */
function bannerFor(workflow: AgentWorkflow, trace: CopilotTrace): { tone: Tone; icon: string; title: string; body: string; list: string[] } {
  if (workflow.status === 'Completed') {
    return { tone: 'info', icon: '✅', title: 'Applied to the schedule', body: workflow.finalOutcome ?? 'The proposed bookings were created.', list: [] };
  }
  if (workflow.status === 'Failed' || trace.status === 'Failed') {
    return {
      tone: 'bad', icon: '🛑', title: 'Stopped safely',
      body: 'The agents stopped before producing a plan. Nothing was booked, and the reason is recorded below.',
      list: [trace.error ?? workflow.errorLog ?? 'Unknown error'],
    };
  }
  if (workflow.approvalStatus === 'Rejected') {
    return { tone: 'bad', icon: '✋', title: 'Rejected by a manager', body: workflow.errorLog || 'No reason given.', list: [] };
  }
  if (trace.status === 'Rejected' || workflow.status === 'Rejected') {
    return {
      tone: 'bad', icon: '↩️', title: 'Returned for revision',
      body: 'The Validation/Safety agent found a rule this plan would break, so it was not offered for approval.',
      list: [trace.safety?.rejection_reason ?? trace.error ?? 'A business rule failed.'],
    };
  }
  if (workflow.approvalStatus === 'Pending') {
    return {
      tone: 'warn', icon: '⏸️', title: 'Needs your approval',
      body: 'Every rule passed, but this change is high-impact, so it waits for a manager before anything is booked.',
      list: trace.safety?.approval_reasons ?? [],
    };
  }
  return {
    tone: 'good', icon: '🟢', title: workflow.approvalStatus === 'Approved' ? 'Approved — ready to apply' : 'Ready to apply',
    body: workflow.approvalStatus === 'Approved'
      ? `Approved${workflow.approvedAt ? ` on ${new Date(workflow.approvedAt).toLocaleString()}` : ''}. Apply it to create the bookings.`
      : 'Every rule passed and it is under the approval thresholds. Nothing is booked until you apply it.',
    list: [],
  };
}

function groupByDay(proposals: ScheduleProposal[]) {
  const groups = new Map<string, { label: string; items: { p: ScheduleProposal; index: number }[] }>();
  proposals.forEach((p, index) => {
    const d = new Date(p.start);
    const key = d.toDateString();
    if (!groups.has(key)) groups.set(key, { label: formatDayLabel(d), items: [] });
    groups.get(key)!.items.push({ p, index });
  });
  return [...groups.values()];
}

export function CopilotResult({
  workflow,
  trace,
  onRerun,
}: {
  workflow: AgentWorkflow;
  trace: CopilotTrace;
  onRerun?: (trace: CopilotTrace) => void;
}) {
  const { show } = useToast();
  const [approve, { isLoading: approving }] = useApproveWorkflowMutation();
  const [reject, { isLoading: rejecting }] = useRejectWorkflowMutation();
  const [apply, { isLoading: applying }] = useApplyWorkflowMutation();
  const [revise, { isLoading: revising }] = useReviseWorkflowMutation();
  const [revisingOpen, setRevisingOpen] = useState(false);
  const [dropped, setDropped] = useState<Set<number>>(new Set());

  const proposals = trace.action?.proposals ?? [];
  const metrics = trace.metrics;
  const planner = trace.planner;
  const banner = bannerFor(workflow, trace);
  const days = useMemo(() => groupByDay(proposals), [proposals]);

  const canDecide = workflow.approvalStatus === 'Pending';
  const canApply = workflow.status === 'Approved'
    && (workflow.approvalStatus === 'Approved' || workflow.approvalStatus === 'NotRequired');
  const canDiscard = canApply;

  const toolSummary = useMemo(() => {
    const byTool = new Map<string, { agent: AgentName; calls: number; ms: number; failed: number }>();
    for (const c of trace.tool_calls ?? []) {
      const key = `${c.tool}|${c.agent}`;
      const entry = byTool.get(key) ?? { agent: c.agent, calls: 0, ms: 0, failed: 0 };
      entry.calls += 1;
      entry.ms += c.duration_ms;
      if (!c.success) entry.failed += 1;
      byTool.set(key, entry);
    }
    return [...byTool.entries()].map(([key, v]) => ({ tool: key.split('|')[0], ...v }))
      .sort((a, b) => b.calls - a.calls);
  }, [trace.tool_calls]);

  const slowest = Math.max(1, ...(trace.agent_steps ?? []).map((s) => s.duration_ms));
  const retries = (trace.llm_calls ?? []).filter((c) => !c.ok).length;

  const run = async (label: string, action: () => Promise<unknown>) => {
    try {
      await action();
      show(label, 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'That action did not go through.'), 'error');
    }
  };

  const handleReject = () => {
    const reason = window.prompt('Why are you rejecting this schedule? (recorded in the audit trail)');
    if (reason === null) return;
    run('Schedule rejected.', () => reject({ id: workflow.id, reason: reason || 'Rejected without a reason.' }).unwrap());
  };

  const handleApply = async () => {
    try {
      const result = await apply(workflow.id).unwrap();
      show(`Applied: ${result.created} booking(s) created${result.skipped ? `, ${result.skipped} skipped` : ''}.`, 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not apply this schedule.'), 'error');
    }
  };

  const handleSaveRevision = async () => {
    // The stored plan's steps are in the same order as the proposals; the
    // server additionally refuses any step that was not in the original.
    let steps: unknown[] = [];
    try {
      const plan = JSON.parse(workflow.planJson ?? '{}');
      steps = plan.steps ?? plan.Steps ?? [];
    } catch {
      show('This workflow has no readable plan to revise.', 'error');
      return;
    }
    const kept = steps.filter((_, i) => !dropped.has(i));
    if (kept.length === 0) {
      show('Keep at least one booking, or reject the schedule instead.', 'error');
      return;
    }
    await run(`Revised to ${kept.length} booking(s) — still awaiting approval.`, () =>
      revise({ id: workflow.id, plan: { steps: kept, estimatedRevenueImpact: 0 } }).unwrap());
    setRevisingOpen(false);
    setDropped(new Set());
  };

  return (
    <div className="cop-stack">
      {/* ── status and decision ────────────────────────────────────── */}
      <section className={`cop-banner cop-banner--${banner.tone}`} aria-live="polite">
        <div className="cop-banner-left">
          <span className="cop-banner-icon" aria-hidden="true">{banner.icon}</span>
          <div>
            <h2>{banner.title}</h2>
            <p>{banner.body}</p>
            {banner.list.length > 0 && <ul>{banner.list.map((line, i) => <li key={i}>{line}</li>)}</ul>}
          </div>
        </div>
        <div className="cop-banner-actions">
          {canDecide && !revisingOpen && (
            <>
              <button className="btn btn-primary btn-sm" disabled={approving}
                onClick={() => run('Approved. Apply it when you are ready.', () => approve(workflow.id).unwrap())}>
                {approving ? <span className="spinner" /> : 'Approve'}
              </button>
              {proposals.length > 1 && (
                <button className="btn btn-secondary btn-sm" onClick={() => setRevisingOpen(true)}>Revise</button>
              )}
              <button className="btn btn-ghost btn-sm" disabled={rejecting} onClick={handleReject}>Reject</button>
            </>
          )}
          {canDecide && revisingOpen && (
            <>
              <button className="btn btn-primary btn-sm" disabled={revising || dropped.size === proposals.length}
                onClick={handleSaveRevision}>
                {revising ? <span className="spinner" /> : `Keep ${proposals.length - dropped.size}`}
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => { setRevisingOpen(false); setDropped(new Set()); }}>
                Cancel
              </button>
            </>
          )}
          {canApply && (
            <button className="btn btn-primary btn-sm" disabled={applying} onClick={handleApply}>
              {applying ? <span className="spinner" /> : `Apply ${proposals.length} to schedule`}
            </button>
          )}
          {canDiscard && <button className="btn btn-ghost btn-sm" disabled={rejecting} onClick={handleReject}>Discard</button>}
          {(workflow.status === 'Rejected' || workflow.status === 'Failed') && onRerun && (
            <button className="btn btn-secondary btn-sm" onClick={() => onRerun(trace)}>Adjust and run again</button>
          )}
        </div>
      </section>
      {revisingOpen && (
        <p className="cop-note">Untick the bookings you do not want. A revision can only remove proposals the agents already
          validated — it can never add a slot that did not go through the safety gate.</p>
      )}

      <AgentPipeline trace={trace} />

      {/* ── headline numbers ────────────────────────────────────────── */}
      {metrics && (
        <div className="cop-kpis">
          <div className="cop-kpi cop-kpi--violet">
            <b>{metrics.proposed}/{metrics.requested}</b>
            <span>Bookings proposed</span>
            <small>{pct(metrics.coverage_pct)} of the request</small>
          </div>
          <div className="cop-kpi cop-kpi--blue">
            <b>{planner ? pct(planner.confidence_score * 100) : '—'}</b>
            <span>Planner confidence</span>
            <small>{planner?.used_fallback ? 'deterministic planner' : 'language-model plan'}</small>
          </div>
          <div className="cop-kpi cop-kpi--cyan">
            <b>{metrics.resources_used} · {metrics.days_used}</b>
            <span>Resources · days</span>
            <small>{trace.action?.candidates_considered ?? 0} slots considered</small>
          </div>
          <div className="cop-kpi cop-kpi--green">
            <b>{pct(metrics.utilisation_before_pct)} → {pct(metrics.utilisation_after_pct)}</b>
            <span>Utilisation</span>
            <small>before → after this plan</small>
          </div>
          <div className="cop-kpi cop-kpi--amber">
            <b>{metrics.expected_no_shows.toFixed(1)}</b>
            <span>Expected no-shows</span>
            <small>from 90-day history</small>
          </div>
          <div className="cop-kpi cop-kpi--pink">
            <b>{money(metrics.estimated_revenue, metrics.currency)}</b>
            <span>Revenue impact</span>
            <small>{metrics.estimated_revenue_usd != null && metrics.currency !== 'USD'
              ? `≈ ${money(metrics.estimated_revenue_usd, 'USD')}` : 'estimated from past bookings'}</small>
          </div>
        </div>
      )}

      <div className="cop-two">
        {/* ── the plan ─────────────────────────────────────────────── */}
        <div className="cop-stack">
          {planner && (
            <section className="cop-card">
              <div className="cop-card-head">
                <div>
                  <h3>The plan</h3>
                  <p>Written by the Planner/Coordinator and delegated step by step</p>
                </div>
                <span className="cop-pill">{planner.plan.length} steps</span>
              </div>
              <div className="cop-card-body">
                {planner.summary && <p style={{ margin: '0 0 14px', fontSize: '.84rem' }}>{planner.summary}</p>}
                <ol className="cop-steps">
                  {planner.plan.map((step) => {
                    const meta = AGENT_META[step.assigned_agent];
                    return (
                      <li key={step.order} className="cop-step" style={{ ['--agent' as string]: meta.tone }}>
                        <span className="cop-step-no">{step.order}</span>
                        <div>
                          <span className="cop-agent-tag">{meta.short}</span>
                          <h4>{step.action}</h4>
                          <p>{step.description}</p>
                          {step.tools.length > 0 && (
                            <div className="cop-tools">{step.tools.map((t) => <code key={t} className="cop-tool">{t}</code>)}</div>
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ol>
                <div className="cop-intent">
                  {planner.intent.priority_rules.map((r) => (
                    <span key={r} className="cop-pill">{RULE_LABELS[r]?.icon} {RULE_LABELS[r]?.label ?? r}</span>
                  ))}
                  {planner.intent.weekdays.length > 0 && (
                    <span className="cop-pill">📅 {planner.intent.weekdays.map((d) => WEEKDAYS[d]).join(', ')}</span>
                  )}
                  {planner.intent.time_window !== 'any' && <span className="cop-pill">🕘 {planner.intent.time_window} only</span>}
                  {planner.intent.min_gap_minutes > 0 && <span className="cop-pill">↔ {planner.intent.min_gap_minutes} min gap</span>}
                </div>
                {trace.warnings.map((w, i) => <p key={i} className="cop-note">{w}</p>)}
              </div>
            </section>
          )}

          {planner && planner.predicted_conflicts.length > 0 && (
            <section className="cop-card">
              <div className="cop-card-head">
                <div>
                  <h3>Predicted conflicts</h3>
                  <p>What the planner expected the other agents to run into</p>
                </div>
              </div>
              <div className="cop-card-body cop-conflicts">
                {planner.predicted_conflicts.map((c, i) => (
                  <div key={i} className="cop-conflict">
                    <div className="cop-conflict-top">
                      <span>{c.kind.replace(/_/g, ' ')}</span>
                      <span>{pct(c.likelihood * 100)} likely</span>
                    </div>
                    <p>{c.description}</p>
                    <div className="cop-bar"><i style={{ width: pct(c.likelihood * 100), ['--fill' as string]: 'var(--color-warning)' }} /></div>
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>

        {/* ── proposed schedule ──────────────────────────────────────── */}
        <section className="cop-card">
          <div className="cop-card-head">
            <div>
              <h3>Proposed schedule</h3>
              <p>Every slot is a real open slot, re-checked against live bookings</p>
            </div>
            <span className="cop-pill">{proposals.length} booking{proposals.length === 1 ? '' : 's'}</span>
          </div>
          <div className="cop-card-body">
            {proposals.length === 0 ? (
              <div className="cop-empty"><b>No slot satisfied every rule</b>See why slots were skipped below.</div>
            ) : days.map((day) => (
              <div key={day.label} className="cop-day">
                <div className="cop-day-head"><b>{day.label}</b><span>{day.items.length} booking(s)</span></div>
                {day.items.map(({ p, index }) => (
                  <div key={index} className={`cop-slot${dropped.has(index) ? ' is-dropped' : ''}`}>
                    <div className="cop-slot-time">
                      {revisingOpen && (
                        <input
                          type="checkbox"
                          aria-label={`Keep ${p.resource_name} at ${formatTime(p.start)}`}
                          checked={!dropped.has(index)}
                          onChange={(e) => setDropped((prev) => {
                            const next = new Set(prev);
                            if (e.target.checked) next.delete(index); else next.add(index);
                            return next;
                          })}
                          style={{ marginRight: 6 }}
                        />
                      )}
                      {formatTime(p.start)}–{formatTime(p.end)}
                    </div>
                    <div className="cop-slot-main">
                      <b>{p.resource_name}</b>
                      <div className="cop-slot-reasons">
                        {p.reasons.slice(0, 4).map((r, i) => <span key={i}>{r}</span>)}
                      </div>
                    </div>
                    <div className="cop-score" title={Object.entries(p.score_breakdown).map(([k, v]) => `${k}: ${v}`).join('\n')}>
                      <b>{p.score.toFixed(0)}</b>
                      <div className="cop-bar"><i style={{ width: `${Math.max(4, Math.min(100, p.score))}%` }} /></div>
                      score
                    </div>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </section>
      </div>

      {/* ── validation ───────────────────────────────────────────────── */}
      {trace.safety && (
        <section className="cop-card">
          <div className="cop-card-head">
            <div>
              <h3>Validation &amp; safety checks</h3>
              <p>Deterministic rules — no language model can argue with these</p>
            </div>
            <span className="cop-pill">
              {trace.safety.checks.filter((c) => c.status === 'pass').length}/{trace.safety.checks.length} passed
            </span>
          </div>
          <div className="cop-card-body cop-checks">
            {trace.safety.checks.map((c) => (
              <div key={c.rule} className={`cop-check cop-check--${c.status}`}>
                <span className="cop-check-icon" aria-hidden="true">{c.status === 'pass' ? '✓' : c.status === 'warn' ? '!' : '✕'}</span>
                <div>
                  <b>{CHECK_LABELS[c.rule] ?? c.rule}</b>
                  <p>{c.detail}</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* ── resource analysis ────────────────────────────────────────── */}
      {trace.analysis && trace.analysis.resources.length > 0 && (
        <section className="cop-card">
          <div className="cop-card-head">
            <div>
              <h3>Resource analysis</h3>
              <p>How Domain Analysis ranked each candidate</p>
            </div>
          </div>
          <div className="cop-card-body" style={{ overflowX: 'auto' }}>
            <table className="cop-table">
              <thead>
                <tr><th>#</th><th>Resource</th><th>Open days</th><th>Already booked</th><th>No-show rate</th><th>Daily cap</th><th>Score</th></tr>
              </thead>
              <tbody>
                {trace.analysis.resources.map((r, i) => (
                  <tr key={r.resource_id} title={r.reasons.join('\n')}>
                    <td><span className="cop-rank">{i + 1}</span></td>
                    <td><b>{r.resource_name}</b></td>
                    <td>{r.working_days_in_range}</td>
                    <td style={{ minWidth: 140 }}>
                      <div className="cop-bar"><i style={{ width: pct(r.utilisation_pct), ['--fill' as string]: r.utilisation_pct >= 80 ? 'var(--color-critical)' : 'var(--color-primary)' }} /></div>
                      <small>{pct(r.utilisation_pct)}</small>
                    </td>
                    <td>{r.no_show_sample ? `${pct(r.no_show_rate * 100)} (${r.no_show_sample})` : '—'}</td>
                    <td>{Math.round(r.max_daily_minutes / 60)}h{r.lunch_start ? ` · lunch ${r.lunch_start}` : ''}</td>
                    <td><b>{r.score.toFixed(0)}</b></td>
                  </tr>
                ))}
              </tbody>
            </table>
            {trace.analysis.insights.map((line, i) => <p key={i} className="cop-note">{line}</p>)}
          </div>
        </section>
      )}

      {(trace.action?.skipped?.length ?? 0) > 0 && (
        <section className="cop-card">
          <div className="cop-card-body">
            <details className="cop-details">
              <summary>Why some open slots were skipped ({trace.action!.skipped.length})</summary>
              <table className="cop-mini" style={{ marginTop: 10 }}>
                <tbody>
                  {trace.action!.skipped.map((s, i) => (
                    <tr key={i}>
                      <td>{formatDayLabel(new Date(s.start))} {formatTime(s.start)}</td>
                      <td>{s.resource_name}</td>
                      <td>{s.reason}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </details>
          </div>
        </section>
      )}

      {/* ── execution trace ─────────────────────────────────────────── */}
      <section className="cop-card">
        <div className="cop-card-head">
          <div>
            <h3>Execution trace</h3>
            <p>Stored with the workflow for audit: timings, allow-listed tool calls and model calls</p>
          </div>
          <span className="cop-pill">{trace.tool_calls.length} tool calls{retries ? ` · ${retries} model retr${retries === 1 ? 'y' : 'ies'}` : ''}</span>
        </div>
        <div className="cop-card-body cop-trace-grid">
          <div>
            <h4>Agent timings</h4>
            <div className="cop-timing">
              {trace.agent_steps.map((s) => (
                <div key={s.agent} className="cop-timing-row">
                  <span>{AGENT_META[s.agent]?.short ?? s.agent}</span>
                  <div className="cop-bar">
                    <i style={{ width: `${(s.duration_ms / slowest) * 100}%`, ['--fill' as string]: s.ok ? AGENT_META[s.agent]?.tone : 'var(--color-critical)' }} />
                  </div>
                  <span>{s.duration_ms} ms</span>
                </div>
              ))}
            </div>
          </div>
          <div>
            <h4>Tool calls</h4>
            <table className="cop-mini">
              <tbody>
                {toolSummary.map((t) => (
                  <tr key={`${t.tool}-${t.agent}`}>
                    <td><code>{t.tool}</code></td>
                    <td>{AGENT_META[t.agent]?.short}</td>
                    <td className={t.failed ? 'cop-fail-text' : undefined}>
                      ×{t.calls}{t.failed ? ` (${t.failed} failed)` : ''} · {Math.round(t.ms / t.calls)} ms
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div>
            <h4>Model calls</h4>
            {trace.llm_calls.length === 0 ? (
              <p className="cop-note" style={{ marginTop: 0 }}>No model call was made — the deterministic planner ran.</p>
            ) : (
              <table className="cop-mini">
                <tbody>
                  {trace.llm_calls.map((c, i) => (
                    <tr key={i} title={c.error ?? undefined}>
                      <td><code>{c.model}</code></td>
                      <td>try {c.attempt}</td>
                      <td className={c.ok ? undefined : 'cop-fail-text'}>{c.ok ? `${c.duration_ms} ms` : 'failed → next'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
