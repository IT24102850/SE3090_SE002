# SE3090_SE002 — Universal SME Booking Platform

A multi-tenant SaaS booking platform originally built for clinics and generalized to any
appointment/reservation-based small business — clinics, restaurants, gyms, tuition
centers, real estate agencies, tourism operators, and general services. One backend,
one admin web app, one customer/staff mobile app, shared by every tenant.

## Repository layout

```
backend/SmeBackend/        ASP.NET Core 8 API (C#, EF Core, PostgreSQL/Supabase)
frontend/                  React + TypeScript admin web app (Admin/Manager/Staff only)
mobile/sme_mobile/         Flutter app (Customer self-service + Staff check-in/schedule)
agentic-ai-service/        Python FastAPI microservice — Gemini-powered 4-agent booking pipeline
scripts/                   PowerShell seed scripts for realistic demo data
docs/                      ADRs, AI usage log, feature-template docs
```

## Tech stack

| Layer | Stack |
|---|---|
| Backend | ASP.NET Core 8, Entity Framework Core 8, Npgsql (PostgreSQL), JWT auth (BCrypt password hashing), Swashbuckle/Swagger |
| Database | PostgreSQL, hosted on Supabase (project `se3090-booking-db`) |
| Web admin | React 18, TypeScript, Redux Toolkit (RTK Query), React Router 7, Vite |
| Mobile | Flutter (Dart), Riverpod (state), Dio (HTTP), flutter_secure_storage (JWT), go_router, qr_flutter/mobile_scanner (check-in QR) |
| Agentic AI | Python, FastAPI, Google Gemini (`google-genai`), httpx |

## Architecture: three apps, one backend

- **`backend/SmeBackend`** — the only thing that talks to the database. Every tenant's
  data lives in the same tables, isolated by `TenantId` (multi-tenant, shared-schema
  model). Role-based auth via JWT: `Admin`, `Manager`, `Staff`, `Customer`.
- **`frontend/` (web)** — **Admin/Manager/Staff only.** Business setup, resource/staff
  management, booking-type configuration, calendar/booking management, reports, agent
  workflow approvals. There is no customer-facing flow in the web app by design.
