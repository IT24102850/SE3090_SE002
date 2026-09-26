"""Four-step inventory replenishment workflow: plan, inspect, recommend, validate."""
from __future__ import annotations

import math
import os
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field

from llm_client import AgentSafeFailure, generate_structured
from schemas.contracts import InventoryHealthInsight, InventoryRecommendation
from tools.inventory_tools import InventoryToolsClient


class InventoryPlan(BaseModel):
    summary: str
    lead_time_days: int = Field(ge=1, le=90)
    safety_days: int = Field(ge=0, le=60)
    used_fallback: bool = False


class InventoryPlanSummary(BaseModel):
    summary: str


class DomainSnapshot(BaseModel):
    items: list[dict[str, Any]] = Field(default_factory=list)
    movements: list[dict[str, Any]] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


def plan_inventory(objective: str) -> InventoryPlan:
    try:
        generated = generate_structured(
            system_instruction=(
                "You coordinate inventory replenishment analysis. Summarize the user's objective in "
                "one practical sentence. Do not claim to know stock, usage, supplier lead times, prices, "
                "or business policies. Return only the schema."
            ),
            user_content=f"Inventory planning objective: {objective}",
            response_schema=InventoryPlanSummary,
            model=os.getenv(
                "GEMINI_MODEL_INVENTORY",
                os.getenv("GEMINI_MODEL_PLANNER", os.getenv("GEMINI_MODEL_DEFAULT", "gemini-2.5-flash")),
            ),
        )
        summary = generated.summary
    except AgentSafeFailure:
        # Inventory recommendations are calculated from authorized stock and
        # movement data below; Gemini only phrases the planning summary. Keep
        # this workflow useful when Gemini credentials, connectivity, quota,
        # or response generation are unavailable. Surface the fallback in the
        # trace rather than failing an otherwise usable inventory analysis.
        summary = f"Inventory replenishment review for: {objective.strip() or 'low-stock items'}."
        used_fallback = True
    else:
        used_fallback = False
    return InventoryPlan(
        summary=summary,
        lead_time_days=int(os.getenv("INVENTORY_DEFAULT_LEAD_TIME_DAYS", "7")),
        safety_days=int(os.getenv("INVENTORY_DEFAULT_SAFETY_DAYS", "7")),
        used_fallback=used_fallback,
    )


def analyze_inventory_domain(
    *, objective: str, branch_id: str | None, client: InventoryToolsClient
) -> DomainSnapshot:
    # The analyst reads through the existing API using the caller-scoped
    # token. Keep records out of the LLM response entirely so it cannot
    # truncate or alter quantities before the calculation step.
    inventory_response = client.query_inventory(branch_id)
    movements = client.query_stock_movements(branch_id)
    items = inventory_response.get("items")
    if not isinstance(items, list) or not isinstance(movements, list):
        raise ValueError("The inventory API returned an unreadable stock snapshot.")
    return DomainSnapshot(
        items=items,
        movements=movements,
        warnings=["Inventory snapshot is limited to the first 100 items."] if inventory_response.get("totalCount", len(items)) > len(items) else [],
    )


def _recent_outflow(movements: list[dict[str, Any]]) -> dict[str, tuple[float, int, int]]:
    """Return SKU -> total outflow, age of oldest sample event, event count."""
    outflow: dict[str, tuple[float, int, int]] = {}
    now = datetime.now(timezone.utc)
    for movement in movements:
        kind = str(movement.get("movementType", "")).strip().lower()
        if kind not in {"issue", "issued", "sale", "sold", "consume", "consumed", "usage", "outflow", "adjustment"}:
            continue
        raw_quantity = float(movement.get("quantity") or 0)
        if kind == "adjustment" and raw_quantity >= 0:
            continue
        try:
            occurred = datetime.fromisoformat(str(movement.get("occurredAt", "")).replace("Z", "+00:00"))
            if occurred.tzinfo is None:
                occurred = occurred.replace(tzinfo=timezone.utc)
            age_days = (now - occurred).total_seconds() / 86400
            if age_days < 0 or age_days > 30:
                continue
            age = max(1, int(age_days))
        except (TypeError, ValueError):
            continue
        sku = str(movement.get("sku", ""))
        quantity = abs(raw_quantity)
        if not sku or quantity <= 0:
            continue
        old_quantity, old_age, old_count = outflow.get(sku, (0.0, 0, 0))
        outflow[sku] = (old_quantity + quantity, max(old_age, age), old_count + 1)
    return outflow


