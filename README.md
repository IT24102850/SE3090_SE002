# SE3090_SE002 - Universal SME Management Platform

## Team Members

A three-member group, so three primary business components - one per
student, as Section 3 of the specification requires.

> **⚠ GROUP-SIZE APPROVAL — NOT YET RECORDED. Fill in before submitting.**
>
> Section 3 requires the lecturer-in-charge's **written** approval for a group
> size other than four. Replace this whole block with the real details and put
> a copy of the approval in the consolidated report:
>
> - Approved by: `<lecturer-in-charge's name>`
> - Date of approval: `<date>`
> - Evidence: `<email / Course Web message / other, and where it is in the report>`
>
> This block is deliberately visible rather than a hidden comment: an
> unfilled placeholder that ships is an obvious gap an evaluator can ask
> about, whereas an invented name and date would be fabricated evidence
> under Section 18.2. If the approval does not exist yet, request it — do not
> write something here to make the warning go away.

The Agentic AI column names the files each student authored; it matches
`git log --author`.

| Student | ID | Primary component | Agentic AI contribution (own files) |
|---|---|---|---|
| Hasiru Chamika | IT24102850 | Universal Booking & Resource Engine (bookings, resources, schedules, availability, check-in) | The four-agent booking pipeline - Planner/Coordinator, Domain Analysis, Action/Tool and Validation/Safety - used by **Schedule Copilot** and customer **find-and-book** (`agentic-ai-service/agents/planner_agent.py`, `domain_analysis_agent.py`, `action_tool_agent.py`, `validation_safety_agent.py`, `schedule_*.py`, `tools/booking_tools.py`, `tools/schedule_tools.py`, `Services/PlannerAgentService.cs`, `Controllers/AgentWorkflowController.cs`); also the Platform Operations Copilot (`agents/platform_*.py`) |
| Oshadi | IT24101203 | Billing, Payments & Dynamic Forms Engine | **Billing Copilot** - the planning and narration agent at the model edges (`agentic-ai-service/agents/billing_planner.py`, `schemas/billing_contracts.py`) and the deterministic billing analysis agent it drives (`Services/Billing/BillingAgentService.cs`, `Controllers/BillingAgentController.cs`) |
| Hasaranga Abeyrathna | IT24102315 | Inventory, Analytics & Intelligence Hub | **StockSense** - inventory agents for planning, inventory-domain analysis, replenishment recommendation and health analysis (`agentic-ai-service/agents/inventory_agents.py`, `tools/inventory_tools.py`, `Services/InventoryAgentService.cs`). The StockSense reorder workflow built on it - deterministic safety gate, persisted state and human approval (`Services/Inventory/ReorderSafetyGate.cs`, `Controllers/StockSenseReordersController.cs`) - was prepared by Hasiru Chamika with Claude Code and reviewed by Hasaranga, as `git log` shows |

The Platform console (SuperAdmin, Unify subscriptions) is additional scope
beyond the three primary components.

## Tech Stack
- **Backend:** ASP.NET Core 8 Web API, Entity Framework Core, PostgreSQL
- **Frontend:** React 18, Vite, Redux Toolkit (+ RTK Query)
- **Mobile:** Flutter, Dart, Riverpod
- **Agentic AI:** FastAPI (Python) with a custom four-agent orchestration
  (Planner -> Domain Analysis -> Action/Tool -> Validation/Safety). Gemini is
  the default model provider, with an Ollama provider behind `LLM_PROVIDER`.
  Not LangGraph: the pipeline is a fixed, auditable sequence with a
  deterministic (non-LLM) safety gate, so a graph runtime would add a
  dependency without adding control. See `agentic-ai-service/README.md`.
  Two assessed workflows run on it: **Schedule Copilot** (staff objective → plan →
  validated proposal → manager approval → apply; React and Flutter) and customer
  **find-and-book** (Flutter request → agents → approval in React → status back to Flutter).
- **Database:** PostgreSQL (Supabase)
- **Deployment:** Render (API + agent service, Docker), Supabase (PostgreSQL), Vercel (React), Android APK (Flutter)

