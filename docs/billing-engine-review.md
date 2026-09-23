# Billing & Payments Engine: Status and Improvements

Component 3 of the Universal SME Management Platform (owned by Student 2).
Branch: `feature/billing-engine` · Reviewed: 2026-09-23

This covers what is built against the assignment spec (sections 3.1–3.9),
how it was verified, and what should be improved or added next, in
priority order.

---

## 1. Summary

| Area | Status | Notes |
|---|---|---|
| Database schema (3.3) | ✅ Complete | All 9 tables, plus `invoice_templates`; migration `CompleteBillingEngine` |
| API endpoints (3.4) | ✅ Complete | All 15 spec endpoints, plus ~35 supporting endpoints |
| React screens (3.5) | ✅ Complete | 7 spec screens, plus Invoices, Commission Rules, customer "My bills" |
| Flutter screens (3.6) | ✅ Complete | 6 spec screens, plus bill detail |
| Domain Analysis Agent (3.7) | ✅ Complete | Rule-based, 5 allow-listed tools, approval gates, audit trail |
| Integrations (3.8) | 🟡 Mostly | Stripe, PayPal, SendGrid, Twilio done; **MessageBird not done** |
| Testing (3.9) | ✅ Complete | 123 backend + 38 web + 26 mobile tests, all passing |

---

## 2. What is built

### 2.1 Supported business types (3.2)

| Business type | How it is supported |
|---|---|
| Clinic / Dental | Per-visit invoices with per-treatment line items; insurance claims with policy checks and document upload |
| Restaurant / Cafe | Split payments (`PUT /invoices/{id}/split-pay`, "split evenly" in the UI); discount %/amount and discount code; tax rate |
| Gym / Fitness | Weekly/monthly/quarterly/yearly subscriptions, auto-renewal job, plan upgrade/downgrade with pro-rata invoice |
| School / Tuition | Installment schedules (`POST /invoices/schedule`), subscriptions for monthly fees |
| Real Estate | Commission rules (percentage/fixed, min/max, per role) with split calculator; milestone payment schedules |
| Tourism | Deposit + balance schedules; currency stored per invoice |
| General | Generic invoices, recurring billing engine, invoice templates |

### 2.2 Backend (`backend/SmeBackend`)

- **Services** (`Services/Billing/`):
  - `BillingService`: invoices, payments, receipts, subscriptions, claims. Customers only see their own records.
  - `PaymentCheckoutService`: gateway checkout, confirm, and verified webhooks.
  - `BillingReportService`: daily revenue, outstanding aging, dashboard.
  - `BillingSettingsService`: gateways (encrypted secrets), commission rules, invoice templates.
  - `BillingAgentService` + `BillingDomainAnalysisAgent`: the analysis agent.
  - `BillingApprovalService`: approval requests, approve/reject/apply, audit rows.
  - `BillingAutomationService`: hourly job that marks invoices overdue, renews or expires subscriptions, and sends reminders.
  - `ReceiptPdfBuilder`: dependency-free PDF that follows the tenant's invoice template.
  - `PaymentProcessors`: Stripe PaymentIntents and Checkout Sessions, PayPal Orders, and a sandbox provider.
  - `BillingMessenger`: SendGrid email and Twilio SMS/WhatsApp, simulated when not configured.
- **Security:**
  - Tenant always comes from the JWT. A mismatched `?tenantId=` returns 403.
  - Role policies on every endpoint.
  - Webhook signatures verified (Stripe HMAC, PayPal verify API).
  - Gateway keys are AES-GCM encrypted and only returned as a masked hint.
- **Approval rules (3.7):**
  - Invoice adjustment over 100: Admin.
  - Insurance claim over 500: Admin.
  - Subscription cancellation with refund: Admin.
  - An Admin acting directly is recorded as an already-approved workflow, so the audit trail has no gaps.

### 2.3 Web (`frontend/src/features/billing`)

Billing Dashboard · Invoices (create, schedule, pay, split, adjust, cancel,
send, remind, receipt/PDF) · Subscription Manager (list, renewal calendar,
cancellation requests) · Insurance Claim Tracker (drag-and-drop pipeline)
· Invoice Designer (drag-and-drop sections, live preview) · Dynamic Form
Builder (visual + JSON Schema, live preview, server check) · Payment
Gateway Settings · Billing Agent monitor (approval queue, run analysis,
audit trail) · Commission Rules · My bills (customer).

