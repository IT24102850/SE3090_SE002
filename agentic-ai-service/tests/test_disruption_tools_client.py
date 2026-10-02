"""The HTTP layer of the disruption toolbox.

test_disruption_copilot.py drives the agents through a fake toolbox, which is
the right shape for testing agent behaviour but means the real client's
contract with the API is never exercised. These tests cover that seam, because
a mismatch there surfaces as "'str' object has no attribute 'get'" raised deep
inside an agent, nowhere near the endpoint that actually caused it.
"""

import httpx
import pytest

from tools.disruption_tools import DisruptionToolsClient, ToolError, _as_items


def client_returning(handler) -> DisruptionToolsClient:
    """A real client whose transport is stubbed, so routing and parsing run."""
    tools = DisruptionToolsClient(base_url="http://api.test", auth_token="t")
    tools._client = httpx.Client(
        base_url="http://api.test",
        transport=httpx.MockTransport(handler),
    )
    return tools


class TestAsItems:
    def test_unwraps_a_paged_envelope(self):
        assert _as_items({"items": [{"id": "r1"}], "total": 1, "page": 1}) == [{"id": "r1"}]

    def test_passes_a_bare_array_through(self):
        assert _as_items([{"id": "r1"}]) == [{"id": "r1"}]

    def test_an_envelope_without_items_is_empty_not_its_keys(self):
        # The original bug: iterating the dict yielded "total", "page", ...
        assert _as_items({"total": 0, "page": 1, "pageSize": 20}) == []

    @pytest.mark.parametrize("payload", [None, "unexpected", 7])
    def test_a_non_collection_is_empty_rather_than_a_crash(self, payload):
        assert _as_items(payload) == []

    def test_drops_entries_that_are_not_records(self):
        assert _as_items([{"id": "r1"}, "junk", None]) == [{"id": "r1"}]


class TestListResources:
    def test_unwraps_the_envelope_the_api_actually_sends(self):
        tools = client_returning(lambda request: httpx.Response(
            200, json={"items": [{"id": "r1", "name": "Morning Cruise"}], "total": 1,
                       "page": 1, "pageSize": 100, "totalPages": 1},
        ))

        resources = tools.list_resources("tenant-1")

        # Every caller does record.get(...), so records are what must come back.
        assert [r.get("name") for r in resources] == ["Morning Cruise"]

    def test_asks_for_more_than_one_page_of_candidates(self):
        seen: dict[str, str] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen.update(request.url.params)
            return httpx.Response(200, json={"items": []})

        client_returning(handler).list_resources("tenant-1", branch_id="b1")

        # A substitute on page two is a substitute never offered.
        assert seen["pageSize"] == "100"
        assert seen["tenantId"] == "tenant-1"
        assert seen["branchId"] == "b1"

    def test_an_http_error_is_a_tool_error(self):
        tools = client_returning(lambda request: httpx.Response(500, json={"message": "boom"}))

        with pytest.raises(ToolError):
            tools.list_resources("tenant-1")

    def test_the_call_is_recorded_for_the_trace(self):
        tools = client_returning(lambda request: httpx.Response(200, json={"items": []}))
        tools.current_agent = "RecoveryActionAgent"

        tools.list_resources("tenant-1")

        assert [(c["tool"], c["agent"], c["success"]) for c in tools.calls] == [
            ("list_resources", "RecoveryActionAgent", True),
        ]


class TestBookingCollections:
    def test_affected_bookings_survive_an_envelope_too(self):
        tools = client_returning(lambda request: httpx.Response(
            200, json={"items": [{"bookingId": "b1"}], "total": 1},
        ))

        assert tools.list_affected_bookings("r1", "2026-10-02", "2026-10-09") == [{"bookingId": "b1"}]

    def test_detect_conflicts_survives_an_envelope_too(self):
        tools = client_returning(lambda request: httpx.Response(
            200, json={"items": [{"bookingId": "b1"}], "total": 1},
        ))

        assert tools.detect_conflicts("r1", "2026-10-02", "2026-10-09") == [{"bookingId": "b1"}]
