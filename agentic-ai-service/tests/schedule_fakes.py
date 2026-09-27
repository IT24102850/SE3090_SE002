"""An in-memory stand-in for the ASP.NET Core endpoints the Schedule Copilot
reads, served through httpx.MockTransport.

Faking at the HTTP boundary rather than mocking the tool methods means the
tests run the real ScheduleToolsClient: its recorder, its cache, its
permission gate and its response parsing. A test that mocks the tools cannot
tell you the tools work.

Slot generation mirrors SlotCalculator closely enough for these tests:
consecutive `duration`-minute slots from open to close, none crossing lunch,
unavailable where a live booking overlaps. Times are UTC wall-clock, which is
the convention the real backend uses.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from urllib.parse import unquote

import httpx

from tools.schedule_tools import ScheduleToolsClient

LIVE = ("Pending", "Confirmed", "CheckedIn", "InProgress", "Completed")


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed


def _hhmm(value: str | None) -> int | None:
    if not value:
        return None
    h, m = value.split(":")[:2]
    return int(h) * 60 + int(m)


@dataclass
class FakeBackend:
    resources: list[dict] = field(default_factory=list)
    schedules: dict[str, list[dict]] = field(default_factory=dict)
    bookings: list[dict] = field(default_factory=list)
    fail_paths: set[str] = field(default_factory=set)
    # (resource_id, iso start): report the slot free on the first read and
    # taken on every read after - a booking made mid-workflow.
    stolen_after_first_read: set[tuple[str, str]] = field(default_factory=set)
    _reads: dict[tuple[str, str], int] = field(default_factory=dict)

    # ── builders ────────────────────────────────────────────────────────
    def add_resource(self, rid: str, name: str, *, open_at="09:00", close_at="17:00", days=(1, 2, 3, 4, 5),
                     lunch: tuple[str, str] | None = None, max_hours: float | None = None,
                     hourly_rate: float | None = None, coords: tuple[float, float] | None = None,
                     status: str = "Available") -> None:
        attrs = {"latitude": coords[0], "longitude": coords[1]} if coords else {}
        self.resources.append({"id": rid, "name": name, "status": status, "hourlyRate": hourly_rate,
                               "customAttributes": json.dumps(attrs)})
        self.schedules[rid] = [{
            "dayOfWeek": d, "startTime": f"{open_at}:00", "endTime": f"{close_at}:00", "isAvailable": True,
            "lunchBreakStart": f"{lunch[0]}:00" if lunch else None,
            "lunchBreakEnd": f"{lunch[1]}:00" if lunch else None,
            "maxDailyBookedHours": max_hours,
        } for d in days]

    def add_booking(self, rid: str, start: datetime, minutes: int, *, status: str = "Confirmed",
                    total_cost: float | None = None, booking_type_id: str = "bt-1") -> None:
        self.bookings.append({"id": f"b{len(self.bookings)}", "resourceId": rid, "bookingTypeId": booking_type_id,
                              "startTime": iso(start), "endTime": iso(start + timedelta(minutes=minutes)),
                              "status": status, "totalCost": total_cost})

    # ── transport ───────────────────────────────────────────────────────
    def client(self) -> ScheduleToolsClient:
        client = ScheduleToolsClient(base_url="http://testserver/api", auth_token="manager-jwt")
        client._client = httpx.Client(base_url="http://testserver/api",
                                      headers={"Authorization": "Bearer manager-jwt"},
                                      transport=httpx.MockTransport(self._handle))
        return client

    def _handle(self, request: httpx.Request) -> httpx.Response:
        path = unquote(request.url.path).removeprefix("/api")
        if any(path.startswith(p) for p in self.fail_paths):
            return httpx.Response(500, json={"message": "simulated backend failure"})
        if request.headers.get("authorization") != "Bearer manager-jwt":
            return httpx.Response(401, json={"message": "unauthorised"})
        q = request.url.params
        if path == "/resources":
            return httpx.Response(200, json={"items": self.resources, "total": len(self.resources)})
        if path.startswith("/resources/") and path.endswith("/schedule"):
            rid = path.split("/")[2]
            return httpx.Response(200, json=self.schedules.get(rid, []))
        if path == "/bookings/available-slots":
            return httpx.Response(200, json=self._slots(q["resourceId"], date.fromisoformat(q["date"][:10]),
                                                        int(q.get("duration", 60))))
        if path == "/bookings":
            rows = self.bookings
            if q.get("resourceId"):
                rows = [b for b in rows if b["resourceId"] == q["resourceId"]]
            if q.get("type"):
                rows = [b for b in rows if b["bookingTypeId"] == q["type"]]
            if q.get("dateFrom"):
                lo = _parse(q["dateFrom"])
                rows = [b for b in rows if _parse(b["startTime"]) >= lo]
            if q.get("dateTo"):
                hi = _parse(q["dateTo"])
                rows = [b for b in rows if _parse(b["startTime"]) <= hi]
            return httpx.Response(200, json={"items": rows, "total": len(rows)})
        return httpx.Response(404, json={"message": f"no fake for {path}"})

    def _slots(self, rid: str, day: date, duration: int) -> dict:
        weekday = (day.weekday() + 1) % 7
        entry = next((s for s in self.schedules.get(rid, []) if s["dayOfWeek"] == weekday and s["isAvailable"]), None)
        if entry is None:
            return {"isOpen": False, "slots": []}
        open_m, close_m = _hhmm(entry["startTime"]), _hhmm(entry["endTime"])
        ls, le = _hhmm(entry["lunchBreakStart"]), _hhmm(entry["lunchBreakEnd"])
        base = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
        live = [(_parse(b["startTime"]), _parse(b["endTime"])) for b in self.bookings
                if b["resourceId"] == rid and b["status"] in LIVE]
        slots, t = [], open_m
        while t + duration <= close_m:
            if ls is not None and t < le and ls < t + duration:
                t = le
                continue
            start, end = base + timedelta(minutes=t), base + timedelta(minutes=t + duration)
            free = not any(s < end and start < e for s, e in live)
            key = (rid, iso(start))
            if key in self.stolen_after_first_read:
                self._reads[key] = self._reads.get(key, 0) + 1
                if self._reads[key] > 1:
                    free = False
            slots.append({"startTime": iso(start), "endTime": iso(end), "isAvailable": free})
            t += duration
        return {"isOpen": True, "slots": slots}
