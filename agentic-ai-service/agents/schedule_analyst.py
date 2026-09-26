"""Agent 2 of the Schedule Copilot: Domain Analysis.

Deterministic, no LLM. Before anything is scheduled it answers the questions
a good manager would ask about each candidate resource:

- Does it work at all in this window, and for how many hours?
- How full is it already?
- Do its bookings tend to turn up?
- What is its lunch break and its daily hour cap?

and ranks the resources on those facts. The ranking is data, not opinion:
every score is decomposed into reasons that name the number behind them, so
a manager can disagree with a specific input rather than with a black box.

Business-type agnostic: a "resource" is a dentist, a table, a boat or a
viewing agent - the arithmetic is the same.
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone

from schemas.schedule_contracts import DomainAnalysisReport, ResourceInsight, ScheduleConstraints
from tools.booking_tools import ToolError
from tools.schedule_tools import AgentToolbox, parse_dt, parse_hhmm

DEFAULT_MAX_DAILY_MINUTES = 8 * 60  # spec 2.7: "max 8 hours/day per doctor"
SETTLED_STATUSES = ("Completed", "NoShow")
LIVE_STATUSES = ("Pending", "Confirmed", "CheckedIn", "InProgress", "Completed")


def _days(constraints: ScheduleConstraints) -> list[date]:
    rng = constraints.date_range
    return [rng.date_from + timedelta(days=i) for i in range((rng.date_to - rng.date_from).days + 1)]


def _coordinates(resource: dict) -> tuple[float, float] | None:
    """Latitude/longitude from the resource's CustomAttributes JSON, when the
    business has recorded them (properties, pickup points, clinics)."""
    raw = resource.get("customAttributes")
    try:
        attrs = json.loads(raw) if isinstance(raw, str) else (raw or {})
    except (ValueError, TypeError):
        return None
    if not isinstance(attrs, dict):
        return None
    for lat_key, lng_key in (("latitude", "longitude"), ("lat", "lng"), ("lat", "lon")):
        if lat_key in attrs and lng_key in attrs:
            try:
                return float(attrs[lat_key]), float(attrs[lng_key])
            except (TypeError, ValueError):
                return None
    return None


def _weekday_key(day: date) -> int:
    """Backend DayOfWeek is .NET's: Sunday = 0."""
    return (day.weekday() + 1) % 7


