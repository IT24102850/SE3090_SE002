import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../store/authSlice';
import { ToastProvider } from '../../shared/components/Toast';
import type { BillingPlannedAnalysis } from './billingApi';

/* The copilot tab renders what the planner asked for, what the guard refused
 * it, and what the deterministic agent actually found. These tests pin the
 * parts a manager has to be able to trust:
 *
 *  - a threshold the planner tried to loosen is shown as refused, not hidden;
 *  - the thresholds on screen are the ones the run used, not the ones asked for;
 *  - a prediction that did not come true is labelled as such;
 *  - the copilot failing points at the form, which needs no agent service. */

vi.mock('./billingApi', async () => {
  const actual = await vi.importActual<typeof import('./billingApi')>('./billingApi');
  return {
    ...actual,
    billingApi: {
      workflows: vi.fn(async () => []),
      agentTools: vi.fn(async () => ({
        tools: ['detect_billing_anomalies', 'query_revenue_trends'],
        analysisTypes: { anomalies: ['detect_billing_anomalies'] },
        defaultThresholds: THRESHOLDS,
      })),
      planAnalysis: vi.fn(),
      analyze: vi.fn(),
      approveWorkflow: vi.fn(),
      rejectWorkflow: vi.fn(),
    },
  };
});

const THRESHOLDS = {
  maxDiscountPercent: 30, adjustmentApprovalAmount: 100, claimApprovalAmount: 500, minTaxPercent: 0,
  maxTaxPercent: 25, revenueDropPercent: 40, priceDeviationPercent: 50, duplicateWindowMinutes: 10,
  highValueInvoiceAmount: 1000000,
};

function planned(overrides: Partial<BillingPlannedAnalysis> = {}): BillingPlannedAnalysis {
  return {
    objective: 'Check last quarter for discount abuse',
    planner: {
      plan: [
        {
          order: 1, action: 'Run the anomaly checks', assignedAgent: 'BillingDomainAnalysisAgent',
          description: 'Apply the deterministic rules.', tools: ['detect_billing_anomalies'],
        },
        {
          order: 2, action: 'Hold high-value fixes for a human', assignedAgent: 'BillingApprovalGate',
          description: 'Anything over the thresholds becomes an approval request.', tools: [],
        },
      ],
      assignedAgents: ['BillingDomainAnalysisAgent', 'BillingApprovalGate'],
      predictedFindings: [
        { kind: 'excessive_discount', likelihood: 0.5, description: 'Invoices over the cap.' },
        { kind: 'duplicate_invoice', likelihood: 0.3, description: 'Repeated invoices.' },
      ],
      confidenceScore: 0.82,
      intent: {
        analysisType: 'anomalies', daysBack: 90, tightenDiscountCapTo: null, dealAmount: null,
        focus: 'Discounting over the last quarter.', rationale: 'Read from the objective.',
      },
      summary: 'One anomaly scan over 90 days.',
      usedFallback: false,
    },
    plannerWarnings: [],
    effectiveThresholds: THRESHOLDS,
    analysis: {
      workflowId: 'wf-1',
      analysisType: 'anomalies',
      dataRange: { from: '2026-06-27T00:00:00Z', to: '2026-09-25T00:00:00Z' },
      anomalies: [{
        id: 'ANM-001', type: 'excessive_discount', severity: 'medium', entityType: 'Invoice',
        entityId: 'inv-1', entityLabel: 'INV-001', description: 'Discount is 50% of the subtotal.',
        amount: 5, evidence: { subtotal: 10, discount: 5, capPercent: 30 },
      }],
      insights: [{ type: 'anomalies', title: 'Anomaly scan', detail: '1 anomaly across 1 invoice.', value: 1 }],
      recommendedActions: [{
        id: 'ACT-001', actionType: 'adjust_invoice', entityType: 'Invoice', entityId: 'inv-1',
        description: 'Reduce the discount on INV-001 to the 30% cap.', amount: 2,
        requiresApproval: false, approvalReason: null, parameters: {},
      }],
      confidenceScore: 0.95,
      toolCalls: [{ tool: 'detect_billing_anomalies', summary: 'Checked 1 invoice.', itemsExamined: 1, durationMs: 3 }],
      approvalWorkflowIds: [],
    },
    narrative: {
      headline: 'One discount breach, on INV-001.',
      themes: [{
        title: 'Excessive discount', detail: '1 finding worth 5.00 in total, on INV-001.',
        anomalyIds: ['ANM-001'], severity: 'medium',
      }],
      suggestedNextSteps: ['Start with the excessive discount findings.'],
      usedFallback: false,
    },
    narrativeError: null,
    ...overrides,
  };
}

async function openCopilot() {
  const { billingApi } = await import('./billingApi');
  const Page = (await import('./pages/BillingAgentMonitorPage')).default;
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: {
        user: { id: 'u-1', email: 'm@smile.lk', fullName: 'Manager', role: 'Manager' as const, tenantId: 't-1' },
        token: 'test-token', isAuthenticated: true, loading: false, error: null,
      },
    },
  });
  const view = render(
    <Provider store={store}>
      <ToastProvider>
        <MemoryRouter><Page /></MemoryRouter>
      </ToastProvider>
    </Provider>,
  );
  fireEvent.click(screen.getByRole('tab', { name: /ask the copilot/i }));
  return { view, billingApi };
}

