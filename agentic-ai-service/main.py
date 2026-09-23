"""FastAPI app for the Agentic AI subsystem.

Called only by ASP.NET Core (never React/Flutter directly) — every route
except /health requires the shared-secret bearer token in
AGENT_SERVICE_INTERNAL_TOKEN.

/plan runs the full 4-agent pipeline synchronously and returns one complete
WorkflowTrace. /workflow/{id}/trace, /approve, /reject operate on an
in-memory store keyed by the workflow_id /plan generated — useful for
direct testing/introspection of this service in isolation, but NOT the
production approval path: this service never touches Postgres, so the
authoritative AgentWorkflow record (and the real /approve, /reject, /apply
React actually calls) live in ASP.NET Core. See README.md.
"""
from __future__ import annotations

import logging
import os
import uuid
from datetime import datetime, timezone

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse

load_dotenv()

from agents import action_tool_agent, domain_analysis_agent, planner_agent, validation_safety_agent  # noqa: E402
from gemini_client import AgentSafeFailure  # noqa: E402
from schemas.contracts import (  # noqa: E402
    ApproveRejectRequest, InventoryAgentTrace, InventoryPlanRequest,
    PlanRequest, WorkflowTrace,
)
from tools.booking_tools import BookingToolsClient, ToolError  # noqa: E402
from tools.inventory_tools import InventoryToolsClient  # noqa: E402
from agents.inventory_agents import (  # noqa: E402
    analyze_inventory_domain, analyze_inventory_health, plan_inventory, recommend_replenishment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agentic-ai-service")

app = FastAPI(title="Agentic AI Subsystem", version="1.0.0")

# In-memory only — see module docstring. Not a substitute for the
# AgentWorkflows table in Postgres, which ASP.NET Core owns.
_workflows: dict[str, WorkflowTrace] = {}


def _require_internal_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.getenv("AGENT_SERVICE_INTERNAL_TOKEN")
    if not expected:
        raise HTTPException(status_code=500, detail="AGENT_SERVICE_INTERNAL_TOKEN is not configured on this service.")
    if authorization != f"Bearer {expected}":
        raise HTTPException(status_code=401, detail="Missing or invalid internal service token.")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/plan", response_model=WorkflowTrace, dependencies=[Depends(_require_internal_token)])
def plan(request: PlanRequest) -> WorkflowTrace | JSONResponse:
    workflow_id = str(uuid.uuid4())
    trace = WorkflowTrace(
        workflow_id=workflow_id,
        objective=request.objective,
        tenant_id=request.tenant_id,
        business_type=request.business_type,
        status="Failed",
    )

    booking_type_id = request.extra_constraints.get("booking_type_id")
    if not booking_type_id:
        trace.error = "extra_constraints.booking_type_id is required."
        _workflows[workflow_id] = trace
        return JSONResponse(status_code=422, content=trace.model_dump(mode="json"))

    duration_minutes = int(request.extra_constraints.get("duration_minutes", 60))
    date_from = (request.date_from or datetime.now(timezone.utc)).date().isoformat()
    date_to = (request.date_to or request.date_from or datetime.now(timezone.utc)).date().isoformat()

    client = BookingToolsClient(base_url=os.getenv("BACKEND_API_BASE_URL", "http://localhost:5298/api"), auth_token=request.auth_token)
    try:
        try:
            trace.planner_output = planner_agent.run(
                objective=request.objective, business_type=request.business_type, extra_constraints=request.extra_constraints
            )

            trace.domain_analysis_output = domain_analysis_agent.run(
                objective=request.objective,
                business_type=request.business_type,
                tenant_id=request.tenant_id,
                branch_id=request.branch_id,
                extra_constraints=request.extra_constraints,
                client=client,
            )
            if not trace.domain_analysis_output.ranked_candidates:
                trace.status = "Failed"
                trace.error = "No candidate resources found for this objective."
                _workflows[workflow_id] = trace
                return JSONResponse(status_code=422, content=trace.model_dump(mode="json"))

            trace.action_tool_output = action_tool_agent.run(
                objective=request.objective,
                ranked_candidates=trace.domain_analysis_output.ranked_candidates,
                booking_type_id=booking_type_id,
                duration_minutes=duration_minutes,
                date_from=date_from,
                date_to=date_to,
                client=client,
            )

            trace.validation_output = validation_safety_agent.run(
                proposed_bookings=trace.action_tool_output.proposed_bookings,
                tenant_id=request.tenant_id,
                client=client,
                estimated_revenue_impact=float(request.extra_constraints.get("estimated_revenue_impact", 0.0)),
            )
        except AgentSafeFailure as e:
            logger.warning("Workflow %s failed safely: %s", workflow_id, e)
            trace.status = "Failed"
            trace.error = str(e)
            _workflows[workflow_id] = trace
            return JSONResponse(status_code=422, content=trace.model_dump(mode="json"))
        except ToolError as e:
            logger.warning("Workflow %s tool error: %s", workflow_id, e)
            trace.status = "Failed"
            trace.error = f"Tool error: {e}"
            _workflows[workflow_id] = trace
            return JSONResponse(status_code=422, content=trace.model_dump(mode="json"))
    finally:
        client.close()
    validation = trace.validation_output
    if not validation.is_allowed:
        trace.status = "Rejected"
        trace.error = validation.rejection_reason
    elif validation.requires_human_approval:
        trace.status = "AwaitingApproval"
    else:
        trace.status = "Completed"

    trace.completed_at = datetime.now(timezone.utc)
    _workflows[workflow_id] = trace
    return trace


@app.post("/inventory/plan", response_model=InventoryAgentTrace, dependencies=[Depends(_require_internal_token)])
def plan_inventory_stock(request: InventoryPlanRequest) -> InventoryAgentTrace | JSONResponse:
    """Analyze inventory with read-only tools; it never creates an order or edits stock."""
    workflow_id = str(uuid.uuid4())
    trace = InventoryAgentTrace(
        workflow_id=workflow_id,
        objective=request.objective,
        tenant_id=request.tenant_id,
        status="Failed",
        planner_summary="",
        data_sources=[],
    )
    backend_url = os.getenv("BACKEND_API_BASE_URL", "http://localhost:5298/api")
    try:
        with InventoryToolsClient(base_url=backend_url, auth_token=request.auth_token) as client:
            plan_output = plan_inventory(request.objective)
            trace.planner_summary = plan_output.summary
            if plan_output.used_fallback:
                trace.warnings.append(
                    "Gemini is unavailable; deterministic inventory planning is being used. "
                    "Recommendations still use authorized stock and movement data, with reorder-level fallback when history is missing."
                )
            trace.warnings.append(
                f"No supplier lead-time data is available; planning assumes "
                f"{plan_output.lead_time_days} lead-time days plus {plan_output.safety_days} safety-stock days."
            )
            domain = analyze_inventory_domain(
                objective=request.objective,
                branch_id=request.branch_id,
                client=client,
            )
            trace.data_sources = ["Authorized inventory snapshot", "Recent stock movements"]
            trace.warnings.extend(domain.warnings)
            if len(domain.movements) >= 100:
                trace.warnings.append("The backend returned its 100 most recent movements; older history is not included.")
            if not domain.items:
                trace.status = "NoAction"
                trace.warnings.append("No inventory items were available in the selected branch scope.")
                return trace
            recommendations = recommend_replenishment(
                snapshot=domain, plan=plan_output, objective=request.objective, workflow_id=workflow_id,
            )
            trace.insights = analyze_inventory_health(
                snapshot=domain, plan=plan_output, recommendations=recommendations,
            )
            # Deterministic safety review; this route has no write tools.
            for recommendation in recommendations:
                try:
                    uuid.UUID(recommendation.inventory_item_id)
                    if recommendation.recommended_quantity <= 0:
                        raise ValueError("quantity must be positive")
                    if recommendation.estimated_unit_cost is not None and recommendation.estimated_unit_cost < 0:
                        raise ValueError("unit cost cannot be negative")
                    trace.recommendations.append(recommendation)
                except (ValueError, TypeError):
                    trace.warnings.append(f"A recommendation for {recommendation.item_name} was omitted by the safety review.")
            trace.status = "NeedsReview" if trace.recommendations else "NoAction"
            if trace.recommendations:
                trace.warnings.append("Recommendations are drafts only. Review quantities, supplier, branch and budget before creating a purchase order.")
            return trace
    except Exception as exc:
        logger.exception("Inventory workflow %s failed safely", workflow_id)
        return JSONResponse(
            status_code=422,
            content={**trace.model_dump(mode="json"), "status": "Failed", "warnings": [*trace.warnings, str(exc)]},
        )


@app.get("/workflow/{workflow_id}/trace", response_model=WorkflowTrace, dependencies=[Depends(_require_internal_token)])
def get_trace(workflow_id: str) -> WorkflowTrace:
    trace = _workflows.get(workflow_id)
    if trace is None:
        raise HTTPException(status_code=404, detail="Workflow not found.")
    return trace


@app.post("/workflow/{workflow_id}/approve", response_model=WorkflowTrace, dependencies=[Depends(_require_internal_token)])
def approve(workflow_id: str, _body: ApproveRejectRequest | None = None) -> WorkflowTrace:
    trace = _workflows.get(workflow_id)
    if trace is None:
        raise HTTPException(status_code=404, detail="Workflow not found.")
    if trace.status != "AwaitingApproval":
        raise HTTPException(status_code=400, detail=f"Workflow is '{trace.status}', not awaiting approval.")
    trace.status = "Completed"
    return trace


@app.post("/workflow/{workflow_id}/reject", response_model=WorkflowTrace, dependencies=[Depends(_require_internal_token)])
def reject(workflow_id: str, body: ApproveRejectRequest | None = None) -> WorkflowTrace:
    trace = _workflows.get(workflow_id)
    if trace is None:
        raise HTTPException(status_code=404, detail="Workflow not found.")
    trace.status = "Rejected"
    trace.error = (body.reason if body else None) or "Rejected."
    return trace
