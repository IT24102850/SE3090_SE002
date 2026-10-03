"""Agent 3: Action/Tool. Checks real-time availability for the top-ranked
candidate(s) and proposes a concrete booking. Never creates anything and
never re-judges who's "best" — that's already decided by Domain Analysis.
Read-only tools: query_resource_availability, detect_conflicts.
"""
from __future__ import annotations

import os

from llm_client import ToolSpec, generate_with_tools
from schemas.contracts import ActionToolOutput, RankedCandidate
from tools.booking_tools import BookingToolsClient, calculate_travel_time

SYSTEM_INSTRUCTION = """You are the Action/Tool agent for a multi-tenant \
booking platform. You are given a shortlist of already-ranked candidate \
resources — do not re-rank or second-guess that ranking. Your only job: \
find a real, currently-open time slot for the top candidate(s) within the \
requested date range and duration, using `query_resource_availability`, \
then confirm it's still free with `detect_conflicts` right before you \
finish (availability can change between calls). If the objective mentions \
travel time or urgency, use `get_resource_metadata` to read a candidate's \
`distanceKm` (if present) and `calculate_travel_time` to estimate how long \
getting there takes — this is a rough estimate, not real traffic data, so \
mention it only as an estimate if you use it.

If the top candidate has no availability in range, try the next one down \
the ranked list. You propose bookings — you never create them. If nothing \
in the shortlist has availability, return an empty `proposed_bookings` \
list and explain why in a low confidence score rather than inventing a slot.

Respond with ONLY a JSON object matching the required schema once you're \
done — no prose, no markdown fences."""


def _build_tools(client: BookingToolsClient) -> list[ToolSpec]:
    return [
        ToolSpec(
            name="query_resource_availability",
            description="Real open/booked slots for one resource on one date, given a duration in minutes.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "resource_id": {"type": "string"},
                    "date": {"type": "string", "description": "ISO date, e.g. 2026-08-20"},
                    "duration_minutes": {"type": "integer"},
                    "booking_type_id": {"type": "string"},
                },
                "required": ["resource_id", "date", "duration_minutes"],
            },
            handler=client.query_resource_availability,
        ),
        ToolSpec(
            name="detect_conflicts",
            description="Re-checks one exact proposed slot is still free right before finalizing the proposal.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "resource_id": {"type": "string"},
                    "date": {"type": "string"},
                    "duration_minutes": {"type": "integer"},
                    "scheduled_datetime": {"type": "string", "description": "Exact ISO datetime of the proposed slot start"},
                    "booking_type_id": {"type": "string"},
                },
                "required": ["resource_id", "date", "duration_minutes", "scheduled_datetime"],
            },
            handler=client.detect_conflicts,
        ),
        ToolSpec(
            name="get_resource_metadata",
            description="Full detail for one resource, including customAttributes/locationMetadata JSON (e.g. distanceKm) if present.",
            parameters_json_schema={
                "type": "object",
                "properties": {"resource_id": {"type": "string"}},
                "required": ["resource_id"],
            },
            handler=client.get_resource_metadata,
        ),
        ToolSpec(
            name="calculate_travel_time",
            description="Rough travel-time ESTIMATE (not real traffic data) from a distance in km.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "distance_km": {"type": "number"},
                    "average_speed_kmh": {"type": "number", "description": "Defaults to 30 (generic urban average) if omitted."},
                },
                "required": ["distance_km"],
            },
            handler=calculate_travel_time,
        ),
    ]


def run(
    *,
    objective: str,
    ranked_candidates: list[RankedCandidate],
    booking_type_id: str,
    duration_minutes: int,
    date_from: str,
    date_to: str,
    client: BookingToolsClient,
) -> ActionToolOutput:
    model = os.getenv("GEMINI_MODEL_DEFAULT", "gemini-2.5-flash")
    candidates_desc = "\n".join(f"- {c.resource_id} ({c.resource_name}): score {c.score}" for c in ranked_candidates)
    user_content = (
        f"Objective: {objective}\n"
        f"Booking type id: {booking_type_id}\n"
        f"Duration needed: {duration_minutes} minutes\n"
        f"Date range: {date_from} to {date_to}\n"
        f"Ranked candidates (best first):\n{candidates_desc}\n\n"
        "Find a real open slot and propose the booking."
    )
    result = generate_with_tools(
        system_instruction=SYSTEM_INSTRUCTION,
        user_content=user_content,
        response_schema=ActionToolOutput,
        tools=_build_tools(client),
        model=model,
    )
    assert isinstance(result, ActionToolOutput)
    return result
