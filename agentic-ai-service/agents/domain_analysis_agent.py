"""Agent 2: Domain Analysis. Finds and ranks candidate resources using
criteria appropriate to the business type — read from the request, never
hardcoded. Read-only tools: search_resources, get_resource_metadata.
"""
from __future__ import annotations

import os

from llm_client import ToolSpec, generate_with_tools
from schemas.contracts import DomainAnalysisOutput
from tools.booking_tools import BookingToolsClient

SYSTEM_INSTRUCTION = """You are the Domain Analysis agent for a multi-tenant \
booking platform. Your job: find candidate resources for the customer's \
request, then RANK them best-to-worst.

The ranking criteria depend entirely on `business_type` — decide them \
yourself from context, don't assume a clinic. Examples of what to weigh, \
by business type (use these as guidance, not a fixed list):
- Clinic: specialty match, rating, distance, current wait time.
- Restaurant: cuisine match, party-size fit, ambiance/price tier.
- Gym: class/trainer specialty match, time-of-day fit, rating.
- Tuition: subject match, tutor rating, format (online/in-person).
- Real estate / Tourism / General: whatever domain-appropriate signals \
  exist in the resource's metadata.

Use `search_resources` to find candidates (map the customer's request onto \
its `resource_category`/`specialty` params using the business type's own \
vocabulary), then `get_resource_metadata` on the promising ones to read \
their `customAttributes`/`locationMetadata` JSON for the actual ranking \
signals (rating, distance, cuisine, etc. — whatever is present; if a \
resource has no metadata, rank it conservatively rather than guessing). \
If the objective mentions a specific day, use `check_staff_schedule` on \
promising candidates to rule out ones not open that day before ranking \
them highly.

Explain each candidate's score in `reasoning` and list which criteria you \
actually used in `ranking_criteria_used`. Respond with ONLY a JSON object \
matching the required schema once you're done — no prose, no markdown \
fences."""


def _build_tools(client: BookingToolsClient) -> list[ToolSpec]:
    return [
        ToolSpec(
            name="search_resources",
            description="Find candidate resources for this tenant, optionally filtered by category/specialty/branch/free-text search.",
            parameters_json_schema={
                "type": "object",
                "properties": {
                    "tenant_id": {"type": "string"},
                    "resource_category": {"type": "string", "description": "Room, Equipment, Vehicle, Staff, Desk, or Other"},
                    "specialty": {"type": "string", "description": "Free-text specialty/type match, e.g. 'Cardiology' or 'Italian'"},
                    "branch_id": {"type": "string"},
                    "search": {"type": "string"},
                },
                "required": ["tenant_id"],
            },
            handler=client.search_resources,
        ),
        ToolSpec(
            name="get_resource_metadata",
            description="Full detail for one resource, including its custom ranking metadata (rating, cuisine, distance, etc.).",
            parameters_json_schema={
                "type": "object",
                "properties": {"resource_id": {"type": "string"}},
                "required": ["resource_id"],
            },
            handler=client.get_resource_metadata,
        ),
        ToolSpec(
            name="check_staff_schedule",
            description="This resource's full weekly working pattern (which days it's open at all, plus any lunch break) - coarser than checking one day's exact slots.",
            parameters_json_schema={
                "type": "object",
                "properties": {"resource_id": {"type": "string"}},
                "required": ["resource_id"],
            },
            handler=client.check_staff_schedule,
        ),
    ]


def run(
    *, objective: str, business_type: str, tenant_id: str, branch_id: str | None, extra_constraints: dict, client: BookingToolsClient
) -> DomainAnalysisOutput:
    model = os.getenv("GEMINI_MODEL_DEFAULT", "gemini-2.5-flash")
    user_content = (
        f"Objective: {objective}\n"
        f"Business type: {business_type}\n"
        f"Tenant id: {tenant_id}\n"
        f"Branch id: {branch_id or 'any'}\n"
        f"Extra constraints: {extra_constraints}\n\n"
        "Find and rank candidate resources."
    )
    result = generate_with_tools(
        system_instruction=SYSTEM_INSTRUCTION,
        user_content=user_content,
        response_schema=DomainAnalysisOutput,
        tools=_build_tools(client),
        model=model,
    )
    assert isinstance(result, DomainAnalysisOutput)
    return result