## Sub-type dashboards
The tenant admin dashboard adapts to what the business actually does. A
registry keyed on `Tenant.SubType` supplies each of the 12 tourism
sub-types with its own terminology, KPI cards, resource columns and booking
form fields; a tenant with no sub-type, an unrecognised one, or a
non-Tourism business type gets the generic dashboard unchanged.

- Registry: `frontend/src/features/dashboard/subtypes/` (mirrors the Flutter
  app's `lib/registry/tourism_dashboard_registry.dart`)
- Router: `frontend/src/features/dashboard/DashboardRouter.tsx`
- Whale / dolphin watching is the first sub-type with a full operational
  dashboard: a departure board with manifests, per-ticket-type pricing,
  waiver and check-in tracking, a weather/sea-state console, a
  cancel-with-notify flow, a wildlife sightings log with success-rate
  analytics, and a safety-equipment panel.

Details, including the shared-capacity rules and the jsonb key contract the
Flutter app depends on, are in
[`docs/tourism-business-template.md`](docs/tourism-business-template.md).

Demo data: `./scripts/seed-whalewatching-full.ps1` (needs `dotnet run` in
`backend/SmeBackend` first).

## Clinic operations dashboard
A tenant whose `BusinessType` is `Clinic` gets an operations desk instead
of the generic calendar (the calendar is still one toggle away). It is
backed by `api/reports/clinic/*` (`ClinicReportsController`) and is served
by both the web console (`frontend/src/features/dashboard/clinic/`) and the
Flutter app (`lib/screens/clinic/clinic_desk_screen.dart`, reached from the
home screen's "Clinic desk" card and the analytics / reports tiles):

- **KPIs** - patients (total, new, seen), doctors and rooms, appointments,
  revenue realised vs booked, completion / no-show / cancellation rates,
  average wait (check-in to consultation) and visit time, patients per
  doctor today. Rates with nothing to measure are `null` and render as a
  dash, never a fake zero.
- **Patient flow** - today's queue from scheduled -> waiting -> in
  consultation -> discharged with live waiting minutes, room occupancy and
  the staff-to-patient ratio; check-in / start consult / complete / no-show
  actions per row; polled every minute. Starting a consult now stamps
  `Booking.ConsultationStartedAt` (new nullable column, migration
  `20260918090000`), completing stamps the previously unused `CheckOutAt`.
- **Alerts** - long waits, overdue arrivals, requests unconfirmed >24h,
  unreminded appointments in the next 24h, inventory at/below reorder level,
  doctors/rooms marked unavailable, an abnormal no-show day. Each links to
  where the fix happens.
- **Reports** - trend by day/week/month, breakdowns by doctor, treatment,
  branch, insurance provider, booking channel and hour; every breakdown is
  clickable and cross-filters the rest; Daily / Weekly / Monthly presets and
  a one-click CSV export of the whole view (web).
- **Reminders & follow-ups** - the next 48h with reminder status and
  send / send-all, plus patients seen in the last 30 days with nothing booked.
- **Customisation** (web) - show/hide and reorder every panel, saved per
  user and tenant in the browser.

Not covered because the platform records no such data: vitals / lab
results, and payment method / payment status (billing is a deferred module -
revenue here is `Booking.TotalCost`).

## Restaurant operations dashboard
A tenant whose `BusinessType` is `Restaurant` (or `Cafe`) gets a service
desk, kitchen board and report in one screen instead of the generic
calendar (the calendar is still one toggle away). It is backed by
`api/reports/restaurant/*` (`RestaurantReportsController`) and served by the
web console (`frontend/src/features/dashboard/restaurant/`). An "order" is a
`Booking`; the mapping is documented in the controller header:

- **Live order feed** - today's orders by stage: new (Pending) -> accepted
  (Confirmed) -> preparing (CheckedIn, `CheckInAt` = kitchen start) ->
  ready (InProgress, `ConsultationStartedAt` reused as "ready at") ->
  served / delivered (Completed, `CheckOutAt`). Accept / reject / start
  prep / ready / served actions per row; polled every 30s.
- **Sales KPIs** - orders, completed, cancelled and revenue with the change
  against the previous period, average order value, covers and revenue per
  cover, table turnover, sales trend (revenue / orders / covers), peak
  hours, and a dine-in vs takeaway/delivery customer-flow chart.
- **Channels** - by `Booking.Source` (POS, Online, Phone, a delivery app...)
  and by service mode (dine-in / takeaway / delivery / drive-thru, from the
  menu type's `ConfigJson.serviceMode` or inferred from its name).
- **Kitchen performance** - prep time (start prep -> ready) and ticket time
  (-> served) against a per-menu-type target (`ConfigJson.prepTargetMinutes`,
  default 20), on-time rate, delayed tickets, and throughput per station
  (Equipment resource), table (Room/Desk) and rider (Vehicle).
- **Inventory** - stock against reorder level, a waste log
  (`POST api/inventory/{id}/waste`, its own "Waste" movement type, priced
  at unit cost, grouped by reason), and recipe auto-decrement: a menu type
  with `ConfigJson.recipe: [{sku, qty, perCover}]` takes its ingredients
  off stock when an order starts prep (`RecipeConsumptionService`,
  idempotent per order).
- **Staff & labor** - who is rostered right now (Staff resources' weekly
  schedules; there is no time clock, and the panel says so), hours and
  wages so far (x `Resource.HourlyRate`), labor as a share of sales for the
  day and for the range.
- **Alerts** - tickets over target, unaccepted orders, a deep kitchen queue,
  late starts, low stock, waste > 5% of sales, labor > 35% of sales, nobody
  rostered while orders are open, an abnormal cancellation day, reservation
  requests unconfirmed > 24h.
- **Reports** - Today / Yesterday / 7 / 30 days / month and Daily / Weekly /
  Monthly presets, a custom range, grouping by hour / day / week / month,
  a shift filter (breakfast / lunch / dinner / late night) and cross-filters
  by branch, station, menu type, channel and service mode; one-click CSV.
  Hour-based logic runs in the viewer's local time (`tz` query param).
- **Role-based views** - Admin (owner) sees everything; Manager (floor)
  opens on the feed and tables; Staff (kitchen) opens on the kitchen board
  and never sees a revenue figure (panels, KPIs and the CSV all respect
  it). Show/hide and reorder is saved per user, tenant and role.

Demo data: `psql "$DATABASE_URL" -f scripts/seed-spice-garden-sample-records.sql`
(creates the tenant if `seed-demo-data.ps1` has not; logins are listed at
the end of the script - the admin keeps `Demo@12345` when it came from
`seed-demo-data.ps1`, the manager / chef logins use `Passw0rd!`).

## Gym operations dashboard
A tenant whose `BusinessType` is `Gym` (or `Fitness`) gets the floor, the
membership book, revenue against target and the equipment in one screen
(the calendar is still one toggle away). Backed by `api/reports/gym/*`
(`GymReportsController`), served by `frontend/src/features/dashboard/gym/`.
Mapping (documented in the controller header): member = Customer user
(new optional `DateOfBirth` / `Gender`), membership = `Subscription` (new
table - migration `AddGymMembershipsAndDemographics`; `Status` is the
lifecycle, `PaymentStatus` the latest billing run), visit = Booking with a
`CheckInAt` (`Source` = RFID / App / Biometric / Front desk), class =
booking type of kind `class` (`ConfigJson.kind`, or inferred), zone = Room
resource with a capacity, trainer = Staff resource, equipment =
`EquipmentItem` with `equipment_reservations` for usage and
`equipment_maintenances` for service.

- **Live check-in monitor** - inside now against capacity, entries and
  exits by hour, who is on the floor with their membership state beside
  them (a lapsed keycard shows the moment it is scanned), check-out action;
  polled every 30s.
- **Peak hours heatmap** - check-ins by day of week and hour (viewer's
  local time), single-hue sequential, busiest cell labelled.
- **Attendance log** - searchable, paged, filterable by method, with
  duration (`api/reports/gym/attendance`).
- **Memberships** - active / frozen / expired / cancelled / none, sign-ups,
  lapsed and churn for the range, renewals due in 30 days (7-day urgency),
  demographics by age band, gender and tier.
- **Revenue** - membership payments (`LastPaymentAt`) plus drop-in / PT
  sales, MTD and YTD against targets from the Memberships module config
  (`facilityCapacity`, `monthlyRevenueTarget`, `yearlyRevenueTarget`,
  `openHoursPerDay`, `maintenanceEveryUses`), monthly recurring value,
  payment status (paid / pending / failed / overdue) with the list to chase,
  popular plans.
- **Classes, trainers, zones** - sessions, bookings, fill rate and no-shows
  per class; load per trainer; booked hours against opening hours per zone.
- **Equipment** - hours and utilisation per machine, last / next service,
  uses since service against the threshold, overdue / due-soon / in-service
  flags.
- **Alerts** - near or at capacity, renewals within 7 days, unsettled
  billings, check-ins by members without a valid membership, maintenance
  overdue or due, machines out of service, full classes today, nobody
  rostered, low stock.
- **Role-based views** - Admin opens on revenue and members, Manager on
  the live floor, Staff (front desk / trainer) never sees a revenue or
  billing panel (KPIs and the CSV export respect it). Panels can be
  shown / hidden / reordered per user, tenant and role. CSV export.

Demo data: `psql "$DATABASE_URL" -f scripts/seed-powerhouse-fitness-sample-records.sql`
then `scripts/seed-powerhouse-fitness-profile.sql` (the API must have started
once so the Subscriptions migration has run). Logins are listed at the end
of the records script.

## School dashboard
A tenant whose `BusinessType` is `School` (or `Tuition`, `Education`,
`Academy`) gets registers, the gradebook, student performance, enrolment,
tuition and a simple P&L in one screen (the calendar is still one toggle
away). Backed by `api/reports/school/*` (`SchoolReportsController`), served
by `frontend/src/features/dashboard/school/`. No new tables: the mapping,
documented in the controller header and `Shared/SchoolConfig.cs`, is
student = Customer user (`MedicalNotes` = medical alerts / accommodations,
`IsApproved` = registration approved); teacher = Staff resource; classroom
= Room resource; subject = booking type with `ConfigJson.kind` =
`lesson | tutoring | exam | assignment` plus `subject`, `grade`, `weight`;
a lesson session = one start time on the teacher with one booking per
student whose `FormData` carries the attendance mark and behaviour points,
and a "room hold" booking on the classroom for utilisation and clashes; an
assessment = one booking per student with `score / maxScore / feedback /
submittedAt / dueAt` in `FormData`; tuition = `Subscription`; terms and
holidays = the Scheduling module config; thresholds and the grade scale =
the Attendance module config.

- **Today's timetable & registers** - every session with its state, the
  roster with P / L / A / E marks, +/− behaviour points with a note, and
  the student's medical alert on the row; "registers to mark" flagged once
  a session has started (`POST api/reports/school/attendance`).
- **Gradebook** - every exam / assignment in the range with per-student
  marks entered inline, submission time (late flagged), feedback, letter
  from the tenant's grade scale (`GET gradebook`, `POST grade`).
- **Student performance** - the cohort with attendance, average, points and
  at-risk flags (attendance / average below the thresholds, or 3+
  incidents); a drawer per student with per-subject bars, scores over time,
  the assessment list, attendance history and behaviour log
  (`GET students/{id}`).
- **Attendance, behaviour, subjects, year groups, teachers, classrooms** -
  mix and trend, incidents and commendations, per-subject and per-grade
  attendance and averages, teacher load with registers outstanding and a
  pay estimate, room utilisation.
- **Enrolment & retention, tuition & payments, income & costs** - new /
  lapsed / retention, tuition invoice status with the list to chase,
  tuition + fees against payroll (rostered hours × rate) and purchases.
- **Term calendar** - current term progress, holidays, timetable clashes
  (the same teacher or room double-booked); a holiday-tomorrow alert when
  sessions are still timetabled.
- **Registrations to approve** - pending students and staff, approved from
  the panel (`POST approve`; staff need a role and an Admin).
- **Alerts** - at-risk students, unmarked registers, grading overdue,
  unpaid / lapsed tuition, pending approvals, clashes, no teacher on duty,
  holiday tomorrow.
- **Role-based views** - Admin sees finance, payroll and approvals; Manager
  (academic head) academics, enrolment and tuition status; Staff (teacher)
  the timetable, gradebook and students - never money or user admin.

Not built because the platform records nothing for them: backups, Zoom /
Google Workspace integrations, access-log auditing, parent accounts, and
staff bonuses / expense claims (payroll here is the roster, not a
timesheet).

Demo data: `psql "$DATABASE_URL" -f scripts/seed-brightminds-sample-records.sql`
then `scripts/seed-brightminds-profile.sql`. Logins are listed at the end of
the records script.

## Customer side (web)
A user with the `Customer` role gets the same four destinations the
Flutter app's customer tabs offer, in `frontend/src/features/customer/`,
scoped to the business they registered with:

- **Home** (`/dashboard`) - the business (logo, cover, today's hours), the
  next booking with its check-in QR one click away, quick actions, recent
  bookings with "Book again", latest notifications.
- **Book a service** (`/book`) - four steps: service (duration, approval,
  price) -> who / where (branch and specialty filters) -> date & time (14
  days of free slots from `available-slots`, or a date range with
  `unavailable-ranges` for night / multi-day types) -> confirm (people,
  notes, optional weekly repeat), then the success screen with the QR.
  `?type=&resource=` prefills the first two steps.
- **My bookings** (`/my-bookings`) - upcoming / past / cancelled; check-in
  QR (the raw booking id `PUT /bookings/{id}/checkin` scans), reschedule to
  another free slot, cancel - each offered only inside the tenant's cutoff
  hours.
- **AI planner** (`/ai-planner`) - `POST /agent/find-and-book` in plain
  words with a search window, plus every past request and its status
  (`GET /agent/workflow/mine`).
- **About the business** (`/business`) - description, hours with today
  highlighted, amenities, gallery, branches, contact and social links.

Customers never see an operations screen; `DashboardRouter` sends the
role to the customer home before any business-type dashboard.

## Website booking widget
A business can take bookings on its own website by pasting a two-line snippet
(Settings → Business Settings → Website booking widget). Bookings arrive in
the dashboard as Pending with source `Website`. See
[`docs/website-booking-widget.md`](docs/website-booking-widget.md).

## Customer accounts (global, join-on-first-booking)

A customer signs up with just a name, email and password - no business to
choose - and joins a business automatically the first time they open it in
the app. Under the hood one identity row plus one membership row per business
(`User.LinkedAccountId`), so every per-business screen keeps seeing an ordinary
customer; see "Customer accounts are global" in
[`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md). Endpoints:
`POST /api/auth/register` (TenantId now optional) and
`POST /api/auth/join/{tenantId}` (returns a token scoped to that business).

## Platform console (owner only)

`/platform` is the site owner's cross-tenant dashboard: every tenant, user
and booking on the platform, the busiest businesses, an append-only audit
log, and the levers to suspend a tenant, deactivate a user or issue a
temporary password. It is a separate app inside the SPA
(`frontend/src/features/platform/`) with its own sign-in, session store and
API slice; nothing under `/platform` is reachable with a tenant login.

How it is protected (`backend/SmeBackend/Controllers/Platform*.cs`,
`Authorization/PlatformOwnerPolicy.cs`):

- **Account isolation** — the owner is a `SuperAdmin` user in a reserved
  "Unify Platform" tenant. The ordinary `/api/auth/login` never matches it,
  it holds no tenant role, and only the `PlatformOwner` policy honours it.
- **Password** — BCrypt work factor 12; 14+ characters, mixed case, digit,
  symbol.
- **Two-factor** — TOTP (RFC 6238, `Services/TotpService.cs`) on every
  sign-in, enrolled from the login screen on first use. Each code is
  single-use (the accepted 30 s step is remembered) and the secret is stored
  AES-256-GCM encrypted with a key from configuration
  (`Services/PlatformSecretProtector.cs`), never in plain text.
- **Lockout + rate limit** — 5 failures lock the account for 15 min; the
  login endpoints allow 5 requests/min per IP.
- **Server-side sessions** — every token's `jti` is a row in
  `platform_sessions`; the policy refuses revoked, expired (60 min) or idle
  (15 min) sessions. Sessions can be revoked individually or all at once.
- **Step-up** — suspend/reactivate a tenant, deactivate/activate a user,
  reset a password and change the owner password all require a fresh code
  (`X-Platform-Otp` header).
- **Audit** — every attempt and action lands in `platform_audit_logs` with
  IP and user agent; the console never edits or deletes rows.
- `/api/platform/*` responses are `Cache-Control: no-store` with
  `X-Frame-Options: DENY`.

Configuration (`Platform:*` in appsettings / user-secrets, or `Platform__*`
environment variables; see `Data/PlatformOwnerSeeder.cs`):

| Key | Purpose |
|---|---|
| `Platform:OwnerEmail` | who the owner is (defaults to the site owner's address) |
| `Platform:OwnerPasswordHash` | BCrypt hash used **only** when the account is first created (preferred) |
| `Platform:OwnerInitialPassword` | plain-text alternative, hashed on the way in |
| `Platform:SecretKey` | key material for encrypting the TOTP secret (falls back to `Jwt:Key`) |
| `Platform:MfaIssuer` | the name shown in the authenticator app |

The owner is seeded on startup in every environment, once. After that the
password lives only as a hash in the database and is rotated from
Security → Change password.

## Platform Operations Copilot (the owner's Agentic AI)

The fourth agentic workflow, and the only one that reasons **across** tenants
rather than inside one. The platform owner gives it an objective — "reduce
churn risk this month" — and four agents plan, read the platform's own
commercial records, propose one intervention per at-risk business, and check
every proposal against policy. Full detail in
[`docs/platform-operations-copilot.md`](docs/platform-operations-copilot.md).

The property it is built on: **the agent cannot carry out a high-impact
action.** Extending a term or comping a plan goes through an endpoint that
demands a fresh authenticator code, and the agent service has no database
credentials, no write tool and no way to produce one. So no sequence of model
outputs — however well injected — moves money here. A person with the
authenticator does, or it does not happen.

| Agent | Responsibility | Tools | Model |
|---|---|---|---|
| Planner | Objective → plan, states its reading of the goal | none | yes |
| Analysis | Who is at risk, on what evidence | 3 read-only | yes |
| Action | One intervention each, with cost | 1 read-only | yes |
| Safety | Policy, caps, blast radius | none | **no** |

- Tools are read-only *by construction* — there is no write method to call
- Ceilings enforced three times: agent gate, API boundary, execution
- The apply request carries *which* businesses, never *what to do* to them
- No suspend or delete exists; every reachable write is additive for the tenant
- 33 tests (19 Python, 14 C#), none of which involve a language model
- Screen: `/platform/copilot`

## Unify subscriptions (what a tenant pays us)

A tenant admin has to hold a Unify subscription to get the platform. The price
list, the payment gateways behind it, the gate that decides what a plan allows
and the owner's revenue console are all described in
[`docs/unify-subscription-pricing.md`](docs/unify-subscription-pricing.md).

Not to be confused with `/subscriptions`, which is the memberships a tenant
sells to *its own* customers (`Models/Subscription.cs`). Two different
ledgers; they never share a table or a gateway credential.

The ladder follows Tinder's playbook, because it is the best-documented
consumer subscription funnel there is and most of it translates:

| Plan | Monthly (LKR) | 12 months | Hook |
|---|---|---|---|
| **Starter** | Free forever | — | 1 branch, 2 team members, 60 bookings/month, a public listing. Capped, not crippled. |
| **Grow** | 5,900 | 38,940 (−45%) | Unlimited bookings, card payments, SMS, the website widget |
| **Pro** ★ | 14,900 | 98,340 (−45%) | The AI copilots and demand analytics — the "See Who Likes You" rung. 14-day free trial. |
| **Prime** | 34,900 | 230,340 (−45%) | No ceilings, API access, 4-hour support |

Plus consumables sold in packs where the bigger pack always wins on unit
price — **Spotlight** (24 h at the top of the directory, on sale to free
tenants too), AI credits, message credits and extra seats — and a 50% intro
offer on a first term. USD pricing runs alongside LKR from the same catalogue.

What Tinder's playbook is deliberately missing here: its age-tiered pricing,
which produced a California class action and an ACCC finding. Offers here are
earned by what a business *does* (never paid before, lapsed, anniversary), and
no demographic value is an input to any price the system quotes.

- Price list in code, synced every boot: `backend/SmeBackend/Data/PlatformPlanCatalog.cs`
- The gate: `[RequiresPlanFeature]` / `[MetersPlanQuota]` answer **402** with
  the exact limit hit and the cheapest plan that clears it; the apps render
  that as a paywall over whatever the user was doing
- Payments reuse the billing engine's Stripe/PayPal processors with
  platform-level credentials from configuration (`Platform:Billing:*`); with
  nothing configured the sandbox runs the whole flow and says so
- Screens: `/pricing` (public), `/subscription` (tenant admin),
  `/platform/revenue` (owner), and *Business → Your Unify Plan* in the Flutter app
- A business that stops paying loses the paid features and keeps every row of
  its data — a failed renewal opens a 14-day grace window, and cancelling
  keeps every day already bought

## Getting Started
See [`docs/TECHNICAL_DOCUMENTATION.md`](docs/TECHNICAL_DOCUMENTATION.md) for the
complete project overview, architecture, installation, environment variables,
API, testing, deployment, accounts, contribution record, security notes, and
AI usage declaration. Component-specific details remain in
[`agentic-ai-service/README.md`](agentic-ai-service/README.md) and
[`mobile/README.md`](mobile/README.md).

- Load testing and results: [`docs/PERFORMANCE_REPORT.md`](docs/PERFORMANCE_REPORT.md)
- Where the delivered system differs from the original task-assignment plan,
  and why: [`docs/CHANGES_FROM_PLAN.md`](docs/CHANGES_FROM_PLAN.md)

## Deployment (Render + Supabase + Vercel)

[`render.yaml`](render.yaml) is a Render Blueprint that deploys two Docker
services from this repository: `sme-backend` (`backend/SmeBackend`) and
`sme-agentic-ai` (`agentic-ai-service`). PostgreSQL is hosted on Supabase;
the API applies its EF Core migrations on startup. The React app is deployed
on Vercel, whose [`frontend/vercel.json`](frontend/vercel.json) rewrites
`/api/*` to the Render API. Secrets are set in each host's dashboard, never in
the repository:

- `ConnectionStrings__DefaultConnection` — the Supabase PostgreSQL connection
  string (`Ssl Mode=Require;Trust Server Certificate=true`)
- `Jwt__Key` — a long, private signing key (at least 32 bytes)
- `Platform__SecretKey` — key for the platform console's MFA secret
  (optional; falls back to `Jwt__Key` — keep both stable, changing either
  invalidates the enrolled authenticator)
- `AgentService__InternalToken` / `AGENT_SERVICE_INTERNAL_TOKEN` — the shared
  secret between the API and the agent service (same value on both)
- `GEMINI_API_KEY` — on the agent service only
- `Cors__AllowedOrigins__0` — optional extra browser origin (the Vercel
  domain is allowed by default)

The free Render tier sleeps idle services: the first request after a quiet
spell takes about 40 seconds. Open both `/health` URLs a few minutes before a
demonstration.

## Live URLs

| What | URL |
|---|---|
| React web app | https://se-3090-se-002.vercel.app |
| API health (checks PostgreSQL) | https://sme-backend-lxsp.onrender.com/health |
| API liveness | https://sme-backend-lxsp.onrender.com/health/live |
| Swagger UI | https://sme-backend-lxsp.onrender.com/swagger |
| OpenAPI JSON | https://sme-backend-lxsp.onrender.com/swagger/v1/swagger.json |
| Agentic AI service health (internal service, token-protected apart from `/health`) | https://sme-agentic-ai.onrender.com/health |
| Platform owner console | https://se-3090-se-002.vercel.app/platform/login |
| Android APK | GitHub Actions → "Build Android APK" workflow artifact, and attached to the submission |
| Demonstration video | _add the public link before submitting_ |

Test accounts for evaluators are listed in
[`docs/TECHNICAL_DOCUMENTATION.md` §15](docs/TECHNICAL_DOCUMENTATION.md#15-live-urls-and-test-accounts).

## License
MIT
