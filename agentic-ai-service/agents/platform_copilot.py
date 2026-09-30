"""Orchestrator for the Platform Operations Copilot.

Runs Planner → Domain Analysis → Action → Safety and returns one trace.

Two behaviours are deliberate and worth stating, because both look like
bugs until you know why:

  A model outage does not fail the run. Each language-model stage has a
    deterministic counterpart, and the pipeline falls through to it. The
    agents, the tools and the safety gate are all still real; only the
    reading of the objective gets simpler. The trace records which happened,
    so "it produced proposals" is never mistaken for "the model produced
    them".

  A successful run ends AwaitingApproval, never Completed. There is no
    branch here that applies anything. Completion is something the owner
    does afterwards, in ASP.NET Core, with an authenticator code.
"""
from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

import gemini_client
from agents import platform_action, platform_analysis, platform_planner, platform_safety
from schemas.platform_contracts import (
    PlatformAgentStep,
    PlatformAnalysisOutput,
    PlatformLlmCall,
    PlatformPlanRequest,
    PlatformToolCall,
    PlatformTrace,
)
from tools.platform_tools import PlatformToolsClient

logger = logging.getLogger("agentic-ai-service.platform")


def _step(trace: PlatformTrace, client: PlatformToolsClient | None, agent: str, fn):
    """Run one agent, timing it and attributing its tool calls, whether or
    not it succeeds. 'Which agent was the run in when it died' is the first
    question asked of a failure and is unanswerable from outputs alone."""
    if client is not None:
        client.agent = agent
    started = time.monotonic()
    try:
        result = fn()
    except Exception as e:
        trace.agent_steps.append(
            PlatformAgentStep(agent=agent, duration_ms=int((time.monotonic() - started) * 1000), ok=False, error=str(e)[:200])
        )
        raise
    trace.agent_steps.append(
        PlatformAgentStep(agent=agent, duration_ms=int((time.monotonic() - started) * 1000), ok=True, error=None)
    )
    return result


def _drain_tool_calls(trace: PlatformTrace, client: PlatformToolsClient) -> None:
    for call in client.calls:
        trace.tool_calls.append(PlatformToolCall(**call))
    client.calls.clear()


def _drain_llm_calls(trace: PlatformTrace) -> None:
    """Collect every model attempt made since the last drain.

    Without this the trace shows no model calls at all, and a run the model
    genuinely reasoned through is indistinguishable from one the
    deterministic fallbacks carried - which is exactly the distinction the
    rest of the design leans on being visible. Several records for one
    logical step is the retry/fallback layer working, not a fault.
    """
    for call in gemini_client.drain_call_log():
        trace.llm_calls.append(PlatformLlmCall(**call))


def run(request: PlatformPlanRequest, *, backend_base_url: str) -> PlatformTrace:
    trace = PlatformTrace(
        workflow_id=str(uuid.uuid4()),
        objective=request.objective,
        actor_email=request.actor_email,
        status="Failed",
    )
    # Start from a clean buffer so this run's trace shows this run's calls.
    gemini_client.reset_call_log()

    with PlatformToolsClient(backend_base_url, request.auth_token) as client:
        # ── 1. Planner ──────────────────────────────────────────────────
        def plan():
            try:
                return platform_planner.run(
                    objective=request.objective,
                    max_interventions=request.max_interventions,
                    currency=request.currency,
                )
            except Exception as e:  # noqa: BLE001
                logger.warning("Platform planner fell back to deterministic: %s", e)
                return platform_planner.deterministic_plan(request.objective)

        trace.planner_output = _step(trace, None, "PlatformPlannerAgent", plan)
        _drain_llm_calls(trace)

        # ── 2. Domain analysis ──────────────────────────────────────────
        # The tools run first and separately from the model: a tool failure
        # here is a platform problem and should stop the run, rather than
        # being handed to a model that then invents a tenant base.
        try:
            facts = _step(trace, client, "PlatformAnalysisAgent", lambda: platform_analysis.gather(client))
        except Exception as e:  # noqa: BLE001
            _drain_tool_calls(trace, client)
            _drain_llm_calls(trace)
            trace.status = "Failed"
            trace.error = f"Could not read the platform's own records: {e}"
            trace.completed_at = datetime.now(timezone.utc)
            return trace
        _drain_tool_calls(trace, client)

        def analyse() -> PlatformAnalysisOutput:
            try:
                return platform_analysis.run(objective=request.objective, facts=facts)
            except Exception as e:  # noqa: BLE001
                logger.warning("Platform analysis fell back to deterministic: %s", e)
                return platform_analysis.deterministic_analysis(facts)

        trace.analysis_output = _step(trace, client, "PlatformAnalysisAgent", analyse)
        _drain_llm_calls(trace)

        # Nothing at risk is a real, good answer - and a common one on a
        # healthy platform. It is not a failure and must not read as one.
        if not trace.analysis_output.at_risk:
            trace.status = "NothingToDo"
            trace.completed_at = datetime.now(timezone.utc)
            return trace

        # ── 3. Action ───────────────────────────────────────────────────
        activity = _step(
            trace, client, "PlatformActionAgent",
            lambda: platform_action.enrich(client, trace.analysis_output),
        )
        _drain_tool_calls(trace, client)

        def propose():
            try:
                return platform_action.run(
                    objective=request.objective,
                    analysis=trace.analysis_output,
                    activity=activity,
                    max_interventions=request.max_interventions,
                    max_comp_months=request.max_comp_months,
                    currency=request.currency,
                )
            except Exception as e:  # noqa: BLE001
                logger.warning("Platform action fell back to deterministic: %s", e)
                return platform_action.deterministic_actions(
                    trace.analysis_output, activity, request.max_interventions
                )

        trace.action_output = _step(trace, client, "PlatformActionAgent", propose)
        _drain_llm_calls(trace)

        # ── 4. Safety - deterministic, and never falls back to anything ──
        trace.safety_output = _step(
            trace, client, "PlatformSafetyAgent",
            lambda: platform_safety.run(
                analysis=trace.analysis_output,
                actions=trace.action_output,
                activity=activity,
                max_interventions=request.max_interventions,
                max_comp_months=request.max_comp_months,
            ),
        )
        _drain_tool_calls(trace, client)

    safety = trace.safety_output
    if not safety.is_allowed:
        trace.status = "Rejected"
        trace.error = safety.rejection_reason
    elif safety.accepted:
        trace.status = "AwaitingApproval"
    else:
        trace.status = "NothingToDo"

    trace.completed_at = datetime.now(timezone.utc)
    return trace
