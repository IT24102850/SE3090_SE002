# Agentic AI Subsystem

A four-agent pipeline (Planner → Domain Analysis → Action/Tool → Validation/Safety) that turns a customer's natural-language objective ("find and book the best dentist near me this week") into a real booking — or a manager-approval request when the action is high-impact.

This is an **internal microservice**. It is called only by the ASP.NET Core backend (`backend/SmeBackend`), never directly by the React admin app or the Flutter mobile app. It never touches Postgres directly — every read/write goes back through the existing, already-authorized ASP.NET Core API, using a JWT minted for the actual customer making the request.

## Architecture

```
Flutter app → ASP.NET Core (POST /api/agent/find-and-book)
                   │
                   │ mints a short-lived customer JWT, calls:
                   ▼
        agentic-ai-service (POST /plan, shared-secret bearer auth)
                   │
     ┌─────────────┼──────────────┬───────────────────┐
     ▼             ▼               ▼                   ▼
 Planner    Domain Analysis   Action/Tool      Validation/Safety
 (no tools)  (search_resources, (query_availability,  (plain Python,
             get_resource_metadata)  detect_conflicts)   no LLM — creates
                                                          the booking or
                                                          flags for approval)
                   │
                   │ every tool call uses the customer's JWT
                   ▼
        ASP.NET Core's existing, already-authorized endpoints
        (GET /resources, GET /resources/{id}, GET /bookings/available-slots,
         POST /bookings)
```

The inventory assistant has its own internal endpoint, `POST /inventory/plan`. The Planner interprets the request, Domain Analysis uses caller-authorized inventory and movement tools, Action/Tool computes replenishment suggestions from the returned data, and the deterministic Validation/Safety step rejects invalid suggestions. This flow is read-only: a user reviews a suggested quantity and explicitly creates any purchase order through the existing ASP.NET Core purchase-order screen. It does not edit stock, place an order, or let the model invent the stock values used for its calculations.

`/plan` runs all four agents **synchronously** and returns one complete trace. `/workflow/{id}/trace`, `/approve`, `/reject` operate on an **in-memory** store keyed by that run's `workflow_id` — useful for testing/introspecting this service in isolation, but they are **not** the production approval path. Production approval always goes through ASP.NET Core's own `/api/agent/workflow/{id}/approve` / `/reject` / `/apply` (already built, backed by Postgres) — React and the customer's phone never talk to this service directly.

## Setup

1. **Get a free Gemini API key**: go to [Google AI Studio](https://aistudio.google.com/apikey), sign in, click "Create API key". No paid subscription required — this uses the free tier.
2. `cp .env.example .env` and fill in `GEMINI_API_KEY` and a random `AGENT_SERVICE_INTERNAL_TOKEN` (this same value must be configured on the ASP.NET Core side, under `AgentService:InternalToken`).
3. `python -m venv .venv && .venv/Scripts/activate` (or `source .venv/bin/activate` on macOS/Linux)
4. `pip install -r requirements.txt`

## Startup order

1. `backend/SmeBackend` — `dotnet run` (must be up first; this service calls back into it)
2. `agentic-ai-service` — `uvicorn main:app --port 8001 --reload`
3. Then a customer request through the Flutter app (or a direct `curl` to `POST /api/agent/find-and-book` on the backend) can exercise the full pipeline.

## Deployment

`render.yaml` deploys only the ASP.NET Core backend. Deploy this Python service separately, then set the backend's `AgentService:BaseUrl` (`AgentService__BaseUrl` on Render) to the service's reachable HTTPS URL. Set the same `AGENT_SERVICE_INTERNAL_TOKEN` value on both services, and configure `BACKEND_API_BASE_URL` on the Python service to the backend API URL. Until the base URL and shared token are configured, customer AI booking requests return a clear configuration error; the rest of the app remains available.

## Running tests

```
pytest tests/ -v
```

All tests run with the real Gemini SDK **mocked out** at the `gemini_client` boundary (or, for pipeline-level tests, at each agent's `run()` boundary) — no live API key or live backend needed to run the suite. This is deliberate: the tests validate orchestration, the deterministic safety gate, and defensive JSON parsing, not Gemini's own output quality on a given day.

## Model IDs

The inventory planner defaults to `gemini-3.5-flash-lite` and can be overridden with `GEMINI_MODEL_INVENTORY`. Other agents use `GEMINI_MODEL_DEFAULT` (default `gemini-2.5-flash`); the booking planner can also be overridden with `GEMINI_MODEL_PLANNER`. Choose model IDs supported by the API key's project; Google currently limits access to Gemini 2.5 models for projects that have actively used them. See [the current Gemini model list](https://ai.google.dev/gemini-api/docs/models).

## Known limitations

- Inventory movement history is capped at the backend's latest 100 records, and the inventory snapshot at 100 items. The forecast counts explicit issue/sale/consumption and negative manual-adjustment movements as outflow; waste and positive corrections are excluded. When no such history is present, it clearly falls back to the item's reorder level and marks confidence lower. Supplier choice, lead time, and budget still need human review before creating a purchase order.

- The underlying `Resource`/`BookingType` schema in the backend was built during earlier clinic-focused work and still has a few clinic-shaped names (`Specialty`'s doc-comment literally says "Doctor/staff specialty"). This service's agents and tools stay generic (driven by `business_type`/`resource_type`/`extra_constraints`), but the DB schema itself wasn't reshaped in this pass.
- Domain Analysis's ranking quality depends on `Resource.CustomAttributes`/`LocationMetadata` (rating, cuisine, distance, etc.) actually being populated — there's no web UI for editing that JSON blob yet, only the API fields. Demo data needs it set directly via the API for ranking to show real differentiation instead of "first match wins."
- `/plan` requires the caller to already know which `BookingType` applies (`extra_constraints.booking_type_id`) — it doesn't infer the visit type from free text. A customer picks a booking type in the app before typing their objective, same as the rest of the booking flow.
