"""The tool-calling loop's conversation shape, and how it fails.

"Ask AI to book for you" died on every attempt with

    400 INVALID_ARGUMENT: Role 'tool' is not supported.

The loop fed function results back as a "tool" turn, which is the OpenAI
convention - Gemini has no such role and rejects the whole request. The first
turn always succeeded, so nothing caught it until a real booking ran two turns
deep, and the model-fallback chain then retried the same malformed request on
every model before giving up.
"""
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from google.genai import types

import gemini_client
from gemini_client import AgentSafeFailure, ToolSpec, generate_with_tools
from schemas.contracts import PlannerOutput

FINAL_JSON = '{"plan": [], "assigned_agents": [], "confidence_score": 0.9}'

# The roles Gemini actually accepts in `contents`. The API error lists more,
# but these are the two a tool loop has any business sending.
VALID_CONTENT_ROLES = {"user", "model"}


def _tool() -> ToolSpec:
    return ToolSpec(
        name="check_availability",
        description="Check whether a departure has space.",
        parameters_json_schema={"type": "object", "properties": {}},
        handler=lambda **_: {"seats": 4},
    )


def _function_call_turn() -> SimpleNamespace:
    """A model turn asking for one tool call."""
    call = SimpleNamespace(name="check_availability", args={})
    part = SimpleNamespace(function_call=call, text=None)
    content = types.Content(role="model", parts=[types.Part.from_text(text="")])
    return SimpleNamespace(
        candidates=[SimpleNamespace(content=content)],
        text=None,
        _parts=[part],
    )


def _client_doing_one_tool_call(recorder: list):
    """A client that asks for a tool on turn 1 and answers on turn 2,
    recording the `contents` it is handed each time."""
    call = SimpleNamespace(name="check_availability", args={})
    asking = SimpleNamespace(
        candidates=[
            SimpleNamespace(
                content=SimpleNamespace(
                    role="model", parts=[SimpleNamespace(function_call=call, text=None)]
                )
            )
        ],
        text=None,
    )
    answering = SimpleNamespace(
        candidates=[
            SimpleNamespace(
                content=SimpleNamespace(
                    role="model",
                    parts=[SimpleNamespace(function_call=None, text=FINAL_JSON)],
                )
            )
        ],
        text=FINAL_JSON,
    )

    responses = [asking, answering]

    def generate_content(*, model, contents, config):
        # Copy the roles now: the loop keeps appending to the same list.
        recorder.append([getattr(c, "role", None) for c in contents])
        return responses.pop(0)

    client = MagicMock()
    client.models.generate_content.side_effect = generate_content
    return client


def test_tool_results_go_back_as_a_user_turn_not_a_tool_turn(monkeypatch):
    """The regression. Gemini rejects role='tool' outright, so the second
    turn must carry the function responses as 'user'."""
    seen: list[list[str]] = []
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _client_doing_one_tool_call(seen))

    result = generate_with_tools(
        system_instruction="test",
        user_content="book me something",
        response_schema=PlannerOutput,
        tools=[_tool()],
        model="gemini-3.5-flash",
    )

    assert isinstance(result, PlannerOutput)

    # Turn 2 is the one that used to be malformed.
    assert len(seen) == 2, "the model should have been called twice"
    second_turn_roles = seen[1]
    assert "tool" not in second_turn_roles, (
        f"role 'tool' is not a Gemini role and 400s the whole request: {second_turn_roles}"
    )
    assert second_turn_roles[-1] == "user", (
        f"function results belong in a user turn, got {second_turn_roles[-1]!r}"
    )


def test_every_role_the_loop_sends_is_one_gemini_accepts(monkeypatch):
    seen: list[list[str]] = []
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _client_doing_one_tool_call(seen))

    generate_with_tools(
        system_instruction="test",
        user_content="book me something",
        response_schema=PlannerOutput,
        tools=[_tool()],
        model="gemini-3.5-flash",
    )

    for turn in seen:
        for role in turn:
            assert role in VALID_CONTENT_ROLES, f"{role!r} is not a valid Gemini content role"


