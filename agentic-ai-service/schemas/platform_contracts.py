"""Contracts for the Platform Operations Copilot - the platform owner's
cross-tenant agent.

Every other flow in this service is scoped to one tenant and acts on that
tenant's own data. This one is the opposite: it reads across every business
on the platform and proposes interventions that move money (a comped plan, an
extended term) or a business's standing. That difference drives two rules
that show up throughout these schemas:

  1. Nothing here carries a tenant's operational data - no customer names,
     no booking contents. The agent reasons over subscription standing and
     activity counts, which is all an intervention decision needs, and is
     the least it can be given.

  2. Nothing here is an instruction to act. The pipeline's output is a
     *proposal*; the fields that would execute it (the OTP, the applied
     result) do not exist on this side of the wire at all. Execution is
     ASP.NET Core's, behind a fresh authenticator code the agent cannot
     produce.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from pydantic import BaseModel, Field

# The interventions the owner console can actually carry out. The safety
# agent refuses anything outside this list, so a model that invents
# "delete_tenant" gets a rejection rather than a best-effort match.
InterventionKind = Literal["extend_term", "comp_plan", "winback_offer", "contact_owner", "no_action"]


class PlatformPlanRequest(BaseModel):
    """POST /platform/plan. `auth_token` is the owner's platform-scoped JWT,
    minted after MFA; tools call back into /api/platform/* with it, so the
    same PlatformOwner policy that guards the console guards the agent. It is
    never echoed into a response or a trace."""

    objective: str
    actor_email: str
    # A ceiling the owner sets per run. The safety agent treats it as hard,
    # so "spend whatever it takes" is not expressible even by prompt.
    max_interventions: int = Field(default=5, ge=1, le=25)
    max_comp_months: int = Field(default=12, ge=1, le=24)
    currency: str = "LKR"
    auth_token: str = Field(repr=False)


# ── Agent 1: Planner / Coordinator (no tools) ───────────────────────────
class PlatformPlanStep(BaseModel):
    order: int
    action: str
    assigned_agent: Literal["PlatformAnalysisAgent", "PlatformActionAgent", "PlatformSafetyAgent"]
    description: str


class PlatformPlannerOutput(BaseModel):
    plan: list[PlatformPlanStep]
    assigned_agents: list[str]
    # What the planner believes the objective is really asking for. Kept
    # separate from the objective so a vague request is visible as vague
    # rather than silently reinterpreted.
    interpreted_goal: str
    confidence_score: float = Field(ge=0.0, le=1.0)


# ── Agent 2: Domain Analysis (read-only tools) ──────────────────────────
class TenantRisk(BaseModel):
    tenant_id: str
    tenant_name: str
    plan_code: str
    status: str
    # 0 = healthy, 1 = about to leave. The model's judgement, which is why
    # the evidence that produced it travels alongside it.
    risk_score: float = Field(ge=0.0, le=1.0)
    risk_factors: list[str] = Field(default_factory=list)
    monthly_value: float = 0.0
    days_until_period_end: int | None = None
    open_invoices: int = 0


class PlatformAnalysisOutput(BaseModel):
    at_risk: list[TenantRisk]
    criteria_used: list[str]
    platform_summary: str


# ── Agent 3: Action / Tool (proposes, never executes) ───────────────────
class ProposedIntervention(BaseModel):
    tenant_id: str
    tenant_name: str
    kind: InterventionKind
    # Only meaningful for extend_term / comp_plan; the safety agent bounds
    # both against the request's ceilings.
    extend_days: int | None = None
    comp_plan_code: str | None = None
    comp_months: int | None = None
    rationale: str
    # What the platform gives up if this is approved, in the run's currency.
    estimated_cost: float = 0.0
    # What it protects, over the same horizon.
    protected_value: float = 0.0
    confidence: float = Field(ge=0.0, le=1.0)


class PlatformActionOutput(BaseModel):
    interventions: list[ProposedIntervention]
    reasoning: str


# ── Agent 4: Validation / Safety (deterministic, no LLM) ────────────────
class InterventionVerdict(BaseModel):
    """One proposal's fate. Kept per-intervention rather than as a single
    pass/fail for the batch: a run where four proposals are sound and one is
    out of policy should leave the owner with four to approve, not nothing."""

    tenant_id: str
    # A plain string, unlike ProposedIntervention.kind, and deliberately.
    # This records what was *proposed*, which includes proposals that are
    # invalid - and the commonest reason to refuse one is that its kind is
    # not a real intervention. Typing this as the strict Literal meant the
    # safety agent raised a ValidationError while trying to write the
    # rejection, turning a clean refusal into a crashed gate.
    kind: str
    accepted: bool
    reason: str | None = None
    # Present when the safety agent trimmed a value into policy instead of
    # rejecting it outright - the owner sees both numbers.
    adjusted_from: str | None = None


class PlatformSafetyOutput(BaseModel):
    is_allowed: bool
    # Always true when anything survives validation. High-impact by
    # definition: these move money and access.
    requires_human_approval: bool
    accepted: list[ProposedIntervention] = Field(default_factory=list)
    verdicts: list[InterventionVerdict] = Field(default_factory=list)
    rejection_reason: str | None = None
    validation_notes: list[str] = Field(default_factory=list)
    total_estimated_cost: float = 0.0


# ── Observability ───────────────────────────────────────────────────────
class PlatformToolCall(BaseModel):
    tool: str
    agent: str
    duration_ms: int
    success: bool
    error: str | None = None


class PlatformLlmCall(BaseModel):
    model: str
    attempt: int
    duration_ms: int
    ok: bool
    error: str | None = None


class PlatformAgentStep(BaseModel):
    agent: str
    duration_ms: int
    ok: bool
    error: str | None = None


class PlatformTrace(BaseModel):
    workflow_id: str
    objective: str
    actor_email: str
    # AwaitingApproval is the success path here. A run that "Completed" on
    # its own would mean something acted without the owner, which this
    # pipeline has no route to do.
    status: Literal["AwaitingApproval", "NothingToDo", "Failed", "Rejected"]
    planner_output: PlatformPlannerOutput | None = None
    analysis_output: PlatformAnalysisOutput | None = None
    action_output: PlatformActionOutput | None = None
    safety_output: PlatformSafetyOutput | None = None
    tool_calls: list[PlatformToolCall] = Field(default_factory=list)
    llm_calls: list[PlatformLlmCall] = Field(default_factory=list)
    agent_steps: list[PlatformAgentStep] = Field(default_factory=list)
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: datetime | None = None

    def scrubbed(self) -> dict[str, Any]:
        """The trace as it is safe to persist and show. There is no token on
        the trace to begin with; this exists so that stays true by
        construction if a field is ever added."""
        data = self.model_dump(mode="json")
        data.pop("auth_token", None)
        return data
