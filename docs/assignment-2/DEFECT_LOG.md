# Defect and Bug Report

## DEF-001 - Inventory price-edit test timed out in full frontend suite

| Field | Detail |
|---|---|
| Severity / priority | Medium / High for CI evidence reliability |
| Component | React inventory manager test |
| Reproduction | Run `cd frontend; npm run test -- --reporter=verbose` on the full suite. The asynchronous `saves a selling price for an existing uncategorized item` case exceeded Vitest's default 5-second test timeout. |
| Expected | The test completes and verifies the PUT payload and refreshed `LKR 75` row. |
| Actual before fix | 193 passed, 1 failed, failure due to 5-second timeout. A focused rerun passed in 702 ms with a longer timeout. |
| Root cause | The test performs multiple async fetch/render/confirmation/refresh transitions and was too close to the default timeout under full-suite CPU and jsdom load. |
| Fix | Added an explicit 15-second timeout to this asynchronous workflow test in `frontend/src/features/inventory/pages/InventoryManagerPage.test.tsx`. Assertions and production behavior were unchanged. |
| Retest | Full frontend suite: 22 test files, 194 tests passed, 0 failed. Frontend production build also passed. |
| Status | Closed and retested |

## Security finding SF-001 - npm dependency advisories

`npm audit --audit-level=high` initially reported four advisories, including two high severity advisories in transitive dependencies. `npm audit fix` updated the lockfile-compatible dependency tree. Retest reports `found 0 vulnerabilities`. This is recorded as remediated rather than omitted from the security evidence.

## Environment-limited findings

- Fifteen PostgreSQL/Testcontainers tests were skipped because Docker was not available during the local run. They are not counted as passes.
- Authenticated k6 scenarios and the live cross-platform workflow still require approved deployed credentials and should be demonstrated before submission.
- Existing frontend warnings about `act()` and jsdom canvas/chart layout do not currently fail tests, but should be listed as residual technical debt if screenshots are included.
