import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { bookingApi } from '../../../api/bookingApi';
import authReducer from '../../../store/authSlice';
import { ToastProvider } from '../../../shared/components/Toast';
import type { AgentWorkflow } from '../types';
import { CopilotResult } from './CopilotResult';
import type { CopilotTrace } from './copilotTypes';
import ScheduleCopilotPage from './ScheduleCopilotPage';

/* The Schedule Copilot UI renders the agents' stored trace and offers only
 * the decisions the backend will accept - these tests pin both. */

const TENANT_ID = '11111111-1111-1111-1111-111111111111';

function trace(overrides: Partial<CopilotTrace> = {}): CopilotTrace {
  const start = '2030-01-07T09:00:00Z';
  return {
    workflow_type: 'schedule-copilot',
    workflow_id: 'wf-1',
    objective: 'Fit 2 follow-ups this week',
    business_type: 'Clinic',
    status: 'Completed',
    constraints: { date_range: { date_from: '2030-01-07', date_to: '2030-01-11' }, priority_rules: ['prefer_mornings'], target_count: 2, duration_minutes: 60 },
    planner: {
      plan: [
        { order: 1, action: 'Rank candidate resources', assigned_agent: 'DomainAnalysisAgent', description: 'Rank them.', tools: ['check_staff_schedule'] },
        { order: 2, action: 'Build the schedule', assigned_agent: 'ActionToolAgent', description: 'Find slots.', tools: ['query_resource_availability'] },
        { order: 3, action: 'Validate', assigned_agent: 'ValidationSafetyAgent', description: 'Gate.', tools: ['detect_conflicts'] },
      ],
      assigned_agents: ['DomainAnalysisAgent', 'ActionToolAgent', 'ValidationSafetyAgent'],
      predicted_conflicts: [{ kind: 'capacity_exceeded', description: 'Tight week.', likelihood: 0.4 }],
      confidence_score: 0.82,
      intent: { priority_rules: ['prefer_mornings'], min_gap_minutes: 15, weekdays: [3], time_window: 'morning', rationale: '' },
      summary: 'Two morning follow-ups.',
      used_fallback: false,
    },
    analysis: {
      resources: [{
        resource_id: 'r1', resource_name: 'Dr. Perera', working_days_in_range: 5, booked_minutes_in_range: 600,
        capacity_minutes_in_range: 2400, utilisation_pct: 25, no_show_rate: 0.1, no_show_sample: 20,
        max_daily_minutes: 480, lunch_start: '12:00', lunch_end: '13:00', score: 78, reasons: ['Open 5 of 5 day(s).'],
      }],
      average_booking_value: 45,
      insights: ['Dr. Perera ranks first.'],
    },
    action: {
      proposals: [0, 1].map((i) => ({
        resource_id: 'r1', resource_name: 'Dr. Perera',
        start: start.replace('09', String(9 + i).padStart(2, '0')), end: start.replace('09', String(10 + i).padStart(2, '0')),
        duration_minutes: 60, score: 60 - i, score_breakdown: { resource: 31 }, reasons: ['Matches the time-of-day preference.'],
        no_show_risk: 0.1, travel_minutes_from_previous: null,
      })),
      skipped: [{ resource_name: 'Dr. Perera', start, reason: 'Crosses the lunch break' }],
      candidates_considered: 40,
      notes: [],
    },
    safety: {
      is_allowed: true, requires_human_approval: false, approval_reasons: [], rejection_reason: null,
      checks: [
        { rule: 'no_double_booking', status: 'pass', detail: 'No two proposals share a resource at the same time.' },
        { rule: 'daily_hours', status: 'pass', detail: 'Within cap.' },
        { rule: 'coverage', status: 'pass', detail: 'Met the full request (2/2).' },
      ],
    },
    metrics: {
      requested: 2, proposed: 2, coverage_pct: 100, resources_used: 1, days_used: 1, expected_no_shows: 0.2,
      estimated_revenue: 90, estimated_revenue_usd: 90, currency: 'USD', utilisation_before_pct: 25, utilisation_after_pct: 30,
    },
    warnings: ['Limited to Thursday as the objective asked.'],
    agent_steps: [
      { agent: 'PlannerAgent', duration_ms: 6100, ok: true },
      { agent: 'DomainAnalysisAgent', duration_ms: 120, ok: true },
      { agent: 'ActionToolAgent', duration_ms: 340, ok: true },
      { agent: 'ValidationSafetyAgent', duration_ms: 80, ok: true },
    ],
    tool_calls: [
      { tool: 'check_staff_schedule', agent: 'DomainAnalysisAgent', duration_ms: 12, success: true },
      { tool: 'query_resource_availability', agent: 'ActionToolAgent', duration_ms: 20, success: true },
      { tool: 'detect_conflicts', agent: 'ValidationSafetyAgent', duration_ms: 15, success: true },
    ],
    llm_calls: [
      { model: 'gemini-3.5-flash', attempt: 1, duration_ms: 900, ok: false, error: '429 quota' },
      { model: 'gemini-flash-lite-latest', attempt: 1, duration_ms: 5200, ok: true },
    ],
    error: null,
    created_at: '2030-01-06T10:00:00Z',
    ...overrides,
  };
}

