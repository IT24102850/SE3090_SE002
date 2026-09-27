"""Observability and resilience evidence (spec 9.1 Observability/Security, 12).

The rubric asks for auditable execution summaries covering tool calls,
timings, validation results, errors and retries. `WorkflowTrace` has always
declared those fields; these tests exist because declaring a field and
filling it are different things, and an always-empty `tool_calls` list looks
identical to a workflow that used no tools.

The resilience half matters just as much: free-tier Gemini returns 503
"high demand" on individual models under load, and before the retry/fallback
layer a single spike aborted the whole workflow.
"""
from datetime import timedelta
from unittest.mock import MagicMock

import httpx
import pytest

import gemini_client
from agents import action_tool_agent
from gemini_client import AgentSafeFailure
from schemas.contracts import ActionToolOutput, ProposedBooking
from tools.booking_tools import BookingToolsClient, ToolError

PIPELINE_AGENTS = ["PlannerAgent", "DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"]


# ── Per-agent step timings ──────────────────────────────────────────────
def test_every_agent_stage_is_timed_and_recorded_in_order(
    api_client, auth_headers, base_request, future_slot, monkeypatch,
    mock_planner, mock_domain_analysis, mock_booking_tools_success,
):
    """A completed workflow must account for all four agents, in pipeline
    order, each with a wall-clock cost."""
    monkeypatch.setattr(
        action_tool_agent, "run",
        MagicMock(return_value=ActionToolOutput(
            proposed_bookings=[ProposedBooking(
                resource_id="77777777-7777-7777-7777-777777777777",
                booking_type_id=base_request["extra_constraints"]["booking_type_id"],
                scheduled_datetime=future_slot, duration_minutes=30, has_conflict=False,
            )],
            confidence=0.9,
        )),
    )

    body = api_client.post("/plan", json=base_request, headers=auth_headers).json()

    assert [s["agent"] for s in body["agent_steps"]] == PIPELINE_AGENTS
    assert all(s["ok"] for s in body["agent_steps"])
    assert all(s["duration_ms"] >= 0 for s in body["agent_steps"])


def test_a_failing_stage_is_attributed_to_its_agent(
    api_client, auth_headers, base_request, monkeypatch, mock_planner, mock_domain_analysis,
):
    """"Which agent was it in when it died" must be answerable from the
    trace. Outputs alone cannot say: they are simply absent."""
    monkeypatch.setattr(
        action_tool_agent, "run",
        MagicMock(side_effect=AgentSafeFailure("model refused to produce a slot")),
    )

    response = api_client.post("/plan", json=base_request, headers=auth_headers)
    assert response.status_code == 422
    body = response.json()

    assert body["status"] == "Failed"
    steps = {s["agent"]: s for s in body["agent_steps"]}
    # The two stages before it completed; the third is recorded as the failure.
    assert steps["PlannerAgent"]["ok"] is True
    assert steps["DomainAnalysisAgent"]["ok"] is True
    assert steps["ActionToolAgent"]["ok"] is False
    assert "refused" in steps["ActionToolAgent"]["error"]
    # A stage that never ran must not be invented.
    assert "ValidationSafetyAgent" not in steps


# ── Tool-call audit trail ───────────────────────────────────────────────
def _client_with_transport(handler) -> BookingToolsClient:
    client = BookingToolsClient(base_url="http://testserver/api", auth_token="t")
    client._client = httpx.Client(base_url="http://testserver/api", transport=httpx.MockTransport(handler))
    return client


def test_tool_calls_are_recorded_with_agent_and_timing():
    client = _client_with_transport(lambda r: httpx.Response(200, json={"totalPast": 2, "noShows": 0, "rate": 0.0}))
    client.current_agent = "ValidationSafetyAgent"

    client.predict_no_show_probability()

    assert len(client.calls) == 1
    call = client.calls[0]
    assert call["tool"] == "predict_no_show_probability"
    assert call["agent"] == "ValidationSafetyAgent"
    assert call["success"] is True
    assert call["error"] is None
    assert call["duration_ms"] >= 0


def test_a_failing_tool_is_still_recorded():
    """The call that broke the workflow is the one most worth auditing, so
    recording must happen on the raising path too."""
    client = _client_with_transport(lambda r: httpx.Response(500, json={"message": "boom"}))
    client.current_agent = "DomainAnalysisAgent"

    with pytest.raises(ToolError):
        client.predict_no_show_probability()

    assert len(client.calls) == 1
    assert client.calls[0]["success"] is False
    assert client.calls[0]["error"]


# ── LLM retry / model fallback ──────────────────────────────────────────
class _Boom(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} simulated")
        self.code = code


def _driver(monkeypatch, outcomes: dict[str, list]):
    """Fake one attempt: `outcomes` maps model name -> per-attempt results,
    each either an exception to raise or a value to return."""
    seen: list[str] = []

    def attempt(model: str):
        seen.append(model)
        result = outcomes[model].pop(0)
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(gemini_client.time, "sleep", lambda _s: None)  # no real backoff in tests
    return attempt, seen


