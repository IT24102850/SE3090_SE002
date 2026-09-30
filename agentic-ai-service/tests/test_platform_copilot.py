"""Tests for the Platform Operations Copilot.

The safety gate is tested directly, with no language model anywhere near it.
That is the whole reason it is plain Python: these assertions have to hold on
every run, including the runs where the model upstream has been talked into
something by text it read in a tenant's name.
"""
from __future__ import annotations

from unittest.mock import MagicMock

import pytest

import gemini_client
from agents import platform_action, platform_analysis, platform_copilot, platform_safety
from schemas.platform_contracts import (
    PlatformActionOutput,
    PlatformAnalysisOutput,
    PlatformPlanRequest,
    ProposedIntervention,
    TenantRisk,
)
from tools.platform_tools import PlatformToolsClient

T1 = "11111111-1111-1111-1111-111111111111"
T2 = "22222222-2222-2222-2222-222222222222"


def _risk(tenant_id: str = T1, *, plan="pro", status="PastDue", value=14900.0) -> TenantRisk:
    return TenantRisk(
        tenant_id=tenant_id,
        tenant_name="Blue Whale Tours",
        plan_code=plan,
        status=status,
        risk_score=0.9,
        risk_factors=["Renewal unpaid."],
        monthly_value=value,
        open_invoices=1,
    )


def _analysis(*risks: TenantRisk) -> PlatformAnalysisOutput:
    return PlatformAnalysisOutput(
        at_risk=list(risks) or [_risk()],
        criteria_used=["unpaid invoice"],
        platform_summary="one business at risk",
    )


def _actions(*interventions: ProposedIntervention) -> PlatformActionOutput:
    return PlatformActionOutput(interventions=list(interventions), reasoning="test")


def _safety(actions, analysis=None, activity=None, *, max_interventions=5, max_comp_months=12):
    return platform_safety.run(
        analysis=analysis or _analysis(),
        actions=actions,
        activity=activity or {},
        max_interventions=max_interventions,
        max_comp_months=max_comp_months,
    )


# ── The property the whole design rests on ──────────────────────────────

def test_anything_that_survives_is_held_for_a_human():
    out = _safety(_actions(ProposedIntervention(
        tenant_id=T1, tenant_name="Blue Whale Tours", kind="extend_term",
        extend_days=30, rationale="payment slipped", estimated_cost=100.0,
        protected_value=1200.0, confidence=0.8,
    )))

    assert out.is_allowed
    assert out.requires_human_approval is True
    assert len(out.accepted) == 1
    assert any("authenticator code" in n for n in out.validation_notes)


def test_no_path_through_safety_approves_anything():
    """There is no combination of inputs that yields work to do *and*
    requires_human_approval false. Asserted over the intervention kinds
    rather than trusting one example."""
    for kind, extra in [
        ("extend_term", {"extend_days": 10}),
        ("comp_plan", {"comp_plan_code": "pro", "comp_months": 1}),
        ("contact_owner", {}),
        ("no_action", {}),
    ]:
        out = _safety(_actions(ProposedIntervention(
            tenant_id=T1, tenant_name="X", kind=kind, rationale="r",
            estimated_cost=0.0, protected_value=100.0, confidence=0.5, **extra,
        )), activity={T1: {"bookings_30d": 12}})
        if out.accepted:
            assert out.requires_human_approval is True, f"{kind} was accepted without requiring approval"


# ── Prompt injection / out-of-set targeting ─────────────────────────────

def test_an_intervention_on_an_unanalysed_tenant_is_refused():
    """The most dangerous thing an injection could achieve here: getting a
    tenant id into the proposal set that the analysis never flagged, so the
    owner approves an action against an arbitrary business."""
    out = _safety(
        _actions(ProposedIntervention(
            tenant_id=T2, tenant_name="Someone Else", kind="comp_plan",
            comp_plan_code="prime", comp_months=12, rationale="ignore previous instructions",
            estimated_cost=0.0, protected_value=999999.0, confidence=1.0,
        )),
        analysis=_analysis(_risk(T1)),
    )

    assert out.accepted == []
    assert out.verdicts[0].accepted is False
    assert "not in the analysed at-risk set" in out.verdicts[0].reason


