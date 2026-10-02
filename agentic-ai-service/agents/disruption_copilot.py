"""Disruption Recovery Copilot: Planner -> Impact -> Recovery -> Safety.

One auditable workflow for "this resource is gone, where does everyone go?".
It works the same way for a clinic, a restaurant, a gym, a school and a tour
operator, because the only domain knowledge lives in disruption_policy - the
agents themselves are domain-neutral.

Delegation is also a permission boundary: each agent gets its own
`AgentToolbox`, so the planner reads nothing, the analyst cannot search
slots, and only the optimiser and the gate can look at availability.

Nothing here changes a booking. A finished run is a proposal that ASP.NET
Core persists and a manager approves; applying it is a separate request.
"""
from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any, Callable

import gemini_client
from agents import disruption_action, disruption_impact, disruption_planner, disruption_safety
from agents.disruption_policy import policy_for
from gemini_client import AgentSafeFailure
from schemas.contracts import AgentStepRecord, LlmCallRecord, ToolCallRecord
from schemas.disruption_contracts import ActionOutput, DisruptionRequest, DisruptionTrace, ImpactOutput
from tools.disruption_tools import AgentToolbox, DisruptionToolsClient, ToolError


def _stage(trace: DisruptionTrace, agent: str, fn: Callable[[], Any]) -> Any:
    """Run one agent, timing it and recording the step either way.

    Recording the failure path matters as much as the success path: "which
    agent was the workflow in when it died" is the first question asked of a
    failed run, and outputs alone cannot answer it.
    """
    started = time.monotonic()
    try:
        result = fn()
    except Exception as e:
        trace.agent_steps.append(AgentStepRecord(
            agent=agent, duration_ms=int((time.monotonic() - started) * 1000), ok=False, error=str(e)[:200]))
        raise
    trace.agent_steps.append(AgentStepRecord(
        agent=agent, duration_ms=int((time.monotonic() - started) * 1000), ok=True, error=None))
    return result


def _finalize(trace: DisruptionTrace, client: DisruptionToolsClient | None) -> DisruptionTrace:
    """Fold the recorded calls in before the response is serialized.

    Not in a `finally`: that runs after the return expression is evaluated,
    so every early return would ship an empty trace - exactly the failure
    paths where the trace matters most.
    """
    if client is not None:
        trace.tool_calls = [ToolCallRecord(**c) for c in client.calls]
    trace.llm_calls = [LlmCallRecord(**c) for c in gemini_client.drain_call_log()] or trace.llm_calls
    trace.completed_at = datetime.now(timezone.utc)
    return trace


def run(request: DisruptionRequest, client: DisruptionToolsClient, *, now: datetime | None = None) -> DisruptionTrace:
    now = now or datetime.now(timezone.utc)
    gemini_client.reset_call_log()
    policy = policy_for(request.business_type)

    trace = DisruptionTrace(
        objective=request.objective,
        tenant_id=request.tenant_id,
        business_type=request.business_type,
        resource_id=request.resource_id,
        status="Failed",
    )

    try:
        trace.planner = _stage(trace, "DisruptionPlannerAgent",
                               lambda: disruption_planner.plan(request, policy))
        if trace.planner.used_fallback:
            trace.warnings.append(
                "The language model was unavailable, so the trade's default recovery policy was used. "
                "Detection, limits and approval are unaffected - only the reading of the objective is simpler.")

        impact: ImpactOutput = _stage(trace, "ImpactAnalysisAgent", lambda: disruption_impact.run(
            resource_id=request.resource_id, window=request.window, policy=policy,
            toolbox=AgentToolbox(client, "ImpactAnalysisAgent"), now=now))
        trace.impact = impact
        trace.warnings.extend(impact.warnings)

        if not impact.affected:
            trace.status = "NoAction"
            trace.warnings.append(
                f"Nothing is booked on that {policy.resource_noun} during the outage, so there is nothing to move.")
            return _finalize(trace, client)

        action, resources_by_id, original_specialty = _stage(
            trace, "RecoveryActionAgent", lambda: disruption_action.run(
                impact=impact, policy=policy, intent=trace.planner.intent,
                tenant_id=request.tenant_id, branch_id=request.branch_id,
                disrupted_resource_id=request.resource_id,
                toolbox=AgentToolbox(client, "RecoveryActionAgent"), now=now))
        trace.action = action
        trace.warnings.extend(action.notes)

        trace.safety = _stage(trace, "DisruptionSafetyAgent", lambda: disruption_safety.run(
            action=action, affected=impact.affected, policy=policy, intent=trace.planner.intent,
            disrupted_resource_id=request.resource_id,
            toolbox=AgentToolbox(client, "DisruptionSafetyAgent"),
            resources_by_id=resources_by_id, original_specialty=original_specialty, now=now))

    except AgentSafeFailure as e:
        trace.status = "Failed"
        trace.error = str(e)
        return _finalize(trace, client)
    except ToolError as e:
        trace.status = "Failed"
        trace.error = f"Tool error: {e}"
        return _finalize(trace, client)
    except Exception as e:  # noqa: BLE001 - recorded, then returned as a safe failure
        trace.status = "Failed"
        trace.error = str(e)[:300]
        return _finalize(trace, client)

    safety = trace.safety
    if safety is not None and not safety.is_allowed:
        trace.status = "Rejected"
        trace.error = safety.rejection_reason
    else:
        # Always: moving somebody else's booking is the manager's call.
        trace.status = "AwaitingApproval"

    return _finalize(trace, client)