def test_transient_error_is_retried_on_the_same_model(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    gemini_client.reset_call_log()
    attempt, seen = _driver(monkeypatch, {"primary": [_Boom(503), "recovered"]})

    assert gemini_client._call_with_resilience(attempt, model="primary") == "recovered"
    assert seen == ["primary", "primary"]

    log = gemini_client.drain_call_log()
    assert [(e["model"], e["attempt"], e["ok"]) for e in log] == [("primary", 1, False), ("primary", 2, True)]


def test_permanent_error_skips_straight_to_the_next_model(monkeypatch):
    """A 404 means this key cannot use that model. Retrying it three times
    only spends the demo's clock, so the chain must move on immediately."""
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    gemini_client.reset_call_log()
    attempt, seen = _driver(monkeypatch, {"primary": [_Boom(404)], "backup-model": ["ok"]})

    assert gemini_client._call_with_resilience(attempt, model="primary") == "ok"
    assert seen == ["primary", "backup-model"]  # exactly one attempt on primary


def test_exhausting_every_model_fails_safely(monkeypatch):
    """Still a safe failure, not a crash: the caller's 422 path is unchanged."""
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    monkeypatch.setattr(gemini_client, "GEMINI_MAX_ATTEMPTS", 2)
    gemini_client.reset_call_log()
    attempt, _ = _driver(monkeypatch, {"primary": [_Boom(503)] * 2, "backup-model": [_Boom(503)] * 2})

    with pytest.raises(AgentSafeFailure) as excinfo:
        gemini_client._call_with_resilience(attempt, model="primary")
    assert "primary" in str(excinfo.value) and "backup-model" in str(excinfo.value)
    assert len(gemini_client.drain_call_log()) == 4  # every attempt is auditable


def test_the_requested_model_is_never_retried_twice_in_the_chain(monkeypatch):
    """Naming the default among the fallbacks must not double its attempts."""
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "primary,backup-model")
    assert gemini_client._model_chain("primary") == ["primary", "backup-model"]


def test_a_failed_workflow_still_returns_its_tool_and_model_calls(
    api_client, auth_headers, base_request, monkeypatch, mock_planner, mock_domain_analysis,
):
    """Regression: the trace is finalised before the body is serialized.

    Draining the recorded calls in a `finally` reads as equivalent but is
    not - `finally` runs after the return expression has been evaluated, so
    the 422 body went out with empty `tool_calls`/`llm_calls`. The failure
    paths are precisely where the audit trail is worth having, so an empty
    trace there is worse than no feature at all.
    """
    import time as _time

    def explode(**kwargs):
        client = kwargs["client"]
        client._record("detect_conflicts", _time.monotonic(), ok=False, error="simulated tool failure")
        gemini_client._record_call(model="test-model", attempt=2, duration_ms=7, ok=False, error="simulated 503")
        raise AgentSafeFailure("action agent gave up")

    monkeypatch.setattr(action_tool_agent, "run", explode)

    response = api_client.post("/plan", json=base_request, headers=auth_headers)
    assert response.status_code == 422
    body = response.json()

    assert body["status"] == "Failed"
    assert [t["tool"] for t in body["tool_calls"]] == ["detect_conflicts"]
    assert body["tool_calls"][0]["success"] is False
    assert [(c["model"], c["attempt"]) for c in body["llm_calls"]] == [("test-model", 2)]


def test_an_exhausted_quota_is_not_retried(monkeypatch):
    """"Exceeded your current quota" is a plan allowance, not a spike;
    retrying it three times with backoff only spends the demo's clock."""
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    gemini_client.reset_call_log()
    quota = _Boom(429)
    quota.args = ("429 RESOURCE_EXHAUSTED. You exceeded your current quota",)
    attempt, seen = _driver(monkeypatch, {"primary": [quota], "backup-model": ["ok"]})

    assert gemini_client._call_with_resilience(attempt, model="primary") == "ok"
    assert seen == ["primary", "backup-model"]


def test_a_plain_rate_limit_is_still_retried(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    attempt, seen = _driver(monkeypatch, {"primary": [_Boom(429), "ok"]})
    assert gemini_client._call_with_resilience(attempt, model="primary") == "ok"
    assert seen == ["primary", "primary"]


def test_the_breaker_skips_a_spent_model_on_the_next_call(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "backup-model")
    quota = _Boom(429)
    quota.args = ("429 You exceeded your current quota",)
    attempt, seen = _driver(monkeypatch, {"primary": [quota], "backup-model": ["first", "second"]})

    gemini_client._call_with_resilience(attempt, model="primary")
    seen.clear()
    assert gemini_client._call_with_resilience(attempt, model="primary") == "second"
    assert seen == ["backup-model"]          # primary not even tried


def test_the_breaker_never_leaves_an_empty_chain(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL_FALLBACKS", "")
    quota = _Boom(429)
    quota.args = ("429 You exceeded your current quota",)
    attempt, seen = _driver(monkeypatch, {"primary": [quota, "recovered"]})

    with pytest.raises(AgentSafeFailure):
        gemini_client._call_with_resilience(attempt, model="primary")
    # Every model is cooling down, so it is tried anyway rather than refused.
    assert gemini_client._call_with_resilience(attempt, model="primary") == "recovered"
