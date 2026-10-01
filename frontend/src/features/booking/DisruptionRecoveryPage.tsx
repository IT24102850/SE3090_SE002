import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../store/store';
import { useGetResourcesQuery } from '../../api/bookingApi';
import { formatDateTime } from '../../shared/dateUtils';
import {
  disruptionApi,
  errorMessage,
  parseTrace,
  type DisruptionTrace,
  type DisruptionWorkflow,
  type RecoveryProposal,
} from './disruptionApi';

/* Where a manager handles "a resource is out of service".
 *
 * Two halves: start a recovery, and decide the ones already proposed. The
 * evidence is shown beside each decision - who is affected and why they were
 * ranked that way, what the agents propose, and every check the deterministic
 * safety gate ran - because approving a plan you cannot see is not approval. */

function kindLabel(kind: RecoveryProposal['kind']): string {
  switch (kind) {
    case 'MoveResource': return 'Same time, different resource';
    case 'MoveTime': return 'Same day, later';
    case 'MoveBoth': return 'Another day';
    case 'Cancel': return 'Cancel';
    default: return 'No option found';
  }
}

export default function DisruptionRecoveryPage() {
  const user = useSelector((state: RootState) => state.auth.user);
  const { data: resources } = useGetResourcesQuery(
    { tenantId: user?.tenantId ?? '' },
    { skip: !user?.tenantId },
  );

  const [workflows, setWorkflows] = useState<DisruptionWorkflow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [reasons, setReasons] = useState<Record<string, string>>({});

  // The endpoint answers either a bare array or a paged envelope depending
  // on the query, so both shapes are accepted here.
  const resourceOptions = useMemo(
    () => (Array.isArray(resources) ? resources : resources?.items ?? []),
    [resources],
  );

  const today = new Date().toISOString().slice(0, 10);
  const [form, setForm] = useState({ resourceId: '', dateFrom: today, dateTo: today, objective: '', reason: '' });
  const [planning, setPlanning] = useState(false);

  const load = useCallback(async () => {
    try {
      setWorkflows(await disruptionApi.list());
      setError('');
    } catch (e) {
      setError(errorMessage(e, 'Recovery plans could not be loaded.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function startRecovery(event: React.FormEvent) {
    event.preventDefault();
    setMessage('');
    if (!form.resourceId) { setMessage('Choose the resource that is unavailable.'); return; }
    if (form.objective.trim().length < 3) { setMessage('Describe what happened in at least 3 characters.'); return; }
    setPlanning(true);
    try {
      const result = await disruptionApi.plan({
        objective: form.objective.trim(),
        resourceId: form.resourceId,
        dateFrom: form.dateFrom,
        dateTo: form.dateTo,
        reason: form.reason.trim() || undefined,
      });
      setMessage(`Recovery planned: ${result.status}. Review it below.`);
      await load();
    } catch (e) {
      setMessage(errorMessage(e, 'The recovery could not be planned.'));
    } finally {
      setPlanning(false);
    }
  }

  async function decide(workflow: DisruptionWorkflow, action: 'apply' | 'reject') {
    const reason = (reasons[workflow.id] ?? '').trim();
    if (action === 'reject' && reason.length < 3) {
      setMessage('Give a reason of at least 3 characters before rejecting.');
      return;
    }
    setBusyId(workflow.id);
    setMessage('');
    try {
      if (action === 'apply') {
        const result = await disruptionApi.apply(workflow.id);
        setMessage(result.outcome);
      } else {
        const result = await disruptionApi.reject(workflow.id, reason);
        setMessage(result.outcome);
      }
      await load();
    } catch (e) {
      setMessage(errorMessage(e, 'The decision could not be recorded.'));
    } finally {
      setBusyId(null);
    }
  }

  const pending = useMemo(() => workflows.filter((w) => w.status === 'AwaitingApproval'), [workflows]);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">DISRUPTION RECOVERY</p>
          <h1>When a resource goes out of service</h1>
          <p className="page-sub">
            Four agents work out who is stranded and where each booking can go. Nothing moves until you approve it.
          </p>
        </div>
        <span className="badge">{pending.length} awaiting your approval</span>
      </header>

      {message && <p className="page-notice" role="status">{message}</p>}
      {error && <p className="page-notice" role="alert">{error}</p>}

      <section className="panel">
        <div className="panel-head">
          <div><h2>Report an outage</h2><p className="hint">The agents only read and propose.</p></div>
        </div>
        <form className="toolbar toolbar-wrap" onSubmit={startRecovery} aria-label="Report an outage" noValidate>
          <label>
            Unavailable{' '}
            <select
              className="filter-select"
              value={form.resourceId}
              aria-label="Unavailable resource"
              onChange={(e) => setForm({ ...form, resourceId: e.target.value })}
            >
              <option value="">Choose a resource…</option>
              {resourceOptions.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
          </label>
          <label>
            From{' '}
            <input type="date" aria-label="From" value={form.dateFrom}
              onChange={(e) => setForm({ ...form, dateFrom: e.target.value })} />
          </label>
          <label>
            To{' '}
            <input type="date" aria-label="To" value={form.dateTo}
              onChange={(e) => setForm({ ...form, dateTo: e.target.value })} />
          </label>
          <input
            type="text"
            aria-label="What happened"
            placeholder="What happened, and how would you rather recover?"
            value={form.objective}
            maxLength={500}
            onChange={(e) => setForm({ ...form, objective: e.target.value })}
          />
          <button className="btn btn-primary" type="submit" disabled={planning}>
            {planning ? 'Planning the recovery…' : 'Plan recovery'}
          </button>
        </form>
      </section>

      {loading && <p className="empty-state">Loading recovery plans…</p>}
      {!loading && workflows.length === 0 && (
        <p className="empty-state">No recovery plans yet.</p>
      )}

      {workflows.map((workflow) => {
        const trace = parseTrace(workflow);
        return (
          <article key={workflow.id} className="panel" aria-label={`Recovery plan: ${workflow.objective}`}>
            <div className="panel-head">
              <div>
                <h2>{workflow.objective}</h2>
                <p className="hint">
                  {formatDateTime(workflow.createdAt)} · {workflow.finalOutcome ?? workflow.status}
                </p>
              </div>
              <span className={`badge badge-${workflow.status === 'AwaitingApproval' ? 'amber' : 'slate'}`}>
                {workflow.status}
              </span>
            </div>

            {workflow.errorLog && <p className="page-notice" role="alert">{workflow.errorLog}</p>}
            {trace && <RecoveryEvidence trace={trace} />}

            {workflow.status === 'AwaitingApproval' && (
              <div className="toolbar toolbar-wrap">
                <input
                  type="text"
                  aria-label={`Reason for rejecting ${workflow.objective}`}
                  placeholder="Reason (needed to reject)"
                  value={reasons[workflow.id] ?? ''}
                  maxLength={500}
                  onChange={(e) => setReasons({ ...reasons, [workflow.id]: e.target.value })}
                />
                <button className="btn btn-primary" type="button" disabled={busyId === workflow.id}
                  onClick={() => void decide(workflow, 'apply')}>
                  Approve and move them
                </button>
                <button className="btn btn-danger" type="button" disabled={busyId === workflow.id}
                  onClick={() => void decide(workflow, 'reject')}>
                  Reject
                </button>
              </div>
            )}
          </article>
        );
      })}
    </div>
  );
}

/** Everything the manager needs to judge the plan, rather than trust it. */
function RecoveryEvidence({ trace }: { trace: DisruptionTrace }) {
  const noun = trace.impact?.resource_noun ?? 'resource';
  return (
    <>
      {trace.warnings.map((warning, i) => <p className="page-notice" key={i}>{warning}</p>)}

      {trace.impact && (
        <p className="cell-sub">
          {trace.impact.affected.length} booking(s) on {trace.impact.resource_name} ({noun}),{' '}
          {trace.impact.total_attendees} people, {trace.impact.revenue_at_risk.toLocaleString('en-LK', {
            style: 'currency', currency: 'LKR',
          })} at risk.
        </p>
      )}

      {trace.action && trace.action.proposals.length > 0 && (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr><th>Customer</th><th>Was</th><th>Proposed</th><th>Why</th></tr>
            </thead>
            <tbody>
              {trace.action.proposals.map((p) => (
                <tr key={p.booking_id}>
                  <td>{p.customer_name}</td>
                  <td>{formatDateTime(p.original_starts_at)}</td>
                  <td>
                    <strong>{kindLabel(p.kind)}</strong>
                    {p.proposed_starts_at && (
                      <div className="cell-sub">
                        {formatDateTime(p.proposed_starts_at)}
                        {p.proposed_resource_name ? ` · ${p.proposed_resource_name}` : ''}
                      </div>
                    )}
                  </td>
                  <td className="cell-sub">{p.explanation}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {trace.safety && (
        <ul className="stocksense-gate-checks" aria-label="Safety gate checks">
          {trace.safety.checks.map((check) => (
            <li key={check.rule} className={check.passed ? 'is-pass' : 'is-fail'}>
              <span aria-hidden="true">{check.passed ? '✓' : '!'}</span> {check.detail}
            </li>
          ))}
        </ul>
      )}

      {trace.agent_steps.length > 0 && (
        <p className="cell-sub">
          Agents: {trace.agent_steps.map((s) => `${s.agent} (${s.duration_ms}ms)`).join(' → ')} ·{' '}
          {trace.tool_calls.length} tool call(s)
        </p>
      )}
    </>
  );
}
