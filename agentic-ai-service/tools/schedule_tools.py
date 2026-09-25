"""Allow-listed tools for the Schedule Copilot, and the per-agent permission
boundary around them.

Every tool here is a read-only call back into the ASP.NET Core API using the
calling manager's own JWT, so the API's tenant scoping and role checks apply
exactly as they would to that manager clicking through the app. None of
them can write: the Copilot proposes, a human approves, and ASP.NET Core's
/apply endpoint is the only thing that ever creates the bookings.

The spec (2.7) names five allow-listed tools:

    query_resource_availability, check_staff_schedule, detect_conflicts,
    calculate_travel_time, predict_no_show_probability

Two supporting reads sit alongside them - `search_resources` to find the
candidates and `query_booking_history` to measure load and booking value -
and they go through the same recorder and the same permission gate.

Least privilege is enforced, not just documented: an agent only ever
receives an `AgentToolbox`, and a toolbox refuses any tool outside that
agent's entry in ALLOWED_TOOLS. The refusal is recorded in the trace like
any other call, so a misbehaving agent is visible rather than silent.
"""
from __future__ import annotations

import math
import time
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable

from tools.booking_tools import BookingToolsClient, ToolError, _records_call, calculate_travel_time

ALLOWED_TOOLS: dict[str, frozenset[str]] = {
    # The planner reasons over the objective alone. Giving it tools would let
    # the one LLM-driven agent act on data before the others have vetted it.
    "PlannerAgent": frozenset(),
    "DomainAnalysisAgent": frozenset({
        "search_resources", "check_staff_schedule", "predict_no_show_probability", "query_booking_history",
    }),
    "ActionToolAgent": frozenset({
        "query_resource_availability", "calculate_travel_time", "detect_conflicts",
    }),
    "ValidationSafetyAgent": frozenset({"detect_conflicts", "check_staff_schedule"}),
}

NO_SHOW_LOOKBACK_DAYS = 90


class ToolPermissionError(ToolError):
    """An agent asked for a tool it is not allow-listed for."""


class ScheduleToolsClient(BookingToolsClient):
    """The booking client plus the reads the scheduler needs.

    Responses are cached per call-arguments for the life of one workflow.
    The optimiser and the safety gate both look at the same day's slots; a
    cache means they look at the same answer, and it halves the calls.
    """

    def __init__(self, base_url: str, auth_token: str, timeout: float = 15.0):
        super().__init__(base_url=base_url, auth_token=auth_token, timeout=timeout)
        self._cache: dict[tuple, Any] = {}

    def _cached(self, key: tuple, fetch: Callable[[], Any]) -> Any:
        if key not in self._cache:
            self._cache[key] = fetch()
        return self._cache[key]

    def invalidate_availability(self) -> None:
        """Drop cached slot lists so a re-check sees the live state."""
        self._cache = {k: v for k, v in self._cache.items() if k[0] != "slots"}

    @_records_call("search_resources")
    def list_resources(self, tenant_id: str, branch_id: str | None = None) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"tenantId": tenant_id, "pageSize": 100}
        if branch_id:
            params["branchId"] = branch_id
        data = self._get("/resources", params)
        items = data.get("items", data) if isinstance(data, dict) else data
        # A resource in maintenance or archived must not be offered new work,
        # whatever its weekly hours say.
        return [r for r in items if str(r.get("status", "Available")) not in ("UnderMaintenance", "Archived")]

    @_records_call("check_staff_schedule")
    def weekly_schedule(self, resource_id: str) -> list[dict[str, Any]]:
        return self._cached(("schedule", resource_id),
                            lambda: self._get(f"/resources/{resource_id}/schedule"))

    @_records_call("query_booking_history")
    def booking_history(self, tenant_id: str, date_from: date, date_to: date,
                        resource_id: str | None = None, booking_type_id: str | None = None) -> list[dict[str, Any]]:
        params: dict[str, Any] = {
            "tenantId": tenant_id,
            "dateFrom": datetime.combine(date_from, datetime.min.time()).isoformat(),
            "dateTo": datetime.combine(date_to, datetime.max.time()).replace(microsecond=0).isoformat(),
            "pageSize": 1000,
        }
        if resource_id:
            params["resourceId"] = resource_id
        if booking_type_id:
            params["type"] = booking_type_id
        key = ("history", tenant_id, date_from, date_to, resource_id, booking_type_id)
        data = self._cached(key, lambda: self._get("/bookings", params))
        return data.get("items", []) if isinstance(data, dict) else list(data)

    @_records_call("predict_no_show_probability")
    def resource_no_show_rate(self, tenant_id: str, resource_id: str, today: date) -> dict[str, Any]:
        """Historical no-show rate for one resource over the last 90 days.

        A frequency, not a trained model, and labelled as such. It uses the
        same booking rows the no-show report does, so the number a manager
        sees here matches the one on the Reports page.
        """
        rows = self.booking_history(tenant_id, today - timedelta(days=NO_SHOW_LOOKBACK_DAYS), today,
                                    resource_id=resource_id)
        settled = [r for r in rows if r.get("status") in ("Completed", "NoShow")]
        no_shows = sum(1 for r in settled if r.get("status") == "NoShow")
        rate = no_shows / len(settled) if settled else 0.0
        return {"rate": round(rate, 4), "sample": len(settled), "basis": f"last {NO_SHOW_LOOKBACK_DAYS} days"}

    @_records_call("query_resource_availability")
    def day_slots(self, resource_id: str, day: date, duration_minutes: int, booking_type_id: str | None) -> dict[str, Any]:
        params: dict[str, Any] = {"resourceId": resource_id, "date": day.isoformat(), "duration": duration_minutes}
        if booking_type_id:
            params["bookingTypeId"] = booking_type_id
        key = ("slots", resource_id, day, duration_minutes, booking_type_id)
        return self._cached(key, lambda: self._get("/bookings/available-slots", params))

    @_records_call("detect_conflicts")
    def slot_conflict(self, resource_id: str, start: datetime, duration_minutes: int,
                      booking_type_id: str | None) -> dict[str, Any]:
        """Is this exact start still an open slot right now? Reads live state
        (bypassing the cache) because it exists to catch a booking made
        between planning and approval."""
        params: dict[str, Any] = {"resourceId": resource_id, "date": start.date().isoformat(),
                                  "duration": duration_minutes}
        if booking_type_id:
            params["bookingTypeId"] = booking_type_id
        data = self._get("/bookings/available-slots", params)
        if not data.get("isOpen", False):
            return {"has_conflict": True, "reason": "Resource is closed on this date."}
        for slot in data.get("slots", []):
            if _parse_dt(slot.get("startTime")) == _as_utc(start):
                if slot.get("isAvailable", False):
                    return {"has_conflict": False, "reason": None}
                return {"has_conflict": True, "reason": "Slot is already booked."}
        return {"has_conflict": True, "reason": "Time is not a bookable slot for this resource."}

    @_records_call("calculate_travel_time")
    def travel_minutes(self, distance_km: float, average_speed_kmh: float = 30.0) -> dict[str, Any]:
        return calculate_travel_time(distance_km, average_speed_kmh)


