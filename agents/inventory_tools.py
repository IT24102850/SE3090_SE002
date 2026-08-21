from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any, Literal, TypedDict
import re
import math


UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)

ALLOWED_TOOL_NAMES = {
    "query_stock_levels",
    "query_historical_usage",
    "predict_demand",
    "generate_purchase_order",
    "send_notification",
    "update_inventory_count",
}


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


def _pick_value(payload: dict[str, Any], *keys: str) -> Any:
    if not isinstance(payload, dict):
        return None
    for key in keys:
        if key in payload:
            return payload[key]
    lowered = {str(k).lower(): v for k, v in payload.items()}
    for key in keys:
        lowered_key = key.lower()
        if lowered_key in lowered:
            return lowered[lowered_key]
    return None


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


@dataclass
class DemandPredictionRequest:
    tenant_id: str
    inventory_item_id: str
    historical_usage: list[dict[str, Any]]
    forecast_days: int = 7
    lead_time_days: int = 7
    safety_stock_days: int = 7

    def validate(self) -> "DemandPredictionRequest":
        self.tenant_id = _ensure_uuid(self.tenant_id, "tenant_id")
        self.inventory_item_id = _ensure_uuid(self.inventory_item_id, "inventory_item_id")
        if not isinstance(self.historical_usage, list):
            raise ValidationError("historical_usage must be a list of usage points.")
        if not self.historical_usage:
            raise ValidationError("historical_usage must not be empty.")
        if not isinstance(self.forecast_days, int) or self.forecast_days < 1:
            raise ValidationError("forecast_days must be a positive integer.")
        if not isinstance(self.lead_time_days, int) or self.lead_time_days < 1:
            raise ValidationError("lead_time_days must be a positive integer.")
        if not isinstance(self.safety_stock_days, int) or self.safety_stock_days < 0:
            raise ValidationError("safety_stock_days must be a non-negative integer.")
        return self


@dataclass
class PurchaseOrderRequest:
    tenant_id: str
    inventory_item_id: str
    supplier_id: str
    current_stock: float
    reorder_level: float
    predicted_demand: float
    lead_time_days: int = 7
    unit_cost: float = 0.0
    safety_stock_days: int = 7
    budget_limit: float | None = None
    order_multiple: int | None = None
    supplier_active: bool | None = None

    def validate(self) -> "PurchaseOrderRequest":
        self.tenant_id = _ensure_uuid(self.tenant_id, "tenant_id")
        self.inventory_item_id = _ensure_uuid(self.inventory_item_id, "inventory_item_id")
        self.supplier_id = _ensure_uuid(self.supplier_id, "supplier_id")
        if not isinstance(self.current_stock, (int, float)):
            raise ValidationError("current_stock must be a number.")
        if not isinstance(self.reorder_level, (int, float)):
            raise ValidationError("reorder_level must be a number.")
        if not isinstance(self.predicted_demand, (int, float)):
            raise ValidationError("predicted_demand must be a number.")
        if not isinstance(self.lead_time_days, int) or self.lead_time_days < 1:
            raise ValidationError("lead_time_days must be a positive integer.")
        if not isinstance(self.unit_cost, (int, float)):
            raise ValidationError("unit_cost must be a number.")
        if not isinstance(self.safety_stock_days, int) or self.safety_stock_days < 0:
            raise ValidationError("safety_stock_days must be a non-negative integer.")
        if self.budget_limit is not None:
            try:
                self.budget_limit = float(self.budget_limit)
            except (TypeError, ValueError):
                raise ValidationError("budget_limit must be numeric if provided.")
            if self.budget_limit < 0:
                raise ValidationError("budget_limit must be non-negative.")
        if self.order_multiple is not None:
            if not isinstance(self.order_multiple, int) or self.order_multiple < 1:
                raise ValidationError("order_multiple must be an integer >= 1 if provided.")
        if self.supplier_active is not None and not isinstance(self.supplier_active, bool):
            raise ValidationError("supplier_active must be a boolean if provided.")
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


