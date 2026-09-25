# SE3090_SE002 - Universal SME Management Platform

## Team Members
- Hasiru - Universal Booking & Resource Engine + Planner/Coordinator Agent
- Student 2 - Billing, Payments & Dynamic Forms Engine + Domain Analysis Agent
- Student 3 - Inventory, Analytics & Intelligence Hub + Action/Tool Agent + Validation/Safety Agent

## Tech Stack
- **Backend:** ASP.NET Core 8 Web API, Entity Framework Core, PostgreSQL
- **Frontend:** React 19, Vite, Redux Toolkit, Tailwind CSS
- **Mobile:** Flutter, Dart, Riverpod
- **Agentic AI:** LangGraph (Python), FastAPI, Ollama (llama3)
- **Database:** PostgreSQL (Supabase/Railway)
- **Deployment:** Railway (API + DB), Vercel (React), Local APK (Flutter)

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

## Getting Started
See `/docs/` for setup instructions.

## Railway deployment

> The current deployment configuration is `render.yaml` (Render API + AI
> service) and `frontend/vercel.json` (Vercel React app). The Railway section
> below is retained as historical setup guidance; use the Render steps for a
> new deployment.

The root [`railway.toml`](railway.toml) publishes `backend/SmeBackend` and
configures Railway's deployment health check. Create a Railway service from
this repository and set these variables:

- `ASPNETCORE_ENVIRONMENT=Production`
- `Jwt__Key` — a long, private signing key (at least 32 bytes)
- `Platform__SecretKey` — a second private key for the platform console's
  MFA secret (optional; `Jwt__Key` is used when unset — but changing either
  key later invalidates the enrolled authenticator, so keep them stable)
- `ConnectionStrings__DefaultConnection` — the PostgreSQL connection string.
  For a Railway PostgreSQL service, use its `PGHOST`, `PGPORT`, `PGDATABASE`,
  `PGUSER`, and `PGPASSWORD` reference variables to build an Npgsql connection
  string, with `Ssl Mode=Require;Trust Server Certificate=true`.

After deployment, substitute the generated Railway domain below:

- Health/readiness: `https://<railway-domain>/health` (200 only when PostgreSQL is reachable)
- Liveness: `https://<railway-domain>/health/live`
- Swagger UI: `https://<railway-domain>/swagger`
- OpenAPI JSON: `https://<railway-domain>/swagger/v1/swagger.json`

## Live URLs
- API: [pending — add the generated Railway domain after the first deployment]
- React: [pending]
- Swagger: `https://<railway-domain>/swagger`
- Demo Video: [pending]

## Render + Vercel deployment

The root `render.yaml` creates the ASP.NET Core API and Python agent service
as two Render web services. In Render, choose **New + → Blueprint**, connect
this repository, then provide the requested values when prompted. Because the
new service URLs do not exist yet, enter `https://example.invalid` for both
URL values below during the initial setup; replace them in the services'
Environment settings after Render creates the services:

- API `ConnectionStrings__DefaultConnection`: the production PostgreSQL
  connection string (the API runs migrations at startup).
- API `Jwt__Key`: a stable, random signing key of at least 32 bytes.
- API `AgentService__BaseUrl`: the agent service's HTTPS URL after Render
  creates it (no trailing slash).
- API `AgentService__InternalToken` and agent
  `AGENT_SERVICE_INTERNAL_TOKEN`: the same long random secret on both
  services.
- API `Cloudinary__CloudName`, `Cloudinary__ApiKey`, and
  `Cloudinary__ApiSecret`: the Cloudinary credentials used for uploads.
- Agent `GEMINI_API_KEY`: a key from Google AI Studio.
- Agent `BACKEND_API_BASE_URL`: the API's HTTPS URL followed by `/api`.

After the services are created, replace both temporary URLs and make sure the
shared token matches in each service's Environment settings, then redeploy
both. Check
`https://<api-domain>/health` for database readiness and
`https://<agent-domain>/health` for the agent service.

For the frontend, import the repository into Vercel and set the project Root
Directory to `frontend`. Use `npm run build` and `dist` as the output
directory. Set `VITE_API_URL` to `https://<api-domain>/api`, then deploy. The
existing `vercel.json` rewrite is a fallback for the previous Render API
domain; setting `VITE_API_URL` ensures the frontend calls the API you just
deployed.

## License
MIT
