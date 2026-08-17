# Action/Tool Agent Contract

## Purpose
The Action/Tool Agent decides whether the system should trigger an operational response for a tenant-level or item-level inventory risk. It returns actionable next steps, draft purchase orders, and notifications that are safe to execute or review.

## Input contract

```json
{
  "triggerType": "low_stock | stockout | forecast_risk | threshold_breach | manual_review",
  "inventoryItemId": "uuid-string | null",
  "tenantId": "uuid-string",
  "thresholds": {
    "reorderLevel": 25,
    "criticalLevel": 10,
    "safetyStock": 12,
    "leadTimeDays": 7,
    "maxStock": 120
  }
}
```

### Field rules
- triggerType identifies the reason the agent was invoked.
- inventoryItemId is required for item-specific triggers such as low_stock, stockout, forecast_risk, and threshold_breach.
- tenantId scopes all recommendations to a single tenant.
- thresholds contains the operational limits the agent should compare against when generating actions.

## Output contract

```json
{
  "actions": [
    {
      "actionType": "create_purchase_order | adjust_reorder_level | escalate_to_manager | flag_supplier_issue | notify_branch",
      "itemId": "uuid-string | null",
      "priority": "low | medium | high | critical",
      "reason": "human readable rationale",
      "recommendedQuantity": 60,
      "targetBranchId": "uuid-string | null",
      "dueAt": "ISO-8601 timestamp | null",
      "confidence": 0.93
    }
  ],
  "purchaseOrders": [
    {
      "supplierId": "uuid-string",
      "itemId": "uuid-string",
      "quantity": 60,
      "priority": "low | medium | high | critical",
      "expectedDeliveryDays": 5,
      "estimatedUnitCost": 4.5,
      "notes": "optional text"
    }
  ],
  "notifications": [
    {
      "channel": "in_app | email | sms | dashboard",
      "title": "short title",
      "message": "clear message",
      "priority": "low | medium | high | critical",
      "targetRole": "Manager | Admin | Staff | null",
      "tenantId": "uuid-string | null"
    }
  ],
  "confidenceScore": 0.93
}
```

## Notes
- actions is the agent's recommended remediation list.
- purchaseOrders contains draft orders that can be handed to the purchase-order workflow.
- notifications contains user-facing alerts for supervisors or branch staff.
- confidenceScore is a scalar between 0 and 1 that summarises how certain the agent is about the recommendation set.
- The canonical Python contract lives in `agents/action_tool_agent_contract.py`.
