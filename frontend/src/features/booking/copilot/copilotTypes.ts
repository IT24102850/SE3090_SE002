/* The Schedule Copilot trace, exactly as the agent service produces it and
 * ASP.NET Core stores it on AgentWorkflow.ToolResultsJson. snake_case is
 * kept on purpose: this is the agents' own audit record, rendered as-is,
 * not a view model that could quietly disagree with what was stored. */

export type AgentName = 'PlannerAgent' | 'DomainAnalysisAgent' | 'ActionToolAgent' | 'ValidationSafetyAgent';

export type PriorityRule =
  | 'prefer_mornings'
  | 'prefer_afternoons'
  | 'balance_load'
  | 'minimise_travel'
  | 'avoid_high_no_show'
  | 'earliest_first'
  | 'keep_lunch_free'
  | 'cluster_same_day';

export interface CopilotPlanStep {
  order: number;
  action: string;
  assigned_agent: Exclude<AgentName, 'PlannerAgent'>;
  description: string;
  tools: string[];
}

export interface PredictedConflict {
  kind: string;
  description: string;
  resource_id?: string | null;
  likelihood: number;
}

export interface ScheduleIntent {
  target_count?: number | null;
  priority_rules: PriorityRule[];
  min_gap_minutes: number;
  weekdays: number[];
  time_window: 'any' | 'morning' | 'afternoon';
  rationale: string;
}

export interface PlannerOutput {
  plan: CopilotPlanStep[];
  assigned_agents: string[];
  predicted_conflicts: PredictedConflict[];
  confidence_score: number;
  intent: ScheduleIntent;
  summary: string;
  used_fallback: boolean;
}

export interface ResourceInsight {
  resource_id: string;
  resource_name: string;
  working_days_in_range: number;
  booked_minutes_in_range: number;
  capacity_minutes_in_range: number;
  utilisation_pct: number;
  no_show_rate: number;
  no_show_sample: number;
  max_daily_minutes: number;
  lunch_start?: string | null;
  lunch_end?: string | null;
  score: number;
  reasons: string[];
}

export interface ScheduleProposal {
  resource_id: string;
  resource_name: string;
  start: string;
  end: string;
  duration_minutes: number;
  score: number;
  score_breakdown: Record<string, number>;
  reasons: string[];
  no_show_risk: number;
  travel_minutes_from_previous?: number | null;
}

export interface SkippedCandidate {
  resource_name: string;
  start: string;
  reason: string;
}

export interface ValidationCheck {
  rule: string;
  status: 'pass' | 'fail' | 'warn';
  detail: string;
}

export interface SafetyReport {
  is_allowed: boolean;
  requires_human_approval: boolean;
  approval_reasons: string[];
  rejection_reason?: string | null;
  checks: ValidationCheck[];
}

export interface ScheduleMetrics {
  requested: number;
  proposed: number;
  coverage_pct: number;
  resources_used: number;
  days_used: number;
  expected_no_shows: number;
  estimated_revenue?: number | null;
  estimated_revenue_usd?: number | null;
  currency: string;
  utilisation_before_pct: number;
  utilisation_after_pct: number;
}

export interface CopilotTrace {
  workflow_type: 'schedule-copilot';
  workflow_id: string;
  objective: string;
  business_type: string;
  status: 'Completed' | 'AwaitingApproval' | 'Rejected' | 'Failed';
  constraints: {
    date_range: { date_from: string; date_to: string };
    priority_rules: PriorityRule[];
    target_count: number;
    duration_minutes: number;
  };
  planner?: PlannerOutput | null;
  analysis?: { resources: ResourceInsight[]; average_booking_value?: number | null; insights: string[] } | null;
  action?: { proposals: ScheduleProposal[]; skipped: SkippedCandidate[]; candidates_considered: number; notes: string[] } | null;
  safety?: SafetyReport | null;
  metrics?: ScheduleMetrics | null;
  warnings: string[];
  agent_steps: { agent: AgentName; duration_ms: number; ok: boolean; error?: string | null }[];
  tool_calls: { tool: string; agent: AgentName; duration_ms: number; success: boolean; error?: string | null }[];
  llm_calls: { model: string; attempt: number; duration_ms: number; ok: boolean; error?: string | null }[];
  error?: string | null;
  created_at: string;
  completed_at?: string | null;
}

export function parseCopilotTrace(raw?: string | null): CopilotTrace | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed?.workflow_type === 'schedule-copilot' ? (parsed as CopilotTrace) : null;
  } catch {
    return null;
  }
}

export const RULE_LABELS: Record<PriorityRule, { label: string; hint: string; icon: string }> = {
  prefer_mornings: { label: 'Prefer mornings', hint: 'Favour slots before noon', icon: '🌅' },
  prefer_afternoons: { label: 'Prefer afternoons', hint: 'Favour slots from noon', icon: '🌇' },
  balance_load: { label: 'Balance load', hint: 'Even out work across resources', icon: '⚖️' },
  minimise_travel: { label: 'Minimise travel', hint: 'Leave drive time between locations', icon: '🧭' },
  avoid_high_no_show: { label: 'Avoid no-shows', hint: 'Steer from high no-show history', icon: '🛡️' },
  earliest_first: { label: 'Earliest first', hint: 'Fill the soonest days first', icon: '⏱️' },
  keep_lunch_free: { label: 'Keep lunch free', hint: 'Never cross 12:00–13:00', icon: '🥗' },
  cluster_same_day: { label: 'Cluster days', hint: 'Group onto as few days as possible', icon: '🧩' },
};

export const AGENT_META: Record<AgentName, { short: string; role: string; tone: string }> = {
  PlannerAgent: { short: 'Planner', role: 'Reads the objective, plans and delegates', tone: '#7c3aed' },
  DomainAnalysisAgent: { short: 'Domain Analysis', role: 'Ranks resources on hours, load and no-shows', tone: '#2563eb' },
  ActionToolAgent: { short: 'Action / Tool', role: 'Searches real slots and optimises the schedule', tone: '#0891b2' },
  ValidationSafetyAgent: { short: 'Validation / Safety', role: 'Deterministic rules and the approval decision', tone: '#059669' },
};

export const CHECK_LABELS: Record<string, string> = {
  proposals: 'Something to schedule',
  schema: 'Well-formed proposals',
  count: 'Within the requested count',
  future: 'Nothing in the past',
  duration: 'Within the 2-hour limit',
  no_double_booking: 'No double-booking',
  daily_hours: 'Daily hour cap (8h)',
  lunch_break: 'Lunch break kept',
  live_conflicts: 'Re-verified against live bookings',
  coverage: 'Request coverage',
};
