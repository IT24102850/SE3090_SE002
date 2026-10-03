"""Mocks Ollama's HTTP API with respx (no real Ollama install needed) to
verify ollama_client.py's structured-output and tool-calling loops work,
mirroring how tests/test_gemini_client.py verifies gemini_client.py."""
import httpx
import pytest
import respx

from gemini_client import AgentSafeFailure, ToolSpec
from ollama_client import OLLAMA_BASE_URL, generate_structured, generate_with_tools
from schemas.contracts import DomainAnalysisOutput, PlannerOutput

CHAT_URL = f"{OLLAMA_BASE_URL}/api/chat"


@respx.mock
def test_ollama_structured_response_parses():
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json={"message": {"content": '{"plan": [], "assigned_agents": [], "confidence": 0.7}'}})
    )

    result = generate_structured(system_instruction="x", user_content="y", response_schema=PlannerOutput, model="llama3.1")

    assert isinstance(result, PlannerOutput)
    assert result.confidence == 0.7


@respx.mock
def test_ollama_prose_wrapped_json_still_parses():
    """Reuses gemini_client's defensive parser, so this must behave the same way it does for Gemini."""
    wrapped = 'Sure, here you go:\n```json\n{"plan": [], "assigned_agents": [], "confidence": 0.5}\n```'
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json={"message": {"content": wrapped}}))

    result = generate_structured(system_instruction="x", user_content="y", response_schema=PlannerOutput, model="llama3.1")
    assert result.confidence == 0.5


@respx.mock
def test_ollama_empty_response_fails_safely():
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json={"message": {"content": ""}}))

    with pytest.raises(AgentSafeFailure):
        generate_structured(system_instruction="x", user_content="y", response_schema=PlannerOutput, model="llama3.1")


@respx.mock
def test_ollama_malformed_json_fails_safely():
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json={"message": {"content": "{not json"}}))

    with pytest.raises(AgentSafeFailure):
        generate_structured(system_instruction="x", user_content="y", response_schema=PlannerOutput, model="llama3.1")


@respx.mock
def test_ollama_connection_error_fails_safely():
    respx.post(CHAT_URL).mock(side_effect=httpx.ConnectError("connection refused"))

    with pytest.raises(AgentSafeFailure):
        generate_structured(system_instruction="x", user_content="y", response_schema=PlannerOutput, model="llama3.1")


@respx.mock
def test_ollama_tool_call_then_final_answer():
    """First turn: model calls the tool. Second turn: model returns the
    final structured answer using the tool's result."""
    calls = {"count": 0}

    def _respond(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] == 1:
            return httpx.Response(
                200,
                json={
                    "message": {
                        "role": "assistant",
                        "tool_calls": [{"function": {"name": "search_resources", "arguments": {"tenant_id": "t1"}}}],
                    }
                },
            )
        return httpx.Response(
            200,
            json={"message": {"content": '{"ranked_candidates": [], "ranking_criteria_used": ["test"]}'}},
        )

    respx.post(CHAT_URL).mock(side_effect=_respond)

    tool = ToolSpec(
        name="search_resources",
        description="test tool",
        parameters_json_schema={"type": "object", "properties": {"tenant_id": {"type": "string"}}},
        handler=lambda tenant_id: {"items": []},
    )

    result = generate_with_tools(
        system_instruction="x", user_content="y", response_schema=DomainAnalysisOutput, tools=[tool], model="llama3.1"
    )

    assert isinstance(result, DomainAnalysisOutput)
    assert calls["count"] == 2


@respx.mock
def test_ollama_unknown_tool_call_does_not_crash():
    """The model hallucinating a tool name that isn't in our allow-list must
    feed back a structured error, not raise."""
    calls = {"count": 0}

    def _respond(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] == 1:
            return httpx.Response(
                200,
                json={"message": {"role": "assistant", "tool_calls": [{"function": {"name": "not_a_real_tool", "arguments": {}}}]}},
            )
        return httpx.Response(200, json={"message": {"content": '{"ranked_candidates": [], "ranking_criteria_used": []}'}})

    respx.post(CHAT_URL).mock(side_effect=_respond)

    result = generate_with_tools(
        system_instruction="x", user_content="y", response_schema=DomainAnalysisOutput, tools=[], model="llama3.1"
    )
    assert isinstance(result, DomainAnalysisOutput)


@respx.mock
def test_ollama_exceeds_max_turns_fails_safely():
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json={"message": {"role": "assistant", "tool_calls": [{"function": {"name": "loops_forever", "arguments": {}}}]}},
        )
    )

    tool = ToolSpec(
        name="loops_forever", description="always called again", parameters_json_schema={"type": "object"}, handler=lambda: {"ok": True}
    )

    with pytest.raises(AgentSafeFailure):
        generate_with_tools(
            system_instruction="x", user_content="y", response_schema=DomainAnalysisOutput, tools=[tool], model="llama3.1", max_turns=2
        )