class AgentToolbox:
    """The only handle an agent gets on the tools: bound to one agent name and
    limited to that agent's allow-list."""

    def __init__(self, client: ScheduleToolsClient, agent: str):
        if agent not in ALLOWED_TOOLS:
            raise ToolPermissionError(f"Unknown agent '{agent}'.")
        self._client = client
        self.agent = agent
        self.allowed = ALLOWED_TOOLS[agent]

    def _enter(self, tool: str) -> ScheduleToolsClient:
        self._client.current_agent = self.agent
        if tool not in self.allowed:
            self._client.calls.append({
                "tool": tool, "agent": self.agent, "duration_ms": 0, "success": False,
                "error": f"refused: '{tool}' is not allow-listed for {self.agent}",
            })
            raise ToolPermissionError(f"{self.agent} is not permitted to call '{tool}'.")
        return self._client

    def search_resources(self, tenant_id: str, branch_id: str | None = None) -> list[dict[str, Any]]:
        return self._enter("search_resources").list_resources(tenant_id, branch_id)

    def check_staff_schedule(self, resource_id: str) -> list[dict[str, Any]]:
        return self._enter("check_staff_schedule").weekly_schedule(resource_id)

    def query_booking_history(self, tenant_id: str, date_from: date, date_to: date, **kw: Any) -> list[dict[str, Any]]:
        return self._enter("query_booking_history").booking_history(tenant_id, date_from, date_to, **kw)

    def predict_no_show_probability(self, tenant_id: str, resource_id: str, today: date) -> dict[str, Any]:
        return self._enter("predict_no_show_probability").resource_no_show_rate(tenant_id, resource_id, today)

    def query_resource_availability(self, resource_id: str, day: date, duration_minutes: int,
                                    booking_type_id: str | None) -> dict[str, Any]:
        return self._enter("query_resource_availability").day_slots(resource_id, day, duration_minutes, booking_type_id)

    def detect_conflicts(self, resource_id: str, start: datetime, duration_minutes: int,
                         booking_type_id: str | None) -> dict[str, Any]:
        return self._enter("detect_conflicts").slot_conflict(resource_id, start, duration_minutes, booking_type_id)

    def calculate_travel_time(self, distance_km: float, average_speed_kmh: float = 30.0) -> dict[str, Any]:
        return self._enter("calculate_travel_time").travel_minutes(distance_km, average_speed_kmh)


# ── helpers shared by the agents ────────────────────────────────────────
def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    text = str(value).replace("Z", "+00:00")
    try:
        return _as_utc(datetime.fromisoformat(text))
    except ValueError:
        return None


def parse_hhmm(value: Any) -> int | None:
    """'09:30:00' / '09:30' -> minutes after midnight."""
    if not value:
        return None
    parts = str(value).split(":")
    try:
        return int(parts[0]) * 60 + int(parts[1])
    except (ValueError, IndexError):
        return None


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


parse_dt = _parse_dt
as_utc = _as_utc
monotonic = time.monotonic
