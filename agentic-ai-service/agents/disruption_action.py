"""Agent 3: Recovery Action. One concrete proposal per stranded booking.

Read-only: it searches real open slots on real substitute resources and
proposes, it never books. Applying is a separate approved request to
ASP.NET Core.

The search follows the trade's policy rather than a single hard-coded idea of
a good outcome. A clinic would rather keep the time and change the doctor,
because a patient has taken the morning off; a gym would rather keep the
trainer and move the hour. Where the policy has no preference, keeping the
time is tried first, because that is what the customer planned around.

It also books nothing twice: a slot it has already promised to an earlier,
higher-priority booking is held in `taken` and not offered again.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from agents.disruption_policy import DisruptionPolicy
from schemas.disruption_contracts import (
    ActionOutput, AffectedBooking, DisruptionIntent, ImpactOutput, RecoveryProposal,
)
from tools.disruption_tools import AgentToolbox, ToolError


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _parse(value: Any) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _suitable(
    candidate: dict[str, Any],
    *,
    original: dict[str, Any] | None,
    booking: AffectedBooking,
    policy: DisruptionPolicy,
) -> bool:
    """Whether one resource could stand in for another, per the trade's rules."""
    if policy.require_same_specialty and original:
        wanted = (original.get("specialty") or "").strip().lower()
        if wanted and (candidate.get("specialty") or "").strip().lower() != wanted:
            return False
    if policy.require_equal_capacity:
        capacity = candidate.get("capacity")
        if isinstance(capacity, int) and 0 < capacity < booking.attendee_count:
            return False
    if original and candidate.get("category") and original.get("category"):
        # A boat cannot stand in for a consulting room.
        if str(candidate["category"]).lower() != str(original["category"]).lower():
            return False
    return True


