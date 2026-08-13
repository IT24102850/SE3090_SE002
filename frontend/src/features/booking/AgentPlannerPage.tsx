import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import {
  useApplyWorkflowMutation,
  useApproveWorkflowMutation,
  useGetBookingTypesQuery,
  useGetBranchesQuery,
  useGetWorkflowsQuery,
  useProposeScheduleMutation,
  useRejectWorkflowMutation,
} from '../../api/bookingApi';
import { formatTime } from '../../shared/dateUtils';
import type { AgentWorkflow, WorkflowStep } from './types';

const STATUS_TONE: Record<string, string> = {
  Pending: 'var(--color-warning, #d97706)',
  Approved: 'var(--color-primary)',
  NotRequired: 'var(--color-good)',
  Rejected: 'var(--color-critical)',
};

function parseSteps(planJson?: string | null): WorkflowStep[] {
  if (!planJson) return [];
  try {
    const plan = JSON.parse(planJson);
    return Array.isArray(plan?.steps) ? plan.steps : [];
  } catch {
    return [];
  }
}

export default function AgentPlannerPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: bookingTypes } = useGetBookingTypesQuery({ tenantId }, { skip: !tenantId });
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const { data: workflows, isLoading: workflowsLoading } = useGetWorkflowsQuery({ tenantId }, { skip: !tenantId });

  const [proposeSchedule, { isLoading: proposing }] = useProposeScheduleMutation();
  const [approveWorkflow] = useApproveWorkflowMutation();
  const [rejectWorkflow] = useRejectWorkflowMutation();
  const [applyWorkflow, { isLoading: applying }] = useApplyWorkflowMutation();

  const [objective, setObjective] = useState('Fit follow-up appointments this week');
  const [count, setCount] = useState(5);
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [branchId, setBranchId] = useState('');
  const [withinDays, setWithinDays] = useState(7);
  const [lastProposed, setLastProposed] = useState<AgentWorkflow | null>(null);

  const handlePropose = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!bookingTypeId) {
      show('Choose a booking type first.', 'error');
      return;
    }
    try {
      const workflow = await proposeSchedule({
        tenantId,
        objective,
        count,
        bookingTypeId,
        branchId: branchId || undefined,
        withinDays,
      }).unwrap();
      setLastProposed(workflow);
      show('Plan proposed.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not propose a plan.'), 'error');
    }
  };

  const handleApprove = async (id: string) => {
    try {
      await approveWorkflow(id).unwrap();
      show('Workflow approved.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not approve workflow.'), 'error');
    }
  };

  const handleReject = async (id: string) => {
    const reason = window.prompt('Reason for rejecting this plan?') ?? '';
    try {
      await rejectWorkflow({ id, reason }).unwrap();
      show('Workflow rejected.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not reject workflow.'), 'error');
    }
  };

  const handleApply = async (id: string) => {
    try {
      const result = await applyWorkflow(id).unwrap();
      show(result.message, 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not apply workflow.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">AI Planner</h1>
          <p className="page-subtitle">Propose a schedule from an objective, then approve and apply it.</p>
        </div>
      </div>

      <div className="card" style={{ padding: 20, marginBottom: 24 }}>
        <form onSubmit={handlePropose} className="form-grid">
          <div className="field field-full">
            <label>Objective</label>
            <input className="input" value={objective} onChange={(e) => setObjective(e.target.value)} placeholder='e.g. "Fit 5 follow-ups this week"' required />
          </div>
          <div className="field">
            <label>Booking type</label>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} required>
              <option value="">Select…</option>
              {bookingTypes?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
          <div className="field">
            <label>Branch</label>
            <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">All branches</option>
              {branches?.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </div>
          <div className="field">
            <label>How many bookings</label>
            <input className="input" type="number" min={1} max={200} value={count} onChange={(e) => setCount(Number(e.target.value))} required />
          </div>
          <div className="field">
            <label>Within next (days)</label>
            <input className="input" type="number" min={1} max={30} value={withinDays} onChange={(e) => setWithinDays(Number(e.target.value))} required />
          </div>
          <div className="field field-full">
            <button className="btn btn-primary" type="submit" disabled={proposing}>
              {proposing ? <span className="spinner" /> : 'Propose plan'}
            </button>
          </div>
        </form>
      </div>

      {lastProposed && (
        <div className="card" style={{ padding: 20, marginBottom: 24, borderColor: 'var(--color-primary)' }}>
          <p className="chart-title">Just proposed</p>
          <WorkflowCard
            workflow={lastProposed}
            onApprove={handleApprove}
            onReject={handleReject}
            onApply={handleApply}
            applying={applying}
          />
        </div>
      )}

      <p className="chart-title" style={{ marginBottom: 12 }}>All workflows</p>
      {workflowsLoading ? (
        <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading…</div></div>
      ) : !workflows || workflows.length === 0 ? (
        <div className="card"><div className="empty-state">No workflows proposed yet.</div></div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {workflows.map((w) => (
            <div className="card" style={{ padding: 20 }} key={w.id}>
              <WorkflowCard workflow={w} onApprove={handleApprove} onReject={handleReject} onApply={handleApply} applying={applying} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function WorkflowCard({
  workflow,
  onApprove,
  onReject,
  onApply,
  applying,
}: {
  workflow: AgentWorkflow;
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
  onApply: (id: string) => void;
  applying: boolean;
}) {
  const steps = parseSteps(workflow.planJson);
  const canApprove = workflow.approvalStatus === 'Pending';
  const canApply = (workflow.approvalStatus === 'Approved' || workflow.approvalStatus === 'NotRequired') && workflow.status !== 'Completed';

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <div>
          <strong>{workflow.objective}</strong>
          <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 2 }}>
            {steps.length} step(s) · {new Date(workflow.createdAt).toLocaleString()}
          </div>
        </div>
        <span
          style={{
            fontSize: 11,
            fontWeight: 700,
            padding: '4px 10px',
            borderRadius: 20,
            color: '#fff',
            background: STATUS_TONE[workflow.approvalStatus] ?? '#64748b',
          }}
        >
          {workflow.status}
        </span>
      </div>

      {steps.length > 0 && (
        <ul style={{ margin: '12px 0 0', paddingLeft: 18, fontSize: 13 }}>
          {steps.slice(0, 10).map((s, i) => (
            <li key={i}>
              {String(s.parameters?.resourceName ?? 'Resource')} — {formatTime(String(s.parameters?.startTime ?? ''))}
            </li>
          ))}
          {steps.length > 10 && <li>…and {steps.length - 10} more</li>}
        </ul>
      )}

      {workflow.finalOutcome && (
        <p style={{ fontSize: 12.5, color: 'var(--color-text-secondary)', marginTop: 10 }}>{workflow.finalOutcome}</p>
      )}

      <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
        {canApprove && (
          <>
            <button className="btn btn-primary btn-sm" onClick={() => onApprove(workflow.id)}>Approve</button>
            <button className="btn btn-secondary btn-sm" onClick={() => onReject(workflow.id)}>Reject</button>
          </>
        )}
        {canApply && (
          <button className="btn btn-primary btn-sm" onClick={() => onApply(workflow.id)} disabled={applying}>
            {applying ? <span className="spinner" /> : 'Apply to schedule'}
          </button>
        )}
      </div>
    </div>
  );
}
