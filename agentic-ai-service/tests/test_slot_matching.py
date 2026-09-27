"""Matching a proposed time against the slot list.

Every AI booking was rejected with "Requested time is not a valid slot for
this resource" while the slot sat free in the very list being searched. The
re-check compared timestamps as strings, and the two sides do not spell the
same instant the same way: .NET writes a UTC DateTime as
"2026-09-28T10:00:00Z", Python's isoformat() writes
"2026-09-28T10:00:00+00:00". Equal instants, unequal text.
"""
from datetime import datetime, timezone

import pytest

from tools.booking_tools import BookingToolsClient, as_utc, parse_dt

# The two spellings that collided in production.
DOTNET = "2026-09-28T10:00:00Z"
PYTHON = "2026-09-28T10:00:00+00:00"


class _FakeClient(BookingToolsClient):
    """Only query_resource_availability matters here; everything else stays
    as the real class defines it."""

    def __init__(self, payload):
        # Deliberately skips the real __init__ (it opens an httpx client), so
        # the two attributes the @_records_call decorator writes to are set
        # by hand.
        self._payload = payload
        self.calls = []
        self.current_agent = "test"

    def query_resource_availability(self, *_args, **_kwargs):
        return self._payload


def _check(payload, scheduled):
    return _FakeClient(payload).detect_conflicts(
        resource_id="r1",
        date="2026-09-28",
        duration_minutes=60,
        scheduled_datetime=scheduled,
    )


# ---------- the regression ----------


def test_a_dotnet_slot_matches_a_python_timestamp_for_the_same_instant():
    payload = {"isOpen": True, "slots": [{"startTime": DOTNET, "isAvailable": True}]}

    assert _check(payload, PYTHON) == {"has_conflict": False, "reason": None}


def test_the_two_spellings_really_are_different_text():
    # Guards the premise: if these ever became equal as strings the test
    # above would pass for the wrong reason.
    assert DOTNET != PYTHON
    assert parse_dt(DOTNET) == parse_dt(PYTHON)


@pytest.mark.parametrize(
    "written",
    [
        "2026-09-28T10:00:00Z",
        "2026-09-28T10:00:00z",
        "2026-09-28T10:00:00+00:00",
        "2026-09-28T10:00:00",          # naive: the API's UTC wall clock
        "2026-09-28T12:00:00+02:00",    # same instant, another offset
    ],
)
def test_every_way_the_wire_spells_that_instant_is_accepted(written):
    payload = {"isOpen": True, "slots": [{"startTime": written, "isAvailable": True}]}

    assert _check(payload, PYTHON)["has_conflict"] is False


# ---------- the checks that must still say no ----------


def test_a_genuinely_absent_slot_is_still_rejected():
    payload = {"isOpen": True, "slots": [{"startTime": "2026-09-28T14:00:00Z", "isAvailable": True}]}

    result = _check(payload, PYTHON)

    assert result["has_conflict"] is True
    assert "not a valid slot" in result["reason"]


def test_a_taken_slot_is_still_rejected():
    payload = {"isOpen": True, "slots": [{"startTime": DOTNET, "isAvailable": False}]}

    result = _check(payload, PYTHON)

    assert result["has_conflict"] is True
    assert "no longer available" in result["reason"]


def test_a_closed_day_is_still_rejected():
    payload = {"isOpen": False, "slots": [{"startTime": DOTNET, "isAvailable": True}]}

    assert _check(payload, PYTHON)["has_conflict"] is True


def test_an_unparseable_proposal_is_rejected_rather_than_matching_anything():
    # A bad timestamp must never fall through to "free"; booking on a time
    # nobody can parse is worse than refusing.
    payload = {"isOpen": True, "slots": [{"startTime": DOTNET, "isAvailable": True}]}

    assert _check(payload, "next Tuesday-ish")["has_conflict"] is True


def test_a_slot_with_an_unreadable_time_does_not_match():
    payload = {"isOpen": True, "slots": [{"startTime": "not a date", "isAvailable": True}]}

    assert _check(payload, PYTHON)["has_conflict"] is True


# ---------- the parser itself ----------


def test_parse_dt_returns_none_rather_than_raising_on_rubbish():
    assert parse_dt(None) is None
    assert parse_dt("") is None
    assert parse_dt("not a date") is None


def test_a_naive_timestamp_is_read_as_utc_not_local():
    # Reading it as local would silently shift every slot by the machine's
    # offset, which is how a demo passes in London and fails in Colombo.
    assert as_utc(datetime(2026, 9, 28, 10, 0)) == datetime(
        2026, 9, 28, 10, 0, tzinfo=timezone.utc
    )
