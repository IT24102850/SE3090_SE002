import api from '../../api/axiosConfig';

/* Disruption Recovery Copilot - api/agent/disruption
 * (backend Controllers/DisruptionRecoveryController.cs).
 *
 * The agents only ever propose. Every one of these calls except `plan` is a
 * manager's decision, and `plan` changes nothing. */

export type RecoveryKind = 'MoveResource' | 'MoveTime' | 'MoveBoth' | 'Cancel' | 'NoOptionFound';

export interface RecoveryProposal {
  booking_id: string;
  customer_name: string;
  kind: RecoveryKind;
  original_starts_at: string;
  original_ends_at: string;
  proposed_resource_id: string | null;
  proposed_resource_name: string | null;
  proposed_starts_at: string | null;
  proposed_ends_at: string | null;
  explanation: string;
  confidence: number;
}

export interface AffectedBooking {
  booking_id: string;
  customer_name: string;
  starts_at: string;
  ends_at: string;
  attendee_count: number;
  deposit_paid: boolean;
  priority: number;
  priority_reason: string;
}

export interface SafetyCheck {
  rule: string;
  passed: boolean;
  detail: string;
}

export interface DisruptionTrace {
  status: string;
  business_type: string;
  impact?: {
    resource_name: string;
    resource_noun: string;
    affected: AffectedBooking[];
    total_attendees: number;
    revenue_at_risk: number;
    warnings: string[];
  };
  action?: { proposals: RecoveryProposal[]; unresolved: string[]; notes: string[] };
  safety?: {
    is_allowed: boolean;
    requires_human_approval: boolean;
    rejection_reason: string | null;
    checks: SafetyCheck[];
    rejected_booking_ids: string[];
  };
  warnings: string[];
  error: string | null;
  agent_steps: { agent: string; duration_ms: number; ok: boolean; error: string | null }[];
  tool_calls: { tool: string; agent: string; duration_ms: number; success: boolean }[];
}

export interface DisruptionWorkflow {
  id: string;
  objective: string;
  status: string;
  approvalStatus: string;
  finalOutcome: string | null;
  errorLog: string | null;
  createdAt: string;
  completedAt: string | null;
  /** The agents' trace, stored as the JSON the service returned. */
  trace: string | null;
}

export interface ApplyResult {
  workflowId: string;
  moved: { bookingId: string }[];
  skipped: { bookingId: string; reason: string }[];
  outcome: string;
}

export const disruptionApi = {
  list: (status?: string) =>
    api.get<DisruptionWorkflow[]>('/agent/disruption', { params: status ? { status } : undefined })
      .then((r) => r.data),
  plan: (body: { objective: string; resourceId: string; dateFrom: string; dateTo: string; reason?: string }) =>
    api.post<{ workflowId: string; status: string; trace: DisruptionTrace }>('/agent/disruption/plan', body)
      .then((r) => r.data),
  apply: (id: string, acceptedBookingIds?: string[]) =>
    api.post<ApplyResult>(`/agent/disruption/${id}/apply`, { acceptedBookingIds }).then((r) => r.data),
  reject: (id: string, reason: string) =>
    api.post<{ outcome: string }>(`/agent/disruption/${id}/reject`, { reason }).then((r) => r.data),
};

export function parseTrace(workflow: DisruptionWorkflow): DisruptionTrace | null {
  if (!workflow.trace) return null;
  try {
    return JSON.parse(workflow.trace) as DisruptionTrace;
  } catch {
    return null;
  }
}

export function errorMessage(error: unknown, fallback: string): string {
  const response = (error as { response?: { status?: number; data?: { message?: string; title?: string } } })?.response;
  // A 404 here means the route does not exist on the API this build talks to -
  // almost always a backend that has not been deployed with the feature yet.
  // Saying so beats echoing a bare "Not Found".
  if (response?.status === 404) {
    return 'The deployed API does not have the Disruption Recovery endpoints yet. Deploy the backend and reload.';
  }
  if (response?.status === 402) {
    return 'Disruption Recovery is part of the AI features. Upgrade the plan to use it.';
  }
  return response?.data?.message ?? response?.data?.title ?? fallback;
}