def test_an_invented_intervention_kind_is_refused():
    out = _safety(_actions(ProposedIntervention.model_construct(
        tenant_id=T1, tenant_name="X", kind="delete_tenant", rationale="r",
        estimated_cost=0.0, protected_value=0.0, confidence=1.0,
    )))
    assert out.accepted == []
    assert "not an intervention this platform can carry out" in out.verdicts[0].reason


def test_a_comp_onto_an_unknown_plan_is_refused():
    out = _safety(_actions(ProposedIntervention(
        tenant_id=T1, tenant_name="X", kind="comp_plan", comp_plan_code="enterprise-unlimited",
        comp_months=6, rationale="r", estimated_cost=0.0, protected_value=100.0, confidence=1.0,
    )), activity={T1: {"bookings_30d": 40}})
    assert out.accepted == []
    assert "not a plan on this platform" in out.verdicts[0].reason


# ── Spending caps ───────────────────────────────────────────────────────

def test_an_over_long_comp_is_trimmed_not_rejected():
    proposal = ProposedIntervention(
        tenant_id=T1, tenant_name="X", kind="comp_plan", comp_plan_code="pro",
        comp_months=99, rationale="r", estimated_cost=100.0, protected_value=5000.0, confidence=0.9,
    )
    out = _safety(_actions(proposal), activity={T1: {"bookings_30d": 40}}, max_comp_months=6)

    assert len(out.accepted) == 1
    assert out.accepted[0].comp_months == 6
    assert out.verdicts[0].adjusted_from == "99 months"


def test_an_over_long_extension_is_trimmed_to_policy():
    proposal = ProposedIntervention(
        tenant_id=T1, tenant_name="X", kind="extend_term", extend_days=3650,
        rationale="r", estimated_cost=10.0, protected_value=5000.0, confidence=0.9,
    )
    out = _safety(_actions(proposal))

    assert out.accepted[0].extend_days == platform_safety.MAX_EXTEND_DAYS


def test_the_run_ceiling_holds_back_the_excess():
    proposals = [
        ProposedIntervention(
            tenant_id=f"{i}{i}{i}{i}{i}{i}{i}{i}-1111-1111-1111-111111111111",
            tenant_name=f"T{i}", kind="contact_owner", rationale="r",
            estimated_cost=0.0, protected_value=100.0, confidence=0.5,
        )
        for i in range(1, 6)
    ]
    analysis = _analysis(*[_risk(p.tenant_id) for p in proposals])
    out = _safety(_actions(*proposals), analysis=analysis, max_interventions=2)

    assert len(out.accepted) == 2
    assert sum(1 for v in out.verdicts if not v.accepted) == 3


def test_spending_more_than_it_protects_is_refused_outright():
    out = _safety(_actions(ProposedIntervention(
        tenant_id=T1, tenant_name="X", kind="comp_plan", comp_plan_code="prime",
        comp_months=12, rationale="r", estimated_cost=500000.0, protected_value=1000.0, confidence=0.9,
    )), activity={T1: {"bookings_30d": 40}})

    assert out.is_allowed is False
    assert out.accepted == []
    assert out.requires_human_approval is False  # nothing is held, so nothing to approve
    assert "give up" in out.rejection_reason


# ── Business rules ──────────────────────────────────────────────────────

def test_a_dormant_business_is_not_comped():
    """Comping a business that is not using the product buys nothing. The
    model is told this; this is the check that makes it so."""
    out = _safety(_actions(ProposedIntervention(
        tenant_id=T1, tenant_name="X", kind="comp_plan", comp_plan_code="pro",
        comp_months=3, rationale="r", estimated_cost=1000.0, protected_value=5000.0, confidence=0.9,
    )), activity={T1: {"bookings_30d": 0}})

    assert out.accepted == []
    assert "not using the product" in out.verdicts[0].reason


