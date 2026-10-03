from datetime import datetime, timedelta, timezone

from agents.inventory_agents import (
    DomainSnapshot,
    InventoryPlan,
    analyze_inventory_domain,
    analyze_inventory_health,
    recommend_replenishment,
)
from tools.inventory_tools import InventoryToolsClient


def _item(*, quantity: float, reorder: float = 10) -> dict:
    return {
        "id": "8cfab184-8704-4ae0-93eb-1ffbf977e840",
        "name": "Paper towels",
        "sku": "PAPER-01",
        "branchId": "288cb8d5-4742-4b64-af40-601db44d9550",
        "branch": "Main",
        "quantity": quantity,
        "reorderLevel": reorder,
        "unitCost": 25,
    }


def _plan() -> InventoryPlan:
    return InventoryPlan(summary="Review stock replenishment.", lead_time_days=7, safety_days=7)


def _movement(kind: str, quantity: float, *, days_ago: int = 14) -> dict:
    occurred = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return {"sku": "PAPER-01", "movementType": kind, "quantity": quantity, "occurredAt": occurred.isoformat()}


def test_recommendation_uses_negative_mobile_issue_adjustments_and_excludes_waste_and_positive_counts():
    snapshot = DomainSnapshot(
        items=[_item(quantity=5, reorder=10)],
        movements=[
            _movement("Adjustment", -14),
            _movement("Adjustment", 100),
            _movement("Waste", -30),
            _movement("Receive", 80),
        ],
    )

    [recommendation] = recommend_replenishment(snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf")

    assert recommendation.avg_daily_outflow == 1
    assert recommendation.recommended_quantity == 9
    assert "negative manual-adjustment" in recommendation.validation_notes[0]
    assert any("no stock or purchase order was changed" in note for note in recommendation.validation_notes)


def test_no_usage_history_falls_back_to_reorder_level_with_low_confidence():
    snapshot = DomainSnapshot(items=[_item(quantity=3, reorder=12)])

    [recommendation] = recommend_replenishment(snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf")

    assert recommendation.avg_daily_outflow is None
    assert recommendation.recommended_quantity == 9
    assert recommendation.confidence == 0.45
    assert "No reliable daily usage rate" in recommendation.reason


def test_projected_stock_cover_can_trigger_reorder_before_reorder_level():
    snapshot = DomainSnapshot(items=[_item(quantity=12, reorder=10)], movements=[_movement("Issue", -28)])

    [recommendation] = recommend_replenishment(snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf")

    assert recommendation.days_until_reorder == 1
    assert recommendation.recommended_quantity == 16


def test_below_reorder_point_is_not_described_as_zero_days():
    snapshot = DomainSnapshot(items=[_item(quantity=48, reorder=50)], movements=[_movement("Issue", -4)])
    [recommendation] = recommend_replenishment(
        snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf",
    )

    [risk] = [
        insight for insight in analyze_inventory_health(
            snapshot=snapshot, plan=_plan(), recommendations=[recommendation],
        )
        if insight.category == "risk"
    ]

    assert recommendation.days_until_reorder == 0
    assert "already below its reorder level (on hand 48; reorder at 50)" in recommendation.reason
    assert "0.0 days" not in recommendation.reason
    assert "Disposable" not in risk.detail
    assert "Paper towels is already below its reorder level" in risk.detail
    assert "0.0 days" not in risk.detail


def test_positive_sub_tenth_day_estimate_is_not_reported_as_zero():
    snapshot = DomainSnapshot(items=[_item(quantity=10.01, reorder=10)], movements=[_movement("Issue", -280)])
    [recommendation] = recommend_replenishment(
        snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf",
    )
    insights = analyze_inventory_health(snapshot=snapshot, plan=_plan(), recommendations=[recommendation])
    [risk] = [insight for insight in insights if insight.category == "risk"]

    assert recommendation.days_until_reorder == 0
    assert "less than 0.1 days" in risk.detail


def test_outflow_older_than_thirty_days_is_not_treated_as_recent_demand():
    snapshot = DomainSnapshot(
        items=[_item(quantity=3, reorder=10)],
        movements=[_movement("Issue", -80, days_ago=90)],
    )

    [recommendation] = recommend_replenishment(snapshot=snapshot, plan=_plan(), objective="reorder", workflow_id="wf")

    assert recommendation.avg_daily_outflow is None
    assert recommendation.recommended_quantity == 7


def test_domain_analyst_uses_authorized_api_snapshots_without_rewriting_them():
    class FakeClient:
        def query_inventory(self, branch_id):
            assert branch_id == "branch-1"
            return {"items": [_item(quantity=4)], "totalCount": 1}

        def query_stock_movements(self, branch_id):
            assert branch_id == "branch-1"
            return [_movement("Issue", -1)]

    result = analyze_inventory_domain(objective="show low stock", branch_id="branch-1", client=FakeClient())

    assert result.items[0]["quantity"] == 4
    assert result.movements[0]["quantity"] == -1


def test_stock_movement_tool_reads_paginated_inventory_api_response():
    movement = _movement("Issue", -1)
    client = InventoryToolsClient("https://example.test", "test-token")
    client._get = lambda path, params: {
        "items": [movement],
        "page": 1,
        "pageSize": 100,
        "totalCount": 1,
        "totalPages": 1,
    }
    try:
        assert client.query_stock_movements() == [movement]
    finally:
        client.close()


def test_stock_movement_tool_still_accepts_legacy_list_response():
    movement = _movement("Issue", -1)
    client = InventoryToolsClient("https://example.test", "test-token")
    client._get = lambda path, params: [movement]
    try:
        assert client.query_stock_movements() == [movement]
    finally:
        client.close()


def test_stock_movement_tool_rejects_unrecognized_response():
    client = InventoryToolsClient("https://example.test", "test-token")
    client._get = lambda path, params: {"movements": []}
    try:
        try:
            client.query_stock_movements()
        except ValueError as error:
            assert str(error) == "Inventory API returned an invalid stock movement list."
        else:
            raise AssertionError("Expected invalid stock movement response to fail.")
    finally:
        client.close()
