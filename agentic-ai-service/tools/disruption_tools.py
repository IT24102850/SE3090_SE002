"""Allow-listed tools for the Disruption Recovery Copilot, and the per-agent
permission gate.

Every tool is a GET made with the calling manager's own JWT, so the agent can
read nothing the manager could not read in the web app, and it can write
nothing at all - there is no write method on this client to call. Applying a
recovery is a separate, approved, human-initiated request to ASP.NET Core.

Least privilege is enforced, not merely documented: an agent receives an
`AgentToolbox`, and a toolbox refuses any tool outside that agent's entry in
ALLOWED_TOOLS. The refusal is recorded in the trace like any other call, so a
misbehaving agent is visible rather than silent.
"""
from __future__ import annotations

import functools
import time
from typing import Any, Callable

import httpx


class ToolError(Exception):
    """A tool-level failure: an HTTP error, a refused permission, bad input."""


ALLOWED_TOOLS: dict[str, frozenset[str]] = {
    # The planner reads nothing. It turns the manager's sentence into a plan;
    # giving it data would let the one model-driven step act before the
    # deterministic steps have vetted anything.
    "DisruptionPlannerAgent": frozenset(),
    "ImpactAnalysisAgent": frozenset({"list_affected_bookings", "get_resource", "list_resources"}),
    "RecoveryActionAgent": frozenset({"list_resources", "get_resource", "find_free_slots", "detect_conflicts"}),
    # The gate re-checks for itself: a slot that filled up while the agents
    # were thinking must not be waved through on a stale read.
    "DisruptionSafetyAgent": frozenset({"detect_conflicts", "get_resource"}),
}


def _records(tool_name: str):
    """Record every invocation, including the ones that fail or are refused."""

    def decorator(fn: Callable[..., Any]):
        @functools.wraps(fn)
        def wrapper(self: "DisruptionToolsClient", *args: Any, **kwargs: Any):
            started = time.monotonic()
            agent = self.current_agent
            allowed = ALLOWED_TOOLS.get(agent)
            if allowed is not None and tool_name not in allowed:
                error = f"{agent} is not permitted to call {tool_name}."
                self._record(tool_name, started, ok=False, error=error)
                raise ToolError(error)
            try:
                result = fn(self, *args, **kwargs)
            except Exception as e:
                self._record(tool_name, started, ok=False, error=str(e)[:200])
                raise
            self._record(tool_name, started, ok=True, error=None)
            return result

        return wrapper

    return decorator


class DisruptionToolsClient:
    def __init__(self, base_url: str, auth_token: str, timeout: float = 20.0):
        self._client = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {auth_token}"},
            timeout=timeout,
        )
        self.calls: list[dict[str, Any]] = []
        self.current_agent: str = "unknown"

    def _record(self, tool: str, started: float, *, ok: bool, error: str | None) -> None:
        self.calls.append({
            "tool": tool,
            "agent": self.current_agent,
            "duration_ms": int((time.monotonic() - started) * 1000),
            "success": ok,
            "error": error,
        })

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "DisruptionToolsClient":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    # ── Impact ──────────────────────────────────────────────────────────
    @_records("list_affected_bookings")
    def list_affected_bookings(self, resource_id: str, date_from: str, date_to: str) -> list[dict[str, Any]]:
        """Every booking the outage would strand, earliest first."""
        return self._get("/bookings/affected", {"resourceId": resource_id, "from": date_from, "to": date_to})

    @_records("get_resource")
    def get_resource(self, resource_id: str) -> dict[str, Any]:
        """One resource's name, category, specialty and capacity."""
        return self._get(f"/resources/{resource_id}")

    @_records("list_resources")
    def list_resources(self, tenant_id: str, branch_id: str | None = None) -> list[dict[str, Any]]:
        """Candidate substitutes: every resource of this business."""
        params: dict[str, Any] = {"tenantId": tenant_id}
        if branch_id:
            params["branchId"] = branch_id
        return self._get("/resources", params)

    # ── Recovery ────────────────────────────────────────────────────────
    @_records("find_free_slots")
    def find_free_slots(self, resource_id: str, date: str, duration: int, booking_type_id: str | None = None) -> dict[str, Any]:
        """Open slots on one resource for one day."""
        params: dict[str, Any] = {"resourceId": resource_id, "date": date, "duration": duration}
        if booking_type_id:
            params["bookingTypeId"] = booking_type_id
        return self._get("/bookings/available-slots", params)

    @_records("detect_conflicts")
    def detect_conflicts(self, resource_id: str, date_from: str, date_to: str) -> list[dict[str, Any]]:
        """What is already on a resource in a window - the gate's own check."""
        return self._get("/bookings/affected", {"resourceId": resource_id, "from": date_from, "to": date_to})

    def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        try:
            response = self._client.get(path, params=params)
        except httpx.HTTPError as e:
            raise ToolError(f"{path} request failed: {e}") from e
        if response.status_code >= 400:
            raise ToolError(f"{path} failed ({response.status_code}): {_safe_message(response)}")
        try:
            return response.json()
        except ValueError as e:
            raise ToolError(f"{path} returned a non-JSON response.") from e


class AgentToolbox:
    """The only handle an agent gets. It carries that agent's name, so the
    permission gate above knows who is asking."""

    def __init__(self, client: DisruptionToolsClient, agent: str):
        if agent not in ALLOWED_TOOLS:
            raise ValueError(f"Unknown agent: {agent}")
        self._client = client
        self._agent = agent

    def __getattr__(self, name: str) -> Any:
        attr = getattr(self._client, name)
        if not callable(attr):
            return attr

        @functools.wraps(attr)
        def call(*args: Any, **kwargs: Any):
            self._client.current_agent = self._agent
            return attr(*args, **kwargs)

        return call


def _safe_message(response: httpx.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return response.text[:200]
    if isinstance(body, dict):
        for key in ("message", "detail", "title"):
            if isinstance(body.get(key), str):
                return body[key][:200]
    return str(body)[:200]
