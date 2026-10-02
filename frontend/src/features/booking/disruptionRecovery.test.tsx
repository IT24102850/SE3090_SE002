import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../store/authSlice';
import type { DisruptionWorkflow } from './disruptionApi';

/* The manager's view of a disruption recovery. What matters here is that the
 * evidence is on screen before the approve button is: the affected bookings,
 * what the agents propose, and every check the deterministic gate ran. */

vi.mock('./disruptionApi', async () => {
  const actual = await vi.importActual<typeof import('./disruptionApi')>('./disruptionApi');
  return {
    ...actual,
    disruptionApi: { list: vi.fn(), plan: vi.fn(), apply: vi.fn(), reject: vi.fn() },
  };
});
vi.mock('../../api/bookingApi', () => ({
  useGetResourcesQuery: () => ({ data: [{ id: 'r1', name: 'Dr Silva' }] }),
}));

const { disruptionApi } = await import('./disruptionApi');
const { default: DisruptionRecoveryPage } = await import('./DisruptionRecoveryPage');
const api = vi.mocked(disruptionApi);

const trace = {
  status: 'AwaitingApproval',
  business_type: 'Clinic',
  impact: {
    resource_name: 'Dr Silva',
    resource_noun: 'doctor',
    affected: [{
      booking_id: 'b1', customer_name: 'Nimal', starts_at: '2026-12-01T09:00:00Z',
      ends_at: '2026-12-01T10:00:00Z', attendee_count: 1, deposit_paid: true,
      priority: 0.8, priority_reason: 'deposit already paid, starts within 24 hours',
    }],
    total_attendees: 1,
    revenue_at_risk: 5000,
    warnings: [],
  },
  action: {
    proposals: [{
      booking_id: 'b1', customer_name: 'Nimal', kind: 'MoveResource' as const,
      original_starts_at: '2026-12-01T09:00:00Z', original_ends_at: '2026-12-01T10:00:00Z',
      proposed_resource_id: 'r2', proposed_resource_name: 'Dr Perera',
      proposed_starts_at: '2026-12-01T09:00:00Z', proposed_ends_at: '2026-12-01T10:00:00Z',
      explanation: 'Same time, with Dr Perera instead of Dr Silva.', confidence: 0.9,
    }],
    unresolved: [],
    notes: [],
  },
  safety: {
    is_allowed: true, requires_human_approval: true, rejection_reason: null,
    checks: [
      { rule: 'no_conflict', passed: true, detail: 'Every destination slot was re-checked and is free.' },
      { rule: 'specialty_respected', passed: false, detail: '1 substitute(s) do not match the required specialty.' },
    ],
    rejected_booking_ids: [],
  },
  warnings: [],
  error: null,
  agent_steps: [{ agent: 'DisruptionPlannerAgent', duration_ms: 12, ok: true, error: null }],
  tool_calls: [{ tool: 'list_affected_bookings', agent: 'ImpactAnalysisAgent', duration_ms: 4, success: true }],
};

function workflow(overrides: Partial<DisruptionWorkflow> = {}): DisruptionWorkflow {
  return {
    id: 'w1',
    objective: 'Dr Silva is off sick',
    status: 'AwaitingApproval',
    approvalStatus: 'Pending',
    finalOutcome: '1 booking(s) affected, 1 with a proposed move, 0 needing your decision.',
    errorLog: null,
    createdAt: '2026-11-30T08:00:00Z',
    completedAt: null,
    trace: JSON.stringify(trace),
    ...overrides,
  };
}

function renderPage() {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: {
        user: { id: 'u1', email: 'm@t.local', fullName: 'Manager', role: 'Manager' as const, tenantId: 't1' },
        token: 'jwt', isAuthenticated: true, loading: false, error: null,
      },
    },
  });
  return render(
    <Provider store={store}>
      <MemoryRouter><DisruptionRecoveryPage /></MemoryRouter>
    </Provider>,
  );
}