- **`mobile/sme_mobile/` (Flutter)** — **Customer and Staff.** Customers browse
  businesses, book, manage their own bookings, get notifications. Staff use it for
  their own schedule and QR check-in scanning. Two separate registration flows:
  `RegisterScreen` (business/tenant onboarding, mirrors the web's `RegisterPage`) and
  `CustomerRegisterScreen` (a patient/customer signing up with a specific tenant they're
  browsing, forces `Role=Customer` server-side).

## Multi-tenant data model

```
Tenant (BusinessType, SubType) ──┬── Branch
                                  ├── TenantModule (per-business-type feature flags/config)
                                  ├── User (Admin/Manager/Staff/Customer, JWT login)
                                  ├── Resource (the bookable thing: a doctor, a table,
                                  │     a boat, a room, a vehicle...) ── ResourceSchedule
                                  │                                    ── ResourceScheduleException
                                  ├── BookingType (the product being sold: "Consultation",
                                  │     "Whale Watching Tour", "Room Stay"...)
                                  └── Booking (an actual reservation)
```

Key generic-by-design fields:
- **`Resource.Category`**: `Room | Equipment | Vehicle | Staff | Desk | Other`
- **`Resource.CustomAttributes`** (JSONB): free-form per-resource metadata (rating,
  pricing tiers, capacity, season, includes/excludes...) — consumed by both the admin
  UI and the Agentic AI's ranking logic.
- **`BookingType.BookingUnit`**: `Slot | Night | DateRange | Package` — see
  "Universal Tourism Booking System" below.
- **`BookingType.ConfigJson`** (JSONB): free-form per-booking-type config matching the
  chosen unit (weather-dependent, cancellation policy, check-in/out time, itinerary...).

Business types: `Clinic, Restaurant, Gym, School, RealEstate, Tourism, General`. Tourism
tenants additionally carry a `SubType` (one of 11 real sub-categories — see below).

## Business types & booking shapes supported

Originally built clinic-first, the schema is now genuinely business-type-neutral:

| Business type | Example resource | Booking unit used |
|---|---|---|
| Clinic | Doctor | Slot |
| Restaurant | Table | Slot |
| Gym | Trainer | Slot |
| School/Tuition | Tutor | Slot |
| RealEstate | Agent | Slot |
| General | Technician | Slot |
| Tourism — wildlife/safari/whale-watching/surf/dive/hiking/cultural tours | Boat, jeep, guide | Slot |
| Tourism — Accommodation | Room | **Night** (check-in/check-out) |
| Tourism — Vehicle rental | Car/van | **DateRange** (multi-day) |
| Tourism — Multi-day packages | Tour coordinator | **Package** (date range + itinerary) |

See `docs/tourism-business-template.md` for the full sub-type analysis and the
`ConfigJson` schema design.

## Universal Tourism Booking System (booking units)

The booking engine originally only supported one shape: pick a resource, pick a day,
pick a fixed-duration time slot (`SlotCalculator` + `GET /bookings/available-slots`).
That's correct for consultations, tours, and lessons, but wrong for accommodation
(booked by night) and vehicle rental (booked by date range). Rather than building a
separate code path per business type, `BookingType.BookingUnit` drives one of four
handlers, reused by any business that needs that shape:

- **Slot** — the original behavior, unchanged. Fixed-duration time slots within a
  resource's weekly `ResourceSchedule`.
- **Night** — check-in/check-out dates with configurable check-in/check-out times
  (default 14:00/11:00). Availability comes from `GET /bookings/unavailable-ranges`
  (existing bookings only — no weekly schedule needed).
- **DateRange** — multi-day start/end dates (vehicle rental, equipment rental).
- **Package** — one date-range reservation against a primary resource plus a
  structured itinerary (`[{day, title}]`) rendered to the customer. (Not true
  multi-resource atomic composite booking — a deliberately scoped-down version;
  see `docs/tourism-business-template.md` for the reasoning.)

`Resource`/`Booking` creation and conflict-detection logic required **zero changes**
for the new units — the existing overlap check is a plain `DateTime` interval
comparison, not tied to sub-day durations. Only availability *display* (the new
endpoint) and the client UI needed new code.

Proven end-to-end with real, sourced businesses (not test fixtures): **Mirissa
Jetliner** (whale watching, Slot), **The Wallawwa** (accommodation, Night), **Malkey
Rent A Car** (vehicle rental, DateRange) — all seeded from each operator's real
website via `scripts/seed-tourism-night-daterange.ps1` / `seed-mirissa-jetliner.ps1`.

## Feature scope (functional requirements)

Tracked against three requirement sets:

- **FR-B1–FR-B12** (Booking & Resource Engine core) — ✅ fully implemented.
- **FR-AS1–FR-AS11, FR-AS21–FR-AS24** (Admin & Staff: account/access, business setup,
  booking management, agent-workflow oversight, tenant isolation) — ✅ fully implemented.
- **FR-AS12–FR-AS20** (Billing + Inventory: invoices, payments, insurance claims,
  revenue dashboards, stock in/out, suppliers, PO approvals) — ⏸️ **explicitly
  deferred**. Only unused C# model stubs exist (`Invoice`, `InventoryItem`, `Supplier`,
  `Payment`, `InsuranceClaim`, `PurchaseOrder`, ...); they aren't even registered as
  `DbSet`s in `AppDbContext`, so there's no schema for them yet. Treat as a fresh,
  separately-scoped project if picked up later.
- **FR-C1–FR-C11** (Customer actor: browse, book, manage own bookings, notifications)
  — ✅ fully implemented, mobile-only.

## Backend API surface (`backend/SmeBackend`)

| Controller | Responsibility |
|---|---|
| `Services/AuthController` | Login, register (customer), `/auth/me` |
| `Services/TenantController` | Tenant onboarding (`/tenant/onboard`), business settings, staff list |
| `TenantPublicController` | Public tenant directory for the mobile "Find a Business" list |
| `BranchesController` | Branch CRUD |
| `ResourcesController` | Resource CRUD, weekly schedule, schedule exceptions |
| `BookingTypesController` | Booking type CRUD (name, duration, booking unit, config, approval rules) |
| `BookingsController` | Available-slots, unavailable-ranges, create/reschedule/cancel/check-in/status, recurring bookings, conflicts report, my-schedule |
| `NotificationsController` | In-app notifications |
| `AgentWorkflowController` | AI planner workflows (propose/approve/reject/apply), customer find-and-book |

