import { useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import {
  useApplyWorkflowMutation,
  useApproveWorkflowMutation,
  useGetBookingTypesQuery,
  useGetResourcesQuery,
  useGetWorkflowsQuery,
  usePlanScheduleMutation,
  useRejectWorkflowMutation,
} from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { addDays, toISODate } from '../../../shared/dateUtils';
import type { AgentWorkflow } from '../types';
import { AgentPipeline } from './AgentPipeline';
import { ExecutionTracePanel } from './LegacyTracePanel';
import { CopilotResult } from './CopilotResult';
import { parseCopilotTrace, RULE_LABELS, type CopilotTrace, type PriorityRule } from './copilotTypes';
import './copilot.css';

const EXAMPLES = [
  'Fit 5 follow-up appointments this week, mornings only, and keep lunch free',
  "Line up 6 property viewings for Thursday's buyers and leave time to drive between houses",
  'Spread 12 sessions evenly across the team and avoid anyone with a lot of no-shows',
  'Book the earliest 4 slots, clustered onto as few days as possible',
];

const ALL_RULES = Object.keys(RULE_LABELS) as PriorityRule[];

type Filter = 'all' | 'pending' | 'ready' | 'applied' | 'returned' | 'failed';

const FILTERS: { key: Filter; label: string; match: (w: AgentWorkflow) => boolean }[] = [
  { key: 'all', label: 'All runs', match: () => true },
  { key: 'pending', label: 'Needs approval', match: (w) => w.approvalStatus === 'Pending' },
  { key: 'ready', label: 'Ready to apply', match: (w) => w.status === 'Approved' },
  { key: 'applied', label: 'Applied', match: (w) => w.status === 'Completed' },
  { key: 'returned', label: 'Returned / rejected', match: (w) => w.status === 'Rejected' },
  { key: 'failed', label: 'Stopped safely', match: (w) => w.status === 'Failed' },
];

const STATUS_STYLE: Record<string, { label: string; bg: string }> = {
  AwaitingApproval: { label: 'Needs approval', bg: 'var(--color-warning)' },
  Approved: { label: 'Ready', bg: 'var(--color-good)' },
  Completed: { label: 'Applied', bg: 'var(--color-primary)' },
  Rejected: { label: 'Returned', bg: 'var(--color-critical)' },
  Failed: { label: 'Stopped', bg: 'var(--color-neutral)' },
};

function statusOf(w: AgentWorkflow) {
  return STATUS_STYLE[w.status] ?? { label: w.status, bg: 'var(--color-neutral)' };
}

export default function ScheduleCopilotPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: bookingTypesData } = useGetBookingTypesQuery({ tenantId }, { skip: !tenantId });
  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });
  // Polled so an approval given on another screen, or by another manager,
  // shows up here without a refresh.
  const { data: workflows, isLoading: workflowsLoading } = useGetWorkflowsQuery(
    { tenantId }, { skip: !tenantId, pollingInterval: 15000 });
  const [planSchedule, { isLoading: running }] = usePlanScheduleMutation();

  const bookingTypes = useMemo(
    () => (bookingTypesData ?? []).filter((bt) => bt.status !== 'Archived'),
    [bookingTypesData]);
  const resources = useMemo(
    () => (resourcesData?.items ?? []).filter((r) => String(r.status ?? '') !== 'Archived'),
    [resourcesData]);

  const [objective, setObjective] = useState(EXAMPLES[0]);
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [dateFrom, setDateFrom] = useState(() => toISODate(addDays(new Date(), 1)));
  const [dateTo, setDateTo] = useState(() => toISODate(addDays(new Date(), 7)));
  const [targetCount, setTargetCount] = useState(5);
  const [resourceIds, setResourceIds] = useState<string[]>([]);
  const [rules, setRules] = useState<PriorityRule[]>([]);

  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    if (!bookingTypeId && bookingTypes.length > 0) setBookingTypeId(bookingTypes[0].id);
  }, [bookingTypes, bookingTypeId]);

  const all = workflows ?? [];
  const copilotRuns = all.filter((w) => parseCopilotTrace(w.toolResultsJson));
  const selected = all.find((w) => w.id === selectedId) ?? copilotRuns[0] ?? null;
  const selectedTrace = selected ? parseCopilotTrace(selected.toolResultsJson) : null;

  const visible = all
    .filter((w) => FILTERS.find((f) => f.key === filter)!.match(w))
    .filter((w) => !search.trim() || w.objective.toLowerCase().includes(search.trim().toLowerCase()));

  const toggle = <T,>(list: T[], value: T) => (list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);

  const handleRun = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!bookingTypeId) {
      show('Choose what kind of booking to schedule first.', 'error');
      return;
    }
    if (dateTo < dateFrom) {
      show('The end date is before the start date.', 'error');
      return;
    }
    try {
      const result = await planSchedule({
        tenantId, objective, bookingTypeId, dateFrom, dateTo, targetCount,
        resourceIds: resourceIds.length ? resourceIds : undefined,
        priorityRules: rules,
      }).unwrap();
      setSelectedId(result.workflow.id);
      const status = (result.trace as CopilotTrace | null)?.status;
      show(
        status === 'AwaitingApproval' ? 'Plan ready — it needs your approval.'
          : status === 'Completed' ? 'Plan ready to apply.'
          : status === 'Rejected' ? 'The safety gate returned the plan for revision.'
          : 'The agents stopped safely. See the reason below.',
        status === 'Completed' || status === 'AwaitingApproval' ? 'success' : 'info',
      );
    } catch (err) {
      show(apiErrorMessage(err, 'The Schedule Copilot could not run.'), 'error');
    }
  };

  const handleRerun = (trace: CopilotTrace) => {
    setObjective(trace.objective);
    setDateFrom(trace.constraints.date_range.date_from);
    setDateTo(trace.constraints.date_range.date_to);
    setTargetCount(trace.constraints.target_count);
    setRules(trace.constraints.priority_rules);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <div className="cop">
      {/* ── hero ─────────────────────────────────────────────────────── */}
      <header className="cop-hero">
        <div className="cop-hero-id">
          <div className="cop-orb" aria-hidden="true">✦</div>
          <div>
            <p className="cop-eyebrow">PLANNER · COORDINATOR AGENT</p>
            <h1>Schedule Copilot</h1>
            <p>Say what you need in plain words. Four agents plan it, fit it into real open slots, check it against
              your rules and hand it back for your approval. Nothing is booked until you apply it.</p>
          </div>
        </div>
        <div className="cop-hero-stats">
          <div className="cop-hero-stat"><b>{copilotRuns.length}</b><span>Copilot runs</span></div>
          <div className="cop-hero-stat"><b>{all.filter((w) => w.approvalStatus === 'Pending').length}</b><span>Awaiting approval</span></div>
          <div className="cop-hero-stat"><b>{all.filter((w) => w.status === 'Completed').length}</b><span>Applied</span></div>
        </div>
      </header>

      {/* ── composer ─────────────────────────────────────────────────── */}
      <form className="cop-card" onSubmit={handleRun} aria-busy={running}>
        <div className="cop-card-head">
          <div>
            <h2>What should the agents schedule?</h2>
            <p>Name days, times, gaps or counts — the planner reads them. Your settings below always win.</p>
          </div>
        </div>
        <div className="cop-card-body">
          <label htmlFor="cop-objective" className="sr-only">Scheduling objective</label>
          <textarea
            id="cop-objective"
            className="cop-objective"
            value={objective}
            maxLength={500}
            onChange={(e) => setObjective(e.target.value)}
            placeholder="e.g. Fit 5 follow-ups this week, mornings only, and keep lunch free"
            required
            minLength={3}
          />
          <div className="cop-counter">{objective.length}/500</div>
          <div className="cop-examples" aria-label="Example objectives">
            {EXAMPLES.map((ex) => (
              <button key={ex} type="button" className="cop-example" onClick={() => setObjective(ex)}>{ex}</button>
            ))}
          </div>

          <div className="cop-grid">
            <div className="cop-field">
              <label htmlFor="cop-type">Booking type</label>
              <select id="cop-type" className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} required>
                {bookingTypes.length === 0 && <option value="">No booking types yet</option>}
                {bookingTypes.map((bt) => <option key={bt.id} value={bt.id}>{bt.name} · {bt.defaultDurationMinutes} min</option>)}
              </select>
            </div>
            <div className="cop-field">
              <label htmlFor="cop-from">From</label>
              <input id="cop-from" className="input" type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} required />
            </div>
            <div className="cop-field">
              <label htmlFor="cop-to">To</label>
              <input id="cop-to" className="input" type="date" value={dateTo} min={dateFrom} onChange={(e) => setDateTo(e.target.value)} required />
            </div>
            <div className="cop-field">
              <label htmlFor="cop-count">How many (max)</label>
              <div className="cop-stepper">
                <button type="button" aria-label="Fewer" onClick={() => setTargetCount((n) => Math.max(1, n - 1))}>−</button>
                <input id="cop-count" className="input" type="number" min={1} max={50} value={targetCount}
                  onChange={(e) => setTargetCount(Math.min(50, Math.max(1, Number(e.target.value) || 1)))} />
                <button type="button" aria-label="More" onClick={() => setTargetCount((n) => Math.min(50, n + 1))}>+</button>
              </div>
            </div>
          </div>

          <p className="cop-section-label">Resources</p>
          <div className="cop-chips">
            <button type="button" className="cop-chip" aria-pressed={resourceIds.length === 0} onClick={() => setResourceIds([])}>
              All resources
            </button>
            {resources.slice(0, 24).map((r) => (
              <button key={r.id} type="button" className="cop-chip" aria-pressed={resourceIds.includes(r.id)}
                onClick={() => setResourceIds((ids) => toggle(ids, r.id).slice(0, 12))}>
                {r.name}
              </button>
            ))}
          </div>

          <p className="cop-section-label">Priority rules</p>
          <div className="cop-chips">
            {ALL_RULES.map((rule) => {
              const meta = RULE_LABELS[rule];
              return (
                <button key={rule} type="button" className="cop-chip" aria-pressed={rules.includes(rule)}
                  onClick={() => setRules((current) => {
                    let next = toggle(current, rule);
                    // Mornings and afternoons are mutually exclusive.
                    if (rule === 'prefer_mornings') next = next.filter((r) => r !== 'prefer_afternoons');
                    if (rule === 'prefer_afternoons') next = next.filter((r) => r !== 'prefer_mornings');
                    return next;
                  })}>
                  <span aria-hidden="true">{meta.icon}</span>
                  <span>{meta.label}<small>{meta.hint}</small></span>
                </button>
              );
            })}
          </div>

          <div className="cop-run-row">
            <span className="cop-run-note">
              🔒 Read-only: the agents act with your own permissions and cannot book anything. Schedules over 20 bookings
              or ~$500 always wait for a manager.
            </span>
            <button type="submit" className="cop-run" disabled={running || !tenantId || objective.trim().length < 3}>
              {running ? <><span className="spinner" /> Agents working…</> : <>✦ Run the agents</>}
            </button>
          </div>
        </div>
      </form>

      {running && (
        <section className="cop-card">
          <div className="cop-card-body"><AgentPipeline running /></div>
        </section>
      )}

      {!running && selected && selectedTrace && (
        <CopilotResult key={selected.id} workflow={selected} trace={selectedTrace} onRerun={handleRerun} />
      )}
      {!running && selected && !selectedTrace && <LegacyRun workflow={selected} />}

      {/* ── history ──────────────────────────────────────────────────── */}
      <section className="cop-card">
        <div className="cop-card-head" style={{ flexWrap: 'wrap' }}>
          <div>
            <h3>Workflow history</h3>
            <p>Every run is stored with its plan, checks and trace — open one to review or act on it</p>
          </div>
          <input className="input" style={{ maxWidth: 240 }} placeholder="Search objectives…" value={search}
            onChange={(e) => setSearch(e.target.value)} aria-label="Search workflow history" />
        </div>
        <div className="cop-card-body">
          <div className="cop-tabs" role="tablist" style={{ marginBottom: 12 }}>
            {FILTERS.map((f) => (
              <button key={f.key} type="button" role="tab" className="cop-tab" aria-selected={filter === f.key} onClick={() => setFilter(f.key)}>
                {f.label} <span style={{ opacity: 0.7 }}>{all.filter(f.match).length}</span>
              </button>
            ))}
          </div>
          {workflowsLoading ? (
            <div className="cop-empty"><span className="spinner spinner-dark" /> Loading history…</div>
          ) : visible.length === 0 ? (
            <div className="cop-empty"><b>Nothing here yet</b>Run the agents above and the result will be kept here.</div>
          ) : (
            <div className="cop-history">
              {visible.slice(0, 40).map((w) => {
                const trace = parseCopilotTrace(w.toolResultsJson);
                const s = statusOf(w);
                return (
                  <button key={w.id} type="button" className="cop-run-item" aria-current={selected?.id === w.id}
                    onClick={() => { setSelectedId(w.id); window.scrollTo({ top: 0, behavior: 'smooth' }); }}>
                    <span className="cop-status" style={{ background: s.bg }}>{s.label}</span>
                    <span style={{ minWidth: 0 }}>
                      <b>{w.objective}</b>
                      <small>
                        {new Date(w.createdAt).toLocaleString()}
                        {trace ? ` · ${trace.action?.proposals.length ?? 0} proposed · ${Math.round((trace.planner?.confidence_score ?? 0) * 100)}% confidence`
                          : ' · classic planner'}
                      </small>
                    </span>
                    <span aria-hidden="true">›</span>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </section>
    </div>
  );
}

/* Workflows created before the Copilot (the deterministic planner, customer
 * find-and-book) have no Copilot trace. They are still shown and can still be
 * decided on, so nothing already in the approval queue is stranded. */
function LegacyRun({ workflow }: { workflow: AgentWorkflow }) {
  const { show } = useToast();
  const [approve] = useApproveWorkflowMutation();
  const [reject] = useRejectWorkflowMutation();
  const [apply, { isLoading: applying }] = useApplyWorkflowMutation();
  let steps = 0;
  try {
    const plan = JSON.parse(workflow.planJson ?? '{}');
    steps = (plan.steps ?? plan.Steps ?? []).length;
  } catch { /* no readable plan */ }
  const act = async (label: string, fn: () => Promise<unknown>) => {
    try { await fn(); show(label, 'success'); } catch (err) { show(apiErrorMessage(err, 'That did not go through.'), 'error'); }
  };
  const s = statusOf(workflow);
  return (
    <section className="cop-card">
      <div className="cop-card-head">
        <div>
          <h3>{workflow.objective}</h3>
          <p>Created by the classic planner · {steps} proposed booking(s) · {new Date(workflow.createdAt).toLocaleString()}</p>
        </div>
        <span className="cop-status" style={{ background: s.bg }}>{s.label}</span>
      </div>
      <div className="cop-card-body">
        {workflow.finalOutcome && <p className="cop-note">{workflow.finalOutcome}</p>}
        {workflow.errorLog && <p className="cop-note">{workflow.errorLog}</p>}
        <ExecutionTracePanel workflow={workflow} />
        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          {workflow.approvalStatus === 'Pending' && (
            <>
              <button className="btn btn-primary btn-sm" onClick={() => act('Approved.', () => approve(workflow.id).unwrap())}>Approve</button>
              <button className="btn btn-ghost btn-sm" onClick={() => act('Rejected.', () => reject({ id: workflow.id, reason: 'Rejected from the Copilot page.' }).unwrap())}>Reject</button>
            </>
          )}
          {workflow.status === 'Approved' && steps > 0 && (
            <button className="btn btn-primary btn-sm" disabled={applying} onClick={() => act('Applied.', () => apply(workflow.id).unwrap())}>
              Apply to schedule
            </button>
          )}
        </div>
      </div>
    </section>
  );
}