### 2.4 Mobile (`mobile/sme_mobile/lib/screens/billing`)

My Bills · Bill detail · Payment flow (Card → Stripe hosted page, QR → PayPal
or sandbox with QR code, Cash) · Receipt (view, PDF share, WhatsApp, email) ·
Subscriptions (change plan, history, cancel with refund request) ·
Insurance tracker (submit, camera/gallery upload, stage progress) · Saved
payment methods (`flutter_secure_storage`, per user, never card numbers).

### 2.5 Tests

| Suite | Count | What it covers |
|---|---|---|
| `BillingAgentGoldenCaseTests` | 40+ | Both spec golden cases, thresholds, anomalies, allow-list |
| `BillingServiceTests` | 35 | Totals, customer isolation, payments, split, approvals, subscriptions, claims, delivery, PDF |
| `InvoicesControllerTests` (Moq) | 14 | Auth, tenant check, status-code mapping, PDF file result |
| `PaymentAndAutomationTests` | 30+ | Sandbox checkout, Stripe webhooks and signatures, hosted sessions, renewals, reports |
| `BillingDatabaseIntegrationTests` | 5 | Real PostgreSQL: migrations, unique constraint, cascade, rollback, every query translates |
| Vitest (web) | 38 | Invoice form validation, payment flow, dynamic form rendering |
| flutter_test (mobile) | 26 | Payment screen, receipt viewer, secure storage, My Bills |

---

## 3. What to improve or add

Priority: **P1** = do before a real deployment · **P2** = important for
correctness or completeness · **P3** = nice to have.

### P1: Before deploying

1. **Check where the migration will run.**
   - The local user-secrets point `DefaultConnection` at the shared Supabase database, and the app auto-migrates on startup.
   - Before merging, agree with the team and apply `CompleteBillingEngine` deliberately.
   - Consider making auto-migrate opt-in outside Development.
2. **Use a dedicated encryption key for gateway secrets.**
   - Secrets are encrypted with a key derived from `Platform:SecretKey`, falling back to `Jwt:Key`.
   - If `Jwt:Key` is ever rotated, every stored Stripe/PayPal key becomes unreadable.
   - Set `Platform:SecretKey` in every environment, and document how to rotate it.
3. **Add a real return URL for hosted payments.**
   - Stripe/PayPal return to a placeholder URL today, so the customer has to come back and tap "check status" (the webhook still settles the payment).
   - Add a configurable `Billing:PublicAppUrl` for the web app and a deep link for mobile.
   - Auto-confirm when the customer lands back.
4. **Make webhooks idempotent.**
   - Duplicate or out-of-order events are handled by state checks only.
   - Store processed provider event IDs (Stripe `evt_…`, PayPal event id) in a table and skip repeats.
5. **Rate-limit the payment endpoints.**
   - Add per-user limits on `checkout` / `confirm`, and a per-IP limit on the anonymous webhook route, like the existing booking-widget limiter.

### P2: Correctness and completeness

6. **MessageBird is missing.** The spec says Twilio / MessageBird. Add an `IBillingMessenger` provider switch (`Integrations:Sms:Provider`) with a MessageBird implementation.
7. **Refunds don't reach the gateway.**
   - An approved refund is recorded as a `Refunded` payment row, but no money is returned through Stripe/PayPal.
   - Call Stripe `POST /v1/refunds` and PayPal capture refund, and store the provider refund id.
8. **Multi-currency reports.**
   - Each invoice keeps its currency, but the dashboard and daily totals add different currencies together.
   - Group every report by currency, or convert with a stored daily FX rate. Show the currency on every figure.
9. **Coupons are just a stored text code.**
   - Add a `Coupons` table (code, % or amount, validity dates, usage limit, per-customer limit).
   - Validate and apply coupons on the server.
10. **Sequential invoice numbers.**
    - Numbers are `INV-yyyyMMdd-RANDOM`. Many tax authorities (including Sri Lanka VAT) expect gap-free sequential numbers.
    - Add a per-tenant counter table with a configurable prefix.
