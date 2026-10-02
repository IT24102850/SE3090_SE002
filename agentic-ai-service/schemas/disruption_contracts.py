"""Contracts for the Disruption Recovery Copilot.

A resource becomes unavailable - a doctor calls in sick, a boat fails its
safety check, a classroom floods - and every booking already on it has to go
somewhere. The workflow proposes one recovery per affected booking and pauses
for a manager, because moving other people's appointments is not something an
agent should do unsupervised.

Every field a client sees is here; the agents may not invent shapes.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field

from schemas.contracts import AgentStepRecord, LlmCallRecord, ToolCallRecord

MAX_OBJECTIVE_CHARS = 500
MAX_AFFECTED = 200

#: What the recovery did with one booking.
RecoveryKind = Literal["MoveResource", "MoveTime", "MoveBoth", "Cancel", "NoOptionFound"]


class DisruptionWindow(BaseModel):
    """The period the resource is out of service."""

    date_from: date
    date_to: date
    starts_at: datetime | None = None
    ends_at: datetime | None = None


class DisruptionRequest(BaseModel):
    objective: str = Field(min_length=3, max_length=MAX_OBJECTIVE_CHARS)
    tenant_id: str
    business_type: str = "General"
    resource_id: str
    window: DisruptionWindow
    reason: str = Field(default="", max_length=300)
    branch_id: str | None = None
    #: The caller's own JWT. Every tool call is made with it, so the agent can
    #: never read beyond what the manager could read themselves.
    auth_token: str = Field(repr=False)


class DisruptionPlanStep(BaseModel):
    order: int = Field(ge=1)
    action: str
    assigned_agent: Literal["ImpactAnalysisAgent", "RecoveryActionAgent", "DisruptionSafetyAgent"]
    description: str
    tools: list[str] = Field(default_factory=list)


class DisruptionIntent(BaseModel):
    """What the planner read in the manager's sentence."""

    prefer: Literal["same_time_other_resource", "same_resource_later", "either"] = "either"
    allow_cancellation: bool = False
    protect_deposits: bool = True
    max_days_to_move: int = Field(default=7, ge=0, le=60)
    rationale: str = ""


class DisruptionPlannerOutput(BaseModel):
    plan: list[DisruptionPlanStep] = Field(min_length=1)
    assigned_agents: list[str] = Field(default_factory=list)
    intent: DisruptionIntent = Field(default_factory=DisruptionIntent)
    summary: str = ""
    confidence_score: float = Field(default=0.5, ge=0.0, le=1.0)
    used_fallback: bool = False


class AffectedBooking(BaseModel):
    booking_id: str
    customer_name: str = ""
    customer_id: str | None = None
    booking_type_id: str
    booking_type_name: str = ""
    starts_at: datetime
    ends_at: datetime
    status: str = ""
    attendee_count: int = 1
    #: A paid deposit makes a cancellation materially worse for the customer.
    deposit_paid: bool = False
    specialty: str | None = None
    #: 0..1, higher first. Deterministic - see disruption_policy.priority_of.
    priority: float = 0.0
    priority_reason: str = ""


class ImpactOutput(BaseModel):
    resource_name: str = ""
    #: What this business calls the thing that broke: doctor, table, boat...
    resource_noun: str = "resource"
    affected: list[AffectedBooking] = Field(default_factory=list, max_length=MAX_AFFECTED)
    total_attendees: int = 0
    revenue_at_risk: float = 0.0
    warnings: list[str] = Field(default_factory=list)


class RecoveryProposal(BaseModel):
    booking_id: str
    customer_name: str = ""
    kind: RecoveryKind
    original_starts_at: datetime
    original_ends_at: datetime
    proposed_resource_id: str | None = None
    proposed_resource_name: str | None = None
    proposed_starts_at: datetime | None = None
    proposed_ends_at: datetime | None = None
    #: Plain words for the customer, in this business's vocabulary.
    explanation: str = ""
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)


class ActionOutput(BaseModel):
    proposals: list[RecoveryProposal] = Field(default_factory=list)
    unresolved: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)


class SafetyCheck(BaseModel):
    rule: str
    passed: bool
    detail: str


class SafetyOutput(BaseModel):
    is_allowed: bool = True
    requires_human_approval: bool = True
    rejection_reason: str | None = None
    checks: list[SafetyCheck] = Field(default_factory=list)
    #: Proposals the gate struck out; never silently dropped.
    rejected_booking_ids: list[str] = Field(default_factory=list)


class DisruptionTrace(BaseModel):
    workflow_id: str = ""
    objective: str
    tenant_id: str
    business_type: str
    resource_id: str
    status: Literal["AwaitingApproval", "Rejected", "Failed", "NoAction"] = "Failed"
    planner: DisruptionPlannerOutput | None = None
    impact: ImpactOutput | None = None
    action: ActionOutput | None = None
    safety: SafetyOutput | None = None
    warnings: list[str] = Field(default_factory=list)
    error: str | None = None
    agent_steps: list[AgentStepRecord] = Field(default_factory=list)
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)
    llm_calls: list[LlmCallRecord] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: datetime | None = None