class DemandForecast(TypedDict):
    tool: str
    tenantId: str
    inventoryItemId: str
    forecastDays: int
    predictedDailyDemand: float
    predictedTotalDemand: float
    safetyStock: float
    confidence: float
    source: str


class PurchaseOrderDraft(TypedDict):
    tool: str
    tenantId: str
    inventoryItemId: str
    supplierId: str
    quantity: float
    priority: str
    expectedDeliveryDays: int
    estimatedUnitCost: float
    notes: str


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


def _coerce_float(value: Any, field_name: str) -> float:
    try:
        numeric = float(value)
    except (TypeError, ValueError) as exc:
        raise ValidationError(f"{field_name} must be numeric.") from exc
    if numeric < 0:
        raise ValidationError(f"{field_name} must be non-negative.")
    return numeric


def _usage_for_point(point: dict[str, Any]) -> float:
    if not isinstance(point, dict):
        raise ValidationError("historical_usage entries must be objects.")
    issued = _pick_value(point, "quantityIssued", "quantity_issued", "issued", "usage")
    if issued is None:
        issued = _pick_value(point, "quantityReceived", "quantity_received", "received")
    if issued is None:
        raise ValidationError("Each usage point must include quantityIssued or usage.")
    return _coerce_float(issued, "quantityIssued")


def _calculate_average_daily_demand(usage_points: list[dict[str, Any]]) -> float:
    if not usage_points:
        return 0.0
    values = [_usage_for_point(point) for point in usage_points]
    if not values:
        return 0.0
    return sum(values) / len(values)


def query_stock_levels(payload: dict[str, Any]) -> dict[str, Any]:
    """Return structured stock-level data for a tenant or a specific item/branch.

    Expected keys:
      - tenant_id (required UUID)
      - inventory_item_id (optional UUID)
      - branch_id (optional UUID)
      - include_inactive (optional bool)
    """
    request = StockLevelRequest(
        tenant_id=_pick_value(payload, "tenant_id", "tenantId"),
        inventory_item_id=_pick_value(payload, "inventory_item_id", "inventoryItemId"),
        branch_id=_pick_value(payload, "branch_id", "branchId"),
        include_inactive=bool(_pick_value(payload, "include_inactive", "includeInactive", "includeInactiveItems", "includeInactive")),
    )
    request.validate()

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
        tenant_id=_pick_value(payload, "tenant_id", "tenantId"),
        inventory_item_id=_pick_value(payload, "inventory_item_id", "inventoryItemId"),
        start_date=_pick_value(payload, "start_date", "startDate"),
        end_date=_pick_value(payload, "end_date", "endDate"),
        granularity=str(_pick_value(payload, "granularity", "granularity")) if _pick_value(payload, "granularity", "granularity") is not None else "day",
        limit=int(_pick_value(payload, "limit", "limit") or 30),
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


def predict_demand(payload: dict[str, Any]) -> dict[str, Any]:
    """Estimate demand using historical usage data.

    Supported inputs include:
      - tenant_id / tenantId
      - inventory_item_id / inventoryItemId
      - historical_usage / historicalUsage / series
      - forecast_days / forecastDays
      - lead_time_days / leadTimeDays
      - safety_stock_days / safetyStockDays
    """
    usage_points = _pick_value(payload, "historical_usage", "historicalUsage", "usage_history", "usageHistory", "series")
    if usage_points is None:
        raise ValidationError("historical_usage is required for predicting demand.")
    if not isinstance(usage_points, list):
        raise ValidationError("historical_usage must be a list of usage points.")

    request = DemandPredictionRequest(
        tenant_id=_pick_value(payload, "tenant_id", "tenantId"),
        inventory_item_id=_pick_value(payload, "inventory_item_id", "inventoryItemId"),
        historical_usage=usage_points,
        forecast_days=int(_pick_value(payload, "forecast_days", "forecastDays") or 7),
        lead_time_days=int(_pick_value(payload, "lead_time_days", "leadTimeDays") or 7),
        safety_stock_days=int(_pick_value(payload, "safety_stock_days", "safetyStockDays", "safetyStock") or 7),
    )
    request.validate()

    average_daily_demand = _calculate_average_daily_demand(request.historical_usage)
    predicted_total_demand = average_daily_demand * request.forecast_days
    safety_stock = average_daily_demand * request.safety_stock_days
    confidence = min(0.99, max(0.55, 0.7 + min(0.25, len(request.historical_usage) / 50)))

    return {
        "tool": "predict_demand",
        "tenantId": request.tenant_id,
        "inventoryItemId": request.inventory_item_id,
        "forecastDays": request.forecast_days,
        "predictedDailyDemand": round(average_daily_demand, 2),
        "predictedTotalDemand": round(predicted_total_demand, 2),
        "safetyStock": round(safety_stock, 2),
        "confidence": round(confidence, 2),
        "source": "historical_usage",
    }


