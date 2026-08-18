# Validation / Safety Agent (SHARED) Contract

Purpose
-------
The Validation/Safety Agent evaluates potentially risky actions across tenants and enforces safety policies before the system proceeds. It provides a deterministic, auditable decision and a list of required human approvals when necessary.

Input contract
--------------
A single JSON object with the following fields:

- actionType (string) — canonical action being requested (e.g. "create_purchase_order", "update_inventory_count", "adjust_reorder_level").
- payload (object) — opaque action payload the validator should inspect (must be an object).
- userRole (string) — role of the requesting user ("Admin", "Manager", "Staff", ...).
- tenantId (uuid-string) — tenant scope for the action. Required and must be a valid UUID.
- riskLevel ("low" | "medium" | "high" | "critical") — estimated risk severity for the action.

Example input

```json
{
  "actionType": "create_purchase_order",
  "payload": { "tenant_id": "4996e17...", "quantity": 200, "totalCost": 900.0 },
  "userRole": "Staff",
  "tenantId": "4996e17-37d2-4d40-b567-c1aa4a4c0ca5",
  "riskLevel": "medium"
}
```

Output contract
---------------
Returns a JSON object with:

- isAllowed (boolean) — whether the action is approved to proceed automatically.
- requiredApprovals (array[string]) — list of roles that must approve if the action is not auto-allowed (empty when isAllowed=true).
- rejectionReason (string | null) — short human-readable reason when the action is rejected outright.
- auditLog (array[object]) — chronological list of audit entries describing checks performed and the final decision. Each entry contains:
  - timestamp (ISO-8601)
  - actorRole (string) — who/what performed the check (System/PolicyEngine/Manager)
  - actionType (string)
  - outcome (string) — e.g. "ok", "requires_approval", "rejected"
  - details (object) — arbitrary details for auditing

Example output

```json
{
  "isAllowed": false,
  "requiredApprovals": ["Manager","Procurement"],
  "rejectionReason": null,
  "auditLog": [
    { "timestamp": "2026-08-18T11:00:00Z", "actorRole": "System", "actionType": "policy_check", "outcome": "requires_approval", "details": {"reason":"order over soft threshold for staff role"} }
  ]
}
```

Notes
-----
- The agent MUST validate tenantId is a UUID and that payload is an object.
- Decisions should be deterministic and based on documented policy rules (e.g., budget thresholds, user role soft/hard limits, supplier status, regulatory checks).
- The agent should always return an auditLog entry describing the checks performed; this aids debugging and compliance.
- Implementation must not perform side-effects (no DB writes, no messages) — it only evaluates and returns a decision and required approvals. Side-effects must be performed by the caller after approvals are collected.

Integration
-----------
- This contract is intended to be used by any action-orchestration component (Action/Tool Agent, UI workflows, backend API) before performing a high-risk operation.
- The Validation/Safety Agent should be sharable and stateless; callers supply the full action payload and context.
