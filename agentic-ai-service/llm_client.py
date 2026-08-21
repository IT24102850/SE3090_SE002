"""LLM provider abstraction. Every agent imports `generate_structured` /
`generate_with_tools` / `ToolSpec` / `AgentSafeFailure` from HERE, not from
`gemini_client` directly, so the provider can be swapped via one env var
without touching any agent file.

`gemini_client.py` is untouched by this - it's the only path that's ever
actually been exercised (tests mock it), so this module wraps it rather than
modifying it. `ollama_client.py` implements the same two functions against a
local Ollama install; nothing here assumes Ollama is actually installed
(LLM_PROVIDER defaults to "gemini"), so importing this module is always safe.
"""
from __future__ import annotations

import os

from gemini_client import AgentSafeFailure, ToolSpec  # noqa: F401 (re-exported)
from gemini_client import generate_structured as _gemini_generate_structured
from gemini_client import generate_with_tools as _gemini_generate_with_tools
from pydantic import BaseModel

LLM_PROVIDER = os.getenv("LLM_PROVIDER", "gemini")


def generate_structured(*, system_instruction: str, user_content: str, response_schema: type[BaseModel], model: str) -> BaseModel:
    if LLM_PROVIDER == "ollama":
        from ollama_client import generate_structured as _ollama_generate_structured
        return _ollama_generate_structured(
            system_instruction=system_instruction, user_content=user_content, response_schema=response_schema, model=model
        )
    return _gemini_generate_structured(
        system_instruction=system_instruction, user_content=user_content, response_schema=response_schema, model=model
    )


def generate_with_tools(
    *,
    system_instruction: str,
    user_content: str,
    response_schema: type[BaseModel],
    tools: list[ToolSpec],
    model: str,
    max_turns: int = 6,
) -> BaseModel:
    if LLM_PROVIDER == "ollama":
        from ollama_client import generate_with_tools as _ollama_generate_with_tools
        return _ollama_generate_with_tools(
            system_instruction=system_instruction,
            user_content=user_content,
            response_schema=response_schema,
            tools=tools,
            model=model,
            max_turns=max_turns,
        )
    return _gemini_generate_with_tools(
        system_instruction=system_instruction,
        user_content=user_content,
        response_schema=response_schema,
        tools=tools,
        model=model,
        max_turns=max_turns,
    )
