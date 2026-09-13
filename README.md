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

## Getting Started
See `/docs/` for setup instructions.

## Railway deployment

The root [`railway.toml`](railway.toml) publishes `backend/SmeBackend` and
configures Railway's deployment health check. Create a Railway service from
this repository and set these variables:

- `ASPNETCORE_ENVIRONMENT=Production`
- `Jwt__Key` — a long, private signing key (at least 32 bytes)
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

## License
MIT