Auth: JWT bearer, roles `Admin | Manager | Staff | Customer`. Multi-tenant isolation
enforced by `TenantId` scoping in every query (`ITenantScoped` convention).

## Web admin app (`frontend/src/`)

- `pages/` — Login, Register (business onboarding), Dashboard shell.
- `features/booking/` — Calendar dashboard, booking manager, resource manager (+ form
  modal with per-category fields and free-form custom attributes), booking-type
  manager (+ booking-unit selector and config fields), multi-branch schedule, reports,
  Agent Planner (AI workflow review/approval).
- `features/staff/` — Staff management, "My Schedule" (a linked staff login's own
  bookings).
- `features/branches/`, `features/settings/` — Branch CRUD, business settings
  (including reschedule/cancellation cutoffs and Tourism sub-type).
- `api/bookingApi.ts` — single RTK Query API slice for the whole app.

## Mobile app (`mobile/sme_mobile/lib/`)

- `screens/` — Landing, login, business (tenant) registration, profile setup.
- `screens/customer/` — Find a business, business detail (browse resources), booking
  flow (type → date/time or date-range → confirm), booking success, my bookings.
- `screens/staff/` — My schedule, QR check-in scanner.
- `widgets/` — `date_slot_picker.dart` (Slot bookings), `date_range_picker.dart`
  (Night/DateRange/Package bookings), QR code widget.
- `providers/` — Riverpod providers wrapping the backend API (`booking_providers.dart`,
  `auth_provider.dart`, `public_tenant_provider.dart`, ...).
- `models/` — Hand-written JSON models (`Resource`, `BookingType`, `Booking`, ...).

## Agentic AI subsystem (`agentic-ai-service/`)

A separate Python FastAPI microservice implementing a real 4-agent LLM pipeline
(Planner → Domain Analysis → Action/Tool → Validation/Safety, via Gemini), called only
by the ASP.NET Core backend (never directly by the web or mobile apps) through a
shared-secret bearer token. Handles natural-language objectives like *"find me the
best dentist this week"* or *"book a whale watching trip for 4 people this weekend."*
The Validation/Safety agent is plain deterministic Python (never calls Gemini) and is
the only place allowed to create a booking. Converges on the same `AgentWorkflow`
table and `/approve`/`/reject`/`/apply` endpoints as the older deterministic bulk
scheduler, rather than replacing it. Requires a `GEMINI_API_KEY` in
`agentic-ai-service/.env` to exercise live (test suite mocks Gemini entirely).

## Data & deployment

- Database: Supabase-hosted PostgreSQL (`se3090-booking-db`). Table names for the
  core booking domain are lowercase snake_case (`resources`, `bookings`,
  `booking_types`, ...) via explicit EF `ToTable()` calls; `Tenants`/`Users`/
  `Branches`/`TenantModules` keep PascalCase (default EF convention). Columns stay
  PascalCase throughout regardless of table naming.
- Real connection string lives in `dotnet user-secrets` (not `appsettings.json`,
  which only has a local-Postgres placeholder) — run backend commands with
  `ASPNETCORE_ENVIRONMENT=Development` to pick it up.
- Demo/seed data: `scripts/seed-demo-data.ps1` (one business per core type),
  `scripts/seed-mirissa-jetliner.ps1` and `scripts/seed-tourism-night-daterange.ps1`
  (real Tourism sub-type examples), `scripts/seed-tourism-template.ps1` (reusable
  scaffold for adding more).

## Known gaps

- Billing/Inventory (FR-AS12-20) not started — schema stubs only.
- "Package" bookings don't do true atomic multi-resource composite reservation.
- Per-ticket-type pricing (e.g. adult/child counts within one booking) isn't modeled
  natively — approximated via `CustomAttributes`/`ConfigJson` metadata only.
- Some legacy junk/test tenant data exists in the live database from earlier manual
  testing (not cleaned up per user's own choice to leave it for now).