def _demand_trends(movements: list[dict[str, Any]]) -> list[tuple[str, float]]:
    """Compare seven recent days with the preceding 23 days; require evidence in both windows."""
    now = datetime.now(timezone.utc)
    windows: dict[str, list[float]] = {}
    for movement in movements:
        kind = str(movement.get("movementType", "")).strip().lower()
        if kind not in {"issue", "issued", "sale", "sold", "consume", "consumed", "usage", "outflow", "adjustment"}:
            continue
        quantity = float(movement.get("quantity") or 0)
        if kind == "adjustment" and quantity >= 0:
            continue
        try:
            occurred = datetime.fromisoformat(str(movement.get("occurredAt", "")).replace("Z", "+00:00"))
            if occurred.tzinfo is None:
                occurred = occurred.replace(tzinfo=timezone.utc)
            age = (now - occurred).total_seconds() / 86400
        except (TypeError, ValueError):
            continue
        sku = str(movement.get("sku", ""))
        if not sku or quantity == 0 or age < 0 or age > 30:
            continue
        totals = windows.setdefault(sku, [0.0, 0.0])
        totals[0 if age <= 7 else 1] += abs(quantity)
    trends = []
    for sku, (recent, previous) in windows.items():
        if recent <= 0 or previous <= 0:
            continue
        change = (recent / 7 - previous / 23) / (previous / 23)
        if abs(change) >= 0.30:
            trends.append((sku, change))
    return sorted(trends, key=lambda row: abs(row[1]), reverse=True)


def _latest_supplier_lead_times(
    movements: list[dict[str, Any]], items: list[dict[str, Any]] | None = None,
) -> dict[str, tuple[int, str | None, str]]:
    """Prefer the explicitly assigned supplier; otherwise use the latest linked receipt."""
    latest: dict[str, tuple[datetime, int, str | None]] = {}
    receipt_types = {"receive", "received", "purchasereceived"}
    for movement in movements:
        if str(movement.get("movementType", "")).strip().lower() not in receipt_types:
            continue
        if not movement.get("supplierId"):
            continue
        try:
            days = int(movement.get("supplierLeadTimeDays"))
            occurred = datetime.fromisoformat(str(movement.get("occurredAt", "")).replace("Z", "+00:00"))
            if occurred.tzinfo is None:
                occurred = occurred.replace(tzinfo=timezone.utc)
        except (TypeError, ValueError):
            continue
        if days < 1 or days > 90:
            continue
        sku = str(movement.get("sku", ""))
        if not sku:
            continue
        current = latest.get(sku)
        if current is None or occurred > current[0]:
            name = str(movement.get("supplierName", "")).strip() or None
            latest[sku] = (occurred, days, name)
    result = {sku: (days, name, "latest supplier-linked receipt") for sku, (_, days, name) in latest.items()}
    for item in items or []:
        sku = str(item.get("sku", ""))
        if not sku or not item.get("supplierId"):
            continue
        try:
            days = int(item.get("supplierLeadTimeDays"))
        except (TypeError, ValueError):
            continue
        if 1 <= days <= 90:
            name = str(item.get("supplierName", "")).strip() or None
            result[sku] = (days, name, "assigned inventory supplier")
    return result


