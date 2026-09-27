"""Agent 3 of the Schedule Copilot: Action / Tool.

A constraint-aware optimiser. It reads real open slots through the
allow-listed tools, scores every candidate against the priority rules, and
fills the schedule greedily - best-scoring feasible slot first, re-scoring
after each pick, because several rules (balance the load, cluster onto one
day, leave travel time) depend on what has already been chosen.

Why an optimiser and not an LLM loop: the question "which 12 of these 400
open slots satisfy every rule at once" has a right answer that arithmetic
finds exactly and a language model only approximates. The LLM's job was
upstream - turning a manager's sentence into rules. This agent's job is to
honour them, provably, and to say why each slot won.

Hard constraints (a candidate that breaks one is skipped, with the reason
kept for the trace):
  - never overlap another pick on the same resource, plus any minimum gap;
  - never exceed the resource's daily booked-hours cap (existing + new);
  - never cross the resource's lunch break, or 12:00-13:00 under keep_lunch_free;
  - under minimise_travel, leave the estimated travel time between same-day
    picks at different locations.

Every pick is re-verified with detect_conflicts before it is proposed. That
closes the window between reading availability and handing the schedule on.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from schemas.schedule_contracts import (
    ActionReport,
    DomainAnalysisReport,
    ResourceInsight,
    ScheduleConstraints,
    ScheduleProposal,
    SkippedCandidate,
)
from tools.booking_tools import ToolError
from tools.schedule_tools import AgentToolbox, haversine_km, parse_dt, parse_hhmm

LEAD_TIME_MINUTES = 60           # never propose a slot that starts within the hour
MAX_AVAILABILITY_QUERIES = 160   # bounds tool calls for a 12-resource, 31-day search
ASSUMED_DISTANCE_KM = 5.0        # between two locations with no recorded coordinates
DEFAULT_LUNCH = (12 * 60, 13 * 60)
MAX_SKIPPED_KEPT = 40


class _Candidate:
    __slots__ = ("resource", "start", "end", "base", "breakdown", "day_index")

    def __init__(self, resource: ResourceInsight, start: datetime, end: datetime, day_index: int):
        self.resource, self.start, self.end, self.day_index = resource, start, end, day_index
        self.base, self.breakdown = 0.0, {}


def _minute_of_day(value: datetime) -> int:
    return value.hour * 60 + value.minute


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime, gap: int = 0) -> bool:
    pad = timedelta(minutes=gap)
    return a_start < b_end + pad and b_start < a_end + pad


def _lunch_window(resource: ResourceInsight, rules: list[str]) -> tuple[int, int] | None:
    start, end = parse_hhmm(resource.lunch_start), parse_hhmm(resource.lunch_end)
    if start is not None and end is not None and end > start:
        return start, end
    return DEFAULT_LUNCH if "keep_lunch_free" in rules else None


def _base_score(c: _Candidate, rules: list[str], total_days: int) -> None:
    """The part of a slot's score that does not depend on other picks."""
    b: dict[str, float] = {"resource": round(c.resource.score * 0.4, 2)}
    hour = c.start.hour
    if "prefer_mornings" in rules:
        b["time_of_day"] = 15.0 if hour < 12 else -10.0
    elif "prefer_afternoons" in rules:
        b["time_of_day"] = 15.0 if hour >= 12 else -10.0
    if "earliest_first" in rules:
        b["earliest"] = round(15.0 * (1 - c.day_index / max(total_days, 1)), 2)
    else:
        # Mild tie-break towards sooner slots even without the rule: an empty
        # early slot is lost for good, a late one can still be sold.
        b["earliest"] = round(3.0 * (1 - c.day_index / max(total_days, 1)), 2)
    weight = 30.0 if "avoid_high_no_show" in rules else 8.0
    b["no_show"] = round(-weight * c.resource.no_show_rate, 2)
    c.breakdown, c.base = b, sum(b.values())


