"""Contracts for the Schedule Copilot: the staff-facing Planner/Coordinator
workflow (assignment component 2.7).

The spec fixes the Planner's contract:

    Input : { objective, constraints: { dateRange, resources[], priorityRules[] }, tenantId }
    Output: { plan: Step[], assignedAgents: string[], predictedConflicts: Conflict[], confidenceScore }

Everything below either *is* that contract or is the typed record of what
each downstream agent did with it, so a stored workflow can be audited field
by field instead of as free text.

Priority rules are a closed vocabulary on purpose. They reach the optimiser
as data, and a rule the optimiser does not implement would be a rule the
planner claims to honour and silently ignores. A closed set also means text
in the objective cannot smuggle a new behaviour in through the LLM: an
unknown rule fails schema validation instead of being obeyed.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from schemas.contracts import AgentStepRecord, LlmCallRecord, PredictedConflict, ToolCallRecord

PriorityRule = Literal[
    "prefer_mornings",
    "prefer_afternoons",
    "balance_load",
    "minimise_travel",
    "avoid_high_no_show",
    "earliest_first",
    "keep_lunch_free",
    "cluster_same_day",
]

PRIORITY_RULES: tuple[str, ...] = PriorityRule.__args__  # type: ignore[attr-defined]

AgentName = Literal["PlannerAgent", "DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"]

# Hard ceilings the objective text can never raise. The form's own limits
# are tighter; these exist so a direct API caller cannot ask for a thousand
# bookings or a year-long scan either.
MAX_TARGET_COUNT = 50
MAX_RANGE_DAYS = 31
MAX_RESOURCES = 12
MAX_OBJECTIVE_CHARS = 500


# ── Input ───────────────────────────────────────────────────────────────
class DateRange(BaseModel):
    date_from: date
    date_to: date

    @model_validator(mode="after")
    def _ordered(self) -> "DateRange":
        if self.date_to < self.date_from:
            raise ValueError("date_to must be on or after date_from")
        if (self.date_to - self.date_from).days + 1 > MAX_RANGE_DAYS:
            raise ValueError(f"date range may span at most {MAX_RANGE_DAYS} days")
        return self


class ScheduleConstraints(BaseModel):
    date_range: DateRange
    resource_ids: list[str] = Field(default_factory=list, max_length=MAX_RESOURCES)
    priority_rules: list[PriorityRule] = Field(default_factory=list)
    booking_type_id: str
    target_count: int = Field(ge=1, le=MAX_TARGET_COUNT)
    duration_minutes: int = Field(default=60, ge=5, le=480)
    branch_id: str | None = None


class SchedulePlanRequest(BaseModel):
    """POST /schedule/plan. `auth_token` is the calling manager's own JWT,
    forwarded by ASP.NET Core so every tool call carries that person's real
    identity and permissions. It is never echoed into the trace."""

    objective: str = Field(min_length=3, max_length=MAX_OBJECTIVE_CHARS)
    tenant_id: str
    business_type: str = "General"
    constraints: ScheduleConstraints
    currency: str = "USD"
    auth_token: str = Field(repr=False)

    @field_validator("objective")
    @classmethod
    def _clean_objective(cls, value: str) -> str:
        # Control characters have no business in a scheduling objective and
        # are a common carrier for prompt-injection payloads.
        cleaned = "".join(ch for ch in value if ch.isprintable() or ch in " \t")
        return " ".join(cleaned.split())


# ── Agent 1: Planner / Coordinator ──────────────────────────────────────
class CopilotPlanStep(BaseModel):
    order: int = Field(ge=1)
    action: str
    assigned_agent: Literal["DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"]
    description: str
    tools: list[str] = Field(default_factory=list)


class ScheduleIntent(BaseModel):
    """What the planner understood the objective to be asking for. Merged
    with the explicit form constraints afterwards; the form always wins."""

    target_count: int | None = Field(default=None, ge=1, le=MAX_TARGET_COUNT)
    priority_rules: list[PriorityRule] = Field(default_factory=list)
    min_gap_minutes: int = Field(default=0, ge=0, le=240)
    # Narrowing only, like everything the planner infers: days of the week
    # (0 = Monday) the objective names, and a hard time window when it says
    # "only". Neither can reach outside the manager's date range.
    weekdays: list[int] = Field(default_factory=list)
    time_window: Literal["any", "morning", "afternoon"] = "any"
    rationale: str = ""

    @field_validator("weekdays")
    @classmethod
    def _valid_weekdays(cls, value: list[int]) -> list[int]:
        return sorted({d for d in value if 0 <= d <= 6})


class CopilotPlannerOutput(BaseModel):
    """The spec 2.7 output contract, plus the parsed intent."""

    plan: list[CopilotPlanStep] = Field(min_length=1)
    assigned_agents: list[str]
    predicted_conflicts: list[PredictedConflict] = Field(default_factory=list)
    confidence_score: float = Field(ge=0.0, le=1.0)
    intent: ScheduleIntent = Field(default_factory=ScheduleIntent)
    summary: str = ""
    used_fallback: bool = False

    @model_validator(mode="after")
    def _delegates_to_every_downstream_agent(self) -> "CopilotPlannerOutput":
        # A plan that skips the safety gate is not a plan this system runs.
        agents = {step.assigned_agent for step in self.plan}
        if "ValidationSafetyAgent" not in agents:
            raise ValueError("plan must delegate a step to ValidationSafetyAgent")
        return self


# ── Agent 2: Domain Analysis ────────────────────────────────────────────
class ResourceInsight(BaseModel):
    resource_id: str
    resource_name: str
    working_days_in_range: int
    booked_minutes_in_range: int
    capacity_minutes_in_range: int
    utilisation_pct: float
    no_show_rate: float = Field(ge=0.0, le=1.0)
    no_show_sample: int
    max_daily_minutes: int
    lunch_start: str | None = None
    lunch_end: str | None = None
    # Handed to the Action/Tool agent through this contract rather than by
    # giving it the booking-history tool: it needs the numbers, not the reach.
    booked_minutes_by_day: dict[str, int] = Field(default_factory=dict)
    latitude: float | None = None
    longitude: float | None = None
    score: float
    reasons: list[str] = Field(default_factory=list)


class DomainAnalysisReport(BaseModel):
    resources: list[ResourceInsight]
    average_booking_value: float | None = None
    value_sample: int = 0
    insights: list[str] = Field(default_factory=list)


# ── Agent 3: Action / Tool (optimiser) ──────────────────────────────────
class ScheduleProposal(BaseModel):
    resource_id: str
    resource_name: str
    start: datetime
    end: datetime
    duration_minutes: int
    score: float
    score_breakdown: dict[str, float] = Field(default_factory=dict)
    reasons: list[str] = Field(default_factory=list)
    no_show_risk: float = Field(default=0.0, ge=0.0, le=1.0)
    travel_minutes_from_previous: float | None = None
    has_conflict: bool = False
    conflict_reason: str | None = None


class SkippedCandidate(BaseModel):
    resource_name: str
    start: datetime
    reason: str


class ActionReport(BaseModel):
    proposals: list[ScheduleProposal]
    skipped: list[SkippedCandidate] = Field(default_factory=list)
    candidates_considered: int = 0
    notes: list[str] = Field(default_factory=list)


# ── Agent 4: Validation / Safety (deterministic) ────────────────────────
class ValidationCheck(BaseModel):
    rule: str
    status: Literal["pass", "fail", "warn"]
    detail: str


class SafetyReport(BaseModel):
    is_allowed: bool
    requires_human_approval: bool
    approval_reasons: list[str] = Field(default_factory=list)
    rejection_reason: str | None = None
    checks: list[ValidationCheck] = Field(default_factory=list)


# ── Outcome ─────────────────────────────────────────────────────────────
class ScheduleMetrics(BaseModel):
    requested: int
    proposed: int
    coverage_pct: float
    resources_used: int
    days_used: int
    expected_no_shows: float
    estimated_revenue: float | None = None
    estimated_revenue_usd: float | None = None
    currency: str = "USD"
    utilisation_before_pct: float = 0.0
    utilisation_after_pct: float = 0.0


class ScheduleTrace(BaseModel):
    workflow_type: Literal["schedule-copilot"] = "schedule-copilot"
    workflow_id: str
    objective: str
    tenant_id: str
    business_type: str
    status: Literal["Completed", "AwaitingApproval", "Rejected", "Failed"]
    constraints: ScheduleConstraints
    planner: CopilotPlannerOutput | None = None
    analysis: DomainAnalysisReport | None = None
    action: ActionReport | None = None
    safety: SafetyReport | None = None
    metrics: ScheduleMetrics | None = None
    warnings: list[str] = Field(default_factory=list)
    agent_steps: list[AgentStepRecord] = Field(default_factory=list)
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)
    llm_calls: list[LlmCallRecord] = Field(default_factory=list)
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: datetime | None = None