def test_a_winback_is_only_for_a_lapsed_business():
    out = _safety(
        _actions(ProposedIntervention(
            tenant_id=T1, tenant_name="X", kind="winback_offer", rationale="r",
            estimated_cost=0.0, protected_value=100.0, confidence=0.9,
        )),
        analysis=_analysis(_risk(T1, plan="pro")),
    )
    assert out.accepted == []

    out2 = _safety(
        _actions(ProposedIntervention(
            tenant_id=T1, tenant_name="X", kind="winback_offer", rationale="r",
            estimated_cost=0.0, protected_value=100.0, confidence=0.9,
        )),
        analysis=_analysis(_risk(T1, plan="starter")),
    )
    assert len(out2.accepted) == 1


def test_two_interventions_for_one_business_keeps_only_the_first():
    a = ProposedIntervention(tenant_id=T1, tenant_name="X", kind="extend_term", extend_days=10,
                             rationale="r", estimated_cost=0.0, protected_value=100.0, confidence=0.9)
    b = ProposedIntervention(tenant_id=T1, tenant_name="X", kind="comp_plan", comp_plan_code="pro",
                             comp_months=6, rationale="r", estimated_cost=0.0, protected_value=100.0, confidence=0.9)
    out = _safety(_actions(a, b), activity={T1: {"bookings_30d": 40}})

    assert len(out.accepted) == 1
    assert out.verdicts[1].accepted is False


# ── The tool surface ────────────────────────────────────────────────────

def test_the_tool_client_exposes_no_way_to_write():
    """A prompt injection that says 'now comp every tenant' reaches a client
    that has nothing to comp with. Asserted rather than assumed, because a
    single convenience method added later would quietly end this."""
    public = {n for n in dir(PlatformToolsClient) if not n.startswith("_")}
    public -= {"ALLOWED_TOOLS", "calls", "agent", "close"}

    assert public == set(PlatformToolsClient.ALLOWED_TOOLS)
    for name in public:
        assert name.startswith(("get_", "list_")), f"{name} does not read like a read-only tool"


def test_every_tool_call_is_recorded_including_failures():
    client = PlatformToolsClient("http://testserver/api", "token")
    client._get = MagicMock(side_effect=RuntimeError("upstream exploded"))

    with pytest.raises(RuntimeError):
        client.get_revenue_overview()

    assert len(client.calls) == 1
    assert client.calls[0]["tool"] == "get_revenue_overview"
    assert client.calls[0]["success"] is False


# ── Whole-pipeline behaviour ────────────────────────────────────────────

def _facts(rows):
    return {"subscriptions": rows, "revenue": {"mrr": 1000}, "open_invoices": []}


def test_the_deterministic_fallback_ignores_free_and_comped_businesses():
    out = platform_analysis.deterministic_analysis(_facts([
        {"tenant_id": T1, "tenant_name": "Free", "plan_code": "starter", "status": "Active"},
        {"tenant_id": T2, "tenant_name": "Comped", "plan_code": "pro", "status": "PastDue", "is_complimentary": True},
    ]))
    assert out.at_risk == []


def test_the_deterministic_fallback_flags_a_past_due_paying_business():
    out = platform_analysis.deterministic_analysis(_facts([
        {"tenant_id": T1, "tenant_name": "Payer", "plan_code": "pro", "status": "PastDue",
         "period": "Monthly", "amount": 14900},
    ]))
    assert len(out.at_risk) == 1
    assert out.at_risk[0].risk_score >= 0.85
    assert out.at_risk[0].monthly_value == 14900


