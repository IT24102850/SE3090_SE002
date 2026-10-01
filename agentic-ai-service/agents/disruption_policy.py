"""What a good recovery looks like, per business type.

A cancelled doctor and a broken boat are not the same problem. Moving a
patient to a different doctor needs the same specialty; moving a diner to a
different table only needs it to seat the party; moving a class needs the
whole group to move together, because a student cannot attend half a lesson.
Encoding that in one table keeps the agents' prompts domain-neutral and keeps
the rules reviewable - a human can read this file and say whether it is right
for their business.

Everything here is deterministic. No model output reaches it, so a prompt
injection cannot widen what counts as an acceptable substitute.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class DisruptionPolicy:
    """How one family of businesses recovers from a lost resource."""

    #: What the thing that broke is called, in this trade's words.
    resource_noun: str
    #: What a customer calls their booking.
    booking_noun: str
    #: A substitute must match the original's specialty (a cardiologist for a
    #: cardiologist). False where any equivalent resource will do.
    require_same_specialty: bool = False
    #: A substitute must seat or carry at least as many people.
    require_equal_capacity: bool = False
    #: Everyone on the same original slot must move together - a class, a
    #: tour party, a table of eight. Splitting them is not a recovery.
    keep_group_together: bool = False
    #: Prefer keeping the time and changing the resource, or the reverse.
    prefer: str = "either"  # same_time_other_resource | same_resource_later | either
    #: How far the booking may be moved before it stops being a recovery.
    max_days_to_move: int = 7
    #: Phrases that help the planner speak the trade's language.
    vocabulary: dict[str, str] = field(default_factory=dict)


_GENERAL = DisruptionPolicy(
    resource_noun="resource",
    booking_noun="booking",
    prefer="either",
    max_days_to_move=7,
)

#: Keyed by the lowercased Tenant.BusinessType the backend sends.
POLICIES: dict[str, DisruptionPolicy] = {
    "clinic": DisruptionPolicy(
        resource_noun="doctor",
        booking_noun="appointment",
        require_same_specialty=True,
        prefer="same_time_other_resource",
        max_days_to_move=3,
        vocabulary={"customer": "patient", "staff": "clinician"},
    ),
    "dental": DisruptionPolicy(
        resource_noun="dentist",
        booking_noun="appointment",
        require_same_specialty=True,
        prefer="same_time_other_resource",
        max_days_to_move=3,
        vocabulary={"customer": "patient"},
    ),
    "restaurant": DisruptionPolicy(
        resource_noun="table",
        booking_noun="reservation",
        require_equal_capacity=True,
        keep_group_together=True,
        prefer="same_time_other_resource",
        max_days_to_move=0,  # nobody wants their dinner moved to Thursday
        vocabulary={"customer": "guest", "attendees": "covers"},
    ),
    "gym": DisruptionPolicy(
        resource_noun="trainer or studio",
        booking_noun="session",
        keep_group_together=True,
        prefer="same_resource_later",
        max_days_to_move=7,
        vocabulary={"customer": "member"},
    ),
    "school": DisruptionPolicy(
        resource_noun="teacher or classroom",
        booking_noun="lesson",
        keep_group_together=True,
        prefer="same_time_other_resource",
        max_days_to_move=14,
        vocabulary={"customer": "student", "attendees": "pupils"},
    ),
    "tourism": DisruptionPolicy(
        resource_noun="vessel or vehicle",
        booking_noun="trip",
        require_equal_capacity=True,
        keep_group_together=True,
        prefer="same_resource_later",
        max_days_to_move=5,
        vocabulary={"customer": "guest", "attendees": "passengers"},
    ),
    "realestate": DisruptionPolicy(
        resource_noun="agent",
        booking_noun="viewing",
        prefer="either",
        max_days_to_move=10,
        vocabulary={"customer": "client"},
    ),
    "salon": DisruptionPolicy(
        resource_noun="stylist",
        booking_noun="appointment",
        require_same_specialty=True,
        prefer="same_time_other_resource",
        max_days_to_move=7,
    ),
}

#: Business types the dashboards already treat as one family.
_ALIASES = {
    "cafe": "restaurant",
    "fitness": "gym",
    "tuition": "school",
    "education": "school",
    "academy": "school",
    "real estate": "realestate",
    "real_estate": "realestate",
    "property": "realestate",
    "spa": "salon",
    "beauty": "salon",
    "travel": "tourism",
    "tours": "tourism",
    "dentist": "dental",
}


def policy_for(business_type: str | None) -> DisruptionPolicy:
    """The policy for a business type; the general one for anything unknown.

    Unknown is a normal answer, not an error: the platform onboards new kinds
    of business, and they get sensible neutral behaviour rather than a crash.
    """
    key = (business_type or "").strip().lower().replace("-", " ")
    key = _ALIASES.get(key, key)
    return POLICIES.get(key, _GENERAL)


def priority_of(
    *,
    deposit_paid: bool,
    attendee_count: int,
    hours_until_start: float,
    status: str,
) -> tuple[float, str]:
    """How urgently one booking should be re-placed, 0..1 with a reason.

    Deterministic and explainable on purpose: a customer who has paid, is
    bringing a group, or is due within hours is hurt most by being left
    without an answer. The reason is shown to the manager, so the ordering
    can be argued with rather than taken on trust.
    """
    score = 0.0
    reasons: list[str] = []

    if deposit_paid:
        score += 0.4
        reasons.append("deposit already paid")

    if hours_until_start <= 24:
        score += 0.3
        reasons.append("starts within 24 hours")
    elif hours_until_start <= 72:
        score += 0.15
        reasons.append("starts within 3 days")

    if attendee_count >= 6:
        score += 0.2
        reasons.append(f"group of {attendee_count}")
    elif attendee_count > 1:
        score += 0.1
        reasons.append(f"party of {attendee_count}")

    if status.lower() in {"confirmed", "checkedin"}:
        score += 0.1
        reasons.append("already confirmed")

    return min(score, 1.0), ", ".join(reasons) or "no special factors"
