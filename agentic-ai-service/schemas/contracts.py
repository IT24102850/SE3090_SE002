"""Pydantic contracts for every agent's input/output, plus the top-level
/plan request/response. Business-type-agnostic throughout: nothing here
names "doctor"/"patient" — that vocabulary only ever appears inside prompt
strings supplied at runtime via `extra_constraints`, never in the schema.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from pydantic import BaseModel, Field


class PlanRequest(BaseModel):
    """POST /plan body. `auth_token` is the short-lived customer-scoped JWT
    minted by ASP.NET Core — used by tools to call back into the API with
    the caller's real identity, never echoed into any response or trace."""

    objective: str
    tenant_id: str
    business_type: str
    branch_id: str | None = None
    customer_id: str
    date_from: datetime | None = None
    date_to: datetime | None = None
    extra_constraints: dict[str, Any] = Field(default_factory=dict)
    auth_token: str = Field(repr=False)


# ── Agent 1: Planner / Coordinator ──────────────────────────────────────
class PlanStep(BaseModel):
    order: int
    action: str
    assigned_agent: Literal["DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"]
    description: str


class PlannerOutput(BaseModel):
    plan: list[PlanStep]
    assigned_agents: list[str]
    confidence: float = Field(ge=0.0, le=1.0)


# ── Agent 2: Domain Analysis ────────────────────────────────────────────
class RankedCandidate(BaseModel):
    resource_id: str
    resource_name: str
    score: float
    reasoning: str


class DomainAnalysisOutput(BaseModel):
    ranked_candidates: list[RankedCandidate]
    ranking_criteria_used: list[str]


# ── Agent 3: Action / Tool ──────────────────────────────────────────────
class ProposedBooking(BaseModel):
    resource_id: str
    resource_name: str | None = None
    booking_type_id: str
    scheduled_datetime: datetime
    duration_minutes: int
    has_conflict: bool
    conflict_reason: str | None = None


class ActionToolOutput(BaseModel):
    proposed_bookings: list[ProposedBooking]
    confidence: float = Field(ge=0.0, le=1.0)


# ── Agent 4: Validation / Safety (deterministic, no LLM) ────────────────
class ValidationSafetyOutput(BaseModel):
    is_allowed: bool
    requires_human_approval: bool
    rejection_reason: str | None = None
    validation_notes: list[str] = Field(default_factory=list)
    booking_id: str | None = None  # set only if create_booking actually ran


# ── Full trace, returned by /plan and stored (in-memory) for /trace ─────
class ToolCallRecord(BaseModel):
    tool: str
    agent: str
    duration_ms: int
    success: bool
    error: str | None = None


class WorkflowTrace(BaseModel):
    workflow_id: str
    objective: str
    tenant_id: str
    business_type: str
    status: Literal["Completed", "AwaitingApproval", "Failed", "Rejected"]
    planner_output: PlannerOutput | None = None
    domain_analysis_output: DomainAnalysisOutput | None = None
    action_tool_output: ActionToolOutput | None = None
    validation_output: ValidationSafetyOutput | None = None
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: datetime | None = None


class ApproveRejectRequest(BaseModel):
    reason: str | None = None


class InventoryPlanRequest(BaseModel):
    """Internal inventory planning request. The delegated user token is never returned."""
    objective: str
    tenant_id: str
    branch_id: str | None = None
    auth_token: str = Field(repr=False)


class InventoryRecommendation(BaseModel):
    inventory_item_id: str
    item_name: str
    sku: str
    branch_id: str | None = None
    branch_name: str | None = None
    on_hand: float
    reorder_level: float
    avg_daily_outflow: float | None = None
    days_until_reorder: float | None = None
    recommended_quantity: float
    estimated_unit_cost: float | None = None
    estimated_total_cost: float | None = None
    confidence: float = Field(ge=0.0, le=1.0)
    reason: str
    validation_notes: list[str] = Field(default_factory=list)


class InventoryHealthInsight(BaseModel):
    category: Literal["overview", "coverage", "movement", "data_quality", "cost", "trend"]
    title: str
    detail: str
    affected_items: list[str] = Field(default_factory=list)


class InventoryAgentTrace(BaseModel):
    workflow_id: str
    objective: str
    tenant_id: str
    status: Literal["Completed", "NeedsReview", "NoAction", "Failed"]
    planner_summary: str
    data_sources: list[str]
    recommendations: list[InventoryRecommendation] = Field(default_factory=list)
    insights: list[InventoryHealthInsight] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