def analyze_inventory_health(
    *, snapshot: DomainSnapshot, plan: InventoryPlan, recommendations: list[InventoryRecommendation]
) -> list[InventoryHealthInsight]:
    """Create transparent portfolio insights from the same read-only snapshot."""
    items = snapshot.items
    movements = snapshot.movements
    outflow = _recent_outflow(movements)
    item_by_sku = {str(item.get("sku", "")): item for item in items if item.get("sku")}
    low_items = [item for item in items if float(item.get("quantity") or 0) <= float(item.get("reorderLevel") or 0)]
    insights: list[InventoryHealthInsight] = [InventoryHealthInsight(
        category="overview",
        title="Inventory snapshot",
        detail=(
            f"Reviewed {len(items)} active inventory items. {len(low_items)} are at or below their reorder level; "
            f"{len(recommendations)} items are recommended for replenishment based on current stock and available usage history."
        ),
        affected_items=[str(item.get("name", "Inventory item")) for item in low_items[:8]],
    )]

    no_outflow = [
        item for item in items
        if float(item.get("quantity") or 0) > 0 and str(item.get("sku", "")) not in outflow
    ]
    if no_outflow:
        insights.append(InventoryHealthInsight(
            category="data_quality",
            title="Items without recorded outflow",
            detail=(
                f"{len(no_outflow)} stocked items have no qualifying issue, sale, consumption, or negative-adjustment "
                "movement in the recent movement sample. Check whether movement history is complete before making demand or excess-stock decisions."
            ),
            affected_items=[str(item.get("name", "Inventory item")) for item in no_outflow[:8]],
        ))

    coverage_rows: list[tuple[float, str, float]] = []
    for sku, (quantity, oldest_age, _) in outflow.items():
        item = item_by_sku.get(sku)
        if not item:
            continue
        daily = quantity / min(30, max(7, oldest_age))
        if daily <= 0:
            continue
        on_hand = float(item.get("quantity") or 0)
        reorder = float(item.get("reorderLevel") or 0)
        days_to_reorder = max(0.0, (on_hand - reorder) / daily)
        days_of_stock = on_hand / daily
        coverage_rows.append((days_to_reorder, str(item.get("name", "Inventory item")), days_of_stock))
    coverage_rows.sort(key=lambda row: row[0])
    if coverage_rows:
        shortest = coverage_rows[:5]
        descriptions = [f"{name}: about {days:.1f} days of stock" for _, name, days in shortest]
        insights.append(InventoryHealthInsight(
            category="coverage",
            title="Stock coverage from recorded outflow",
            detail=(
                "; ".join(descriptions)
                + f". Compare these estimates with the assumed {plan.lead_time_days}-day lead time and {plan.safety_days}-day safety buffer."
            ),
            affected_items=[name for _, name, _ in shortest],
        ))

    # Long stock cover can tie up cash. Treat this as a review signal only,
    # since demand is based on a bounded recent movement sample.
    try:
        slow_cover_days = min(365, max(1, int(os.getenv("INVENTORY_SLOW_MOVING_COVER_DAYS", "60"))))
    except ValueError:
        slow_cover_days = 60
    slow_movers = []
    for sku, (quantity, oldest_age, event_count) in outflow.items():
        item = item_by_sku.get(sku)
        if not item or event_count < 2:
            continue
        daily = quantity / min(30, max(7, oldest_age))
        on_hand = float(item.get("quantity") or 0)
        if daily > 0 and on_hand > 0 and on_hand / daily >= slow_cover_days:
            slow_movers.append((on_hand / daily, item, sku))
    slow_movers.sort(key=lambda row: row[0], reverse=True)
    if slow_movers:
        names = [str(item.get("name", sku)) for _, item, sku in slow_movers[:8]]
        value = sum(float(item.get("quantity") or 0) * float(item.get("unitCost") or 0)
                    for _, item, _ in slow_movers if item.get("unitCost") is not None)
        detail = (
            f"{len(slow_movers)} items have estimated stock cover of at least {slow_cover_days} days based on recent recorded outflow. "
            "Check upcoming demand, expiry and branch transfers before reordering or reducing stock."
        )
        priced = sum(1 for _, item, _ in slow_movers if item.get("unitCost") is not None)
        if priced:
            detail += f" Their priced on-hand value is about {value:,.2f} across {priced} items."
        insights.append(InventoryHealthInsight(
            category="excess", title="Potential slow-moving stock", detail=detail, affected_items=names,
        ))

    # Flag time-sensitive replenishment candidates where recorded demand exists.
    supplier_lead_times = _latest_supplier_lead_times(movements, items)
    at_risk = []
    for recommendation in recommendations:
        if recommendation.days_until_reorder is None or recommendation.avg_daily_outflow is None:
            continue
        lead = supplier_lead_times.get(recommendation.sku, (plan.lead_time_days, None, ""))[0]
        if recommendation.days_until_reorder <= lead:
            at_risk.append((recommendation.days_until_reorder, recommendation.item_name, lead))
    if at_risk:
        at_risk.sort()
        insights.append(InventoryHealthInsight(
            category="risk", title="Reorder review may be time-sensitive",
            detail=("These items are projected to reach their reorder level within their supplier lead time: "
                    + "; ".join(f"{name} in about {days:.1f} days (lead time {lead} days)" for days, name, lead in at_risk[:8])
                    + ". Review supplier availability and budget promptly."),
            affected_items=[name for _, name, _ in at_risk[:8]],
        ))

    trends = _demand_trends(movements)
    if trends:
        descriptions = []
        for sku, change in trends[:8]:
            item = item_by_sku.get(sku)
            if item:
                direction = "increased" if change > 0 else "decreased"
                descriptions.append(f"{item.get('name', sku)}: recorded daily outflow {direction} about {abs(change) * 100:.0f}%")
        if descriptions:
            insights.append(InventoryHealthInsight(
                category="trend",
                title="Recent demand trend",
                detail=("Compared the last 7 days with the preceding 23 days. " + "; ".join(descriptions)
                        + ". This is a short-term signal from recorded movements, not a seasonal forecast."),
                affected_items=[item_by_sku[sku].get("name", sku) for sku, change in trends[:8] if sku in item_by_sku],
            ))

    waste_by_sku: dict[str, float] = {}
    for movement in movements:
        if str(movement.get("movementType", "")).strip().lower() not in {"waste", "wastage", "writeoff", "write-off"}:
            continue
        sku = str(movement.get("sku", ""))
        if sku:
            waste_by_sku[sku] = waste_by_sku.get(sku, 0.0) + abs(float(movement.get("quantity") or 0))
    if waste_by_sku:
        waste_items = [(item_by_sku[sku].get("name", sku), quantity) for sku, quantity in waste_by_sku.items() if sku in item_by_sku]
        waste_units = sum(quantity for _, quantity in waste_items)
        insights.append(InventoryHealthInsight(
            category="movement",
            title="Recorded waste movements",
            detail=f"The recent movement sample contains {waste_units:g} units of waste/write-off across {len(waste_items)} items. Review repeated waste records and handling practices.",
            affected_items=[str(name) for name, _ in waste_items[:8]],
        ))

    priced_items = [item for item in items if item.get("unitCost") is not None]
    if priced_items:
        estimated_value = sum(float(item.get("quantity") or 0) * float(item.get("unitCost") or 0) for item in priced_items)
        insights.append(InventoryHealthInsight(
            category="cost",
            title="Estimated value of priced stock",
            detail=f"Current on-hand value is approximately {estimated_value:,.2f} across {len(priced_items)} items with unit costs recorded. Items without unit cost are excluded.",
        ))
    return insights


