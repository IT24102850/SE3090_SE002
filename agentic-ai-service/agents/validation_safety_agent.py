"""Agent 4: Validation/Safety. Deterministic Python only — NEVER calls
Gemini. A safety gate that could be talked out of its decision by clever
prompt content defeats the point of having one; every check here is a
plain conditional, independently testable without mocking an LLM.

Checks: at least one proposal exists, the slot is still free (re-checked
right now, defense against the ranking/availability race), the datetime
isn't in the past, duration is within MAX_APPOINTMENT_DURATION_MINUTES, and
whether the action crosses the human-approval threshold. Only if everything
clears AND no approval is required does it call `create_booking` — the only
place in the whole pipeline allowed to.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

from schemas.contracts import ProposedBooking, ValidationSafetyOutput
from tools.booking_tools import BookingToolsClient, ToolError

APPROVAL_BOOKING_COUNT_THRESHOLD = int(os.getenv("APPROVAL_BOOKING_COUNT_THRESHOLD", "20"))
APPROVAL_REVENUE_THRESHOLD = float(os.getenv("APPROVAL_REVENUE_THRESHOLD", "500"))
MAX_APPOINTMENT_DURATION_MINUTES = int(os.getenv("MAX_APPOINTMENT_DURATION_MINUTES", "120"))


def run(
    *,
    proposed_bookings: list[ProposedBooking],
    tenant_id: str,
    client: BookingToolsClient,
    booking_count: int | None = None,
    estimated_revenue_impact: float = 0.0,
) -> ValidationSafetyOutput:
    notes: list[str] = []

    if not proposed_bookings:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason="No proposed booking to validate.",
            validation_notes=["Action/Tool agent found no available slot."],
        )

    booking = proposed_bookings[0]
    now = datetime.now(timezone.utc)
    scheduled = booking.scheduled_datetime
    if scheduled.tzinfo is None:
        scheduled = scheduled.replace(tzinfo=timezone.utc)

    if scheduled <= now:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason="Proposed time is in the past.",
            validation_notes=notes,
        )
    notes.append("Proposed time is in the future. OK.")

    if booking.duration_minutes <= 0 or booking.duration_minutes > MAX_APPOINTMENT_DURATION_MINUTES:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=f"Duration {booking.duration_minutes}min exceeds the {MAX_APPOINTMENT_DURATION_MINUTES}min limit.",
            validation_notes=notes,
        )
    notes.append(f"Duration {booking.duration_minutes}min is within the {MAX_APPOINTMENT_DURATION_MINUTES}min limit.")

    if booking.has_conflict:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=booking.conflict_reason or "Action/Tool agent flagged a conflict.",
            validation_notes=notes,
        )

    # Defense-in-depth: re-check right now, independent of the agent's own
    # (possibly stale, from a few tool calls ago) conflict flag. A slot that
    # passes this is also, by construction, within the resource's working
    # hours — SlotCalculator (the same logic every other booking path uses)
    # never marks an out-of-hours slot as available.
    try:
        conflict_check = client.detect_conflicts(
            resource_id=booking.resource_id,
            date=scheduled.date().isoformat(),
            duration_minutes=booking.duration_minutes,
            scheduled_datetime=booking.scheduled_datetime.isoformat(),
            booking_type_id=booking.booking_type_id,
        )
    except ToolError as e:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=f"Could not re-verify availability: {e}",
            validation_notes=notes,
        )

    if conflict_check.get("has_conflict"):
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=conflict_check.get("reason") or "Slot is no longer available.",
            validation_notes=notes,
        )
    notes.append("Slot re-verified free and within working hours immediately before booking.")

    # Informational only - a customer's own no-show history is never a valid
    # reason to deny them service. Best-effort: if the lookup fails for any
    # reason, booking still proceeds with a plain note, not an error.
    try:
        no_show = client.predict_no_show_probability()
        if no_show.get("totalPast", 0) > 0:
            notes.append(
                f"Customer's historical no-show rate: {no_show.get('rate', 0.0) * 100:.0f}% "
                f"based on {no_show['totalPast']} past booking(s). Informational only."
            )
    except ToolError:
        notes.append("Could not retrieve customer's no-show history — proceeding without it.")

    count = booking_count if booking_count is not None else len(proposed_bookings)
    requires_approval = count > APPROVAL_BOOKING_COUNT_THRESHOLD or estimated_revenue_impact > APPROVAL_REVENUE_THRESHOLD
    if requires_approval:
        notes.append(
            f"Crosses approval threshold (count={count} > {APPROVAL_BOOKING_COUNT_THRESHOLD} or "
            f"revenue={estimated_revenue_impact} > {APPROVAL_REVENUE_THRESHOLD}) — routing to human approval."
        )
        return ValidationSafetyOutput(
            is_allowed=True,
            requires_human_approval=True,
            validation_notes=notes,
        )

    try:
        result = client.create_booking(
            tenant_id=tenant_id,
            resource_id=booking.resource_id,
            booking_type_id=booking.booking_type_id,
            start_time=booking.scheduled_datetime.isoformat(),
            end_time=(booking.scheduled_datetime + timedelta(minutes=booking.duration_minutes)).isoformat(),
        )
    except ToolError as e:
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=f"Booking could not be created: {e}",
            validation_notes=notes,
        )

    if not result.get("success"):
        return ValidationSafetyOutput(
            is_allowed=False,
            requires_human_approval=False,
            rejection_reason=result.get("message") or "Booking creation was rejected by the backend.",
            validation_notes=notes,
        )

    notes.append("Booking created.")
    return ValidationSafetyOutput(
        is_allowed=True,
        requires_human_approval=False,
        validation_notes=notes,
        booking_id=str(result.get("booking", {}).get("id")) if result.get("booking") else None,
    )
