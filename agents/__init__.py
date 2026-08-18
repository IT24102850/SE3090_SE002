"""Inventory agent utilities and allow-listed tool definitions."""

from .inventory_tools import (
    ALLOWED_TOOL_NAMES,
    DemandPredictionRequest,
    HistoricalUsageRequest,
    PurchaseOrderRequest,
    StockLevelRequest,
    execute_allowed_tool,
    generate_purchase_order,
    predict_demand,
    query_historical_usage,
    query_stock_levels,
    send_notification,
    update_inventory_count,
)
from .validation_safety_agent_contract import (
    ValidationSafetyInput,
    ValidationSafetyOutput,
)

__all__ = [
    "ALLOWED_TOOL_NAMES",
    "StockLevelRequest",
    "HistoricalUsageRequest",
    "DemandPredictionRequest",
    "PurchaseOrderRequest",
    "query_stock_levels",
    "query_historical_usage",
    "predict_demand",
    "generate_purchase_order",
    "send_notification",
    "update_inventory_count",
    "execute_allowed_tool",
    "ValidationSafetyInput",
    "ValidationSafetyOutput",
]

from .validation_safety_agent import (
    evaluate_validation_safety,
)

__all__ += ["evaluate_validation_safety"]

from .agent_service import (
    app as agent_service_app,
    process_workflow,
)

__all__ += ["agent_service_app", "process_workflow"]
