import { useState } from 'react';
import PlatformLayout from './PlatformLayout';
import OtpPrompt from './OtpPrompt';
import {
  errorMessage,
  useApproveCopilotMutation,
  useCopilotRunQuery,
  useCopilotRunsQuery,
  useRejectCopilotMutation,
  useReviseCopilotMutation,
  useStartCopilotMutation,
  type CopilotIntervention,
  type CopilotRun,
} from './platformApi';

/* The platform owner's Agentic AI console.
 *
 * The screen is built around one claim, so it has to make that claim
 * visible: nothing here has happened yet. A run produces proposals and
 * stops. Applying them is a separate, deliberate act that asks for an
 * authenticator code — the same step-up as suspending a tenant — and the
 * page says so before the owner reaches the button rather than after.
 *
 * The full trace is shown, not a summary: which agent ran, which tools were
 * called, what validation refused and why. An owner approving a decision
 * they cannot inspect is just a slower version of letting the agent decide. */

const EXAMPLES = [
  'Reduce churn risk this month',
  'Recover unpaid renewals without giving away revenue',
  'Find businesses that signed up on a paid plan and never really started',
];

const n = (v: number) => v.toLocaleString();
const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—');
const money = (v: number, c: string) => `${c} ${v.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;

function statusPill(status: string) {
  const tone =
    status === 'Applied' ? 'pf-pill-good'
    : status === 'AwaitingApproval' ? 'pf-pill-accent'
    : status === 'PartiallyApplied' ? 'pf-pill-warn'
    : status === 'Failed' || status === 'Rejected' ? 'pf-pill-bad'
    : 'pf-pill-neutral';
  return <span className={`pf-pill ${tone}`}>{status}</span>;
}

function describe(i: CopilotIntervention): string {
  switch (i.kind) {
    case 'extend_term':
      return `Extend the term by ${i.extend_days} days`;
    case 'comp_plan':
      return `Give ${i.comp_plan_code} free for ${i.comp_months} months`;
    case 'winback_offer':
      return 'Send the win-back offer';
    case 'contact_owner':
      return 'A person should get in touch';
    default:
      return 'Take no action';
  }
}

export default function PlatformCopilotPage() {
  const [objective, setObjective] = useState('');
  const [maxInterventions, setMaxInterventions] = useState(5);
  const [maxCompMonths, setMaxCompMonths] = useState(12);
  const [openRunId, setOpenRunId] = useState<string | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [prompt, setPrompt] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const runs = useCopilotRunsQuery();
  const run = useCopilotRunQuery(openRunId!, { skip: !openRunId });
  const [start, { isLoading: starting }] = useStartCopilotMutation();
  const [approve, { isLoading: approving }] = useApproveCopilotMutation();
  const [reject, { isLoading: rejecting }] = useRejectCopilotMutation();
  const [revise, { isLoading: revising }] = useReviseCopilotMutation();

  const current = run.data;

  const go = async () => {
    setError(null);
    setNotice(null);
    try {
      const created = await start({ objective, maxInterventions, maxCompMonths, currency: 'LKR' }).unwrap();
      setOpenRunId(created.id);
      setChosen(new Set((created.validation?.accepted ?? []).map((i) => i.tenant_id)));
      setObjective('');
    } catch (err) {
      setError(errorMessage(err, 'The copilot could not be run.'));
    }
  };

  const open = (id: string) => {
    setOpenRunId(id);
    setChosen(new Set());
    setNotice(null);
    setError(null);
  };

  const confirmApply = async (code: string, reason: string) => {
    if (!current) return;
    setError(null);
    try {
      const result = await approve({
        id: current.id,
        tenantIds: [...chosen],
        reason,
        otp: code,
      }).unwrap();
      setNotice(
        result.status === 'Applied'
          ? 'Applied. Every approved intervention went through.'
          : `Partly applied — see the outcome below for what failed.`,
      );
      setPrompt(false);
    } catch (err) {
      setError(errorMessage(err, 'The changes were refused.'));
    }
  };

  const accepted = current?.validation?.accepted ?? [];
  const canDecide = current?.status === 'AwaitingApproval';

  return (
    <PlatformLayout title="Copilot">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Agentic AI · platform operations</div>
          <h1>Ask the copilot to look at the tenant base</h1>
          <p>
            Four agents plan, read the platform&rsquo;s own records, propose an intervention per business at risk, and
            check every proposal against policy. Nothing is ever carried out by the agent &mdash; applying a proposal
            needs your authenticator code.
          </p>
        </div>
      </div>

      {notice && <div className="pf-ok" role="status">{notice}</div>}
      {error && <div className="pf-alert pf-alert-bad"><div><b>{error}</b></div></div>}

      {/* ── Start a run ───────────────────────────────────────────── */}
      <div className="pf-card">
        <div className="pf-card-head"><h2>New run</h2><span>Read-only until you approve something</span></div>
        <div className="pf-form">
          <div className="pf-field">
            <label htmlFor="pf-objective">What should it look into?</label>
            <textarea
              id="pf-objective"
              className="pf-input"
              rows={3}
              maxLength={1000}
              value={objective}
              onChange={(e) => setObjective(e.target.value)}
              placeholder="Reduce churn risk this month"
            />
          </div>
          <div className="pf-filters">
            {EXAMPLES.map((e) => (
              <button key={e} type="button" className="pf-btn pf-btn-sm" onClick={() => setObjective(e)}>
                {e}
              </button>
            ))}
          </div>
          <div className="pf-filters">
            <label className="pf-count">
              At most{' '}
              <input
                className="pf-input"
                type="number"
                min={1}
                max={25}
                value={maxInterventions}
                onChange={(e) => setMaxInterventions(Number(e.target.value))}
                style={{ width: 70 }}
              />{' '}
              businesses
            </label>
            <label className="pf-count">
              Comp at most{' '}
              <input
                className="pf-input"
                type="number"
                min={1}
                max={24}
                value={maxCompMonths}
                onChange={(e) => setMaxCompMonths(Number(e.target.value))}
                style={{ width: 70 }}
              />{' '}
              months
            </label>
            <span className="pf-filters-spacer" />
            <button
              type="button"
              className="pf-btn pf-btn-primary"
              disabled={starting || objective.trim().length < 8}
              onClick={go}
            >
              {starting ? 'Running the agents…' : 'Run the copilot'}
            </button>
          </div>
          <p className="pf-count">
            These two are hard ceilings. The safety agent trims anything past them, so a run cannot spend more than you
            allowed here even if the model asks it to.
          </p>
        </div>
      </div>

      {/* ── The open run ──────────────────────────────────────────── */}
      {openRunId && run.isLoading && <div className="pf-empty">Loading the run…</div>}
      {current && <RunDetail
        run={current}
        accepted={accepted}
        chosen={chosen}
        setChosen={setChosen}
        canDecide={canDecide}
        busy={approving || rejecting || revising}
        onApply={() => setPrompt(true)}
        onReject={async (reason) => {
          try {
            await reject({ id: current.id, reason }).unwrap();
            setNotice('Recorded as rejected. Nothing was changed on any business.');
          } catch (err) { setError(errorMessage(err, 'Could not record that.')); }
        }}
        onRevise={async (reason) => {
          try {
            await revise({ id: current.id, reason }).unwrap();
            setNotice('Sent back for revision. Run it again with a sharper objective.');
          } catch (err) { setError(errorMessage(err, 'Could not record that.')); }
        }}
      />}

      {/* ── History ───────────────────────────────────────────────── */}
      <div className="pf-card">
        <div className="pf-card-head"><h2>Previous runs</h2><span>Every run is kept, approved or not</span></div>
        <div className="pf-table-wrap">
          <table className="pf-table">
            <thead>
              <tr>
                <th>Objective</th><th>Status</th><th>Driven by</th><th>Held cost</th><th>Decided by</th><th>When</th><th />
              </tr>
            </thead>
            <tbody>
              {runs.isLoading && <tr><td colSpan={7} className="pf-empty">Loading…</td></tr>}
              {!runs.isLoading && (runs.data?.length ?? 0) === 0 && (
                <tr><td colSpan={7} className="pf-empty">No runs yet.</td></tr>
              )}
              {runs.data?.map((r) => (
                <tr key={r.id}>
                  <td>{r.objective}</td>
                  <td>{statusPill(r.status)}</td>
                  <td>
                    <span className={`pf-pill ${r.modelDriven ? 'pf-pill-accent' : 'pf-pill-neutral'}`}>
                      {r.modelDriven ? 'model' : 'deterministic'}
                    </span>
                  </td>
                  <td>{r.estimatedCost > 0 ? money(r.estimatedCost, r.currency) : '—'}</td>
                  <td>{r.decidedByEmail ?? '—'}</td>
                  <td>{when(r.createdAt)}</td>
                  <td>
                    <button type="button" className="pf-btn pf-btn-sm" onClick={() => open(r.id)}>Open</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {prompt && current && (
        <OtpPrompt
          title={`Apply ${chosen.size || accepted.length} intervention(s)`}
          description={
            'This is the only step that changes anything. It extends terms and comps plans on the businesses you '
            + 'selected, and is written to the audit log against your account.'
          }
          confirmLabel="Apply now"
          busy={approving}
          error={error}
          onConfirm={confirmApply}
          onCancel={() => { setPrompt(false); setError(null); }}
        />
      )}
    </PlatformLayout>
  );
}

function RunDetail({
  run, accepted, chosen, setChosen, canDecide, busy, onApply, onReject, onRevise,
}: {
  run: CopilotRun;
  accepted: CopilotIntervention[];
  chosen: Set<string>;
  setChosen: (s: Set<string>) => void;
  canDecide: boolean;
  busy: boolean;
  onApply: () => void;
  onReject: (reason: string) => void;
  onRevise: (reason: string) => void;
}) {
  const steps = run.plan?.plan ?? [];
  const risks = run.analysis?.at_risk ?? [];
  const verdicts = run.validation?.verdicts ?? [];
  const refused = verdicts.filter((v) => !v.accepted);

  const toggle = (id: string) => {
    const next = new Set(chosen);
    if (next.has(id)) next.delete(id); else next.add(id);
    setChosen(next);
  };

  return (
    <>
      <div className="pf-card">
        <div className="pf-card-head">
          <h2>{run.objective}</h2>
          <span>{statusPill(run.status)} · {when(run.createdAt)}</span>
        </div>

        {!run.modelDriven && (
          <div className="pf-alert pf-alert-warn">
            <div>
              <b>The language model was unreachable for this run.</b>
              The agents, the tools and the safety gate all still ran &mdash; only the reading of your objective was
              simpler, and the proposals are the conservative fallback set.
            </div>
          </div>
        )}

        {run.errorLog && <div className="pf-alert pf-alert-bad"><div><b>{run.errorLog}</b></div></div>}

        {run.plan && (
          <>
            <h3 className="pf-eyebrow">What it understood</h3>
            <p>{run.plan.interpreted_goal}</p>
            <ul className="pf-list">
              {steps.map((s) => (
                <li key={s.order} className="pf-audit-row">
                  <i aria-hidden="true" />
                  <span>
                    <span className="pf-mono">{s.assigned_agent}</span>
                    <small>{s.description}</small>
                  </span>
                  <time>step {s.order}</time>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>

      {risks.length > 0 && (
        <div className="pf-card">
          <div className="pf-card-head">
            <h2>What it found</h2>
            <span>{run.analysis?.platform_summary}</span>
          </div>
          <div className="pf-table-wrap">
            <table className="pf-table">
              <thead>
                <tr><th>Business</th><th>Plan</th><th>Status</th><th>Risk</th><th>Monthly</th><th>Why</th></tr>
              </thead>
              <tbody>
                {risks.map((r) => (
                  <tr key={r.tenant_id}>
                    <td><b>{r.tenant_name}</b></td>
                    <td style={{ textTransform: 'capitalize' }}>{r.plan_code}</td>
                    <td>{r.status}</td>
                    <td>
                      <span className={`pf-pill ${r.risk_score >= 0.8 ? 'pf-pill-bad' : r.risk_score >= 0.5 ? 'pf-pill-warn' : 'pf-pill-neutral'}`}>
                        {Math.round(r.risk_score * 100)}%
                      </span>
                    </td>
                    <td>{n(Math.round(r.monthly_value))}</td>
                    <td><small>{r.risk_factors.join(' ')}</small></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {accepted.length > 0 && (
        <div className="pf-card">
          <div className="pf-card-head">
            <h2>Held for your approval</h2>
            <span>
              {accepted.length} intervention(s) · {money(run.validation?.total_estimated_cost ?? 0, run.currency)} at stake
            </span>
          </div>

          <div className="pf-alert pf-alert-warn">
            <div>
              <b>Nothing here has happened.</b>
              These are proposals. The agent has no way to carry any of them out &mdash; applying them needs your
              authenticator code, below.
            </div>
          </div>

          <div className="pf-table-wrap">
            <table className="pf-table">
              <thead>
                <tr><th /><th>Business</th><th>Proposed</th><th>Costs</th><th>Protects</th><th>Why</th></tr>
              </thead>
              <tbody>
                {accepted.map((i) => (
                  <tr key={i.tenant_id}>
                    <td>
                      <input
                        type="checkbox"
                        checked={chosen.has(i.tenant_id)}
                        onChange={() => toggle(i.tenant_id)}
                        disabled={!canDecide}
                        aria-label={`Approve the intervention for ${i.tenant_name}`}
                      />
                    </td>
                    <td><b>{i.tenant_name}</b></td>
                    <td>{describe(i)}</td>
                    <td>{i.estimated_cost > 0 ? money(i.estimated_cost, run.currency) : '—'}</td>
                    <td>{i.protected_value > 0 ? money(i.protected_value, run.currency) : '—'}</td>
                    <td><small>{i.rationale}</small></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {canDecide && (
            <div className="pf-modal-actions" style={{ marginTop: 14 }}>
              <button type="button" className="pf-btn pf-btn-primary" disabled={busy || chosen.size === 0} onClick={onApply}>
                Apply {chosen.size} selected
              </button>
              <button type="button" className="pf-btn" disabled={busy} onClick={() => onRevise('Objective needs sharpening')}>
                Send back
              </button>
              <button type="button" className="pf-btn pf-btn-danger" disabled={busy} onClick={() => onReject('Not worth it')}>
                Reject
              </button>
            </div>
          )}
        </div>
      )}

      {refused.length > 0 && (
        <div className="pf-card">
          <div className="pf-card-head">
            <h2>Refused by validation</h2>
            <span>Deterministic checks, no model involved</span>
          </div>
          <ul className="pf-list">
            {refused.map((v, i) => (
              <li key={`${v.tenant_id}-${i}`} className="pf-audit-row">
                <i aria-hidden="true" />
                <span><span className="pf-mono">{v.kind}</span><small>{v.reason}</small></span>
              </li>
            ))}
          </ul>
          {(run.validation?.validation_notes ?? []).map((note) => (
            <p key={note} className="pf-count">{note}</p>
          ))}
        </div>
      )}

      {run.outcome && run.outcome.length > 0 && (
        <div className="pf-card">
          <div className="pf-card-head"><h2>What was carried out</h2><span>Decided by {run.decidedByEmail}</span></div>
          <div className="pf-table-wrap">
            <table className="pf-table">
              <thead><tr><th>Business</th><th>Intervention</th><th>Result</th></tr></thead>
              <tbody>
                {run.outcome.map((o, i) => (
                  <tr key={`${o.tenantId}-${i}`}>
                    <td>{o.tenantName}</td>
                    <td>{o.kind}</td>
                    <td>
                      <span className={`pf-pill ${o.applied ? 'pf-pill-good' : 'pf-pill-bad'}`}>
                        {o.applied ? 'applied' : 'failed'}
                      </span>{' '}
                      <small>{o.detail}</small>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </>
  );
}
