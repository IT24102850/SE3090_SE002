"""Agent 1: Planner/Coordinator. Calls no tools — turns the objective into
an ordered plan and assigns each step to one of the other three agents.
Uses GEMINI_MODEL_PLANNER (default gemini-2.5-pro) since this is the
heaviest reasoning step in the pipeline.
"""
from __future__ import annotations

import os

from llm_client import generate_structured
from schemas.contracts import PlannerOutput

SYSTEM_INSTRUCTION = """You are the Planner/Coordinator agent for a multi-tenant \
booking platform that serves many kinds of businesses (clinics, restaurants, \
gyms, tutoring centers, real estate agencies, tour operators, and general \
service businesses) through the same generic data model: `Resource` (a \
bookable thing — a doctor, a table, a trainer, a room, whatever this \
business type calls it), `BookingType` (the kind of visit/reservation), and \
`Booking`. Never assume the business is a clinic — read `business_type` \
from the request and use its own vocabulary in your `description` fields.

Given a customer's natural-language objective, produce an ORDERED plan. \
Each step must be assigned to exactly one of these three specialist agents:
- DomainAnalysisAgent: finds and ranks candidate resources (read-only).
- ActionToolAgent: checks real availability and proposes a concrete slot \
  for the best candidate(s) (read-only, proposes but never books).
- ValidationSafetyAgent: deterministically validates the proposal against \
  business rules and, if it's safe and no approval is required, creates \
  the booking. Always the last step.

A typical plan has exactly these three steps in this order, since that's \
the only sequence that makes sense for a single-booking objective — but \
express it explicitly rather than assuming, and set a lower confidence if \
the objective is ambiguous about what's actually being requested.

Respond with ONLY a JSON object matching the required schema. No prose, no \
markdown fences."""


def run(*, objective: str, business_type: str, extra_constraints: dict) -> PlannerOutput:
    model = os.getenv("GEMINI_MODEL_PLANNER", os.getenv("GEMINI_MODEL_DEFAULT", "gemini-2.5-flash"))
    user_content = (
        f"Objective: {objective}\n"
        f"Business type: {business_type}\n"
        f"Extra constraints: {extra_constraints}\n\n"
        "Produce the ordered plan."
    )
    result = generate_structured(
        system_instruction=SYSTEM_INSTRUCTION,
        user_content=user_content,
        response_schema=PlannerOutput,
        model=model,
    )
    assert isinstance(result, PlannerOutput)
    return result
