"""Read-only, caller-scoped tools for the inventory planning agents."""
from __future__ import annotations

from typing import Any

import httpx


class InventoryToolsClient:
    def __init__(self, base_url: str, auth_token: str, timeout: float = 15.0):
        self._client = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {auth_token}"},
            timeout=timeout,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "InventoryToolsClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        response = self._client.get(path, params=params)
        if response.is_error:
            raise RuntimeError(f"Inventory API {path} returned HTTP {response.status_code}.")
        return response.json()

    def query_inventory(self, branch_id: str | None = None) -> dict[str, Any]:
        """Fetch the user's authorized inventory snapshot (up to 100 items)."""
        params: dict[str, Any] = {"page": 1, "pageSize": 100}
        if branch_id:
            params["branchId"] = branch_id
        return self._get("/inventory", params)

    def query_stock_movements(self, branch_id: str | None = None) -> list[dict[str, Any]]:
        """Fetch recent authorized movements, capped by the backend at 100."""
        params: dict[str, Any] = {"pageSize": 100}
        if branch_id:
            params["branchId"] = branch_id
        return self._get("/inventory/movements", params)