def run(
    *,
    impact: ImpactOutput,
    policy: DisruptionPolicy,
    intent: DisruptionIntent,
    tenant_id: str,
    branch_id: str | None,
    disrupted_resource_id: str,
    toolbox: AgentToolbox,
    now: datetime | None = None,
) -> tuple[ActionOutput, dict[str, dict[str, Any]], str | None]:
    """Returns the proposals, the candidate resources seen, and the original's specialty."""
    now = now or datetime.now(timezone.utc)
    notes: list[str] = []
    unresolved: list[str] = []
    proposals: list[RecoveryProposal] = []

    try:
        original = toolbox.get_resource(disrupted_resource_id)
    except ToolError:
        original = None
        notes.append("The unavailable resource's details could not be read, so substitutes are matched loosely.")

    original_specialty = (original or {}).get("specialty")

    try:
        every = toolbox.list_resources(tenant_id, branch_id)
    except ToolError as e:
        return ActionOutput(proposals=[], unresolved=[b.booking_id for b in impact.affected],
                            notes=[f"No substitutes could be listed: {e}"]), {}, original_specialty

    candidates = [
        r for r in every
        if str(r.get("id")) != disrupted_resource_id and r.get("isActive", True)
    ]
    by_id = {str(r.get("id")): r for r in candidates}

    max_days = min(policy.max_days_to_move, intent.max_days_to_move)
    prefer = intent.prefer if intent.prefer != "either" else policy.prefer

    # Slots already promised in this run, so two customers are never offered
    # the same one: {resource_id: [(start, end)]}
    taken: dict[str, list[tuple[datetime, datetime]]] = {}

    def is_free(resource_id: str, start: datetime, end: datetime) -> bool:
        return not any(start < e and end > s for s, e in taken.get(resource_id, []))

    def hold(resource_id: str, start: datetime, end: datetime) -> None:
        taken.setdefault(resource_id, []).append((start, end))

    for booking in impact.affected:
        duration = int((_as_utc(booking.ends_at) - _as_utc(booking.starts_at)).total_seconds() // 60) or 60
        suitable = [r for r in candidates
                    if _suitable(r, original=original, booking=booking, policy=policy)]

        found: RecoveryProposal | None = None

        def try_same_time() -> RecoveryProposal | None:
            """Keep the hour, change the resource."""
            for candidate in suitable:
                resource_id = str(candidate.get("id"))
                start, end = _as_utc(booking.starts_at), _as_utc(booking.ends_at)
                if not is_free(resource_id, start, end):
                    continue
                try:
                    slots = toolbox.find_free_slots(
                        resource_id, start.date().isoformat(), duration, booking.booking_type_id)
                except ToolError:
                    continue
                for slot in slots.get("slots", []) if isinstance(slots, dict) else []:
                    slot_start = _parse(slot.get("startTime"))
                    if slot_start and slot_start == start and slot.get("isAvailable", True):
                        hold(resource_id, start, end)
                        return RecoveryProposal(
                            booking_id=booking.booking_id,
                            customer_name=booking.customer_name,
                            kind="MoveResource",
                            original_starts_at=start, original_ends_at=end,
                            proposed_resource_id=resource_id,
                            proposed_resource_name=str(candidate.get("name") or ""),
                            proposed_starts_at=start, proposed_ends_at=end,
                            explanation=(
                                f"Same time, with {candidate.get('name')} instead of "
                                f"{impact.resource_name}."),
                            confidence=0.9,
                        )
            return None

        def try_later() -> RecoveryProposal | None:
            """Keep the resource family, move the time."""
            for day_offset in range(0, max_days + 1):
                day = (_as_utc(booking.starts_at) + timedelta(days=day_offset)).date()
                for candidate in suitable:
                    resource_id = str(candidate.get("id"))
                    try:
                        slots = toolbox.find_free_slots(
                            resource_id, day.isoformat(), duration, booking.booking_type_id)
                    except ToolError:
                        continue
                    for slot in slots.get("slots", []) if isinstance(slots, dict) else []:
                        if not slot.get("isAvailable", True):
                            continue
                        slot_start = _parse(slot.get("startTime"))
                        slot_end = _parse(slot.get("endTime")) or (
                            slot_start + timedelta(minutes=duration) if slot_start else None)
                        if not slot_start or not slot_end or slot_start <= now:
                            continue
                        if not is_free(resource_id, slot_start, slot_end):
                            continue
                        hold(resource_id, slot_start, slot_end)
                        same_day = slot_start.date() == _as_utc(booking.starts_at).date()
                        return RecoveryProposal(
                            booking_id=booking.booking_id,
                            customer_name=booking.customer_name,
                            kind="MoveTime" if same_day else "MoveBoth",
                            original_starts_at=_as_utc(booking.starts_at),
                            original_ends_at=_as_utc(booking.ends_at),
                            proposed_resource_id=resource_id,
                            proposed_resource_name=str(candidate.get("name") or ""),
                            proposed_starts_at=slot_start, proposed_ends_at=slot_end,
                            explanation=(
                                f"Moved to {slot_start:%a %d %b, %H:%M} with "
                                f"{candidate.get('name')}."),
                            confidence=0.75 if same_day else 0.6,
                        )
            return None

        order = (try_same_time, try_later) if prefer != "same_resource_later" else (try_later, try_same_time)
        for attempt in order:
            found = attempt()
            if found:
                break

        if found:
            proposals.append(found)
        else:
            unresolved.append(booking.booking_id)
            proposals.append(RecoveryProposal(
                booking_id=booking.booking_id,
                customer_name=booking.customer_name,
                kind="NoOptionFound",
                original_starts_at=_as_utc(booking.starts_at),
                original_ends_at=_as_utc(booking.ends_at),
                explanation=(
                    f"No suitable {policy.resource_noun} is free within {max_days} day(s). "
                    f"This {policy.booking_noun} needs a manager's decision."),
                confidence=0.0,
            ))

    if unresolved:
        notes.append(f"{len(unresolved)} {policy.booking_noun}(s) could not be re-placed automatically.")

    return ActionOutput(proposals=proposals, unresolved=unresolved, notes=notes), by_id, original_specialty
