# Action/Tool Agent Contract

## Purpose
The Action/Tool Agent decides whether the system should trigger an operational response for a tenant-level or item-level inventory risk. It returns actionable next steps, draft purchase orders, and notifications that are safe to execute or review.

## Allow-listed operational tools

The agent may call only the following tools:

- `query_stock_levels`
- `query_historical_usage`
- `predict_demand`
- `generate_purchase_order`

These are implemented in `agents/inventory_tools.py` and are guarded by strict validation before execution.

### `predict_demand`

Input:

```json
{
  "tenant_id": "uuid-string",
  "inventory_item_id": "uuid-string",
  "historical_usage": [
    { "date": "2026-08-01", "quantityIssued": 12 },
    { "date": "2026-08-02", "quantityIssued": 16 }
  ],
  "forecast_days": 7,
  "lead_time_days": 7,
  "safety_stock_days": 7
}
```

Output:

```json
{
  "tool": "predict_demand",
  "tenantId": "uuid-string",
  "inventoryItemId": "uuid-string",
  "forecastDays": 7,
  "predictedDailyDemand": 14.0,
  "predictedTotalDemand": 98.0,
  "safetyStock": 98.0,
  "confidence": 0.75,
  "source": "historical_usage"
}
```

### `generate_purchase_order`

Input:

```json
{
  "tenant_id": "uuid-string",
  "inventory_item_id": "uuid-string",
  "supplier_id": "uuid-string",
  "current_stock": 18,
  "reorder_level": 25,
  "predicted_demand": 98,
  "lead_time_days": 7,
  "unit_cost": 4.5,
  "safety_stock_days": 7
}
```

Output:

```json
{
  "tool": "generate_purchase_order",
  "tenantId": "uuid-string",
  "inventoryItemId": "uuid-string",
  "supplierId": "uuid-string",
  "quantity": 80,
  "priority": "high",
  "expectedDeliveryDays": 7,
  "estimatedUnitCost": 4.5,
  "notes": "Generated from demand forecast and current stock position."
}
```

## Notes
- The demand prediction tool uses historical `quantityIssued` values to estimate average daily demand and compute a safety buffer.
- The purchase order tool derives a replenishment quantity from forecast demand, safety stock, and current stock.
- All tool requests are validated before execution.
