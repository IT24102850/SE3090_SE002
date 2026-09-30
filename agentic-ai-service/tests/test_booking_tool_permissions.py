"""Least privilege in the find-and-book pipeline: each agent may call only
the tools BOOKING_ALLOWED_TOOLS lists for it, and a refusal is recorded in
the trace. Every refused call below would fail loudly if it reached the
network, because the client points at an unroutable address."""
import pytest

from tools.booking_tools import BOOKING_ALLOWED_TOOLS, BookingToolsClient, ToolError


@pytest.fixture
def client():
    c = BookingToolsClient(base_url="http://127.0.0.1:9/api", auth_token="t", timeout=0.5)
    yield c
    c.close()


def test_planner_has_no_tools():
    assert BOOKING_ALLOWED_TOOLS["PlannerAgent"] == frozenset()


def test_only_the_safety_agent_may_create_a_booking():
    holders = [agent for agent, tools in BOOKING_ALLOWED_TOOLS.items() if "create_booking" in tools]
    assert holders == ["ValidationSafetyAgent"]


@pytest.mark.parametrize("agent", ["PlannerAgent", "DomainAnalysisAgent", "ActionToolAgent"])
def test_create_booking_is_refused_outside_the_safety_agent(client, agent):
    client.current_agent = agent

    with pytest.raises(ToolError, match="not permitted"):
        client.create_booking("tenant", "resource", "type", "2026-10-01T09:00:00Z", "2026-10-01T10:00:00Z")

    assert client.calls[-1]["tool"] == "create_booking"
    assert client.calls[-1]["agent"] == agent
    assert client.calls[-1]["success"] is False


def test_planner_cannot_read_resources(client):
    client.current_agent = "PlannerAgent"

    with pytest.raises(ToolError, match="not permitted"):
        client.search_resources("tenant")

    assert client.calls[-1]["success"] is False


def test_permitted_tool_passes_the_gate(client):
    """A listed tool gets past the gate and reaches the transport - here an
    unroutable address - rather than being refused."""
    client.current_agent = "DomainAnalysisAgent"

    with pytest.raises(ToolError) as excinfo:
        client.search_resources("tenant")

    assert "not permitted" not in str(excinfo.value)
