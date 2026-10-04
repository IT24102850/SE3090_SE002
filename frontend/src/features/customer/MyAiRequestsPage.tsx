import { useGetMyWorkflowsQuery } from '../../api/bookingApi';
import type { AgentWorkflow } from '../booking/types';
import { useNavigate } from 'react-router-dom';
import './customer.css';

function statusVisual(status: string) {
  switch (status) {
    case 'AwaitingApproval':
    case 'Pending':
      return { label: 'Awaiting approval', className: 'status-warning' };
    case 'Approved':
      return { label: 'Approved', className: 'status-info' };
    case 'Completed':
      return { label: 'Confirmed', className: 'status-success' };
    case 'Rejected':
      return { label: 'Declined', className: 'status-danger' };
    case 'Failed':
      return { label: 'Could not complete', className: 'status-danger' };
    default:
      return { label: status || 'Unknown', className: 'status-muted' };
  }
}

function RequestCard({ workflow }: { workflow: AgentWorkflow }) {
  const visual = statusVisual(workflow.status);
  const detail = workflow.finalOutcome || workflow.errorLog;

  return (
    <article className="card customer-ai-request-card">
      <div className="customer-ai-request-card__body">
        <h2>{workflow.objective}</h2>
        <span className={`customer-ai-request-status ${visual.className}`}>{visual.label}</span>
        {detail && <p>{detail}</p>}
        <time dateTime={workflow.createdAt}>
          Submitted {new Date(workflow.createdAt).toLocaleString()}
        </time>
      </div>
    </article>
  );
}

export default function MyAiRequestsPage() {
  const navigate = useNavigate();
  const { data: workflows = [], isLoading, isFetching, isError, refetch } = useGetMyWorkflowsQuery();

  return (
    <main className="cust-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">My AI requests</h1>
          <p className="page-subtitle">Track every booking request sent to the Unify assistant.</p>
        </div>
        <button type="button" className="btn btn-secondary" onClick={() => navigate('/ai-planner')}>
          New AI request
        </button>
      </div>
      {isError && (
        <div className="cust-note" role="alert">
          Could not load your AI requests. <button type="button" className="btn btn-secondary" onClick={() => void refetch()}>Retry</button>
        </div>
      )}
      {isLoading && <div className="loading-state">Loading your requests…</div>}
      {!isLoading && !isError && workflows.length === 0 && (
        <section className="card chart-card">
          <h2>No AI booking requests yet</h2>
          <p className="cust-note">Use the AI planner to describe what you need and find a suitable booking.</p>
          <button type="button" className="btn btn-primary" onClick={() => navigate('/ai-planner')}>Open AI planner</button>
        </section>
      )}
      {!isLoading && !isError && workflows.length > 0 && (
        <section className="customer-ai-request-list" aria-busy={isFetching}>
          {workflows.map((workflow) => <RequestCard key={workflow.id} workflow={workflow} />)}
        </section>
      )}
    </main>
  );
}
