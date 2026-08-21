from __future__ import annotations

from datetime import datetime
from typing import Any

# Support running as package or as standalone script: try relative imports then fall back to absolute
try:
    from .validation_safety_agent_contract import (
        ValidationSafetyInput,
        ValidationSafetyOutput,
        AuditEntry,
    )
    from .inventory_tools import ValidationError
except Exception:
    from validation_safety_agent_contract import (
        ValidationSafetyInput,
        ValidationSafetyOutput,
        AuditEntry,
    )
    from inventory_tools import ValidationError


ROLE_LEVELS = {
    "Staff": 10,
    "Manager": 50,
    "Procurement": 60,
    "Admin": 100,
}

# Minimum role required for some actions (inclusive)
ACTION_MIN_ROLE = {
    "create_purchase_order": "Manager",
    "generate_purchase_order": "Manager",
    "update_inventory_count": "Staff",
    "send_notification": "Staff",
    "apply_discount": "Manager",
    "schedule_appointment": "Staff",
}

# Required fields per action for basic schema validation
ACTION_REQUIRED_FIELDS = {
    "create_purchase_order": ["tenant_id", "inventory_item_id", "quantity"],
    "generate_purchase_order": ["tenant_id", "inventory_item_id", "quantity", "totalCost"],
    "update_inventory_count": ["tenant_id", "inventory_item_id", "new_count"],
    "send_notification": ["tenant_id", "channel", "title", "message"],
    "apply_discount": ["tenant_id", "invoice_id", "discount_percentage"],
    "schedule_appointment": ["tenant_id", "appointment_id", "duration_minutes"],
}


def _now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"


def _make_audit(actionType: str, actorRole: str, outcome: str, details: dict[str, Any] | None = None) -> AuditEntry:
    return {
        "timestamp": _now_iso(),
        "actorRole": actorRole,
        "actionType": actionType,
        "outcome": outcome,
        "details": details or {},
    }


def evaluate_validation_safety(payload: ValidationSafetyInput) -> ValidationSafetyOutput:
    """Evaluate ValidationSafetyInput and return ValidationSafetyOutput.

    Rules implemented:
    - role-based permission checks using ACTION_MIN_ROLE and ROLE_LEVELS
    - schema validation (required fields present)
    - business-rule compliance:
      * apply_discount: discount_percentage <= 20
      * schedule_appointment: duration_minutes <= 120 (2 hours)
    - safe-failure fallback: on unexpected exception return isAllowed=False, requiredApprovals=['Admin'], rejectionReason set, and auditLog contains exception details
    """
    audit_log: list[AuditEntry] = []

    try:
        # Basic validation of input
        if not isinstance(payload, ValidationSafetyInput):
            raise ValidationError("Invalid input type for validation agent.")
        payload.validate()
        audit_log.append(_make_audit("input_validation", "System", "ok", {"userRole": payload.userRole}))

        action = payload.actionType
        user_role = payload.userRole

        # Schema validation
        required = ACTION_REQUIRED_FIELDS.get(action)
        if required:
            missing = [f for f in required if f not in payload.payload]
            if missing:
                reason = f"invalid_schema: missing fields {missing}"
                audit_log.append(_make_audit("schema_check", "System", "rejected", {"missing": missing}))
                return {
                    "isAllowed": False,
                    "requiredApprovals": [],
                    "rejectionReason": reason,
                    "auditLog": audit_log,
                }

        # Role check
        min_role = ACTION_MIN_ROLE.get(action)
        if min_role:
            user_level = ROLE_LEVELS.get(user_role, 0)
            min_level = ROLE_LEVELS.get(min_role, 0)
            if user_level < min_level:
                # Not allowed automatically; require approval from min_role
                audit_log.append(_make_audit("role_check", "System", "requires_approval", {"userRole": user_role, "required": min_role}))
                return {
                    "isAllowed": False,
                    "requiredApprovals": [min_role],
                    "rejectionReason": None,
                    "auditLog": audit_log,
                }

        # Business rules
        if action == "apply_discount":
            try:
                disc = float(payload.payload.get("discount_percentage"))
            except Exception:
                audit_log.append(_make_audit("business_check", "System", "rejected", {"reason": "discount not numeric"}))
                return {"isAllowed": False, "requiredApprovals": [], "rejectionReason": "invalid_schema: discount_percentage must be numeric", "auditLog": audit_log}
            if disc > 20.0:
                audit_log.append(_make_audit("business_check", "System", "rejected", {"discount": disc}))
                return {"isAllowed": False, "requiredApprovals": [], "rejectionReason": "discount_exceeds_maximum", "auditLog": audit_log}
            audit_log.append(_make_audit("business_check", "System", "ok", {"discount": disc}))

        if action == "schedule_appointment":
            try:
                dur = float(payload.payload.get("duration_minutes"))
            except Exception:
                audit_log.append(_make_audit("business_check", "System", "rejected", {"reason": "duration not numeric"}))
                return {"isAllowed": False, "requiredApprovals": [], "rejectionReason": "invalid_schema: duration_minutes must be numeric", "auditLog": audit_log}
            if dur > 120.0:
                audit_log.append(_make_audit("business_check", "System", "rejected", {"duration_minutes": dur}))
                return {"isAllowed": False, "requiredApprovals": [], "rejectionReason": "appointment_too_long", "auditLog": audit_log}
            audit_log.append(_make_audit("business_check", "System", "ok", {"duration_minutes": dur}))

        # If reached here, allowed
        audit_log.append(_make_audit("final_decision", "PolicyEngine", "ok", {"action": action}))
        return {"isAllowed": True, "requiredApprovals": [], "rejectionReason": None, "auditLog": audit_log}

    except Exception as exc:
        # Safe-failure fallback: deny and require Admin approval, record exception
        audit_log.append(_make_audit("exception", "PolicyEngine", "rejected", {"error": str(exc)}))
        return {
            "isAllowed": False,
            "requiredApprovals": ["Admin"],
            "rejectionReason": "safety_check_failed",
            "auditLog": audit_log,
        }


__all__ = ["evaluate_validation_safety"]
