"""Single shared wrapper around the google-genai SDK, reused by every agent.

Two modes:
- No tools: constrained JSON generation via `response_mime_type` +
  `response_schema` (the SDK's structured-output feature — the primary
  defense against Gemini wrapping JSON in prose; a defensive parse is the
  backup, see `_parse_json_response`).
- With tools: a manual function-calling loop (automatic_function_calling is
  explicitly disabled) so we control max turns, timeouts, and per-call
  error handling ourselves rather than trusting the SDK's own loop.

NOTE: the exact function-response wire format (`types.Part.from_function_response`,
Content role for tool turns) follows the pattern documented at
https://ai.google.dev/gemini-api/docs/function-calling as of 2026-08-14.
SDK point-releases occasionally shift this — if the manual loop errors on a
live key, that's the first thing to check against whatever `google-genai`
version `pip install` actually resolved.
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass
from typing import Any, Callable

from google import genai
from google.genai import types
from pydantic import BaseModel, ValidationError

GEMINI_TIMEOUT_SECONDS = float(os.getenv("GEMINI_TIMEOUT_SECONDS", "30"))
MAX_AGENT_TURNS = int(os.getenv("MAX_AGENT_TURNS", "6"))

_client: genai.Client | None = None


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise AgentSafeFailure("GEMINI_API_KEY is not configured.")
        _client = genai.Client(api_key=api_key)
    return _client


class AgentSafeFailure(Exception):
    """Raised for any condition that must abort the workflow without a
    crash: malformed LLM output, tool errors after retry, exceeding the
    max-turn budget, timeouts. Callers turn this into an HTTP 422."""


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters_json_schema: dict[str, Any]
    handler: Callable[..., dict[str, Any]]


def _strip_code_fence(text: str) -> str:
    """Gemini sometimes wraps JSON in ```json ... ``` even when told not
    to. Strip fences and any leading/trailing prose before the first `{`."""
    text = text.strip()
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", text, re.DOTALL)
    if fence:
        return fence.group(1).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return text


def _parse_json_response(text: str, schema: type[BaseModel]) -> BaseModel:
    try:
        cleaned = _strip_code_fence(text)
        data = json.loads(cleaned)
        return schema.model_validate(data)
    except (json.JSONDecodeError, ValidationError) as e:
        raise AgentSafeFailure(f"Gemini returned a response that didn't match the expected shape: {e}") from e


def generate_structured(
    *,
    system_instruction: str,
    user_content: str,
    response_schema: type[BaseModel],
    model: str,
) -> BaseModel:
    """No-tools call: the model must answer directly as JSON matching `response_schema`."""
    client = _get_client()
    try:
        response = client.models.generate_content(
            model=model,
            contents=user_content,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.2,
                http_options=types.HttpOptions(timeout=int(GEMINI_TIMEOUT_SECONDS * 1000)),
            ),
        )
    except Exception as e:  # network error, API error, etc.
        raise AgentSafeFailure(f"Gemini call failed: {e}") from e

    text = getattr(response, "text", None)
    if not text:
        raise AgentSafeFailure("Gemini returned an empty response.")
    return _parse_json_response(text, response_schema)


def generate_with_tools(
    *,
    system_instruction: str,
    user_content: str,
    response_schema: type[BaseModel],
    tools: list[ToolSpec],
    model: str,
    max_turns: int = MAX_AGENT_TURNS,
) -> BaseModel:
    """Tool-calling loop: executes any function_call parts the model
    returns, feeds results back, repeats until a final structured JSON
    answer arrives or `max_turns` is exhausted (safe failure past that)."""
    client = _get_client()

    declarations = [
        types.FunctionDeclaration(
            name=t.name, description=t.description, parameters_json_schema=t.parameters_json_schema
        )
        for t in tools
    ]
    handlers = {t.name: t.handler for t in tools}
    tool_config = types.Tool(function_declarations=declarations)

    contents: list[types.Content] = [types.Content(role="user", parts=[types.Part.from_text(text=user_content)])]

    for turn in range(max_turns):
        try:
            response = client.models.generate_content(
                model=model,
                contents=contents,
                config=types.GenerateContentConfig(
                    system_instruction=system_instruction,
                    tools=[tool_config],
                    automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                    temperature=0.2,
                    http_options=types.HttpOptions(timeout=int(GEMINI_TIMEOUT_SECONDS * 1000)),
                ),
            )
        except Exception as e:
            raise AgentSafeFailure(f"Gemini call failed on turn {turn + 1}: {e}") from e

        candidate = response.candidates[0] if response.candidates else None
        if candidate is None or candidate.content is None:
            raise AgentSafeFailure("Gemini returned no candidate content.")

        parts = candidate.content.parts or []
        function_calls = [p.function_call for p in parts if getattr(p, "function_call", None)]

        if not function_calls:
            text = getattr(response, "text", None) or "".join(p.text or "" for p in parts if getattr(p, "text", None))
            if not text:
                raise AgentSafeFailure("Gemini finished without calling a tool or returning text.")
            return _parse_json_response(text, response_schema)

        contents.append(candidate.content)
        response_parts: list[types.Part] = []
        for call in function_calls:
            handler = handlers.get(call.name)
            if handler is None:
                response_parts.append(
                    types.Part.from_function_response(name=call.name, response={"error": f"Unknown tool {call.name}"})
                )
                continue
            result = _run_tool_with_one_retry(handler, dict(call.args or {}))
            response_parts.append(types.Part.from_function_response(name=call.name, response=result))
        contents.append(types.Content(role="tool", parts=response_parts))

    raise AgentSafeFailure(f"Exceeded max agent turns ({max_turns}) without a final answer.")


def _run_tool_with_one_retry(handler: Callable[..., dict[str, Any]], args: dict[str, Any]) -> dict[str, Any]:
    """Tool calls get one retry on failure, then a structured error is fed
    back to the model as the function_response (never a crash) — the model
    gets a chance to recover; if it can't, the overall turn budget still
    bounds the workflow."""
    last_error: Exception | None = None
    for attempt in range(2):
        try:
            return handler(**args)
        except Exception as e:  # noqa: BLE001 - tool failures must never crash the loop
            last_error = e
            if attempt == 0:
                time.sleep(0.5)
    return {"error": f"Tool failed after retry: {last_error}"}
