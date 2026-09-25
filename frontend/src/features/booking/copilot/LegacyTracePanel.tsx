import { useState } from 'react';
import type { AgentWorkflow, ExecutionTrace, ValidationResultsSummary } from '../types';

/* Execution trace for workflows that predate the Schedule Copilot - chiefly
 * customer find-and-book runs, whose trace ASP.NET Core stores in its own
 * camelCase summary shape. Kept so those runs stay auditable from the same
 * page as the Copilot's. */
function parseJson<T>(raw?: string | null): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    // A stored trace that will not parse must not take the whole card down
    // with it - the plan and the approval controls are still usable.
    return null;
  }
}

/* Execution trace (spec 9.1 Observability).
 *
 * The plan says what the agents decided. This says how they got there: which
 * agent ran and for how long, which allow-listed tools it called, and which
 * model answered after how many attempts. The retry column is the part worth
 * showing rather than hiding - a workflow that quietly survived two 503s is
 * evidence the safety net works, and it is invisible everywhere else. */
export function ExecutionTracePanel({ workflow }: { workflow: AgentWorkflow }) {
  const [open, setOpen] = useState(false);
  const trace = parseJson<ExecutionTrace>(workflow.toolResultsJson);
  const validation = parseJson<ValidationResultsSummary>(workflow.validationResults);
  if (!trace && !validation) return null;

  const steps = trace?.agentSteps ?? [];
  const tools = trace?.toolCalls ?? [];
  const llm = trace?.llmCalls ?? [];
  const retries = llm.filter((c) => c.attempt > 1).length;
  const totalMs = steps.reduce((sum, s) => sum + (s.durationMs ?? 0), 0);

  return (
    <div style={{ marginTop: 12, borderTop: '1px solid var(--color-border)', paddingTop: 10 }}>
      <button
        className="btn btn-ghost btn-sm"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        style={{ padding: 0, fontSize: 12, fontWeight: 700 }}
      >
        {open ? '▾' : '▸'} Execution trace
        <span style={{ fontWeight: 500, color: 'var(--color-text-muted)', marginLeft: 6 }}>
          {steps.length} agent step(s) · {tools.length} tool call(s) · {totalMs}ms
          {retries > 0 && ` · ${retries} retry/ies`}
        </span>
      </button>

      {open && (
        <div style={{ marginTop: 10, display: 'grid', gap: 10, fontSize: 12 }}>
          {typeof trace?.plannerConfidence === 'number' && (
            <div>
              <b>Planner confidence:</b> {Math.round(trace.plannerConfidence * 100)}%
              {trace.rankingCriteria?.length ? ` · ranked on ${trace.rankingCriteria.join(', ')}` : ''}
            </div>
          )}

          {trace?.predictedConflicts?.length ? (
            <div>
              <b>Predicted conflicts</b>
              <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                {trace.predictedConflicts.map((c, i) => (
                  <li key={i}>{c.kind} ({Math.round(c.likelihood * 100)}%) — {c.description}</li>
                ))}
              </ul>
            </div>
          ) : null}

          {steps.length > 0 && (
            <div>
              <b>Agents</b>
              <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                {steps.map((s, i) => (
                  <li key={i} style={{ color: s.ok ? undefined : 'var(--color-critical)' }}>
                    {s.agent} — {s.durationMs}ms {s.ok ? '' : `· failed: ${s.error ?? 'unknown error'}`}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {tools.length > 0 && (
            <div>
              <b>Allow-listed tool calls</b>
              <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                {tools.map((t, i) => (
                  <li key={i} style={{ color: t.success ? undefined : 'var(--color-critical)' }}>
                    {t.tool} <span style={{ color: 'var(--color-text-muted)' }}>({t.agent})</span> — {t.durationMs}ms
                    {t.success ? '' : ` · failed: ${t.error ?? 'unknown error'}`}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {llm.length > 0 && (
            <div>
              <b>Model calls</b>
              <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                {llm.map((c, i) => (
                  <li key={i} style={{ color: c.ok ? undefined : 'var(--color-warning)' }}>
                    {c.model} · attempt {c.attempt} — {c.durationMs}ms
                    {c.ok ? '' : ` · ${c.error ?? 'failed'}`}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {validation && (
            <div>
              <b>Validation</b>
              <ul style={{ margin: '4px 0 0', paddingLeft: 18 }}>
                <li>Allowed: {String(validation.isAllowed ?? '—')}</li>
                <li>Needed approval: {String(validation.requiresHumanApproval ?? '—')}</li>
                {validation.rejectionReason && <li>Rejected: {validation.rejectionReason}</li>}
                {validation.notes?.map((n, i) => <li key={i}>{n}</li>)}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
