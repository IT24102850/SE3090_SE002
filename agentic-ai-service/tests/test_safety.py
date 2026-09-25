"""Direct, no-HTTP tests of the deterministic safety gate and the
tool-call retry/fail-safe behavior — these are the pieces the spec
requires stay independently testable without mocking an LLM at all."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest

from agents import validation_safety_agent
from gemini_client import _run_tool_with_one_retry
from schemas.contracts import ProposedBooking
from tools.booking_tools import BookingToolsClient, ToolError


def _future_booking(**overrides) -> ProposedBooking:
    defaults = dict(
        resource_id="r1",
        resource_name="Dr. Smith",
        booking_type_id="bt1",
        scheduled_datetime=datetime.now(timezone.utc) + timedelta(days=1),
        duration_minutes=30,
        has_conflict=False,
        conflict_reason=None,
    )
    defaults.update(overrides)
    return ProposedBooking(**defaults)


def test_malformed_tool_response_fails_safely(monkeypatch):
    """Simulates a broken/timeout tool call (detect_conflicts raising)
    reached from inside the Validation/Safety agent's own re-check. Must
    end in a logged, structured rejection — never a raised exception."""
    client = BookingToolsClient(base_url="http://testserver/api", auth_token="x")
    monkeypatch.setattr(client, "detect_conflicts", MagicMock(side_effect=ToolError("simulated timeout")))
    create_booking = MagicMock()
    monkeypatch.setattr(client, "create_booking", create_booking)

    result = validation_safety_agent.run(
        proposed_bookings=[_future_booking()],
        tenant_id="tenant-1",
        client=client,
    )

    assert result.is_allowed is False
    assert result.requires_human_approval is False
    assert "simulated timeout" in (result.rejection_reason or "")
    create_booking.assert_not_called()


def test_tool_loop_retries_once_then_returns_error_not_raises():
    calls = []

    def always_fails(**kwargs):
        calls.append(kwargs)
        raise RuntimeError("boom")

    result = _run_tool_with_one_retry(always_fails, {"x": 1})

    assert "error" in result
    assert len(calls) == 2  # one attempt + one retry, then give up safely


def test_validation_rejects_past_datetime():
    client = MagicMock()
    result = validation_safety_agent.run(
        proposed_bookings=[_future_booking(scheduled_datetime=datetime.now(timezone.utc) - timedelta(hours=1))],
        tenant_id="tenant-1",
        client=client,
    )
    assert result.is_allowed is False
    assert "past" in (result.rejection_reason or "").lower()
    client.create_booking.assert_not_called()


def test_validation_rejects_over_duration_limit():
    client = MagicMock()
    result = validation_safety_agent.run(
        proposed_bookings=[_future_booking(duration_minutes=999)],
        tenant_id="tenant-1",
        client=client,
    )
    assert result.is_allowed is False
    assert "exceeds" in (result.rejection_reason or "").lower()
    client.create_booking.assert_not_called()


def test_validation_rejects_empty_proposal_list():
    client = MagicMock()
    result = validation_safety_agent.run(proposed_bookings=[], tenant_id="tenant-1", client=client)
    assert result.is_allowed is False
    client.create_booking.assert_not_called()


def test_no_show_history_is_informational_not_blocking():
    """A high no-show rate must appear as a note, never as a rejection —
    history isn't a valid reason to deny service."""
    client = MagicMock()
    client.detect_conflicts.return_value = {"has_conflict": False, "reason": None}
    client.predict_no_show_probability.return_value = {"totalPast": 5, "noShows": 3, "rate": 0.6}
    client.create_booking.return_value = {"success": True, "booking": {"id": "booking-1"}}

    result = validation_safety_agent.run(proposed_bookings=[_future_booking()], tenant_id="tenant-1", client=client)

    assert result.is_allowed is True
    client.create_booking.assert_called_once()
    assert any("no-show rate" in note.lower() for note in result.validation_notes)


def test_no_show_lookup_failure_does_not_block_booking():
    client = MagicMock()
    client.detect_conflicts.return_value = {"has_conflict": False, "reason": None}
    client.predict_no_show_probability.side_effect = ToolError("backend unreachable")
    client.create_booking.return_value = {"success": True, "booking": {"id": "booking-1"}}

    result = validation_safety_agent.run(proposed_bookings=[_future_booking()], tenant_id="tenant-1", client=client)

    assert result.is_allowed is True
    client.create_booking.assert_called_once()