def generate_purchase_order(payload: dict[str, Any]) -> dict[str, Any]:
    """Draft a purchase order based on predicted demand and current stock levels.

    Adds validations:
      - supplier_active (bool) must be True if provided
      - budget_limit (float) if provided must not be exceeded by total PO cost
      - order_multiple (int) will round quantity up to nearest multiple
      - ensure quantity respects reorder_level (bring stock up to reorder level at minimum)
    """
    request = PurchaseOrderRequest(
        tenant_id=_pick_value(payload, "tenant_id", "tenantId"),
        inventory_item_id=_pick_value(payload, "inventory_item_id", "inventoryItemId"),
        supplier_id=_pick_value(payload, "supplier_id", "supplierId"),
        current_stock=_coerce_float(_pick_value(payload, "current_stock", "currentStock", "quantity_on_hand", "quantityOnHand", "on_hand", "onHand"), "current_stock"),
        reorder_level=_coerce_float(_pick_value(payload, "reorder_level", "reorderLevel"), "reorder_level"),
        predicted_demand=_coerce_float(_pick_value(payload, "predicted_demand", "predictedDemand"), "predicted_demand"),
        lead_time_days=int(_pick_value(payload, "lead_time_days", "leadTimeDays") or 7),
        unit_cost=_coerce_float(_pick_value(payload, "unit_cost", "unitCost", "estimated_unit_cost", "estimatedUnitCost"), "unit_cost"),
        safety_stock_days=int(_pick_value(payload, "safety_stock_days", "safetyStockDays", "safetyStock") or 7),
        budget_limit=_pick_value(payload, "budget_limit", "budgetLimit", "budget"),
        order_multiple=_pick_value(payload, "order_multiple", "orderMultiple", "pack_size", "orderPackSize"),
        supplier_active=_pick_value(payload, "supplier_active", "supplierActive", "active"),
    )
    request.validate()

    # Supplier must be active
    if request.supplier_active is not None and request.supplier_active is False:
        raise ValidationError("Supplier is not active and cannot receive purchase orders.")

    # Calculate base recommended quantity from forecast and safety buffer
    safety_buffer = max(0.0, request.predicted_demand * (request.safety_stock_days / max(1, request.lead_time_days)))
    recommended_quantity = max(0.0, request.predicted_demand + safety_buffer - request.current_stock)

    # Ensure we at least order enough to reach reorder level if stock is low
    min_needed_to_reorder = max(0.0, request.reorder_level - request.current_stock)
    if recommended_quantity < min_needed_to_reorder:
        recommended_quantity = min_needed_to_reorder

    # Apply order_multiple rounding if requested
    if request.order_multiple and request.order_multiple > 0:
        multiple = int(request.order_multiple)
        recommended_quantity = math.ceil(recommended_quantity / multiple) * multiple

    # Final safety: non-negative and rounded to 2 decimals
    recommended_quantity = max(0.0, float(recommended_quantity))

    total_cost = recommended_quantity * float(request.unit_cost)

    # Budget validation
    if request.budget_limit is not None:
        try:
            budget = float(request.budget_limit)
        except (TypeError, ValueError):
            raise ValidationError("budget_limit must be numeric if provided.")
        if total_cost > budget:
            raise ValidationError(f"Total PO cost {total_cost:.2f} exceeds budget limit {budget:.2f}.")

    # Decide priority
    priority = "medium"
    if recommended_quantity >= request.reorder_level:
        priority = "high"
    if request.current_stock <= request.reorder_level * 0.5:
        priority = "critical"

    return {
        "tool": "generate_purchase_order",
        "tenantId": request.tenant_id,
        "inventoryItemId": request.inventory_item_id,
        "supplierId": request.supplier_id,
        "quantity": round(recommended_quantity, 2),
        "priority": priority,
        "expectedDeliveryDays": request.lead_time_days,
        "estimatedUnitCost": round(request.unit_cost, 2),
        "totalCost": round(total_cost, 2),
        "notes": "Generated from demand forecast and current stock position.",
    }