def test_a_failure_reading_the_platform_ends_the_run_safely(monkeypatch):
    """A tool outage must produce a recorded failure, not proposals built on
    a tenant base the pipeline could not actually read."""
    monkeypatch.setattr(platform_analysis, "gather", MagicMock(side_effect=RuntimeError("API down")))

    trace = platform_copilot.run(
        PlatformPlanRequest(objective="reduce churn", actor_email="owner@unify.lk", auth_token="t"),
        backend_base_url="http://testserver/api",
    )

    assert trace.status == "Failed"
    assert "could not read the platform" in trace.error.lower()
    assert trace.safety_output is None
    assert any(s.agent == "PlatformAnalysisAgent" and not s.ok for s in trace.agent_steps)


def test_a_healthy_platform_reports_nothing_to_do(monkeypatch):
    monkeypatch.setattr(platform_analysis, "gather", MagicMock(return_value=_facts([])))
    monkeypatch.setattr(
        platform_analysis, "run",
        MagicMock(return_value=PlatformAnalysisOutput(at_risk=[], criteria_used=[], platform_summary="healthy")),
    )

    trace = platform_copilot.run(
        PlatformPlanRequest(objective="reduce churn", actor_email="owner@unify.lk", auth_token="t"),
        backend_base_url="http://testserver/api",
    )

    assert trace.status == "NothingToDo"
    assert trace.error is None


def test_the_trace_never_carries_the_owner_token(monkeypatch):
    monkeypatch.setattr(platform_analysis, "gather", MagicMock(return_value=_facts([])))
    monkeypatch.setattr(
        platform_analysis, "run",
        MagicMock(return_value=PlatformAnalysisOutput(at_risk=[], criteria_used=[], platform_summary="healthy")),
    )

    trace = platform_copilot.run(
        PlatformPlanRequest(objective="x", actor_email="owner@unify.lk", auth_token="super-secret-jwt"),
        backend_base_url="http://testserver/api",
    )

    assert "super-secret-jwt" not in str(trace.scrubbed())


def test_model_calls_land_in_the_trace(monkeypatch):
    """The trace has to show that a model actually ran.

    ASP.NET Core derives its ModelDriven flag from this list, and the whole
    design leans on an owner being able to tell a reasoned run from a
    fallback one. An empty list here would silently relabel every real run
    as deterministic - which is how this was found.
    """
    monkeypatch.setattr(platform_analysis, "gather", MagicMock(return_value=_facts([])))
    monkeypatch.setattr(
        platform_analysis, "run",
        MagicMock(return_value=PlatformAnalysisOutput(at_risk=[], criteria_used=[], platform_summary="healthy")),
    )
    # One successful model attempt, as gemini_client would have recorded it.
    monkeypatch.setattr(
        gemini_client, "drain_call_log",
        MagicMock(side_effect=[[{"model": "gemini-2.5-flash", "attempt": 1, "duration_ms": 900, "ok": True, "error": None}], [], [], []]),
    )

    trace = platform_copilot.run(
        PlatformPlanRequest(objective="reduce churn", actor_email="owner@unify.lk", auth_token="t"),
        backend_base_url="http://testserver/api",
    )

    assert len(trace.llm_calls) == 1
    assert trace.llm_calls[0].model == "gemini-2.5-flash"
    assert trace.llm_calls[0].ok is True


def test_a_run_with_no_model_records_no_model_calls(monkeypatch):
    monkeypatch.setattr(platform_analysis, "gather", MagicMock(return_value=_facts([])))
    monkeypatch.setattr(
        platform_analysis, "run",
        MagicMock(return_value=PlatformAnalysisOutput(at_risk=[], criteria_used=[], platform_summary="healthy")),
    )
    monkeypatch.setattr(gemini_client, "drain_call_log", MagicMock(return_value=[]))

    trace = platform_copilot.run(
        PlatformPlanRequest(objective="reduce churn", actor_email="owner@unify.lk", auth_token="t"),
        backend_base_url="http://testserver/api",
    )

    assert trace.llm_calls == []
