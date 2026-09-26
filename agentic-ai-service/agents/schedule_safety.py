"""Agent 4 of the Schedule Copilot: Validation / Safety.

Deterministic Python. It never calls a model, so nothing written in an
objective can argue it out of a decision. It re-derives every rule from the
proposals themselves rather than trusting the optimiser's say-so - the point
of a gate is that it does not assume the agent before it was right.

Checks, each recorded as a named pass / fail / warn so the approver can see
exactly what was verified:

  schema              every proposal is well-formed and internally consistent
  count               no more bookings than the planner was allowed to ask for
  future              nothing starts in the past
  duration            within MAX_APPOINTMENT_DURATION_MINUTES (spec: 2 hours)
  no_double_booking   no two proposals overlap on one resource
  live_conflicts      every slot is still free right now (detect_conflicts)
  daily_hours         existing + proposed load within the daily cap (spec: 8h)
  lunch_break         nothing crosses a resource's lunch break
  coverage            how much of the request was met (warn, never fail)

A hard failure rejects the whole plan: a schedule with one unsafe line is
returned for revision, not quietly trimmed, because a manager approving it
would otherwise be approving something other than what the agents proposed.

Human approval (spec 2.7): a change affecting more than
APPROVAL_BOOKING_COUNT_THRESHOLD bookings, or with an estimated revenue
impact above APPROVAL_REVENUE_THRESHOLD in USD, pauses for a manager. Both
thresholds come from this service's configuration, never from the request.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

from schemas.schedule_contracts import (
    DomainAnalysisReport,
    SafetyReport,
    ScheduleConstraints,
    ScheduleProposal,
    ValidationCheck,
)
from tools.booking_tools import ToolError
from tools.schedule_tools import AgentToolbox, parse_hhmm

APPROVAL_BOOKING_COUNT_THRESHOLD = int(os.getenv("APPROVAL_BOOKING_COUNT_THRESHOLD", "20"))
APPROVAL_REVENUE_THRESHOLD_USD = float(os.getenv("APPROVAL_REVENUE_THRESHOLD", "500"))
MAX_APPOINTMENT_DURATION_MINUTES = int(os.getenv("MAX_APPOINTMENT_DURATION_MINUTES", "120"))

# Approximate, and labelled so in the trace. The threshold in the spec is in
# dollars; a Sri Lankan operator prices in rupees, and comparing LKR 287,000
# to "500" would send every schedule to approval for no reason.
USD_PER_UNIT = {"USD": 1.0, "LKR": 1 / 300, "EUR": 1.08, "GBP": 1.27, "INR": 1 / 83, "AUD": 0.66}


def to_usd(amount: float, currency: str) -> float | None:
    rate = USD_PER_UNIT.get(currency.upper())
    return round(amount * rate, 2) if rate is not None else None


def _minute(value: datetime) -> int:
    return value.hour * 60 + value.minute


def run(
    *,
    proposals: list[ScheduleProposal],
    constraints: ScheduleConstraints,
    analysis: DomainAnalysisReport,
    target: int,
    rules: list[str],
    currency: str,
    tools: AgentToolbox,
    now: datetime | None = None,
) -> tuple[SafetyReport, float | None, float | None]:
    """Returns the report plus (estimated_revenue, estimated_revenue_usd)."""
    now = now or datetime.now(timezone.utc)
    checks: list[ValidationCheck] = []
    failures: list[str] = []

    def record(rule: str, ok: bool, detail: str, *, warn: bool = False) -> None:
        status = "pass" if ok else ("warn" if warn else "fail")
        checks.append(ValidationCheck(rule=rule, status=status, detail=detail))
        if status == "fail":
            failures.append(detail)

    if not proposals:
        record("proposals", False, "No bookable slot satisfied every rule in the window.")
        return SafetyReport(is_allowed=False, requires_human_approval=False,
                            rejection_reason=failures[0], checks=checks), None, None

    # schema
    malformed = [p for p in proposals
                 if p.end <= p.start or p.duration_minutes <= 0
                 or abs((p.end - p.start).total_seconds() / 60 - p.duration_minutes) > 1]
    record("schema", not malformed,
           "All proposals are well-formed." if not malformed
           else f"{len(malformed)} proposal(s) have an end before the start or a duration that does not match.")

    # count - the optimiser must not return more than it was asked for
    record("count", len(proposals) <= target,
           f"{len(proposals)} proposal(s) within the allowed {target}." if len(proposals) <= target
           else f"{len(proposals)} proposals exceed the allowed {target}.")

    # future
    past = [p for p in proposals if p.start <= now]
    record("future", not past,
           "Every proposal starts in the future." if not past else f"{len(past)} proposal(s) start in the past.")

    # duration
    too_long = [p for p in proposals if p.duration_minutes > MAX_APPOINTMENT_DURATION_MINUTES]
    record("duration", not too_long,
           f"Every booking is within the {MAX_APPOINTMENT_DURATION_MINUTES}-minute limit." if not too_long
           else f"{len(too_long)} booking(s) exceed the {MAX_APPOINTMENT_DURATION_MINUTES}-minute limit.")

    # no double-booking inside the proposal itself
    clashes: list[str] = []
    ordered = sorted(proposals, key=lambda p: (p.resource_id, p.start))
    for a, b in zip(ordered, ordered[1:]):
        if a.resource_id == b.resource_id and b.start < a.end:
            clashes.append(f"{a.resource_name} {a.start:%a %H:%M} overlaps {b.start:%H:%M}")
    record("no_double_booking", not clashes,
           "No two proposals share a resource at the same time." if not clashes
           else "Double-booking: " + "; ".join(clashes[:3]))

    # daily hour cap, existing load included
    by_resource = {r.resource_id: r for r in analysis.resources}
    over_cap: list[str] = []
    load: dict[tuple[str, str], int] = {}
    for p in proposals:
        key = (p.resource_id, p.start.date().isoformat())
        load[key] = load.get(key, 0) + p.duration_minutes
    for (rid, day), planned in load.items():
        info = by_resource.get(rid)
        cap = info.max_daily_minutes if info else 8 * 60
        existing = info.booked_minutes_by_day.get(day, 0) if info else 0
        if existing + planned > cap:
            name = info.resource_name if info else rid
            over_cap.append(f"{name} on {day}: {(existing + planned) / 60:.1f}h of {cap / 60:.0f}h")
    record("daily_hours", not over_cap,
           "Every resource stays within its daily booked-hours cap." if not over_cap
           else "Daily cap exceeded: " + "; ".join(over_cap[:3]))

    # lunch break
    crossing: list[str] = []
    for p in proposals:
        info = by_resource.get(p.resource_id)
        start, end = parse_hhmm(info.lunch_start if info else None), parse_hhmm(info.lunch_end if info else None)
        if start is None and "keep_lunch_free" in rules:
            start, end = 12 * 60, 13 * 60
        if start is None or end is None:
            continue
        s, e = _minute(p.start), _minute(p.end) or 24 * 60
        if s < end and start < e:
            crossing.append(f"{p.resource_name} {p.start:%a %H:%M}")
    record("lunch_break", not crossing,
           "No booking crosses a lunch break." if not crossing
           else "Crosses lunch: " + ", ".join(crossing[:3]))

    # live re-verification - the defence against a booking made since planning
    stale: list[str] = []
    unverifiable = 0
    for p in proposals:
        try:
            result = tools.detect_conflicts(p.resource_id, p.start, p.duration_minutes, constraints.booking_type_id)
        except ToolError:
            unverifiable += 1
            continue
        if result.get("has_conflict"):
            stale.append(f"{p.resource_name} {p.start:%a %H:%M} ({result.get('reason')})")
    if unverifiable:
        record("live_conflicts", False, f"{unverifiable} slot(s) could not be re-verified against live bookings.")
    else:
        record("live_conflicts", not stale,
               f"All {len(proposals)} slot(s) re-verified free against live bookings." if not stale
               else "No longer free: " + "; ".join(stale[:3]))

    # coverage - informative, never a failure
    coverage = len(proposals) / target if target else 1.0
    record("coverage", coverage >= 1.0,
           f"Met the full request ({len(proposals)}/{target})." if coverage >= 1.0
           else f"Found {len(proposals)} of {target} requested; the rest did not fit every rule.",
           warn=True)

    # approval decision (spec 2.7)
    value = analysis.average_booking_value
    revenue = round(value * len(proposals), 2) if value is not None else None
    revenue_usd = to_usd(revenue, currency) if revenue is not None else None
    reasons: list[str] = []
    if len(proposals) > APPROVAL_BOOKING_COUNT_THRESHOLD:
        reasons.append(f"Affects {len(proposals)} bookings (threshold {APPROVAL_BOOKING_COUNT_THRESHOLD}).")
    if revenue_usd is not None and revenue_usd > APPROVAL_REVENUE_THRESHOLD_USD:
        reasons.append(f"Revenue impact ~${revenue_usd:,.0f} (threshold ${APPROVAL_REVENUE_THRESHOLD_USD:,.0f}).")
    if revenue is not None and revenue_usd is None:
        reasons.append(f"Revenue impact {revenue:,.2f} {currency} could not be converted to USD; a manager must check it.")

    allowed = not failures
    return SafetyReport(
        is_allowed=allowed,
        requires_human_approval=allowed and bool(reasons),
        approval_reasons=reasons if allowed else [],
        rejection_reason=None if allowed else failures[0],
        checks=checks,
    ), revenue, revenue_usd