def recommend_replenishment(
    *, snapshot: DomainSnapshot, plan: InventoryPlan, objective: str, workflow_id: str
) -> list[InventoryRecommendation]:
    # Use only explicit consumption/issue/sale and negative adjustments as demand.
    outflow = _recent_outflow(snapshot.movements)
    daily_outflow = {
        sku: quantity / min(30, max(7, oldest_age))
        for sku, (quantity, oldest_age, _) in outflow.items()
    }
    supplier_lead_times = _latest_supplier_lead_times(snapshot.movements, snapshot.items)

    recommendations: list[InventoryRecommendation] = []
    for item in snapshot.items:
        on_hand = float(item.get("quantity") or 0)
        reorder = float(item.get("reorderLevel") or 0)
        sku = str(item.get("sku", ""))
        supplier_lead_time = supplier_lead_times.get(sku)
        lead_time_days = supplier_lead_time[0] if supplier_lead_time else plan.lead_time_days
        supplier_name = supplier_lead_time[1] if supplier_lead_time else None
        supplier_lead_time_source = supplier_lead_time[2] if supplier_lead_time else None
        daily = daily_outflow.get(sku)
        needs_reorder = on_hand <= reorder
        days_until_reorder = max(0, (on_hand - reorder) / daily) if daily and daily > 0 else None
        if not needs_reorder and (days_until_reorder is None or days_until_reorder > lead_time_days):
            continue

        target = max(reorder, daily * (lead_time_days + plan.safety_days) if daily else reorder)
        quantity = max(0, math.ceil(target - on_hand))
        if quantity <= 0:
            continue
        price_raw = item.get("unitCost")
        price = float(price_raw) if price_raw is not None else None
        notes: list[str] = []
        if daily is None:
            notes.append("No recent issue/sale/consumption or negative-adjustment history found; quantity uses the configured reorder level only.")
            confidence = 0.45
        else:
            notes.append("Outflow rate uses recent issue/sale/consumption and negative manual-adjustment movements; waste and positive corrections were excluded.")
            _, _, event_count = outflow[sku]
            confidence = 0.75 if event_count >= 5 and len(snapshot.movements) < 100 else 0.55 if event_count >= 2 else 0.4
        if supplier_lead_time:
            notes.append(f"Uses the configured {lead_time_days}-day lead time for {supplier_name or 'the supplier'} from the {supplier_lead_time_source}.")
        else:
            notes.append(f"No supplier-linked receipt with lead-time data was found; uses the configured {plan.lead_time_days}-day default.")
        if not item.get("branchId"):
            notes.append("Item has no assigned branch; choose a branch before creating a purchase order.")
            confidence = min(confidence, 0.4)
        reason = (
            f"On hand is {on_hand:g} against reorder level {reorder:g}. "
            + (f"Recent recorded outflow averages {daily:.2f} per day; stock is projected to reach the reorder level in {days_until_reorder:.1f} days. " if daily else "No reliable daily usage rate is recorded. ")
            + f"Suggested quantity {quantity:g} covers the reorder target and {lead_time_days}-day lead time plus {plan.safety_days} safety days."
        )
        recommendations.append(InventoryRecommendation(
            inventory_item_id=str(item.get("id", "")),
            item_name=str(item.get("name", "Inventory item")),
            sku=sku,
            branch_id=str(item["branchId"]) if item.get("branchId") else None,
            branch_name=item.get("branch"),
            on_hand=on_hand,
            reorder_level=reorder,
            avg_daily_outflow=round(daily, 2) if daily is not None else None,
            days_until_reorder=round(days_until_reorder, 1) if days_until_reorder is not None else None,
            recommended_quantity=quantity,
            estimated_unit_cost=price,
            estimated_total_cost=round(quantity * price, 2) if price is not None else None,
            confidence=confidence,
            reason=reason,
            validation_notes=notes + ["Read-only recommendation; no stock or purchase order was changed."],
        ))
    return sorted(recommendations, key=lambda row: (row.days_until_reorder if row.days_until_reorder is not None else 9999, row.item_name.lower()))