# ---------- failing fast on a request we built wrong ----------


class _ApiError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code


def test_a_malformed_request_is_recognised_as_our_bug():
    bad = _ApiError(400, "400 INVALID_ARGUMENT. Role 'tool' is not supported.")

    assert gemini_client._is_malformed_request(bad)
    # and it must not look like something waiting will fix
    assert not gemini_client._is_transient(bad)


def test_a_plain_400_still_gets_the_next_model():
    """Not every 400 is our fault - an unsupported parameter can be
    model-specific, and the next model in the chain may accept it."""
    assert not gemini_client._is_malformed_request(
        _ApiError(400, "400 Unsupported parameter 'thinking_config' for this model.")
    )


def test_503_is_still_transient():
    assert gemini_client._is_transient(_ApiError(503, "503 Service Unavailable"))
    assert not gemini_client._is_malformed_request(_ApiError(503, "503 Service Unavailable"))


def test_a_malformed_request_fails_immediately_instead_of_burning_the_chain(monkeypatch):
    """Previously this retried the identical bad request on all three models,
    turning an instant bug into a ~27 second wait and three wasted calls."""
    gemini_client.reset_breakers()
    attempts: list[str] = []

    def always_invalid(candidate_model: str):
        attempts.append(candidate_model)
        raise _ApiError(400, "400 INVALID_ARGUMENT. Role 'tool' is not supported.")

    monkeypatch.setenv(
        "GEMINI_MODEL_FALLBACKS", "gemini-flash-lite-latest,gemini-flash-latest"
    )

    with pytest.raises(AgentSafeFailure) as excinfo:
        gemini_client._call_with_resilience(always_invalid, model="gemini-3.5-flash")

    assert attempts == ["gemini-3.5-flash"], (
        f"should stop after the first rejection, but tried {attempts}"
    )
    # The reason has to survive, or the bug hides behind "tried three models".
    assert "INVALID_ARGUMENT" in str(excinfo.value)


# ---------- telling the model the shape it must answer in ----------


def test_the_final_answer_schema_is_spelled_out_in_the_instruction(monkeypatch):
    """A tool-calling call cannot pass response_schema to Gemini, so the only
    place the required shape can be stated is the instruction. Without it the
    model guessed `ranked_resources` for `ranked_candidates` and the whole
    booking failed validation."""
    captured: list[str] = []

    call = SimpleNamespace(name="check_availability", args={})
    responses = [
        SimpleNamespace(
            candidates=[SimpleNamespace(content=SimpleNamespace(
                role="model", parts=[SimpleNamespace(function_call=call, text=None)]))],
            text=None,
        ),
        SimpleNamespace(
            candidates=[SimpleNamespace(content=SimpleNamespace(
                role="model", parts=[SimpleNamespace(function_call=None, text=FINAL_JSON)]))],
            text=FINAL_JSON,
        ),
    ]

    def generate_content(*, model, contents, config):
        captured.append(config.system_instruction)
        return responses.pop(0)

    client = MagicMock()
    client.models.generate_content.side_effect = generate_content
    monkeypatch.setattr(gemini_client, "_get_client", lambda: client)

    generate_with_tools(
        system_instruction="You rank things.",
        user_content="rank them",
        response_schema=PlannerOutput,
        tools=[_tool()],
        model="gemini-3.5-flash",
    )

    instruction = captured[0]
    assert "You rank things." in instruction, "the agent's own prompt must survive"
    for field in PlannerOutput.model_json_schema()["properties"]:
        assert field in instruction, f"{field!r} is never named, so the model has to guess it"


def test_the_contract_names_every_required_field_of_the_real_schema():
    """The schema that actually broke, checked directly."""
    from schemas.contracts import DomainAnalysisOutput

    contract = gemini_client._with_schema_contract("base", DomainAnalysisOutput)

    assert "ranked_candidates" in contract
    assert "ranking_criteria_used" in contract