def run(
    *,
    constraints: ScheduleConstraints,
    tenant_id: str,
    tools: AgentToolbox,
    rules: list[str],
    today: date | None = None,
) -> DomainAnalysisReport:
    today = today or datetime.now(timezone.utc).date()
    days = _days(constraints)

    resources = tools.search_resources(tenant_id, constraints.branch_id)
    if constraints.resource_ids:
        wanted = set(constraints.resource_ids)
        resources = [r for r in resources if str(r.get("id")) in wanted]
    resources = resources[:12]

    # One history read for the window covers every resource's current load.
    history = tools.query_booking_history(tenant_id, constraints.date_range.date_from, constraints.date_range.date_to)
    booked_by_resource: dict[str, int] = {}
    booked_by_day: dict[str, dict[str, int]] = {}
    for row in history:
        if row.get("status") not in LIVE_STATUSES:
            continue
        start, end = parse_dt(row.get("startTime")), parse_dt(row.get("endTime"))
        if start and end:
            rid = str(row.get("resourceId"))
            minutes = int((end - start).total_seconds() // 60)
            booked_by_resource[rid] = booked_by_resource.get(rid, 0) + minutes
            per_day = booked_by_day.setdefault(rid, {})
            per_day[start.date().isoformat()] = per_day.get(start.date().isoformat(), 0) + minutes

    insights: list[ResourceInsight] = []
    for resource in resources:
        rid, name = str(resource.get("id")), str(resource.get("name") or "Resource")
        reasons: list[str] = []
        coords = _coordinates(resource)
        try:
            weekly = tools.check_staff_schedule(rid)
        except ToolError:
            weekly = []
            reasons.append("Weekly hours could not be read; treated as closed.")

        by_day = {int(d.get("dayOfWeek", -1)): d for d in weekly if d.get("isAvailable", True)}
        working_days, capacity, max_daily, lunch = 0, 0, DEFAULT_MAX_DAILY_MINUTES, (None, None)
        for day in days:
            entry = by_day.get(_weekday_key(day))
            if not entry:
                continue
            open_m, close_m = parse_hhmm(entry.get("startTime")), parse_hhmm(entry.get("endTime"))
            if open_m is None or close_m is None or close_m <= open_m:
                continue
            working_days += 1
            span = close_m - open_m
            ls, le = parse_hhmm(entry.get("lunchBreakStart")), parse_hhmm(entry.get("lunchBreakEnd"))
            if ls is not None and le is not None and le > ls:
                span -= le - ls
                lunch = (entry.get("lunchBreakStart"), entry.get("lunchBreakEnd"))
            cap_hours = entry.get("maxDailyBookedHours")
            if cap_hours:
                max_daily = min(max_daily, int(float(cap_hours) * 60))
            capacity += min(span, max_daily)

        booked = booked_by_resource.get(rid, 0)
        utilisation = (booked / capacity * 100) if capacity else 100.0

        try:
            ns = tools.predict_no_show_probability(tenant_id, rid, today)
            no_show, sample = float(ns.get("rate", 0.0)), int(ns.get("sample", 0))
        except ToolError:
            no_show, sample = 0.0, 0
            reasons.append("No-show history unavailable; assumed 0%.")

        # Score in [0, 100]. Availability dominates: a resource that is not
        # open cannot take a booking however good it looks otherwise.
        score = 0.0
        if working_days:
            score += 40 * (working_days / len(days))
            score += 35 * max(0.0, 1 - utilisation / 100)
            score += 25 * (1 - min(no_show, 1.0)) if "avoid_high_no_show" in rules else 25 * (1 - min(no_show, 1.0) * 0.4)
        reasons.insert(0, f"Open {working_days} of {len(days)} day(s) in the window.")
        reasons.append(f"{utilisation:.0f}% already booked ({booked} of {capacity} bookable minutes).")
        if sample:
            reasons.append(f"No-show rate {no_show * 100:.0f}% over the last {sample} settled booking(s).")
        else:
            reasons.append("No settled bookings in the last 90 days to judge no-shows on.")
        if lunch[0]:
            reasons.append(f"Lunch {str(lunch[0])[:5]}-{str(lunch[1])[:5]} is kept clear.")

        insights.append(ResourceInsight(
            resource_id=rid, resource_name=name,
            working_days_in_range=working_days,
            booked_minutes_in_range=booked, capacity_minutes_in_range=capacity,
            utilisation_pct=round(min(utilisation, 100.0), 1),
            no_show_rate=round(min(no_show, 1.0), 4), no_show_sample=sample,
            max_daily_minutes=max_daily,
            lunch_start=str(lunch[0])[:5] if lunch[0] else None,
            lunch_end=str(lunch[1])[:5] if lunch[1] else None,
            booked_minutes_by_day=booked_by_day.get(rid, {}),
            latitude=coords[0] if coords else None,
            longitude=coords[1] if coords else None,
            score=round(score, 1), reasons=reasons,
        ))

    insights.sort(key=lambda r: r.score, reverse=True)

    # Booking value, for the revenue-impact approval rule: the average of what
    # this booking type actually charged over the last 90 days.
    value, value_sample = None, 0
    try:
        priced = [float(r["totalCost"]) for r in tools.query_booking_history(
            tenant_id, today - timedelta(days=90), today, booking_type_id=constraints.booking_type_id)
            if r.get("totalCost") not in (None, 0, "0")]
        if priced:
            value, value_sample = round(sum(priced) / len(priced), 2), len(priced)
    except ToolError:
        pass
    if value is None:
        # No priced history: fall back to the resources' own hourly rates,
        # which is what the business would charge for the time.
        rates = [float(r.get("hourlyRate") or 0) for r in resources if r.get("hourlyRate")]
        if rates:
            value = round(sum(rates) / len(rates) * constraints.duration_minutes / 60, 2)

    notes: list[str] = []
    open_resources = [r for r in insights if r.working_days_in_range]
    if not open_resources:
        notes.append("No candidate resource is open on any day in the window.")
    else:
        best = open_resources[0]
        notes.append(f"{best.resource_name} ranks first: open {best.working_days_in_range} day(s), "
                     f"{best.utilisation_pct:.0f}% booked.")
        busiest = max(open_resources, key=lambda r: r.utilisation_pct)
        if busiest.utilisation_pct >= 80:
            notes.append(f"{busiest.resource_name} is already {busiest.utilisation_pct:.0f}% booked in this window.")
        risky = [r for r in open_resources if r.no_show_sample >= 5 and r.no_show_rate >= 0.2]
        if risky:
            notes.append("High no-show history: " + ", ".join(f"{r.resource_name} ({r.no_show_rate * 100:.0f}%)" for r in risky) + ".")
    if value is None:
        notes.append("No priced bookings of this type in 90 days and no hourly rates; revenue impact cannot be estimated.")
    elif value_sample == 0:
        notes.append(f"Booking value estimated at {value:,.2f} from the resources' hourly rates (no priced history).")
    else:
        notes.append(f"Average booking value {value:,.2f} from {value_sample} priced booking(s) in 90 days.")

    return DomainAnalysisReport(resources=insights, average_booking_value=value,
                                value_sample=value_sample, insights=notes)
