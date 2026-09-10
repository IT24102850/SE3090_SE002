import unittest
import sys
import os
import uuid

# Ensure agents directory is in Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "agents"))

from validation_safety_agent_contract import ValidationSafetyInput
from validation_safety_agent import evaluate_validation_safety
from action_tool_agent_contract import (
    ActionToolAgentInput,
    Thresholds,
    ActionToolAgentOutput,
    ActionRecommendation,
    PurchaseOrderDraft as ActionPODraft,
    NotificationDraft as ActionNotificationDraft,
)
from inventory_tools import (
    execute_allowed_tool,
    ValidationError,
    ALLOWED_TOOL_NAMES,
)


class TestAgentEvaluationGoldenCases(unittest.TestCase):
    def setUp(self):
        self.tenant_id = str(uuid.uuid4())
        self.item_id = str(uuid.uuid4())
        self.supplier_id = str(uuid.uuid4())

    # Golden Case 1: "Stock below reorder level" MUST generate PO recommendation
    def test_golden_case_stock_below_reorder_level_must_generate_po(self):
        payload = {
            "tenant_id": self.tenant_id,
            "inventory_item_id": self.item_id,
            "quantity": 50,
            "current_stock": 5.0,
            "reorder_level": 25.0,
            "unit_cost": 10.0,
            "totalCost": 500.0,
            "budget_limit": 1000.0,
        }
        val_input = ValidationSafetyInput(
            actionType="create_purchase_order",
            payload=payload,
            userRole="Manager",
            tenantId=self.tenant_id,
            riskLevel="low",
        )
        result = evaluate_validation_safety(val_input)

        self.assertTrue(result["isAllowed"], f"Stock below reorder level should be allowed to generate PO: {result}")
        self.assertEqual(len(result["requiredApprovals"]), 0)
        self.assertIsNone(result["rejectionReason"])

        # Also test tool execution
        tool_payload = {
            "tenant_id": self.tenant_id,
            "inventory_item_id": self.item_id,
            "current_stock": 5.0,
            "reorder_level": 25.0,
            "predicted_demand": 30.0,
            "lead_time_days": 7,
            "unit_cost": 10.0,
            "supplier_id": self.supplier_id,
            "budget_limit": 1000.0,
        }
        po_result = execute_allowed_tool("generate_purchase_order", tool_payload)
        self.assertEqual(po_result["tool"], "generate_purchase_order")
        self.assertGreater(po_result["quantity"], 0)
        self.assertEqual(po_result["supplierId"], self.supplier_id)

    # Golden Case 2: "PO exceeding budget" MUST require approval
    def test_golden_case_po_exceeding_budget_must_require_approval(self):
        payload = {
            "tenant_id": self.tenant_id,
            "inventory_item_id": self.item_id,
            "quantity": 500,
            "current_stock": 5.0,
            "reorder_level": 25.0,
            "unit_cost": 100.0,
            "totalCost": 50000.0,
            "budget_limit": 5000.0,
        }
        val_input = ValidationSafetyInput(
            actionType="create_purchase_order",
            payload=payload,
            userRole="Manager",
            tenantId=self.tenant_id,
            riskLevel="medium",
        )
        result = evaluate_validation_safety(val_input)

        self.assertFalse(result["isAllowed"], "PO exceeding budget limit must not be automatically allowed.")
        self.assertIn("Manager", result["requiredApprovals"])
        self.assertIn("Procurement", result["requiredApprovals"])
        self.assertEqual(result["rejectionReason"], "po_exceeds_budget_limit")

    # Business Rule: Discount <= 20% allowed, > 20% rejected
    def test_discount_business_rule(self):
        allowed_input = ValidationSafetyInput(
            actionType="apply_discount",
            payload={"tenant_id": self.tenant_id, "invoice_id": "inv-001", "discount_percentage": 15.0},
            userRole="Manager",
            tenantId=self.tenant_id,
        )
        allowed_res = evaluate_validation_safety(allowed_input)
        self.assertTrue(allowed_res["isAllowed"], f"Expected discount 15% to be allowed: {allowed_res}")

        rejected_input = ValidationSafetyInput(
            actionType="apply_discount",
            payload={"tenant_id": self.tenant_id, "invoice_id": "inv-002", "discount_percentage": 25.0},
            userRole="Manager",
            tenantId=self.tenant_id,
        )
        rejected_res = evaluate_validation_safety(rejected_input)
        self.assertFalse(rejected_res["isAllowed"])
        self.assertEqual(rejected_res["rejectionReason"], "discount_exceeds_maximum")

    # Business Rule: Appointment <= 120 mins allowed, > 120 mins rejected
    def test_appointment_duration_business_rule(self):
        allowed_input = ValidationSafetyInput(
            actionType="schedule_appointment",
            payload={"tenant_id": self.tenant_id, "appointment_id": "apt-001", "duration_minutes": 60},
            userRole="Staff",
            tenantId=self.tenant_id,
        )
        allowed_res = evaluate_validation_safety(allowed_input)
        self.assertTrue(allowed_res["isAllowed"], f"Expected 60min appointment to be allowed: {allowed_res}")

        rejected_input = ValidationSafetyInput(
            actionType="schedule_appointment",
            payload={"tenant_id": self.tenant_id, "appointment_id": "apt-002", "duration_minutes": 180},
            userRole="Staff",
            tenantId=self.tenant_id,
        )
        rejected_res = evaluate_validation_safety(rejected_input)
        self.assertFalse(rejected_res["isAllowed"])
        self.assertEqual(rejected_res["rejectionReason"], "appointment_too_long")

    # Role-based check: Staff cannot create PO directly
    def test_role_based_permission_checks(self):
        staff_input = ValidationSafetyInput(
            actionType="create_purchase_order",
            payload={"tenant_id": self.tenant_id, "inventory_item_id": self.item_id, "quantity": 10},
            userRole="Staff",
            tenantId=self.tenant_id,
        )
        staff_res = evaluate_validation_safety(staff_input)
        self.assertFalse(staff_res["isAllowed"])
        self.assertIn("Manager", staff_res["requiredApprovals"])

    # Safe-failure fallback
    def test_safe_failure_fallback(self):
        corrupt_input = None
        result = evaluate_validation_safety(corrupt_input)
        self.assertFalse(result["isAllowed"])
        self.assertIn("Admin", result["requiredApprovals"])
        self.assertEqual(result["rejectionReason"], "safety_check_failed")
        self.assertGreater(len(result["auditLog"]), 0)

    # Allow-listed tools
    def test_allow_listed_tools(self):
        self.assertIn("query_stock_levels", ALLOWED_TOOL_NAMES)
        self.assertIn("query_historical_usage", ALLOWED_TOOL_NAMES)
        self.assertIn("predict_demand", ALLOWED_TOOL_NAMES)
        self.assertIn("generate_purchase_order", ALLOWED_TOOL_NAMES)
        self.assertIn("send_notification", ALLOWED_TOOL_NAMES)
        self.assertIn("update_inventory_count", ALLOWED_TOOL_NAMES)

        # Disallowed tool name should raise ValidationError
        with self.assertRaises(ValidationError):
            execute_allowed_tool("execute_arbitrary_shell_command", {})

    # Tool execution: predict_demand
    def test_predict_demand_tool(self):
        payload = {
            "tenant_id": self.tenant_id,
            "inventory_item_id": self.item_id,
            "historical_usage": [
                {"date": "2026-08-01", "quantityIssued": 10.0},
                {"date": "2026-08-02", "quantityIssued": 12.0},
                {"date": "2026-08-03", "quantityIssued": 8.0},
            ],
            "forecast_days": 14,
        }
        res = execute_allowed_tool("predict_demand", payload)
        self.assertEqual(res["tool"], "predict_demand")
        self.assertEqual(res["forecastDays"], 14)
        self.assertGreater(res["predictedDailyDemand"], 0)


if __name__ == "__main__":
    unittest.main()
