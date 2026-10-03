"""Allow-listed tools calling back into the existing ASP.NET Core API.

Every call attaches the customer-scoped JWT `PlannerAgentService` minted, so
the exact same tenant-scoping and role checks a real app request would get
apply here too — no bypass endpoints. Generic on purpose: `resource_type`
lives in the caller's search params, not in these function names.
"""
from __future__ import annotations

from typing import Any

import httpx


class ToolError(Exception):
    """Raised on a tool-level failure (HTTP error, bad input). Caught by
    gemini_client's retry wrapper — never propagates as a raw exception
    into the agent loop."""


class BookingToolsClient:
    def __init__(self, base_url: str, auth_token: str, timeout: float = 15.0):
        self._client = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {auth_token}"},
            timeout=timeout,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "BookingToolsClient":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    # ── Domain Analysis Agent tools (read-only) ─────────────────────────
    def search_resources(
        self,
        tenant_id: str,
        resource_category: str | None = None,
        specialty: str | None = None,
        branch_id: str | None = None,
        search: str | None = None,
    ) -> dict[str, Any]:
        """Finds candidate resources. `resource_category` maps to the
        platform's generic Resource.Category (Room/Equipment/Vehicle/Staff/
        Desk/Other) and `specialty` to its free-text specialty/type field —
        how a business type maps its domain concept ("dentist", "table for
        4", "yoga instructor") onto those two fields is decided by the
        Domain Analysis Agent's prompt, not by this tool."""
        params: dict[str, Any] = {"tenantId": tenant_id, "pageSize": 50}
        if resource_category:
            params["category"] = resource_category
        if specialty:
            params["specialty"] = specialty
        if branch_id:
            params["branchId"] = branch_id
        if search:
            params["search"] = search
        return self._get("/resources", params)

    def get_resource_metadata(self, resource_id: str) -> dict[str, Any]:
        """Full detail for one resource, including the generic CustomAttributes/
        LocationMetadata JSON bags where business-type-specific ranking
        signals (rating, cuisine, distance, wait time, ...) live."""
        return self._get(f"/resources/{resource_id}")

    def check_staff_schedule(self, resource_id: str) -> dict[str, Any]:
        """Coarser than query_resource_availability: the full weekly working
        pattern (which days this resource works at all, plus any configured
        lunch break / max-daily-hours) rather than one day's slot list - lets
        ranking favor candidates actually open on the objective's requested
        day before spending a call on exact slots."""
        return {"schedule": self._get(f"/resources/{resource_id}/schedule")}

    # ── Action/Tool Agent tools (read-only) ─────────────────────────────
    def query_resource_availability(
        self, resource_id: str, date: str, duration_minutes: int, booking_type_id: str | None = None
    ) -> dict[str, Any]:
        params: dict[str, Any] = {"resourceId": resource_id, "date": date, "duration": duration_minutes}
        if booking_type_id:
            params["bookingTypeId"] = booking_type_id
        return self._get("/bookings/available-slots", params)

    def detect_conflicts(
        self,
        resource_id: str,
        date: str,
        duration_minutes: int,
        scheduled_datetime: str,
        booking_type_id: str | None = None,
    ) -> dict[str, Any]:
        """Re-checks the exact proposed slot is still free — guards the gap
        between Domain Analysis's ranking and the final booking, rather than
        the unrelated /bookings/conflicts admin audit report (a different,
        Admin/Manager-only endpoint that finds overlapping pairs across
        existing data, not "is this one slot free")."""
        data = self.query_resource_availability(resource_id, date, duration_minutes, booking_type_id)
        slots = data.get("slots", [])
        match = next((s for s in slots if s.get("startTime") == scheduled_datetime), None)
        if not data.get("isOpen", False):
            return {"has_conflict": True, "reason": "Resource is closed on this date."}
        if match is None:
            return {"has_conflict": True, "reason": "Requested time is not a valid slot for this resource."}
        if not match.get("isAvailable", False):
            return {"has_conflict": True, "reason": "Slot is no longer available."}
        return {"has_conflict": False, "reason": None}

    def predict_no_show_probability(self) -> dict[str, Any]:
        """A real historical-rate heuristic (this customer's own past
        completed-vs-no-show ratio), not a trained ML model. Called directly
        by validation_safety_agent.py, never exposed as an LLM-visible tool —
        informational only, never a reason to deny a booking."""
        return self._get("/bookings/my-no-show-rate")

    # ── Validation/Safety Agent's own direct call (never a Gemini tool) ─
    def create_booking(
        self,
        tenant_id: str,
        resource_id: str,
        booking_type_id: str,
        start_time: str,
        end_time: str,
        title: str | None = None,
        notes: str | None = None,
    ) -> dict[str, Any]:
        # BookedBy is a required field on the wire, but the backend forces
        # it to the caller's own id for a Customer-role token regardless of
        # what's sent here — this placeholder is never actually used.
        body = {
            "tenantId": tenant_id,
            "resourceId": resource_id,
            "bookingTypeId": booking_type_id,
            "bookedBy": "00000000-0000-0000-0000-000000000000",
            "startTime": start_time,
            "endTime": end_time,
            "title": title,
            "notes": notes,
            "priority": "Normal",
        }
        try:
            resp = self._client.post("/bookings", json=body)
        except httpx.HTTPError as e:
            raise ToolError(f"create_booking request failed: {e}") from e

        if resp.status_code == 409:
            return {"success": False, "conflict": True, "message": _safe_message(resp)}
        if resp.status_code >= 400:
            raise ToolError(f"create_booking failed ({resp.status_code}): {_safe_message(resp)}")
        return {"success": True, "booking": resp.json()}

    def _get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        try:
            resp = self._client.get(path, params=params or {})
        except httpx.HTTPError as e:
            raise ToolError(f"GET {path} failed: {e}") from e
        if resp.status_code >= 400:
            raise ToolError(f"GET {path} failed ({resp.status_code}): {_safe_message(resp)}")
        return resp.json()


def calculate_travel_time(distance_km: float, average_speed_kmh: float = 30.0) -> dict[str, Any]:
    """Rough estimate from a straight-line/road distance, not a real
    routing/traffic API (no Google Maps or equivalent key exists in this
    project) - deliberately labeled as an estimate in its own output so
    agents don't present it as authoritative. average_speed_kmh defaults to
    a generic urban average; callers may override it if the resource's
    metadata suggests otherwise (e.g. highway travel)."""
    if distance_km < 0 or average_speed_kmh <= 0:
        raise ToolError("distance_km must be >= 0 and average_speed_kmh must be > 0.")
    minutes = (distance_km / average_speed_kmh) * 60
    return {"estimated_minutes": round(minutes, 1), "is_estimate": True, "basis": f"{distance_km}km at {average_speed_kmh}km/h average"}


def _safe_message(resp: httpx.Response) -> str:
    try:
        data = resp.json()
        return data.get("message") or data.get("title") or resp.text[:200]
    except Exception:
        return resp.text[:200]
