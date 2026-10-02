"""Agent 2: Impact Analysis. Who is stranded, and who needs an answer first.

Read-only. It asks the API which bookings sit on the broken resource during
the outage, then ranks them with the deterministic rule in disruption_policy
- deposit paid, how soon it starts, how many people are coming. The ordering
is a published rule rather than a model's opinion, so a manager can disagree
with it on the evidence shown beside each row.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from agents.disruption_policy import DisruptionPolicy, priority_of
from schemas.disruption_contracts import AffectedBooking, DisruptionWindow, ImpactOutput
from tools.disruption_tools import AgentToolbox, ToolError


def _parse(value: Any) -> datetime:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def run(
    *,
    resource_id: str,
    window: DisruptionWindow,
    policy: DisruptionPolicy,
    toolbox: AgentToolbox,
    now: datetime | None = None,
) -> ImpactOutput:
    now = now or datetime.now(timezone.utc)
    warnings: list[str] = []

    starts = window.starts_at or datetime.combine(window.date_from, datetime.min.time(), tzinfo=timezone.utc)
    ends = window.ends_at or datetime.combine(window.date_to, datetime.max.time(), tzinfo=timezone.utc)

    try:
        resource = toolbox.get_resource(resource_id)
        resource_name = str(resource.get("name") or "the resource")
    except ToolError as e:
        resource_name = "the resource"
        warnings.append(f"The resource's details could not be read: {e}")

    rows = toolbox.list_affected_bookings(resource_id, starts.isoformat(), ends.isoformat())

    affected: list[AffectedBooking] = []
    revenue = 0.0
    for row in rows:
        try:
            booking_starts = _parse(row["startsAt"])
            booking_ends = _parse(row["endsAt"])
        except (KeyError, ValueError):
            warnings.append("A booking was skipped because its times could not be read.")
            continue

        attendees = int(row.get("attendeeCount") or 1)
        deposit = bool(row.get("depositPaid"))
        status = str(row.get("status") or "")
        hours_until = max((booking_starts - now).total_seconds() / 3600.0, 0.0)
        priority, reason = priority_of(
            deposit_paid=deposit,
            attendee_count=attendees,
            hours_until_start=hours_until,
            status=status,
        )
        revenue += float(row.get("totalCost") or 0.0)

        affected.append(AffectedBooking(
            booking_id=str(row["bookingId"]),
            customer_name=str(row.get("customerName") or "Customer"),
            customer_id=str(row["customerId"]) if row.get("customerId") else None,
            booking_type_id=str(row.get("bookingTypeId") or ""),
            booking_type_name=str(row.get("bookingTypeName") or policy.booking_noun),
            starts_at=booking_starts,
            ends_at=booking_ends,
            status=status,
            attendee_count=attendees,
            deposit_paid=deposit,
            priority=priority,
            priority_reason=reason,
        ))

    affected.sort(key=lambda b: (-b.priority, b.starts_at))

    if len(rows) >= 200:
        warnings.append("Only the first 200 affected bookings were read; run again for the rest.")

    return ImpactOutput(
        resource_name=resource_name,
        resource_noun=policy.resource_noun,
        affected=affected,
        total_attendees=sum(b.attendee_count for b in affected),
        revenue_at_risk=round(revenue, 2),
        warnings=warnings,
    )
