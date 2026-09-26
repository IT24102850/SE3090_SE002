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

# Retry/fallback budget. Kept small on purpose: a viva demo would rather
# degrade to a weaker model in two seconds than stall for thirty.
GEMINI_MAX_ATTEMPTS = int(os.getenv("GEMINI_MAX_ATTEMPTS", "3"))
GEMINI_BACKOFF_SECONDS = float(os.getenv("GEMINI_BACKOFF_SECONDS", "0.6"))

_client: genai.Client | None = None

# Every LLM call this module makes, in order, for the observability trace.
# Reset per workflow by `reset_call_log()`; read by `drain_call_log()`.
_call_log: list[dict[str, Any]] = []


def reset_call_log() -> None:
    _call_log.clear()


def drain_call_log() -> list[dict[str, Any]]:
    """Return the calls recorded since the last reset and clear the buffer."""
    entries = list(_call_log)
    _call_log.clear()
    return entries


def _record_call(*, model: str, attempt: int, duration_ms: int, ok: bool, error: str | None) -> None:
    _call_log.append(
        {"model": model, "attempt": attempt, "duration_ms": duration_ms, "ok": ok, "error": error}
    )


def _status_code(error: Exception) -> int | None:
    """google-genai raises APIError subclasses carrying `.code`. Fall back to
    scraping the message, because the SDK has moved this attribute before."""
    code = getattr(error, "code", None)
    if isinstance(code, int):
        return code
    match = re.search(r"\b(4\d\d|5\d\d)\b", str(error))
    return int(match.group(1)) if match else None


def _is_quota_exhausted(error: Exception) -> bool:
    """A 429 comes in two kinds. A per-minute rate limit clears in seconds;
    "you exceeded your current quota" is the plan's allowance and does not.
    Only the message tells them apart."""
    return _status_code(error) == 429 and "quota" in str(error).lower()


def _is_transient(error: Exception) -> bool:
    """503 overloaded, 429 rate-limited, 500/504 server-side: worth retrying
    on the SAME model. A 404 (model not available to this key), a 400/401/403,
    or an exhausted quota never becomes true by waiting, so those skip
    straight to the next model."""
    code = _status_code(error)
    if _is_quota_exhausted(error):
        return False
    if code in (429, 500, 502, 503, 504):
        return True
    if code is not None:
        return False
    # No code at all is usually a socket timeout or a dropped connection.
    return True


def _model_chain(model: str) -> list[str]:
    """The requested model first, then declared fallbacks.

    This exists because free-tier Gemini genuinely fails per-model: at the
    time of writing `gemini-flash-latest` returns 503 "high demand" while
    `gemini-3.5-flash` answers fine, and `gemini-2.5-flash` 404s for keys
    issued recently. A single hard-coded model name is therefore a demo that
    breaks on someone else's traffic spike, not a configuration preference.
    """
    raw = os.getenv("GEMINI_MODEL_FALLBACKS", "gemini-3.5-flash,gemini-flash-lite-latest")
    chain = [model] + [m.strip() for m in raw.split(",") if m.strip()]
    seen: set[str] = set()
    return [m for m in chain if not (m in seen or seen.add(m))]


# Circuit breaker. A model that just told us it is out of quota, or does not
# exist for this key, will say the same thing on the next call - so the next
# call skips it for a while instead of paying for the same failure again.
# Without this, every agent call re-tried a spent model first; that was the
# difference between a 10-second and a 37-second planning step in testing.
QUOTA_COOLDOWN_SECONDS = float(os.getenv("GEMINI_QUOTA_COOLDOWN_SECONDS", "600"))
MISSING_MODEL_COOLDOWN_SECONDS = 3600.0
_cooldown_until: dict[str, float] = {}


def _trip_breaker(model: str, error: Exception) -> None:
    if _is_quota_exhausted(error):
        _cooldown_until[model] = time.monotonic() + QUOTA_COOLDOWN_SECONDS
    elif _status_code(error) == 404:
        _cooldown_until[model] = time.monotonic() + MISSING_MODEL_COOLDOWN_SECONDS


def _available_chain(model: str) -> list[str]:
    """The chain minus models cooling down - unless that leaves nothing, in
    which case try them anyway: a stale breaker must never turn a working
    service into a guaranteed failure."""
    chain = _model_chain(model)
    now = time.monotonic()
    live = [m for m in chain if _cooldown_until.get(m, 0.0) <= now]
    return live or chain


def reset_breakers() -> None:
    _cooldown_until.clear()


def _call_with_resilience(attempt_once: Callable[[str], Any], *, model: str) -> Any:
    """Run `attempt_once(model)` across the fallback chain.

    Transient failures are retried on the same model with exponential backoff;
    permanent ones move to the next model immediately. If every model in the
    chain is exhausted the last error is re-raised as AgentSafeFailure, so the
    caller's safe-failure path is unchanged — this layer only decides how hard
    to try before giving up.
    """
    last_error: Exception | None = None
    for candidate in _available_chain(model):
        for attempt in range(1, GEMINI_MAX_ATTEMPTS + 1):
            started = time.monotonic()
            try:
                result = attempt_once(candidate)
                _record_call(
                    model=candidate, attempt=attempt,
                    duration_ms=int((time.monotonic() - started) * 1000), ok=True, error=None,
                )
                return result
            except Exception as e:  # noqa: BLE001 - re-raised below as AgentSafeFailure
                last_error = e
                _record_call(
                    model=candidate, attempt=attempt,
                    duration_ms=int((time.monotonic() - started) * 1000), ok=False, error=str(e)[:200],
                )
                if not _is_transient(e):
                    _trip_breaker(candidate, e)
                    break  # next model; waiting will not help
                if attempt < GEMINI_MAX_ATTEMPTS:
                    time.sleep(GEMINI_BACKOFF_SECONDS * (2 ** (attempt - 1)))
    raise AgentSafeFailure(f"Gemini call failed after trying {', '.join(_model_chain(model))}: {last_error}")


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

    def _attempt(candidate: str):
        return client.models.generate_content(
            model=candidate,
            contents=user_content,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.2,
                http_options=types.HttpOptions(timeout=int(GEMINI_TIMEOUT_SECONDS * 1000)),
            ),
        )

    # Retries transient failures and falls back across models; still raises
    # AgentSafeFailure once the whole chain is exhausted.
    response = _call_with_resilience(_attempt, model=model)

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
        def _attempt(candidate_model: str, _contents=contents):
            return client.models.generate_content(
                model=candidate_model,
                contents=_contents,
                config=types.GenerateContentConfig(
                    system_instruction=system_instruction,
                    tools=[tool_config],
                    automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
                    temperature=0.2,
                    http_options=types.HttpOptions(timeout=int(GEMINI_TIMEOUT_SECONDS * 1000)),
                ),
            )

        try:
            response = _call_with_resilience(_attempt, model=model)
        except AgentSafeFailure as e:
            # Keep the turn number in the message: which turn died tells you
            # whether the model failed to start or failed mid tool loop.
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
