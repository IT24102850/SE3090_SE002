"""Ollama implementation of the two functions `llm_client.py` dispatches to
when LLM_PROVIDER=ollama. Mirrors gemini_client.py's shape (same function
signatures, same AgentSafeFailure-on-any-failure contract) so agent files
never need to know which provider is active.

Reuses gemini_client's `_parse_json_response` (schema validation + code-fence
stripping - provider-agnostic) and `_run_tool_with_one_retry` (provider-
agnostic retry wrapper) rather than duplicating them.

Not exercised against a real Ollama install in this environment (none is
installed here) - verified instead via tests/test_ollama_client.py, which
mocks Ollama's HTTP API with respx the same way tests/test_gemini_client.py
mocks Gemini's.
"""
from __future__ import annotations

import json
import os

import httpx
from pydantic import BaseModel

from gemini_client import AgentSafeFailure, ToolSpec, _parse_json_response, _run_tool_with_one_retry

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_TIMEOUT_SECONDS = float(os.getenv("OLLAMA_TIMEOUT_SECONDS", "60"))


def _client() -> httpx.Client:
    return httpx.Client(base_url=OLLAMA_BASE_URL, timeout=OLLAMA_TIMEOUT_SECONDS)


def generate_structured(*, system_instruction: str, user_content: str, response_schema: type[BaseModel], model: str) -> BaseModel:
    """No-tools call: Ollama's structured-output support (`format` = a JSON
    schema) constrains the model's output the same way Gemini's
    response_schema does."""
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": user_content},
        ],
        "format": response_schema.model_json_schema(),
        "stream": False,
        "options": {"temperature": 0.2},
    }
    try:
        with _client() as client:
            resp = client.post("/api/chat", json=payload)
            resp.raise_for_status()
            data = resp.json()
    except httpx.HTTPError as e:
        raise AgentSafeFailure(f"Ollama call failed: {e}") from e

    content = data.get("message", {}).get("content")
    if not content:
        raise AgentSafeFailure("Ollama returned an empty response.")
    return _parse_json_response(content, response_schema)


def _tool_to_ollama(tool: ToolSpec) -> dict:
    return {
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters_json_schema,
        },
    }


def generate_with_tools(
    *,
    system_instruction: str,
    user_content: str,
    response_schema: type[BaseModel],
    tools: list[ToolSpec],
    model: str,
    max_turns: int = 6,
) -> BaseModel:
    """Tool-calling loop against Ollama's OpenAI-style `tools` array,
    mirroring gemini_client.generate_with_tools's manual loop."""
    handlers = {t.name: t.handler for t in tools}
    ollama_tools = [_tool_to_ollama(t) for t in tools]
    messages: list[dict] = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": user_content},
    ]

    with _client() as client:
        for turn in range(max_turns):
            try:
                resp = client.post(
                    "/api/chat",
                    json={"model": model, "messages": messages, "tools": ollama_tools, "stream": False, "options": {"temperature": 0.2}},
                )
                resp.raise_for_status()
                data = resp.json()
            except httpx.HTTPError as e:
                raise AgentSafeFailure(f"Ollama call failed on turn {turn + 1}: {e}") from e

            message = data.get("message", {})
            tool_calls = message.get("tool_calls") or []

            if not tool_calls:
                content = message.get("content")
                if not content:
                    raise AgentSafeFailure("Ollama finished without calling a tool or returning content.")
                return _parse_json_response(content, response_schema)

            messages.append(message)
            for call in tool_calls:
                fn = call.get("function", {})
                name = fn.get("name")
                args = fn.get("arguments") or {}
                handler = handlers.get(name)
                result = {"error": f"Unknown tool {name}"} if handler is None else _run_tool_with_one_retry(handler, dict(args))
                messages.append({"role": "tool", "content": json.dumps(result)})

    raise AgentSafeFailure(f"Exceeded max agent turns ({max_turns}) without a final answer.")