describe('DisruptionRecoveryPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.list.mockResolvedValue([workflow()]);
  });

  it('shows who is affected and what is proposed for them', async () => {
    renderPage();

    const plan = await screen.findByRole('article', { name: /Dr Silva is off sick/ });
    expect(within(plan).getByText('Nimal')).toBeInTheDocument();
    expect(within(plan).getByText('Same time, different resource')).toBeInTheDocument();
    expect(within(plan).getByText(/Dr Perera instead of Dr Silva/)).toBeInTheDocument();
  });

  it('shows every safety check, including the ones that failed', async () => {
    renderPage();

    const checks = await screen.findByRole('list', { name: 'Safety gate checks' });
    expect(within(checks).getByText(/re-checked and is free/)).toBeInTheDocument();
    expect(within(checks).getByText(/do not match the required specialty/)).toBeInTheDocument();
  });

  it('applies the recovery and reports the outcome', async () => {
    api.apply.mockResolvedValue({ workflowId: 'w1', moved: [{ bookingId: 'b1' }], skipped: [], outcome: '1 booking(s) moved, 0 skipped.' });
    renderPage();

    fireEvent.click(await screen.findByRole('button', { name: 'Approve and move them' }));

    await waitFor(() => expect(api.apply).toHaveBeenCalledWith('w1'));
    expect(await screen.findByText('1 booking(s) moved, 0 skipped.')).toBeInTheDocument();
  });

  it('will not reject without a reason', async () => {
    renderPage();

    fireEvent.click(await screen.findByRole('button', { name: 'Reject' }));

    expect(await screen.findByText(/Give a reason of at least 3 characters/)).toBeInTheDocument();
    expect(api.reject).not.toHaveBeenCalled();
  });

  it('sends the reason when rejecting', async () => {
    api.reject.mockResolvedValue({ outcome: 'Rejected: I will call them. Nothing was moved.' });
    renderPage();

    fireEvent.change(await screen.findByLabelText(/Reason for rejecting/), { target: { value: 'I will call them' } });
    fireEvent.click(screen.getByRole('button', { name: 'Reject' }));

    await waitFor(() => expect(api.reject).toHaveBeenCalledWith('w1', 'I will call them'));
  });

  it('needs a resource and a description before planning', async () => {
    renderPage();
    await screen.findByRole('article', { name: /Dr Silva is off sick/ });

    fireEvent.click(screen.getByRole('button', { name: 'Plan recovery' }));

    expect(await screen.findByText('Choose the resource that is unavailable.')).toBeInTheDocument();
    expect(api.plan).not.toHaveBeenCalled();
  });

  it('plans a recovery from the form', async () => {
    api.plan.mockResolvedValue({ workflowId: 'w2', status: 'AwaitingApproval', trace: trace as never });
    renderPage();
    await screen.findByRole('article', { name: /Dr Silva is off sick/ });

    fireEvent.change(screen.getByLabelText('Which resource is unavailable?'), { target: { value: 'r1' } });
    fireEvent.change(screen.getByLabelText(/What happened, and how would you rather recover/), { target: { value: 'Dr Silva is off sick' } });
    fireEvent.click(screen.getByRole('button', { name: 'Plan recovery' }));

    await waitFor(() => expect(api.plan).toHaveBeenCalledWith(expect.objectContaining({
      resourceId: 'r1',
      objective: 'Dr Silva is off sick',
    })));
  });

  it('offers no decision buttons once a plan is completed', async () => {
    api.list.mockResolvedValue([workflow({ status: 'Completed', approvalStatus: 'Approved' })]);
    renderPage();

    await screen.findByRole('article', { name: /Dr Silva is off sick/ });
    expect(screen.queryByRole('button', { name: 'Approve and move them' })).not.toBeInTheDocument();
  });

  it('shows an empty state when there is nothing to review', async () => {
    api.list.mockResolvedValue([]);
    renderPage();

    expect(await screen.findByText('No recovery plans yet.')).toBeInTheDocument();
  });

  it('reports a failed load', async () => {
    api.list.mockRejectedValue({ response: { data: { message: 'Forbidden' } } });
    renderPage();

    expect(await screen.findByRole('alert')).toHaveTextContent('Forbidden');
  });
});