def send_notification(payload: dict[str, Any]) -> dict[str, Any]:
    """Queue a notification for delivery by the system.

    Expected keys:
      - tenant_id / tenantId
      - channel (in_app|email|sms|dashboard)
      - title
      - message
      - target_role (optional)
    """
    tenant = _pick_value(payload, "tenant_id", "tenantId")
    channel = _pick_value(payload, "channel", "channel")
    title = _pick_value(payload, "title", "title")
    message = _pick_value(payload, "message", "message")
    target_role = _pick_value(payload, "target_role", "targetRole", "target_role")

    tenant = _ensure_uuid(tenant, "tenant_id")
    if not isinstance(channel, str) or not channel:
        raise ValidationError("channel is required for send_notification.")
    if not isinstance(title, str) or not title.strip():
        raise ValidationError("title is required for send_notification.")
    if not isinstance(message, str) or not message.strip():
        raise ValidationError("message is required for send_notification.")

    # Placeholder: real implementation would enqueue or send via external service
    return {
        "tool": "send_notification",
        "tenantId": tenant,
        "channel": channel,
        "title": title.strip(),
        "message": message.strip(),
        "targetRole": target_role,
        "status": "queued",
    }


def update_inventory_count(payload: dict[str, Any]) -> dict[str, Any]:
    """Update the inventory count for a single item. Validated but does not persist (placeholder).

    Expected keys:
      - tenant_id / tenantId
      - inventory_item_id / inventoryItemId
      - new_count / newCount
      - reason (optional)
    """
    tenant = _pick_value(payload, "tenant_id", "tenantId")
    item_id = _pick_value(payload, "inventory_item_id", "inventoryItemId")
    new_count = _pick_value(payload, "new_count", "newCount", "quantity", "quantity_on_hand")
    reason = _pick_value(payload, "reason", "reason")

    tenant = _ensure_uuid(tenant, "tenant_id")
    item_id = _ensure_uuid(item_id, "inventory_item_id")
    new_count_val = _coerce_float(new_count, "new_count")

    # Placeholder: here the real repository would persist the change and return updated record
    updated = {
        "inventoryItemId": item_id,
        "tenantId": tenant,
        "newQuantity": new_count_val,
        "reason": reason,
        "status": "updated",
    }
    return {
        "tool": "update_inventory_count",
        "tenantId": tenant,
        "inventoryItemId": item_id,
        "newQuantity": new_count_val,
        "status": "updated",
        "details": updated,
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
    if tool_name == "predict_demand":
        return predict_demand(payload)
    if tool_name == "generate_purchase_order":
        return generate_purchase_order(payload)
    if tool_name == "send_notification":
        return send_notification(payload)
    if tool_name == "update_inventory_count":
        return update_inventory_count(payload)

    raise ValidationError(f"No implementation registered for tool '{tool_name}'.")


__all__ = [
    "ALLOWED_TOOL_NAMES",
    "execute_allowed_tool",
    "query_stock_levels",
    "query_historical_usage",
    "predict_demand",
    "generate_purchase_order",
    "send_notification",
    "update_inventory_count",
    "StockLevelRequest",
    "HistoricalUsageRequest",
    "DemandPredictionRequest",
    "PurchaseOrderRequest",
]