def run(
    *,
    constraints: ScheduleConstraints,
    analysis: DomainAnalysisReport,
    rules: list[str],
    target: int,
    min_gap_minutes: int,
    tools: AgentToolbox,
    now: datetime | None = None,
    weekdays: list[int] | None = None,
    time_window: str = "any",
) -> ActionReport:
    now = now or datetime.now(timezone.utc)
    earliest = now + timedelta(minutes=LEAD_TIME_MINUTES)
    rng = constraints.date_range
    days = [rng.date_from + timedelta(days=i) for i in range((rng.date_to - rng.date_from).days + 1)]
    days = [d for d in days if d >= earliest.date()]
    duration = constraints.duration_minutes
    notes: list[str] = []
    if weekdays:
        # The objective named days ("Thursday's buyers"). Honour them when the
        # window contains any; otherwise say so rather than silently ignore.
        named = [d for d in days if d.weekday() in weekdays]
        if named:
            days = named
            notes.append("Limited to " + ", ".join(sorted({d.strftime('%A') for d in named})) + " as the objective asked.")
        else:
            notes.append("The objective named days the date range does not contain; searched the whole range instead.")

    resources = [r for r in analysis.resources if r.working_days_in_range > 0]
    skipped: list[SkippedCandidate] = []
    seen_reasons: set[tuple[str, str]] = set()

    def skip(resource: ResourceInsight, start: datetime, reason: str) -> None:
        # Keep a representative sample: one entry per resource per reason is
        # enough to explain a gap, and a thousand identical rows is not.
        key = (resource.resource_id, reason)
        if key in seen_reasons or len(skipped) >= MAX_SKIPPED_KEPT:
            return
        seen_reasons.add(key)
        skipped.append(SkippedCandidate(resource_name=resource.resource_name, start=start, reason=reason))

    # ── 1. candidate generation through query_resource_availability ─────
    candidates: list[_Candidate] = []
    queries = 0
    for day_index, day in enumerate(days):
        for resource in resources:
            if queries >= MAX_AVAILABILITY_QUERIES:
                break
            queries += 1
            try:
                data = tools.query_resource_availability(resource.resource_id, day, duration, constraints.booking_type_id)
            except ToolError:
                continue
            if not data.get("isOpen", False):
                continue
            for slot in data.get("slots", []):
                if not slot.get("isAvailable", False):
                    continue
                start, end = parse_dt(slot.get("startTime")), parse_dt(slot.get("endTime"))
                if not start or not end:
                    continue
                if start < earliest:
                    continue
                if time_window == "morning" and start.hour >= 12:
                    continue
                if time_window == "afternoon" and start.hour < 12:
                    continue
                candidates.append(_Candidate(resource, start, end, day_index))

    for c in candidates:
        _base_score(c, rules, len(days))

    # ── 2. greedy fill under the hard constraints ───────────────────────
    picks: list[_Candidate] = []
    minutes_by_day: dict[tuple[str, str], int] = {}
    picks_per_resource: dict[str, int] = {}
    travel_cache: dict[tuple[str, str], float] = {}
    rejected_by_recheck: set[int] = set()

    def travel_between(a: ResourceInsight, b: ResourceInsight) -> float:
        if a.resource_id == b.resource_id:
            return 0.0
        key = tuple(sorted((a.resource_id, b.resource_id)))
        if key not in travel_cache:
            if a.latitude is not None and b.latitude is not None:
                km = haversine_km((a.latitude, a.longitude), (b.latitude, b.longitude))  # type: ignore[arg-type]
            else:
                km = ASSUMED_DISTANCE_KM
            try:
                travel_cache[key] = float(tools.calculate_travel_time(round(km, 2))["estimated_minutes"])
            except ToolError:
                travel_cache[key] = 15.0
        return travel_cache[key]

    def dynamic_score(c: _Candidate) -> tuple[float, dict[str, float]]:
        extra: dict[str, float] = {}
        if "balance_load" in rules:
            extra["balance"] = round(-6.0 * picks_per_resource.get(c.resource.resource_id, 0)
                                     - 0.15 * c.resource.utilisation_pct, 2)
        if "cluster_same_day" in rules and any(p.start.date() == c.start.date() for p in picks):
            extra["cluster"] = 12.0
        if "minimise_travel" in rules:
            same_day = [p for p in picks if p.start.date() == c.start.date()]
            if same_day:
                nearest = min(same_day, key=lambda p: abs((p.start - c.start).total_seconds()))
                extra["travel"] = round(-0.3 * travel_between(nearest.resource, c.resource), 2)
        return c.base + sum(extra.values()), extra

    def violation(c: _Candidate) -> str | None:
        rid = c.resource.resource_id
        for p in picks:
            if p.resource.resource_id == rid and _overlaps(c.start, c.end, p.start, p.end, min_gap_minutes):
                return "Overlaps another proposed booking on this resource" + (
                    f" (needs a {min_gap_minutes}-minute gap)" if min_gap_minutes else "")
        day_key = (rid, c.start.date().isoformat())
        existing = c.resource.booked_minutes_by_day.get(c.start.date().isoformat(), 0)
        planned = minutes_by_day.get(day_key, 0)
        if existing + planned + duration > c.resource.max_daily_minutes:
            return f"Would exceed the {c.resource.max_daily_minutes // 60}-hour daily cap"
        lunch = _lunch_window(c.resource, rules)
        if lunch:
            s, e = _minute_of_day(c.start), _minute_of_day(c.end) or 24 * 60
            if s < lunch[1] and lunch[0] < e:
                return "Crosses the lunch break"
        if "minimise_travel" in rules:
            for p in picks:
                if p.start.date() != c.start.date() or p.resource.resource_id == rid:
                    continue
                travel = travel_between(p.resource, c.resource)
                if _overlaps(c.start, c.end, p.start, p.end, int(round(travel))):
                    return f"Leaves less than the ~{travel:.0f} min travel time from {p.resource.resource_name}"
        return None

    while len(picks) < target:
        best: tuple[float, dict[str, float], int] | None = None
        for index, c in enumerate(candidates):
            if index in rejected_by_recheck or any(p is c for p in picks):
                continue
            reason = violation(c)
            if reason:
                skip(c.resource, c.start, reason)
                continue
            score, extra = dynamic_score(c)
            if best is None or score > best[0]:
                best = (score, extra, index)
        if best is None:
            break
        score, extra, index = best
        chosen = candidates[index]

        # Live re-check right before committing the pick.
        try:
            check = tools.detect_conflicts(chosen.resource.resource_id, chosen.start, duration, constraints.booking_type_id)
        except ToolError as e:
            check = {"has_conflict": True, "reason": f"Could not re-verify: {e}"}
        if check.get("has_conflict"):
            rejected_by_recheck.add(index)
            skip(chosen.resource, chosen.start, check.get("reason") or "Slot is no longer free")
            continue

        chosen.breakdown = {**chosen.breakdown, **extra}
        chosen.base = score
        picks.append(chosen)
        rid = chosen.resource.resource_id
        day_key = (rid, chosen.start.date().isoformat())
        minutes_by_day[day_key] = minutes_by_day.get(day_key, 0) + duration
        picks_per_resource[rid] = picks_per_resource.get(rid, 0) + 1

    # ── 3. explain each pick ────────────────────────────────────────────
    picks.sort(key=lambda p: p.start)
    proposals: list[ScheduleProposal] = []
    for i, p in enumerate(picks):
        reasons = [f"{p.resource.resource_name} ranked {p.resource.score:.0f}/100 by Domain Analysis."]
        b = p.breakdown
        if b.get("time_of_day", 0) > 0:
            reasons.append("Matches the time-of-day preference.")
        if b.get("earliest", 0) >= 10:
            reasons.append("One of the earliest open days in the window.")
        if b.get("cluster"):
            reasons.append("Grouped onto a day that already has bookings.")
        if "balance_load" in rules:
            reasons.append(f"Resource was {p.resource.utilisation_pct:.0f}% booked - chosen to even out load.")
        if p.resource.no_show_rate and p.resource.no_show_sample:
            reasons.append(f"Historical no-show rate {p.resource.no_show_rate * 100:.0f}%.")
        travel = None
        prev_same_day = [q for q in picks[:i] if q.start.date() == p.start.date()]
        if prev_same_day and "minimise_travel" in rules:
            travel = travel_between(prev_same_day[-1].resource, p.resource)
            reasons.append(f"~{travel:.0f} min travel from the previous booking (estimate).")
        proposals.append(ScheduleProposal(
            resource_id=p.resource.resource_id, resource_name=p.resource.resource_name,
            start=p.start, end=p.end, duration_minutes=duration,
            score=round(p.base, 1), score_breakdown={k: round(v, 2) for k, v in b.items()},
            reasons=reasons, no_show_risk=p.resource.no_show_rate,
            travel_minutes_from_previous=travel,
        ))

    if time_window != "any":
        notes.append(f"Only {time_window} slots were considered, as the objective asked.")
    return ActionReport(proposals=proposals, skipped=skipped, candidates_considered=len(candidates), notes=notes)
