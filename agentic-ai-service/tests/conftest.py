from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from agents import action_tool_agent, domain_analysis_agent, planner_agent
from main import app
from schemas.contracts import ActionToolOutput, DomainAnalysisOutput, PlannerOutput, ProposedBooking, RankedCandidate
from tools.booking_tools import BookingToolsClient


@pytest.fixture
def api_client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def auth_headers() -> dict:
    return {"Authorization": "Bearer test-internal-token"}


@pytest.fixture
def base_request() -> dict:
    return {
        "objective": "Find and book the best dentist near me this week",
        "tenant_id": "11111111-1111-1111-1111-111111111111",
        "business_type": "Clinic",
        "branch_id": None,
        "customer_id": "22222222-2222-2222-2222-222222222222",
        "date_from": None,
        "date_to": None,
        "extra_constraints": {"booking_type_id": "33333333-3333-3333-3333-333333333333", "duration_minutes": 30},
        "auth_token": "fake-customer-jwt",
    }


@pytest.fixture
def future_slot() -> datetime:
    return (datetime.now(timezone.utc) + timedelta(days=2)).replace(minute=0, second=0, microsecond=0)


@pytest.fixture
def mock_planner(monkeypatch):
    output = PlannerOutput(
        plan=[
            {"order": 1, "action": "Find candidates", "assigned_agent": "DomainAnalysisAgent", "description": "..."},
            {"order": 2, "action": "Propose slot", "assigned_agent": "ActionToolAgent", "description": "..."},
            {"order": 3, "action": "Validate", "assigned_agent": "ValidationSafetyAgent", "description": "..."},
        ],
        assigned_agents=["DomainAnalysisAgent", "ActionToolAgent", "ValidationSafetyAgent"],
        confidence=0.9,
    )
    mock = MagicMock(return_value=output)
    monkeypatch.setattr(planner_agent, "run", mock)
    return mock


@pytest.fixture
def mock_domain_analysis(monkeypatch):
    output = DomainAnalysisOutput(
        ranked_candidates=[
            RankedCandidate(resource_id="r1", resource_name="Dr. Smith", score=0.95, reasoning="Best specialty match and rating."),
        ],
        ranking_criteria_used=["specialty match", "rating"],
    )
    mock = MagicMock(return_value=output)
    monkeypatch.setattr(domain_analysis_agent, "run", mock)
    return mock


def _action_tool_output(future_slot: datetime, has_conflict: bool = False) -> ActionToolOutput:
    return ActionToolOutput(
        proposed_bookings=[
            ProposedBooking(
                resource_id="r1",
                resource_name="Dr. Smith",
                booking_type_id="33333333-3333-3333-3333-333333333333",
                scheduled_datetime=future_slot,
                duration_minutes=30,
                has_conflict=has_conflict,
                conflict_reason="Slot just got taken." if has_conflict else None,
            )
        ],
        confidence=0.85,
    )


@pytest.fixture
def mock_action_tool(monkeypatch, future_slot):
    mock = MagicMock(return_value=_action_tool_output(future_slot, has_conflict=False))
    monkeypatch.setattr(action_tool_agent, "run", mock)
    return mock


@pytest.fixture
def mock_action_tool_conflict(monkeypatch, future_slot):
    mock = MagicMock(return_value=_action_tool_output(future_slot, has_conflict=True))
    monkeypatch.setattr(action_tool_agent, "run", mock)
    return mock


@pytest.fixture
def mock_booking_tools_success(monkeypatch):
    """No-conflict re-check + a successful create_booking — the auto-execute path.
    Also mocks predict_no_show_probability so this doesn't make a real,
    unmocked network call to whatever BACKEND_API_BASE_URL happens to
    resolve to during a test run."""
    detect = MagicMock(return_value={"has_conflict": False, "reason": None})
    create = MagicMock(return_value={"success": True, "booking": {"id": "booking-123"}})
    no_show = MagicMock(return_value={"totalPast": 4, "noShows": 0, "rate": 0.0})
    monkeypatch.setattr(BookingToolsClient, "detect_conflicts", detect)
    monkeypatch.setattr(BookingToolsClient, "create_booking", create)
    monkeypatch.setattr(BookingToolsClient, "predict_no_show_probability", no_show)
    return {"detect_conflicts": detect, "create_booking": create, "predict_no_show_probability": no_show}