function workflow(overrides: Partial<AgentWorkflow> = {}): AgentWorkflow {
  return {
    id: 'wf-db-1', tenantId: TENANT_ID, objective: 'Fit 2 follow-ups this week',
    planJson: JSON.stringify({ Steps: [0, 1].map((i) => ({ Agent: 'ActionToolAgent', Action: 'CreateBooking', Tool: 'bookings.create', Parameters: { resourceId: 'r1', startTime: `2030-01-07T${9 + i}:00:00Z` } })), EstimatedRevenueImpact: 90 }),
    status: 'Approved', approvalStatus: 'NotRequired', createdAt: '2030-01-06T10:00:00Z',
    ...overrides,
  };
}

function renderWith(ui: React.ReactElement) {
  const store = configureStore({
    reducer: { auth: authReducer, [bookingApi.reducerPath]: bookingApi.reducer },
    middleware: (gdm) => gdm().concat(bookingApi.middleware),
    preloadedState: {
      auth: {
        user: { id: 'u-1', email: 'm@example.com', fullName: 'Manager', role: 'Manager' as const, tenantId: TENANT_ID },
        token: 'test-token', isAuthenticated: true, loading: false, error: null,
      },
    },
  });
  return render(
    <Provider store={store}>
      <ToastProvider>
        <MemoryRouter>{ui}</MemoryRouter>
      </ToastProvider>
    </Provider>,
  );
}