11. **Tax rules.**
    - Tax is one rate per invoice.
    - Add per-tenant tax profiles (VAT, SSCL, service charge), per-category rates, and tax lines shown on the PDF.
12. **Invoice from booking.** When a booking is completed, raise the invoice automatically from the booking type's price. Add a tenant setting to switch this on or off.
13. **PDF limitations.**
    - The hand-written PDF uses standard Helvetica, so **Sinhala and Tamil text prints as `?`**, and there is no logo.
    - Embed a Unicode font (e.g. Noto Sans Sinhala/Tamil) and the tenant logo, or switch to a PDF library.
14. **Branch-level access.**
    - Invoices and subscriptions carry `BranchId`, but a branch manager can see every branch's billing.
    - Apply the same branch scoping the inventory module uses.
15. **Scaling the background job.**
    - `BillingAutomationService` assumes a single app instance.
    - Behind multiple instances, add a distributed lock (Postgres advisory lock) so renewals don't run twice.
16. **Reminders.** Automatic reminders are email only.
    - Add per-tenant settings: channels (SMS/WhatsApp), timing (e.g. 3 days before due, on due date, every 7 days after), and quiet hours.
17. **Push notifications.**
    - Payment received / failed / renewal events only create in-app notification rows.
    - Send FCM pushes through the existing `IPushNotificationSender`.

### P3: Nice to have

18. **LLM layer for the agent.**
    - The agent is rule-based and deterministic, which the golden cases rely on.
    - Keep the rules as the safety gate, and add an optional Gemini/Ollama summary (plain-language insights) through the existing `agentic-ai-service`.
19. **Subscription features.** Freeze/pause (the `Frozen` status exists, but there's no endpoint), trial periods, proration for cycle changes (today only same-cycle upgrades), and card-on-file auto-charge through Stripe.
20. **Insurance features.**
    - Partial approval (approved amount lower than claimed).
    - Insurer-specific document checklists.
    - Automatically reduce the patient's balance when a claim is approved.
21. **Commission tracking.** Only calculation exists today. Persist deals, commission lines and payouts (with status Pending/Paid) so real-estate agents can be paid through the system.
22. **Dynamic forms.**
    - Validation supports a practical subset of JSON Schema.
    - Add nested `object`/`array.items`, `if/then` rules, and linking a submission to an invoice line.
23. **Invoice designer.** Custom fields, logo placement, choice of fonts, and more than one layout per business type.
24. **Localisation.** Money and date formats are fixed to English. Use locale-aware formatting, and add Sinhala/Tamil UI strings.
25. **Reporting.** CSV/Excel export, revenue by branch/staff/category, and scheduled email of the daily revenue report.

### Testing gaps

26. **End-to-end tests.** Add Playwright tests for the web pay flow and `integration_test` tests for mobile.
27. **Untested screens.**
    - Web: dashboard, designer, form builder and agent monitor have no component tests.
    - Mobile: the subscription and insurance screens are untested.
28. **Real gateway sandboxes.** Stripe/PayPal are tested with stubs. Add an opt-in test run against Stripe test mode and PayPal sandbox using CI secrets.
29. **Database tests in CI.** The Testcontainers tests skip when Docker isn't available. Run them in CI with Docker, or with the `SME_TEST_POSTGRES` variable.
30. **Existing failures outside billing.** These already fail on `dev`, not because of billing, but should be fixed so CI is green:
    - 24 backend Sightings/DepartureOps tests
    - 12 web WhaleWatching/BusinessProfile tests
    - 4 mobile login-layout tests

---

## 4. Configuration reference

| Setting | Purpose | Empty value means |
|---|---|---|
| `Platform:SecretKey` | Encrypts gateway secrets | Falls back to `Jwt:Key` |
| `Integrations:SendGrid:ApiKey`, `FromEmail`, `FromName` | Invoice/receipt email | Email logged, reported as simulated |
| `Integrations:Twilio:AccountSid`, `AuthToken`, `FromNumber`, `WhatsAppFrom` | SMS / WhatsApp | Messages logged, reported as simulated |
| Payment Gateways page (per tenant) | Stripe / PayPal keys and webhook secret | Payments run in the sandbox |
| `SME_TEST_POSTGRES` (test env var) | Postgres server for integration tests | Uses Testcontainers, or skips |
