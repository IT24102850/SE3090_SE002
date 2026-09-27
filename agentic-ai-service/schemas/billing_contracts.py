"""Contracts for the Billing Copilot: the planner and narrator that sit at
the two edges of the billing Domain Analysis Agent (assignment component
3.7).

The detection itself is **not** here and never will be. It lives in
`BillingDomainAnalysisAgent.cs` as deterministic C#, because a fraud surface
has to flag the same invoice the same way on every run - "invoice with a 50%
discount on a $10 item MUST flag for review" is a golden case, and MUST
means every run, forever. A sampled language model cannot promise that.

What the model does instead is turn a manager's sentence into the request
the agent already accepts, and read the pattern across the findings the
agent produced:

    input edge : "check last quarter for discount abuse at the Galle branch"
                 -> { analysis_type: "anomalies", days_back: 90, ... }
    output edge: three excessive_discount anomalies -> "same staff member,
                 one week, worth reviewing together"

Every field the planner returns is re-validated against these contracts and
then clamped again in C# before anything runs. The direction of travel is
one-way: the planner may **narrow** a request (a shorter window, a tighter
discount cap) and may never widen one. It cannot invent an analysis type,
reach past the one-year data cap, raise a threshold, or approve anything -
approval thresholds live in `ThresholdConfig` on the C# side and no model
output reaches them.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from schemas.contracts import AgentStepRecord, LlmCallRecord

# -- The agent's fixed vocabulary, mirroring the C# side ------------------
# These five names are BillingDomainAnalysisAgent.AllowedTools, and the six
# types are BillingAnalysisTypes.All. A plan that names anything else is not
# a plan this system can run, so it fails schema validation here rather than
# being forwarded and refused later.
BillingTool = Literal[
    "query_revenue_trends",
    "detect_billing_anomalies",
    "validate_insurance_claim",
    "compare_pricing_benchmarks",
    "calculate_commission_split",
]

BILLING_TOOLS: tuple[str, ...] = BillingTool.__args__  # type: ignore[attr-defined]

BillingAnalysisType = Literal["full", "anomalies", "revenue", "insurance", "pricing", "commission"]

BILLING_ANALYSIS_TYPES: tuple[str, ...] = BillingAnalysisType.__args__  # type: ignore[attr-defined]

# Mirrors BillingDomainAnalysisAgent.PlanFor: which tools each analysis type
# runs, in order. Kept here so the planner's plan can be checked against the
# reach the chosen type actually has, instead of describing work that will
# not happen.
ANALYSIS_TOOLS: dict[str, tuple[str, ...]] = {
    "anomalies": ("detect_billing_anomalies",),
    "revenue": ("query_revenue_trends",),
    "insurance": ("validate_insurance_claim",),
    "pricing": ("compare_pricing_benchmarks",),
    "commission": ("calculate_commission_split",),
    "full": ("query_revenue_trends", "detect_billing_anomalies",
             "validate_insurance_claim", "compare_pricing_benchmarks"),
}

# The C# DataRange cap is one year; the planner cannot ask for more history
# than the agent is allowed to load.
MAX_DAYS_BACK = 366
MAX_OBJECTIVE_CHARS = 500

# Anomaly types BillingDomainAnalysisAgent can actually raise. A prediction
# outside this set would be a promise the detector cannot keep.
FindingKind = Literal[
    "excessive_discount",
    "tax_out_of_range",
    "duplicate_invoice",
    "overpayment",
    "amount_mismatch",
    "revenue_drop",
    "price_outlier",
    "claim_exceeds_invoice",
    "claim_policy_mismatch",
    "high_value_invoice",
    "commission_exceeds_deal",
    "other",
]

FINDING_KINDS: tuple[str, ...] = FindingKind.__args__  # type: ignore[attr-defined]


# -- Thresholds ----------------------------------------------------------
class BillingThresholds(BaseModel):
    """The tenant's configured thresholds, sent *to* the planner as context
    so it knows what it is allowed to tighten towards. Defaults match
    `ThresholdConfig` in C#.

    Nothing the model returns is ever deserialized into this type. The
    planner's only lever over a threshold is
    `BillingIntent.tighten_discount_cap_to`, which can lower the discount cap
    and can do nothing else - the approval amounts in particular are
    unreachable from model output by construction, not by instruction.
    """

    max_discount_percent: float = 30.0
    adjustment_approval_amount: float = 100.0
    claim_approval_amount: float = 500.0
    min_tax_percent: float = 0.0
    max_tax_percent: float = 25.0
    revenue_drop_percent: float = 40.0
    price_deviation_percent: float = 50.0
    duplicate_window_minutes: int = 10
    high_value_invoice_amount: float = 1_000_000.0


# -- Agent 1 of the billing workflow: Planner / Coordinator --------------
class BillingIntent(BaseModel):
    """What the planner understood the objective to be asking for.

    Every field is a narrowing. `days_back` is bounded by the same one-year
    cap the C# request validator applies; `tighten_discount_cap_to` is
    dropped later if it is not *stricter* than the configured cap.
    """

    analysis_type: BillingAnalysisType = "full"
    days_back: int = Field(default=30, ge=1, le=MAX_DAYS_BACK)
    # Lower the discount cap for this run only. Never raises it: a value at
    # or above the configured cap is discarded in `_sanitise`.
    tighten_discount_cap_to: float | None = Field(default=None, ge=0.0, le=100.0)
    # Commission analysis only - the deal to split, if the objective names one.
    deal_amount: float | None = Field(default=None, ge=0.0)
    # Plain-English note for the UI: what the planner thinks it is looking
    # at. Advisory text, never a filter - the agent's scope stays the whole
    # tenant, because a model narrowing *what gets audited* could be talked
    # into looking away from the fraud.
    focus: str = ""
    rationale: str = ""

    @field_validator("focus", "rationale")
    @classmethod
    def _trim(cls, value: str) -> str:
        return " ".join(value.split())[:300]


class BillingPlanStep(BaseModel):
    """One step of the plan, delegated to the agent that owns it with the
    tools that step is allowed to use (spec 2.7/3.7 delegation)."""

    order: int = Field(ge=1)
    action: str
    # One agent owns billing analysis; naming it keeps the stored plan
    # readable next to the booking and inventory workflows in the same table.
    assigned_agent: Literal["BillingDomainAnalysisAgent", "BillingApprovalGate"] = "BillingDomainAnalysisAgent"
    description: str = ""
    tools: list[BillingTool] = Field(default_factory=list)

    @field_validator("action", "description")
    @classmethod
    def _trim(cls, value: str) -> str:
        return " ".join(value.split())[:300]


class PredictedFinding(BaseModel):
    """What the planner expects the detector to find, before any data has
    been read. Predicted, not detected - the value is that a manager can see
    the agent's expectation next to the real result and notice when the two
    disagree."""

    kind: FindingKind
    likelihood: float = Field(ge=0.0, le=1.0)
    description: str = ""

    @field_validator("description")
    @classmethod
    def _trim(cls, value: str) -> str:
        return " ".join(value.split())[:300]


class BillingPlannerOutput(BaseModel):
    """The spec 3.7 planner contract: a plan delegating each step, what it
    expects those steps to find, and how confident it is."""

    plan: list[BillingPlanStep] = Field(min_length=1)
    assigned_agents: list[str] = Field(default_factory=list)
    predicted_findings: list[PredictedFinding] = Field(default_factory=list)
    confidence_score: float = Field(ge=0.0, le=1.0)
    intent: BillingIntent = Field(default_factory=BillingIntent)
    summary: str = ""
    # True when every model in the fallback chain was unavailable and the
    # deterministic keyword planner produced this instead.
    used_fallback: bool = False


# -- The counterpart at the output edge: the narrator --------------------
class FindingTheme(BaseModel):
    """A pattern the narrator read *across* findings the detector already
    raised. It never introduces a finding of its own: `anomaly_ids` must
    reference anomalies that were passed in."""

    title: str
    detail: str
    anomaly_ids: list[str] = Field(default_factory=list, max_length=20)
    severity: Literal["low", "medium", "high", "critical"] = "medium"

    @field_validator("title", "detail")
    @classmethod
    def _trim(cls, value: str) -> str:
        return " ".join(value.split())[:600]


class BillingNarrative(BaseModel):
    headline: str = ""
    themes: list[FindingTheme] = Field(default_factory=list)
    suggested_next_steps: list[str] = Field(default_factory=list, max_length=6)
    used_fallback: bool = False

    @field_validator("headline")
    @classmethod
    def _trim(cls, value: str) -> str:
        return " ".join(value.split())[:400]


# -- Requests ------------------------------------------------------------
class BillingPlanRequest(BaseModel):
    """POST /billing/plan.

    `auth_token` is the calling manager's own JWT, forwarded by ASP.NET Core
    for symmetry with the other two workflows. This route reads no business
    data at all - the planner reasons over the objective text only - so the
    token is accepted and never used, and never echoed into the response.
    """

    objective: str = Field(min_length=3, max_length=MAX_OBJECTIVE_CHARS)
    tenant_id: str
    business_type: str = "General"
    currency: str = "USD"
    thresholds: BillingThresholds = Field(default_factory=BillingThresholds)
    auth_token: str = Field(default="", repr=False)

    @field_validator("objective")
    @classmethod
    def _clean_objective(cls, value: str) -> str:
        # Control characters have no business in a billing objective and are
        # a common carrier for prompt-injection payloads.
        cleaned = "".join(ch for ch in value if ch.isprintable() or ch in " \t")
        return " ".join(cleaned.split())


class AnomalyDigest(BaseModel):
    """One anomaly as the narrator sees it: enough to spot a pattern, and no
    more. Amounts and labels come from the C# detector, so the narrator can
    quote them but cannot change them."""

    id: str
    type: str
    severity: str = "medium"
    entity_label: str | None = None
    description: str = ""
    amount: float | None = None


class BillingNarrateRequest(BaseModel):
    """POST /billing/narrate - the output edge, called after the C# agent has
    finished. It receives findings, never raw billing data."""

    objective: str = Field(default="", max_length=MAX_OBJECTIVE_CHARS)
    analysis_type: BillingAnalysisType = "full"
    tenant_id: str
    currency: str = "USD"
    anomalies: list[AnomalyDigest] = Field(default_factory=list, max_length=200)
    insights: list[str] = Field(default_factory=list, max_length=60)
    recommended_actions: list[str] = Field(default_factory=list, max_length=60)
    confidence_score: float = Field(default=0.0, ge=0.0, le=1.0)
    auth_token: str = Field(default="", repr=False)


# -- Traces --------------------------------------------------------------
class BillingPlanTrace(BaseModel):
    workflow_type: Literal["billing-copilot"] = "billing-copilot"
    workflow_id: str = ""
    objective: str
    tenant_id: str
    business_type: str
    status: Literal["Planned", "Failed"] = "Planned"
    planner: BillingPlannerOutput | None = None
    thresholds: BillingThresholds = Field(default_factory=BillingThresholds)
    warnings: list[str] = Field(default_factory=list)
    agent_steps: list[AgentStepRecord] = Field(default_factory=list)
    llm_calls: list[LlmCallRecord] = Field(default_factory=list)
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class BillingNarrateTrace(BaseModel):
    workflow_type: Literal["billing-narrative"] = "billing-narrative"
    tenant_id: str
    status: Literal["Narrated", "Failed"] = "Narrated"
    narrative: BillingNarrative | None = None
    warnings: list[str] = Field(default_factory=list)
    llm_calls: list[LlmCallRecord] = Field(default_factory=list)
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