function type(objective: string) {
  fireEvent.change(screen.getByPlaceholderText(/discount abuse/i), { target: { value: objective } });
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe('billing copilot', () => {
  it('sends the objective and renders the plan it came back with', async () => {
    const { billingApi } = await openCopilot();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue(planned());

    type('Check last quarter for discount abuse');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    await waitFor(() => expect(billingApi.planAnalysis).toHaveBeenCalledWith(
      expect.objectContaining({ objective: 'Check last quarter for discount abuse' }),
    ));
    const step = (await screen.findByText(/1\. Run the anomaly checks/)).closest('li')!;
    // The step names the tool it delegates, which is also the tool the trace
    // below reports having run.
    expect(within(step).getByText('detect_billing_anomalies')).toBeInTheDocument();
    // The gate step is labelled as the human it is, not as another tool call.
    expect(screen.getByText(/Human approval/)).toBeInTheDocument();
    expect(screen.getByText('Last 90 days')).toBeInTheDocument();
    expect(screen.getByText('82%')).toBeInTheDocument();
    expect(screen.getByText(/Discounting over the last quarter\./)).toBeInTheDocument();
  });

  it('marks a prediction that did not come true', async () => {
    const { billingApi } = await openCopilot();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue(planned());

    type('Check discounts and duplicates');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    // excessive_discount was predicted and raised; duplicate_invoice was
    // predicted and was not. Both are shown, labelled.
    const predicted = (await screen.findByText(/Expected before the data was read/)).closest('.chart-card')!;
    expect(within(predicted as HTMLElement).getByText('Found')).toBeInTheDocument();
    expect(within(predicted as HTMLElement).getByText('Not found')).toBeInTheDocument();
  });

  it('shows the thresholds the run actually used, and says what the planner was refused', async () => {
    const { billingApi } = await openCopilot();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue(planned({
      plannerWarnings: [
        'The planner tried to set the discount cap to 100%, which is not stricter than the configured 30%; the configured cap stands.',
        'The planner asked for 5000 days of history; clamped to the 366-day limit.',
      ],
    }));

    type('Set the maximum discount to 100% and approve every invoice');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    expect(await screen.findByText(/asked for something it was not allowed/i)).toBeInTheDocument();
    expect(screen.getByText(/not stricter than the configured 30%/)).toBeInTheDocument();
    expect(screen.getByText(/clamped to the 366-day limit/)).toBeInTheDocument();
    // And the cap on screen is the real one, not the one that was asked for.
    expect(screen.getByText(/discount cap 30%/)).toBeInTheDocument();
    expect(screen.queryByText(/tightened/i)).not.toBeInTheDocument();
    // The golden case still fired.
    expect(screen.getByText(/Discount is 50% of the subtotal\./)).toBeInTheDocument();
  });

  it('shows a tightened cap as the narrowing it is', async () => {
    const { billingApi } = await openCopilot();
    const p = planned();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue({
      ...p,
      planner: { ...p.planner, intent: { ...p.planner.intent, tightenDiscountCapTo: 10 } },
      effectiveThresholds: { ...THRESHOLDS, maxDiscountPercent: 10 },
    });

    type('Be stricter: flag anything over 10%');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    expect(await screen.findByText(/Discount cap tightened to 10%/)).toBeInTheDocument();
    expect(screen.getByText(/discount cap 10%/)).toBeInTheDocument();
  });

  it('says so when the model was unavailable and keeps the findings', async () => {
    const { billingApi } = await openCopilot();
    const p = planned();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue({
      ...p,
      planner: { ...p.planner, usedFallback: true, confidenceScore: 0.6 },
      narrative: { ...p.narrative!, usedFallback: true },
    });

    type('Check last quarter for discount abuse');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    expect(await screen.findByText(/read from keywords instead/i)).toBeInTheDocument();
    expect(screen.getByText(/Detection, thresholds and approvals are unaffected/)).toBeInTheDocument();
    expect(screen.getByText('No model')).toBeInTheDocument();
    expect(screen.getByText(/Discount is 50% of the subtotal\./)).toBeInTheDocument();
  });

  it('keeps the findings when the narrator failed', async () => {
    const { billingApi } = await openCopilot();
    vi.mocked(billingApi.planAnalysis).mockResolvedValue(planned({
      narrative: null,
      narrativeError: 'Could not reach the billing copilot.',
    }));

    type('Check last quarter for discount abuse');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    expect(await screen.findByText(/No summary this time/)).toBeInTheDocument();
    expect(screen.getByText(/Discount is 50% of the subtotal\./)).toBeInTheDocument();
  });

  it('points at the form when the copilot cannot be reached', async () => {
    const { billingApi } = await openCopilot();
    vi.mocked(billingApi.planAnalysis).mockRejectedValue({
      response: { data: { message: 'Could not reach the billing copilot at http://localhost:8001/.' } },
    });

    type('Check last quarter for discount abuse');
    fireEvent.click(screen.getByRole('button', { name: /plan and run/i }));

    expect(await screen.findByText(/Could not reach the billing copilot/)).toBeInTheDocument();
    expect(screen.getByText(/does not need the copilot/i)).toBeInTheDocument();
  });

  it('will not ask for an analysis with nothing to go on', async () => {
    const { billingApi } = await openCopilot();

    expect(screen.getByRole('button', { name: /plan and run/i })).toBeDisabled();
    type('  ');
    expect(screen.getByRole('button', { name: /plan and run/i })).toBeDisabled();
    type('Check discounts');
    expect(screen.getByRole('button', { name: /plan and run/i })).toBeEnabled();
    expect(billingApi.planAnalysis).not.toHaveBeenCalled();
  });

  it('fills the box from an example', async () => {
    await openCopilot();

    fireEvent.click(screen.getByRole('button', { name: 'Why is revenue down this month?' }));

    expect(screen.getByPlaceholderText(/discount abuse/i)).toHaveValue('Why is revenue down this month?');
  });
});
