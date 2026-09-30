"""Allow-listed, read-only tools for the Platform Operations Copilot.

Three properties this module is responsible for, and the reasons they are
enforced here rather than trusted to the agents:

  Read-only.   There is no method on this client that writes. Not "a write
    method the agents are told not to call" - no such method exists, so a
    prompt injection that says "now comp every tenant" reaches a client that
    has nothing to comp with. Applying an intervention is ASP.NET Core's
    job, behind an authenticator code.

  Owner-scoped. Every request carries the owner's platform JWT, so the
    PlatformOwner policy that guards the console guards the agent too. There
    is no service account and no bypass route: if the owner's session has
    expired, the agent's tools stop working exactly when the console would.

  Recorded.    Every invocation lands in the trace, including the ones that
    raise. Recording at the decorator rather than at each call site means a
    tool cannot be used without appearing in the audit trail.
"""
from __future__ import annotations

import functools
import time
from typing import Any

import httpx


class PlatformToolError(Exception):
    """A tool-level failure. Carries no response body: an upstream error page
    can contain anything, and this string ends up in a trace the owner
    reads."""


def _records_call(tool_name: str):
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(self: "PlatformToolsClient", *args, **kwargs):
            started = time.monotonic()
            try:
                result = fn(self, *args, **kwargs)
            except Exception as e:
                self._record(tool_name, started, ok=False, error=str(e)[:200])
                raise
            self._record(tool_name, started, ok=True, error=None)
            return result

        return wrapper

    return decorator


class PlatformToolsClient:
    """The complete tool surface available to the platform agents."""

    # The allow-list, stated once and asserted in tests. A tool that is not
    # named here is not reachable from an agent.
    ALLOWED_TOOLS = (
        "get_revenue_overview",
        "list_subscriptions",
        "list_open_invoices",
        "get_tenant_detail",
    )

    def __init__(self, base_url: str, auth_token: str, agent: str = "PlatformAnalysisAgent", timeout: float = 20.0):
        self._client = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {auth_token}"},
            timeout=timeout,
        )
        self.calls: list[dict[str, Any]] = []
        self.agent = agent

    # ── plumbing ────────────────────────────────────────────────────────
    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "PlatformToolsClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _record(self, tool: str, started: float, *, ok: bool, error: str | None) -> None:
        self.calls.append(
            {
                "tool": tool,
                "agent": self.agent,
                "duration_ms": int((time.monotonic() - started) * 1000),
                "success": ok,
                "error": error,
            }
        )

    def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        try:
            response = self._client.get(path, params=params)
        except httpx.HTTPError as e:
            raise PlatformToolError(f"{path} could not be reached: {type(e).__name__}") from e
        if response.status_code in (401, 403):
            # Worth separating: this is the owner's session having lapsed
            # mid-run, not the platform being broken.
            raise PlatformToolError(f"{path} refused the owner session (HTTP {response.status_code}).")
        if response.is_error:
            raise PlatformToolError(f"{path} returned HTTP {response.status_code}.")
        return response.json()

    # ── the tools ───────────────────────────────────────────────────────
    @_records_call("get_revenue_overview")
    def get_revenue_overview(self) -> dict[str, Any]:
        """MRR, plan mix, trial conversion and churn for the whole platform."""
        return self._get("/platform/revenue")

    @_records_call("list_subscriptions")
    def list_subscriptions(self, status: str | None = None, page_size: int = 100) -> dict[str, Any]:
        """Every business's subscription standing. Capped at one page: an
        agent that needs more than 100 businesses to answer a churn question
        is not answering a churn question."""
        params: dict[str, Any] = {"page": 1, "pageSize": min(page_size, 100)}
        if status:
            params["status"] = status
        return self._get("/platform/revenue/subscriptions", params)

    @_records_call("list_open_invoices")
    def list_open_invoices(self, page_size: int = 100) -> dict[str, Any]:
        """Unpaid platform invoices - the strongest single churn signal
        there is, because it is a decision the business already made."""
        return self._get("/platform/revenue/invoices", {"status": "Issued", "page": 1, "pageSize": min(page_size, 100)})

    @_records_call("get_tenant_detail")
    def get_tenant_detail(self, tenant_id: str) -> dict[str, Any]:
        """One business's users, branches and booking activity - used to tell
        a business that is quiet because it is leaving from one that is quiet
        because it is seasonal."""
        return self._get(f"/platform/tenants/{tenant_id}")