function urlOf(input: RequestInfo | URL): string {
  if (typeof input === 'string') return input;
  if (input instanceof URL) return input.toString();
  return input.url;
}

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
    const url = urlOf(input);
    const body = url.includes('/bookingtypes') ? [{ id: 'bt-1', name: 'Consultation', status: 'Active', defaultDurationMinutes: 45 }]
      : url.includes('/resources') ? { items: [{ id: 'r1', name: 'Dr. Perera', status: 'Available' }], total: 1 }
      : url.includes('/agent/workflow') ? [workflow({ toolResultsJson: JSON.stringify(trace()) })]
      : {};
    return new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }));
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('CopilotResult', () => {
  it('shows a plan that passed the gate as ready to apply, with the full trace', () => {
    renderWith(<CopilotResult workflow={workflow()} trace={trace()} />);

    expect(screen.getByText('Ready to apply')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /apply 2 to schedule/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^approve$/i })).not.toBeInTheDocument();
    // Planner contract, intent and delegation are all visible.
    expect(screen.getByText('Rank candidate resources')).toBeInTheDocument();
    expect(screen.getByText('82%')).toBeInTheDocument();
    expect(screen.getByText('📅 Thu')).toBeInTheDocument();       // the weekday the planner read
    expect(screen.getByText(/morning only/i)).toBeInTheDocument();
    expect(screen.getByText('3/3 passed')).toBeInTheDocument();
    // Retries are shown, not hidden.
    expect(screen.getByText('failed → next')).toBeInTheDocument();
  });

  it('asks for a decision when the gate escalated the plan', () => {
    const escalated = trace({
      status: 'AwaitingApproval',
      safety: { ...trace().safety!, requires_human_approval: true, approval_reasons: ['Affects 24 bookings (threshold 20).'] },
    });
    renderWith(<CopilotResult workflow={workflow({ status: 'AwaitingApproval', approvalStatus: 'Pending' })} trace={escalated} />);

    expect(screen.getByText('Needs your approval')).toBeInTheDocument();
    expect(screen.getByText('Affects 24 bookings (threshold 20).')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^approve$/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^revise$/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /apply/i })).not.toBeInTheDocument();
  });

  it('offers no way to approve or apply a plan the safety gate returned', () => {
    const rejected = trace({
      status: 'Rejected',
      error: 'Double-booking: Dr. Perera Mon 09:00 overlaps 09:30',
      safety: {
        is_allowed: false, requires_human_approval: false, approval_reasons: [],
        rejection_reason: 'Double-booking: Dr. Perera Mon 09:00 overlaps 09:30',
        checks: [{ rule: 'no_double_booking', status: 'fail', detail: 'Double-booking: Dr. Perera Mon 09:00 overlaps 09:30' }],
      },
    });
    renderWith(<CopilotResult workflow={workflow({ status: 'Rejected' })} trace={rejected} onRerun={() => {}} />);

    expect(screen.getByText('Returned for revision')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /approve/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /apply/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /adjust and run again/i })).toBeInTheDocument();
    expect(screen.getByText('✕')).toBeInTheDocument();
  });

  it('explains a safe failure instead of showing an empty page', () => {
    renderWith(<CopilotResult workflow={workflow({ status: 'Failed' })}
      trace={trace({ status: 'Failed', error: 'GET /resources failed (500)', action: null, safety: null, metrics: null })} />);

    expect(screen.getByText('Stopped safely')).toBeInTheDocument();
    expect(screen.getByText('GET /resources failed (500)')).toBeInTheDocument();
  });

  it('revising only ever removes proposals', () => {
    renderWith(<CopilotResult workflow={workflow({ status: 'AwaitingApproval', approvalStatus: 'Pending' })}
      trace={trace({ status: 'AwaitingApproval' })} />);

    fireEvent.click(screen.getByRole('button', { name: /^revise$/i }));
    const boxes = screen.getAllByRole('checkbox');
    expect(boxes).toHaveLength(2);
    fireEvent.click(boxes[0]);
    expect(screen.getByRole('button', { name: 'Keep 1' })).toBeInTheDocument();
    expect(screen.getByText(/can never add a slot/i)).toBeInTheDocument();
  });

  it('is honest when the deterministic planner ran', () => {
    const fallback = trace({ planner: { ...trace().planner!, used_fallback: true, confidence_score: 0.6 }, llm_calls: [] });
    renderWith(<CopilotResult workflow={workflow()} trace={fallback} />);

    expect(screen.getByText('deterministic planner')).toBeInTheDocument();
    expect(screen.getByText(/no model call was made/i)).toBeInTheDocument();
  });
});

describe('ScheduleCopilotPage', () => {
  it('fills the objective from an example and keeps morning/afternoon exclusive', async () => {
    renderWith(<ScheduleCopilotPage />);

    const example = await screen.findByRole('button', { name: /property viewings for thursday/i });
    fireEvent.click(example);
    expect((screen.getByLabelText('Scheduling objective') as HTMLTextAreaElement).value).toMatch(/Thursday/);

    const mornings = screen.getByRole('button', { name: /prefer mornings/i });
    const afternoons = screen.getByRole('button', { name: /prefer afternoons/i });
    fireEvent.click(mornings);
    expect(mornings).toHaveAttribute('aria-pressed', 'true');
    fireEvent.click(afternoons);
    expect(afternoons).toHaveAttribute('aria-pressed', 'true');
    expect(mornings).toHaveAttribute('aria-pressed', 'false');
  });

  it('opens the latest Copilot run from history with its result', async () => {
    renderWith(<ScheduleCopilotPage />);

    // Wait on the history row itself: "Ready to apply" is also a filter-tab
    // label, present before any data arrives, so waiting on that text raced
    // the fetch and failed under load.
    const history = screen.getByText('Workflow history').closest('section')!;
    expect(await within(history).findByText(/2 proposed · 82% confidence/)).toBeInTheDocument();
    // ...and the latest run is opened automatically above the history.
    expect(screen.getByRole('button', { name: /apply 2 to schedule/i })).toBeInTheDocument();
  });

  it('will not run with an objective too short to plan from', async () => {
    renderWith(<ScheduleCopilotPage />);
    const box = await screen.findByLabelText('Scheduling objective');
    fireEvent.change(box, { target: { value: 'hi' } });
    expect(screen.getByRole('button', { name: /run the agents/i })).toBeDisabled();
  });
});
