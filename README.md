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
