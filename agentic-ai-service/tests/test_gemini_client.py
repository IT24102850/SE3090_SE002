"""Tests the defensive JSON parsing around raw Gemini responses — the SDK
call itself is mocked (no live key needed), but the parsing logic under
test is real."""
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

import gemini_client
from gemini_client import AgentSafeFailure, generate_structured
from schemas.contracts import PlannerOutput


def _mock_client_returning(text: str) -> MagicMock:
    fake_client = MagicMock()
    fake_client.models.generate_content.return_value = SimpleNamespace(text=text, candidates=[])
    return fake_client


def test_gemini_non_json_response_handled_prose_wrapped_json(monkeypatch):
    """Gemini often wraps valid JSON in prose/markdown fences even when
    told not to — this must still parse successfully."""
    wrapped = (
        "Sure! Here is the plan you asked for:\n\n```json\n"
        '{"plan": [], "assigned_agents": [], "confidence": 0.5}\n'
        "```\nLet me know if you need anything else!"
    )
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _mock_client_returning(wrapped))

    result = generate_structured(
        system_instruction="test", user_content="test", response_schema=PlannerOutput, model="gemini-2.5-flash"
    )

    assert isinstance(result, PlannerOutput)
    assert result.confidence == 0.5


def test_gemini_non_json_response_handled_no_json_at_all(monkeypatch):
    """No JSON anywhere in the response — must fail safely, not crash."""
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _mock_client_returning("I'm not able to help with that request."))

    with pytest.raises(AgentSafeFailure):
        generate_structured(
            system_instruction="test", user_content="test", response_schema=PlannerOutput, model="gemini-2.5-flash"
        )


def test_gemini_non_json_response_handled_malformed_json(monkeypatch):
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _mock_client_returning('{"plan": [oops this is not json'))

    with pytest.raises(AgentSafeFailure):
        generate_structured(
            system_instruction="test", user_content="test", response_schema=PlannerOutput, model="gemini-2.5-flash"
        )


def test_gemini_empty_response_fails_safely(monkeypatch):
    monkeypatch.setattr(gemini_client, "_get_client", lambda: _mock_client_returning(""))

    with pytest.raises(AgentSafeFailure):
        generate_structured(
            system_instruction="test", user_content="test", response_schema=PlannerOutput, model="gemini-2.5-flash"
        )


def test_gemini_call_exception_fails_safely(monkeypatch):
    fake_client = MagicMock()
    fake_client.models.generate_content.side_effect = RuntimeError("network down")
    monkeypatch.setattr(gemini_client, "_get_client", lambda: fake_client)

    with pytest.raises(AgentSafeFailure):
        generate_structured(
            system_instruction="test", user_content="test", response_schema=PlannerOutput, model="gemini-2.5-flash"
        )
