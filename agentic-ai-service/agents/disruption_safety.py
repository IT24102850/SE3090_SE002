"""Agent 4: Disruption Safety. Deterministic - there is no model in this file.

It is the last word on a recovery plan, and it answers two questions: is each
proposal allowed at all, and may any of it happen without a manager?

The second answer is always the same here. Moving somebody else's booking is
high-impact by definition: the customer has arranged their day around it, may
have paid a deposit, and did not ask for the change. So a run always ends
AwaitingApproval, never Completed. That is the one irreversible step the spec
puts behind a human, and keeping it unconditional means no objective phrased
cleverly enough can talk the system past it.

Checks it applies, each recorded pass or fail:
  no_self_move          a proposal may not put a booking back on the broken resource
  within_move_window    the move stays inside the policy's day limit
  no_conflict           the destination slot is free, re-read now, not trusted from earlier
  capacity_respected    the substitute seats the party, where the trade requires it
  specialty_respected   the substitute has the right specialty, where the trade requires it
  group_kept_together   everyone on one original slot lands on one destination
  cancellation_allowed  nothing is cancelled unless the manager asked for that
"""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Any

from agents.disruption_policy import DisruptionPolicy
from schemas.disruption_contracts import (
    ActionOutput, AffectedBooking, DisruptionIntent, RecoveryProposal, SafetyCheck, SafetyOutput,
)
from tools.disruption_tools import AgentToolbox, ToolError


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    return a_start < b_end and a_end > b_start


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def run(
    *,
    action: ActionOutput,
    affected: list[AffectedBooking],
    policy: DisruptionPolicy,
    intent: DisruptionIntent,
    disrupted_resource_id: str,
    toolbox: AgentToolbox,
    resources_by_id: dict[str, dict[str, Any]],
    original_specialty: str | None,
    now: datetime | None = None,
) -> SafetyOutput:
    now = now or datetime.now(timezone.utc)
    checks: list[SafetyCheck] = []
    rejected: list[str] = []

    by_id = {b.booking_id: b for b in affected}
    max_days = min(policy.max_days_to_move, intent.max_days_to_move)

    # ── no proposal may point back at the resource that broke ───────────
    self_moves = [p for p in action.proposals if p.proposed_resource_id == disrupted_resource_id
                  and p.kind in {"MoveResource", "MoveBoth"}]
    checks.append(SafetyCheck(
        rule="no_self_move",
        passed=not self_moves,
        detail="No recovery sends a booking back to the unavailable "
               f"{policy.resource_noun}." if not self_moves
               else f"{len(self_moves)} proposal(s) point back at the unavailable {policy.resource_noun}.",
    ))
    rejected.extend(p.booking_id for p in self_moves)

    # ── the move has to stay inside the policy's window ─────────────────
    too_far: list[RecoveryProposal] = []
    for p in action.proposals:
        if p.proposed_starts_at is None:
            continue
        moved_days = abs((_as_utc(p.proposed_starts_at).date() - _as_utc(p.original_starts_at).date()).days)
        if moved_days > max_days:
            too_far.append(p)
    checks.append(SafetyCheck(
        rule="within_move_window",
        passed=not too_far,
        detail=f"Every move stays within {max_days} day(s)." if not too_far
               else f"{len(too_far)} proposal(s) move a {policy.booking_noun} more than {max_days} day(s).",
    ))
    rejected.extend(p.booking_id for p in too_far)

    # ── the destination must still be free, read again now ──────────────
    conflicted: list[RecoveryProposal] = []
    could_not_verify = False
    conflict_detail = "Every destination slot was re-checked and is free."
    try:
        wanted: dict[str, list[RecoveryProposal]] = defaultdict(list)
        for p in action.proposals:
            if p.proposed_resource_id and p.proposed_starts_at and p.proposed_ends_at:
                wanted[p.proposed_resource_id].append(p)

        for resource_id, proposals in wanted.items():
            starts = min(_as_utc(p.proposed_starts_at) for p in proposals)  # type: ignore[arg-type]
            ends = max(_as_utc(p.proposed_ends_at) for p in proposals)  # type: ignore[arg-type]
            existing = toolbox.detect_conflicts(resource_id, starts.isoformat(), ends.isoformat())
            booked = [
                (_as_utc(datetime.fromisoformat(str(row["startsAt"]).replace("Z", "+00:00"))),
                 _as_utc(datetime.fromisoformat(str(row["endsAt"]).replace("Z", "+00:00"))),
                 str(row.get("bookingId")))
                for row in existing
            ]
            for p in proposals:
                clash = any(
                    _overlaps(_as_utc(p.proposed_starts_at), _as_utc(p.proposed_ends_at), s, e)  # type: ignore[arg-type]
                    and booking_id != p.booking_id
                    for s, e, booking_id in booked
                )
                if clash:
                    conflicted.append(p)
    except (ToolError, ValueError, KeyError, TypeError) as e:
        # A gate that cannot verify must not pass. Everything is struck out
        # and the manager is told why, rather than approving on a guess.
        conflicted = list(action.proposals)
        could_not_verify = True
        conflict_detail = f"The destination slots could not be re-checked, so nothing is proposed: {e}"

    if conflicted and not could_not_verify:
        conflict_detail = f"{len(conflicted)} destination slot(s) are already taken."
    checks.append(SafetyCheck(rule="no_conflict", passed=not conflicted, detail=conflict_detail))
    rejected.extend(p.booking_id for p in conflicted)

    # ── the substitute has to be able to take the party ─────────────────
    undersized: list[RecoveryProposal] = []
    if policy.require_equal_capacity:
        for p in action.proposals:
            booking = by_id.get(p.booking_id)
            resource = resources_by_id.get(p.proposed_resource_id or "")
            if not booking or not resource:
                continue
            capacity = resource.get("capacity")
            if isinstance(capacity, int) and capacity > 0 and capacity < booking.attendee_count:
                undersized.append(p)
    checks.append(SafetyCheck(
        rule="capacity_respected",
        passed=not undersized,
        detail="Every substitute can take its party." if not undersized
               else f"{len(undersized)} substitute(s) are too small for the party.",
    ))
    rejected.extend(p.booking_id for p in undersized)

    # ── and the right specialty, where the trade requires it ────────────
    wrong_specialty: list[RecoveryProposal] = []
    if policy.require_same_specialty and original_specialty:
        for p in action.proposals:
            resource = resources_by_id.get(p.proposed_resource_id or "")
            if not resource:
                continue
            substitute = (resource.get("specialty") or "").strip().lower()
            if substitute != original_specialty.strip().lower():
                wrong_specialty.append(p)
    checks.append(SafetyCheck(
        rule="specialty_respected",
        passed=not wrong_specialty,
        detail=f"Every substitute {policy.resource_noun} matches the original's specialty."
               if not wrong_specialty
               else f"{len(wrong_specialty)} substitute(s) do not match the required specialty.",
    ))
    rejected.extend(p.booking_id for p in wrong_specialty)

    # ── a group moves together or not at all ────────────────────────────
    split_groups: list[str] = []
    if policy.keep_group_together:
        by_slot: dict[tuple[str, str], set[tuple[str | None, str | None]]] = defaultdict(set)
        for p in action.proposals:
            booking = by_id.get(p.booking_id)
            if not booking:
                continue
            slot = (booking.booking_type_id, _as_utc(booking.starts_at).isoformat())
            destination = (p.proposed_resource_id,
                           _as_utc(p.proposed_starts_at).isoformat() if p.proposed_starts_at else None)
            by_slot[slot].add(destination)
        for slot, destinations in by_slot.items():
            if len(destinations) > 1:
                split_groups.append(slot[1])
    checks.append(SafetyCheck(
        rule="group_kept_together",
        passed=not split_groups,
        detail="Everyone booked on the same slot moves together."
               if not split_groups
               else f"{len(split_groups)} group(s) would be split across destinations.",
    ))

    # ── nothing is cancelled unless that was asked for ──────────────────
    cancels = [p for p in action.proposals if p.kind == "Cancel"]
    cancellation_ok = intent.allow_cancellation or not cancels
    checks.append(SafetyCheck(
        rule="cancellation_allowed",
        passed=cancellation_ok,
        detail="No cancellations proposed." if not cancels
               else ("Cancellations were explicitly permitted." if intent.allow_cancellation
                     else f"{len(cancels)} cancellation(s) proposed, which this run did not permit."),
    ))
    if not cancellation_ok:
        rejected.extend(p.booking_id for p in cancels)

    unique_rejected = sorted(set(rejected))
    survivors = [p for p in action.proposals if p.booking_id not in set(unique_rejected)]

    blocking_failed = [c for c in checks if not c.passed and c.rule != "group_kept_together"]
    is_allowed = bool(survivors) or not action.proposals

    return SafetyOutput(
        is_allowed=is_allowed,
        # Unconditional: a person decides, always.
        requires_human_approval=True,
        rejection_reason=None if is_allowed else
            "; ".join(c.detail for c in blocking_failed) or "No recovery survived the safety checks.",
        checks=checks,
        rejected_booking_ids=unique_rejected,
    )
