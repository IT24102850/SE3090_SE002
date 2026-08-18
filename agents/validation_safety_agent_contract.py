from __future__ import annotations

from dataclasses import dataclass
from typing import Any, TypedDict, Literal
import re

from .inventory_tools import ValidationError, UUID_RE


RiskLevel = Literal["low", "medium", "high", "critical"]


@dataclass
class ValidationSafetyInput:
    """Input contract for the shared Validation / Safety Agent.

    Fields:
      - actionType: the canonical action the system is attempting to perform (string).
      - payload: the full action payload to be validated (opaque JSON object).
      - userRole: the role of the user requesting the action (e.g. "Admin", "Manager", "Staff").
      - tenantId: UUID of the tenant the action applies to.
      - riskLevel: one of: low, medium, high, critical — indicates the estimated risk severity.
    """

    actionType: str
    payload: dict[str, Any]
    userRole: str
    tenantId: str
    riskLevel: RiskLevel = "low"

    def validate(self) -> "ValidationSafetyInput":
        if not isinstance(self.actionType, str) or not self.actionType.strip():
            raise ValidationError("actionType is required and must be a non-empty string.")
        if not isinstance(self.payload, dict):
            raise ValidationError("payload must be a JSON object.")
        if not isinstance(self.userRole, str) or not self.userRole.strip():
            raise ValidationError("userRole is required and must be a non-empty string.")
        if not isinstance(self.tenantId, str) or not self.tenantId.strip():
            raise ValidationError("tenantId is required and must be a UUID string.")
        if not UUID_RE.match(self.tenantId.strip()):
            raise ValidationError("tenantId must be a valid UUID.")
        if self.riskLevel not in ("low", "medium", "high", "critical"):
            raise ValidationError("riskLevel must be one of: low, medium, high, critical.")
        # Normalise strings
        self.actionType = self.actionType.strip()
        self.userRole = self.userRole.strip()
        self.tenantId = self.tenantId.strip()
        return self


class AuditEntry(TypedDict):
    timestamp: str
    actorRole: str
    actionType: str
    outcome: str
    details: dict[str, Any]


class ValidationSafetyOutput(TypedDict):
    isAllowed: bool
    requiredApprovals: list[str]
    rejectionReason: str | None
    auditLog: list[AuditEntry]


# Example helpers and canonical example
EXAMPLE_INPUT = ValidationSafetyInput(
    actionType="create_purchase_order",
    payload={
        "tenant_id": "4996e172-37d2-4d40-b567-c1aa4a4c0ca5",
        "inventory_item_id": "8f2a8d44-51a2-4cb0-9b88-4b3b123d9f0a",
        "quantity": 60,
    },
    userRole="Staff",
    tenantId="4996e172-37d2-4d40-b567-c1aa4a4c0ca5",
    riskLevel="medium",
)

EXAMPLE_OUTPUT: ValidationSafetyOutput = {
    "isAllowed": False,
    "requiredApprovals": ["Manager", "Procurement"],
    "rejectionReason": None,
    "auditLog": [
        {
            "timestamp": "2026-08-18T11:00:00Z",
            "actorRole": "System",
            "actionType": "policy_check",
            "outcome": "requires_approval",
            "details": {"reason": "order over soft threshold for staff role"},
        }
    ],
}


__all__ = [
    "ValidationSafetyInput",
    "ValidationSafetyOutput",
    "AuditEntry",
    "RiskLevel",
]
