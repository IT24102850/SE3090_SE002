"""Schedule Copilot orchestration: Planner -> Domain Analysis -> Action/Tool
-> Validation/Safety, as one auditable workflow.

The Planner coordinates by contract, not by improvisation: its plan names
the agent for each step, the merged priority rules it produced are the only
behaviour the optimiser applies, and its capped target is the only count the
safety gate accepts. Each agent receives its own `AgentToolbox`, so the
delegation is also a permission boundary - the planner reads no data, the
analyst cannot search slots, and only the optimiser and the gate can check
availability.

Nothing here books anything. A completed run is a *proposal*; ASP.NET Core
persists it on AgentWorkflows, a manager approves where the gate requires
it, and /apply creates the bookings. That keeps the one irreversible step
behind the human, which is where the spec puts it.
"""
from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any, Callable

import gemini_client
from agents import schedule_action, schedule_analyst, schedule_planner, schedule_safety
from gemini_client import AgentSafeFailure
from schemas.contracts import AgentStepRecord, LlmCallRecord, ToolCallRecord
from schemas.schedule_contracts import ScheduleMetrics, SchedulePlanRequest, ScheduleTrace
from tools.booking_tools import ToolError
from tools.schedule_tools import AgentToolbox, ScheduleToolsClient


def _stage(trace: ScheduleTrace, agent: str, fn: Callable[[], Any]) -> Any:
    started = time.monotonic()
    try:
        result = fn()
    except Exception as e:
        trace.agent_steps.append(AgentStepRecord(agent=agent, duration_ms=int((time.monotonic() - started) * 1000),
                                                 ok=False, error=str(e)[:200]))
        raise
    trace.agent_steps.append(AgentStepRecord(agent=agent, duration_ms=int((time.monotonic() - started) * 1000),
                                             ok=True, error=None))
    return result


def finalize(trace: ScheduleTrace, client: ScheduleToolsClient | None) -> ScheduleTrace:
    """Fold recorded calls into the trace before it is serialized."""
    if client is not None:
        trace.tool_calls = [ToolCallRecord(**c) for c in client.calls]
    trace.llm_calls = [LlmCallRecord(**c) for c in gemini_client.drain_call_log()] or trace.llm_calls
    trace.completed_at = datetime.now(timezone.utc)
    return trace


def run(request: SchedulePlanRequest, client: ScheduleToolsClient, *, now: datetime | None = None) -> ScheduleTrace:
    now = now or datetime.now(timezone.utc)
    c = request.constraints
    trace = ScheduleTrace(
        workflow_id="", objective=request.objective, tenant_id=request.tenant_id,
        business_type=request.business_type, status="Failed", constraints=c,
    )

    try:
        # 1. Planner / Coordinator - no tools, reasons over the objective only.
        client.current_agent = "PlannerAgent"
        planner = _stage(trace, "PlannerAgent", lambda: schedule_planner.run(
            objective=request.objective, business_type=request.business_type, constraints=c))
        trace.planner = planner
        if planner.used_fallback:
            trace.warnings.append("The language model was unavailable, so the deterministic planner produced this plan. "
                                  "Scheduling and validation are unaffected; only the objective's interpretation is simpler.")
        rules = schedule_planner.merge_rules(c, planner)
        target = schedule_planner.effective_target(c, planner)
        added = [r for r in rules if r not in c.priority_rules]
        if added:
            trace.warnings.append("The planner read these rules from the objective: " + ", ".join(added) + ".")
        if target < c.target_count:
            trace.warnings.append(f"The objective asks for {target}, fewer than the {c.target_count} allowed; planning for {target}.")

        # 2. Domain Analysis.
        analysis = _stage(trace, "DomainAnalysisAgent", lambda: schedule_analyst.run(
            constraints=c, tenant_id=request.tenant_id, rules=rules,
            tools=AgentToolbox(client, "DomainAnalysisAgent"), today=now.date()))
        trace.analysis = analysis

        # 3. Action / Tool - the optimiser.
        action = _stage(trace, "ActionToolAgent", lambda: schedule_action.run(
            constraints=c, analysis=analysis, rules=rules, target=target,
            min_gap_minutes=planner.intent.min_gap_minutes,
            tools=AgentToolbox(client, "ActionToolAgent"), now=now,
            weekdays=planner.intent.weekdays, time_window=planner.intent.time_window))
        trace.action = action
        trace.warnings.extend(action.notes)

        # 4. Validation / Safety - deterministic gate.
        client.invalidate_availability()
        safety, revenue, revenue_usd = _stage(trace, "ValidationSafetyAgent", lambda: schedule_safety.run(
            proposals=action.proposals, constraints=c, analysis=analysis, target=target, rules=rules,
            currency=request.currency, tools=AgentToolbox(client, "ValidationSafetyAgent"), now=now))
        trace.safety = safety
    except (AgentSafeFailure, ToolError) as e:
        trace.status = "Failed"
        trace.error = str(e)[:400]
        return finalize(trace, client)

    # ── outcome ─────────────────────────────────────────────────────────
    proposals = action.proposals
    open_resources = [r for r in analysis.resources if r.working_days_in_range]
    capacity = sum(r.capacity_minutes_in_range for r in open_resources)
    booked = sum(r.booked_minutes_in_range for r in open_resources)
    added_minutes = sum(p.duration_minutes for p in proposals)
    trace.metrics = ScheduleMetrics(
        requested=target,
        proposed=len(proposals),
        coverage_pct=round(len(proposals) / target * 100, 1) if target else 0.0,
        resources_used=len({p.resource_id for p in proposals}),
        days_used=len({p.start.date() for p in proposals}),
        expected_no_shows=round(sum(p.no_show_risk for p in proposals), 2),
        estimated_revenue=revenue,
        estimated_revenue_usd=revenue_usd,
        currency=request.currency.upper(),
        utilisation_before_pct=round(booked / capacity * 100, 1) if capacity else 0.0,
        utilisation_after_pct=round((booked + added_minutes) / capacity * 100, 1) if capacity else 0.0,
    )

    if not safety.is_allowed:
        trace.status = "Rejected"
        trace.error = safety.rejection_reason
    elif safety.requires_human_approval:
        trace.status = "AwaitingApproval"
    else:
        trace.status = "Completed"
    return finalize(trace, client)
