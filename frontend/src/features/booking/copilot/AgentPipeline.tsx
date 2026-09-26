import { useEffect, useState } from 'react';
import { AGENT_META, type AgentName, type CopilotTrace } from './copilotTypes';

const ORDER: AgentName[] = ['PlannerAgent', 'DomainAnalysisAgent', 'ActionToolAgent', 'ValidationSafetyAgent'];

const RUNNING_COPY: Record<AgentName, string> = {
  PlannerAgent: 'Reading the objective and writing a plan…',
  DomainAnalysisAgent: 'Checking working hours, current load and no-show history…',
  ActionToolAgent: 'Searching real open slots and optimising the schedule…',
  ValidationSafetyAgent: 'Re-verifying every slot and applying the business rules…',
};

/* The four agents as a pipeline.
 *
 * While a run is in flight the request is a single synchronous call, so the
 * page cannot know which agent is working. It advances a highlight at a
 * plausible pace instead and says so plainly in the caption ("working") -
 * it never shows a timing it does not have. Once the trace arrives every
 * node shows the real duration the agent service measured. */
export function AgentPipeline({ trace, running }: { trace?: CopilotTrace | null; running?: boolean }) {
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (!running) return;
    setTick(0);
    const id = window.setInterval(() => setTick((t) => t + 1), 2600);
    return () => window.clearInterval(id);
  }, [running]);

  const steps = new Map((trace?.agent_steps ?? []).map((s) => [s.agent, s]));
  const active = running ? ORDER[Math.min(tick, ORDER.length - 1)] : null;

  return (
    <div>
      <div className="cop-pipe" role="list" aria-label="Agent pipeline">
        {ORDER.map((agent, i) => {
          const meta = AGENT_META[agent];
          const step = steps.get(agent);
          const state = running
            ? agent === active ? 'is-active' : i < ORDER.indexOf(active!) ? 'is-done' : 'is-waiting'
            : step ? (step.ok ? 'is-done' : 'is-failed') : 'is-waiting';
          return (
            <div
              key={agent}
              role="listitem"
              className={`cop-node ${state}`}
              style={{ ['--agent' as string]: meta.tone }}
              aria-current={agent === active ? 'step' : undefined}
            >
              <div className="cop-node-top">
                <span className="cop-node-dot" aria-hidden="true">{i + 1}</span>
                <b>{meta.short}</b>
              </div>
              <p>{meta.role}</p>
              <div className="cop-node-time">
                {running
                  ? agent === active ? 'working…' : i < ORDER.indexOf(active!) ? 'handed on' : 'queued'
                  : step
                    ? step.ok ? `${(step.duration_ms / 1000).toFixed(step.duration_ms < 1000 ? 2 : 1)}s` : 'stopped here'
                    : 'did not run'}
              </div>
            </div>
          );
        })}
      </div>
      {running && active && (
        <p className="cop-running-copy" aria-live="polite">
          <span className="spinner spinner-dark" /> {RUNNING_COPY[active]}
        </p>
      )}
    </div>
  );
}
