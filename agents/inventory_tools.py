from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any, Literal, TypedDict
import re


UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)

ALLOWED_TOOL_NAMES = {"query_stock_levels", "query_historical_usage"}


class ValidationError(ValueError):
    pass


def _ensure_uuid(value: str, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field_name} is required.")
    value = value.strip()
    if not UUID_RE.match(value):
        raise ValidationError(f"{field_name} must be a valid UUID.")
    return value


def _ensure_date_string(value: str, field_name: str, *, allow_past: bool = True) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field_name} is required.")
    try:
        parsed = date.fromisoformat(value.strip())
    except ValueError as exc:
        raise ValidationError(f"{field_name} must be a valid ISO date (YYYY-MM-DD).") from exc
    if not allow_past and parsed < date.today():
        raise ValidationError(f"{field_name} must not be in the past.")
    return parsed.isoformat()


@dataclass
class StockLevelRequest:
    tenant_id: str
    inventory_item_id: str | None = None
    branch_id: str | None = None
    include_inactive: bool = False

    def validate(self) -> "StockLevelRequest":
        self.tenant_id = _ensure_uuid(self.tenant_id, "tenant_id")
        if self.inventory_item_id is not None:
            self.inventory_item_id = _ensure_uuid(self.inventory_item_id, "inventory_item_id")
        if self.branch_id is not None:
            self.branch_id = _ensure_uuid(self.branch_id, "branch_id")
        return self


@dataclass
class HistoricalUsageRequest:
    tenant_id: str
    inventory_item_id: str
    start_date: str
    end_date: str
    granularity: Literal["day", "week", "month"] = "day"
    limit: int = 30

    def validate(self) -> "HistoricalUsageRequest":
        self.tenant_id = _ensure_uuid(self.tenant_id, "tenant_id")
        self.inventory_item_id = _ensure_uuid(self.inventory_item_id, "inventory_item_id")
        self.start_date = _ensure_date_string(self.start_date, "start_date")
        self.end_date = _ensure_date_string(self.end_date, "end_date")

        if date.fromisoformat(self.end_date) < date.fromisoformat(self.start_date):
            raise ValidationError("end_date must be on or after start_date.")

        if self.granularity not in {"day", "week", "month"}:
            raise ValidationError("granularity must be one of: day, week, month.")

        if not isinstance(self.limit, int) or self.limit < 1 or self.limit > 365:
            raise ValidationError("limit must be an integer between 1 and 365.")

        return self


class StockLevelItem(TypedDict):
    inventoryItemId: str
    name: str
    sku: str
    branchId: str | None
    quantity: float
    reorderLevel: float
    status: str
    updatedAt: str


class HistoricalUsagePoint(TypedDict):
    date: str
    quantityReceived: float
    quantityIssued: float
    netChange: float
    runningBalance: float


class StockLevelsResponse(TypedDict):
    tool: str
    tenantId: str
    items: list[StockLevelItem]
    count: int


class HistoricalUsageResponse(TypedDict):
    tool: str
    tenantId: str
    inventoryItemId: str
    series: list[HistoricalUsagePoint]
    count: int


def query_stock_levels(payload: dict[str, Any]) -> dict[str, Any]:
    """Return structured stock-level data for a tenant or a specific item/branch.

    Expected keys:
      - tenant_id (required UUID)
      - inventory_item_id (optional UUID)
      - branch_id (optional UUID)
      - include_inactive (optional bool)
    """
    request = StockLevelRequest(
        tenant_id=payload.get("tenant_id"),
        inventory_item_id=payload.get("inventory_item_id"),
        branch_id=payload.get("branch_id"),
        include_inactive=bool(payload.get("include_inactive", False)),
    )
    request.validate()

    # Placeholder data used until the real inventory repository is connected.
    items: list[StockLevelItem] = [
        {
            "inventoryItemId": request.inventory_item_id or "11111111-1111-4111-8111-111111111111",
            "name": "Premium Coffee Beans",
            "sku": "SKU-00132",
            "branchId": request.branch_id or "22222222-2222-4222-8222-222222222222",
            "quantity": 18.0,
            "reorderLevel": 25.0,
            "status": "low_stock",
            "updatedAt": "2026-08-17T08:00:00Z",
        }
    ]

    return {
        "tool": "query_stock_levels",
        "tenantId": request.tenant_id,
        "items": items,
        "count": len(items),
    }


def query_historical_usage(payload: dict[str, Any]) -> dict[str, Any]:
    """Return structured historical usage data for a single inventory item.

    Expected keys:
      - tenant_id (required UUID)
      - inventory_item_id (required UUID)
      - start_date (required ISO date, YYYY-MM-DD)
      - end_date (required ISO date, YYYY-MM-DD)
      - granularity (optional: day|week|month)
      - limit (optional int 1..365)
    """
    request = HistoricalUsageRequest(
        tenant_id=payload.get("tenant_id"),
        inventory_item_id=payload.get("inventory_item_id"),
        start_date=payload.get("start_date"),
        end_date=payload.get("end_date"),
        granularity=payload.get("granularity", "day"),
        limit=int(payload.get("limit", 30)),
    )
    request.validate()

    series: list[HistoricalUsagePoint] = [
        {
            "date": "2026-08-10",
            "quantityReceived": 40.0,
            "quantityIssued": 12.0,
            "netChange": 28.0,
            "runningBalance": 42.0,
        },
        {
            "date": "2026-08-11",
            "quantityReceived": 0.0,
            "quantityIssued": 18.0,
            "netChange": -18.0,
            "runningBalance": 24.0,
        },
    ]

    return {
        "tool": "query_historical_usage",
        "tenantId": request.tenant_id,
        "inventoryItemId": request.inventory_item_id,
        "series": series[: request.limit],
        "count": min(len(series), request.limit),
    }


def execute_allowed_tool(tool_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Only permit agent tools that are explicitly allow-listed."""
    if tool_name not in ALLOWED_TOOL_NAMES:
        raise ValidationError(f"Tool '{tool_name}' is not allow-listed.")

    if not isinstance(payload, dict):
        raise ValidationError("Tool payload must be a JSON object.")

    if tool_name == "query_stock_levels":
        return query_stock_levels(payload)
    if tool_name == "query_historical_usage":
        return query_historical_usage(payload)

    raise ValidationError(f"No implementation registered for tool '{tool_name}'.")


__all__ = [
    "ALLOWED_TOOL_NAMES",
    "execute_allowed_tool",
    "query_stock_levels",
    "query_historical_usage",
    "StockLevelRequest",
    "HistoricalUsageRequest",
]
