from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Literal


TriggerType = Literal[
    "low_stock",
    "stockout",
    "forecast_risk",
    "threshold_breach",
    "manual_review",
]

ActionType = Literal[
    "create_purchase_order",
    "adjust_reorder_level",
    "escalate_to_manager",
    "flag_supplier_issue",
    "notify_branch",
]

ActionPriority = Literal["low", "medium", "high", "critical"]
NotificationChannel = Literal["in_app", "email", "sms", "dashboard"]


@dataclass
class Thresholds:
    reorderLevel: float
    criticalLevel: float | None = None
    safetyStock: float | None = None
    leadTimeDays: int | None = None
    maxStock: float | None = None

    def __post_init__(self) -> None:
        if self.reorderLevel < 0:
            raise ValueError("reorderLevel must be >= 0")
        if self.criticalLevel is not None and self.criticalLevel < 0:
            raise ValueError("criticalLevel must be >= 0")
        if self.safetyStock is not None and self.safetyStock < 0:
            raise ValueError("safetyStock must be >= 0")
        if self.maxStock is not None and self.maxStock < 0:
            raise ValueError("maxStock must be >= 0")
        if self.leadTimeDays is not None and self.leadTimeDays < 0:
            raise ValueError("leadTimeDays must be >= 0")


@dataclass
class ActionToolAgentInput:
    """Input payload sent to the Action/Tool agent.

    Contract:
        {
          "triggerType": "low_stock" | "stockout" | "forecast_risk" | "threshold_breach" | "manual_review",
          "inventoryItemId": "string or null",
          "tenantId": "string",
          "thresholds": {
            "reorderLevel": 0,
            "criticalLevel": 0,
            "safetyStock": 0,
            "leadTimeDays": 7,
            "maxStock": 0
          }
        }
    """

    triggerType: TriggerType
    tenantId: str
    thresholds: Thresholds
    inventoryItemId: str | None = None

    def __post_init__(self) -> None:
        if not self.tenantId:
            raise ValueError("tenantId is required")

        item_based_triggers = {"low_stock", "stockout", "forecast_risk", "threshold_breach"}
        if self.triggerType in item_based_triggers and not self.inventoryItemId:
            raise ValueError(f"inventoryItemId is required for triggerType='{self.triggerType}'")


@dataclass
class ActionRecommendation:
    actionType: ActionType
    itemId: str | None = None
    priority: ActionPriority = "medium"
    reason: str = ""
    recommendedQuantity: float | None = None
    targetBranchId: str | None = None
    dueAt: str | None = None
    confidence: float = 0.0

    def __post_init__(self) -> None:
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError("confidence must be between 0 and 1")


@dataclass
class PurchaseOrderDraft:
    supplierId: str
    itemId: str
    quantity: float
    priority: ActionPriority = "medium"
    expectedDeliveryDays: int | None = None
    estimatedUnitCost: float | None = None
    notes: str | None = None

    def __post_init__(self) -> None:
        if self.quantity <= 0:
            raise ValueError("quantity must be > 0")


@dataclass
class NotificationDraft:
    channel: NotificationChannel
    title: str
    message: str
    priority: ActionPriority = "medium"
    targetRole: str | None = None
    tenantId: str | None = None


@dataclass
class ActionToolAgentOutput:
    """Output payload returned by the Action/Tool agent.

    Contract:
        {
          "actions": [ ... ],
          "purchaseOrders": [ ... ],
          "notifications": [ ... ],
          "confidenceScore": 0.87
        }
    """

    actions: list[ActionRecommendation] = field(default_factory=list)
    purchaseOrders: list[PurchaseOrderDraft] = field(default_factory=list)
    notifications: list[NotificationDraft] = field(default_factory=list)
    confidenceScore: float = 0.0

    def __post_init__(self) -> None:
        if not 0.0 <= self.confidenceScore <= 1.0:
            raise ValueError("confidenceScore must be between 0 and 1")

    def to_dict(self) -> dict[str, Any]:
        return {
            "actions": [asdict(item) for item in self.actions],
            "purchaseOrders": [asdict(item) for item in self.purchaseOrders],
            "notifications": [asdict(item) for item in self.notifications],
            "confidenceScore": self.confidenceScore,
        }


EXAMPLE_INPUT = {
    "triggerType": "low_stock",
    "inventoryItemId": "8f2a8d44-51a2-4cb0-9b88-4b3b123d9f0a",
    "tenantId": "4996e172-37d2-4d40-b567-c1aa4a4c0ca5",
    "thresholds": {
        "reorderLevel": 25,
        "criticalLevel": 10,
        "safetyStock": 12,
        "leadTimeDays": 7,
        "maxStock": 120,
    },
}


EXAMPLE_OUTPUT = {
    "actions": [
        {
            "actionType": "create_purchase_order",
            "itemId": "8f2a8d44-51a2-4cb0-9b88-4b3b123d9f0a",
            "priority": "high",
            "reason": "Inventory is below the reorder threshold and a replenishment order is needed.",
            "recommendedQuantity": 60,
            "targetBranchId": "3c8fdf67-92ef-4f5a-9f6a-3b3596bb74c2",
            "dueAt": "2026-08-18T09:00:00Z",
            "confidence": 0.93,
        }
    ],
    "purchaseOrders": [
        {
            "supplierId": "9a8c9e58-3553-40db-8a92-34dac78e5d4f",
            "itemId": "8f2a8d44-51a2-4cb0-9b88-4b3b123d9f0a",
            "quantity": 60,
            "priority": "high",
            "expectedDeliveryDays": 5,
            "estimatedUnitCost": 4.5,
            "notes": "Replenishment order for low-stock risk.",
        }
    ],
    "notifications": [
        {
            "channel": "in_app",
            "title": "Low stock alert",
            "message": "Item 8f2a... is below reorder level. Reorder recommended.",
            "priority": "high",
            "targetRole": "Manager",
            "tenantId": "4996e172-37d2-4d40-b567-c1aa4a4c0ca5",
        }
    ],
    "confidenceScore": 0.93,
}
