# Main and Hasaranga integration — 3 October 2026

Branch: `integration/hasaranga-main-repaired-20261003`

Inputs: `main` at `1f579f6` and `hasaranga/final-update` at `fdc5c30`.

The previous integration was reverted on main. This branch reapplies that integration, merges the latest Hasaranga commits, and repairs the combined source. Main and the source branch are both ancestors of this branch; neither remote branch is changed.

## Repairs

- Consolidate relocated backend controllers under `Controllers`, combining GPS branch data, staff editing, notifications, mobile login, booking capacity, payment, and billing changes. Remove the obsolete reminder stub and the accidentally tracked `.git-push-work` Git link.
- Restore shared API definitions, dependency registrations, models, session refresh, booking history, availability slots, platform features, and live notifications that the previous integration omitted.
- Preserve the updated inventory and customer order workflows, and connect them to the mobile owner navigation. Keep Admin/Manager approval requirements for StockSense reorder decisions.
- Repair narrow-screen email/PIN layouts and update tests for the default PIN view and the taller business header.
- Reconcile the EF model snapshot, including platform add-ons already created by an existing migration. No new duplicate-table migration is introduced.
- Restore the Android build's configured deployed API URL.

## Local validation

- Frontend production build, navigation parity, and subtype registry: passed.
- Frontend tests: 238 passed across 31 files.
- Backend tests: 661 passed, 15 skipped, 0 failed.
- Agent service and shared Python tests: 220 passed.
- Flutter tests: 217 passed.
- Flutter analysis: no errors or warnings; existing deprecation/style information remains.
- EF pending-model check: no changes since the last migration.
- Git whitespace and conflict checks: passed.

The database-dependent tests reported as skipped were not exercised against a live database. No database was migrated, no application was deployed, and no Android APK build was performed locally.
