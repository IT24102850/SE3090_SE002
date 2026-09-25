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
2. `cp .env.example .env` and fill in `GEMINI_API_KEY` and a random `AGENT_SERVICE_INTERNAL_TOKEN` (this same value must be configured on the ASP.NET Core side, under `AgentService:InternalToken`, which on a dev machine lives in .NET user-secrets rather than `appsettings.Development.json`). Never commit `.env` — it is gitignored.
3. `python -m venv .venv && .venv/Scripts/activate` (or `source .venv/bin/activate` on macOS/Linux)
4. `pip install -r requirements.txt`

## Startup order

1. `backend/SmeBackend` — `dotnet run` (must be up first; this service calls back into it)
2. `agentic-ai-service` — `uvicorn main:app --port 8001 --reload`
3. Then a customer request through the Flutter app (or a direct `curl` to `POST /api/agent/find-and-book` on the backend) can exercise the full pipeline.

## Deployment

`render.yaml` deploys only the ASP.NET Core backend. Deploy this Python service separately, then set the backend's `AgentService:BaseUrl` (`AgentService__BaseUrl` on Render) to the service's reachable HTTPS URL. Set the same `AGENT_SERVICE_INTERNAL_TOKEN` value on both services, and configure `BACKEND_API_BASE_URL` on the Python service to the backend API URL. Until the base URL and shared token are configured, customer AI booking requests return a clear configuration error; the rest of the app remains available.

## Is it working? (`python check_health.py`)

One command, run from this folder, that answers the question before a demo:

```
python check_health.py      # exit code 0 = ready
```

It checks the key, which models the key reaches **today**, that the service is up and its shared
secret matches, and then runs all four agents end to end. The last check is the one that counts: a
working key proves nothing about the agents, and the pipeline deliberately keeps working when Gemini
is down, so "it produced a schedule" is not the same as "the language model drove it". The script
says which happened:

- `Gemini wrote the plan (confidence 0.85)` - the language model planned it.
- `The DETERMINISTIC planner ran` - Gemini was unreachable; the agents, tools and safety gate all
  still ran, only the objective's reading is simpler.

Free-tier quota is per model and per day, so it is normal to see one model exhausted and the next in
`GEMINI_MODEL_FALLBACKS` covering it. That is the resilience layer working, not a fault. The script
never prints the key or the token, so its output is safe to screenshot for the report.

## Running tests

```
pytest tests/ -v
```

All tests run with the real Gemini SDK **mocked out** at the `gemini_client` boundary (or, for pipeline-level tests, at each agent's `run()` boundary) — no live API key or live backend needed to run the suite. This is deliberate: the tests validate orchestration, the deterministic safety gate, and defensive JSON parsing, not Gemini's own output quality on a given day.

## Model IDs

The inventory planner defaults to `gemini-3.5-flash-lite` and can be overridden with `GEMINI_MODEL_INVENTORY`. Other agents use `GEMINI_MODEL_DEFAULT` (default `gemini-3.5-flash`); the booking planner can also be overridden with `GEMINI_MODEL_PLANNER`.

**Model availability is per-key and changes.** Measured against a key issued 2026-09-24:

| Model | Result |
| --- | --- |
| `gemini-3.5-flash` | works, ~6s for a planner call |
| `gemini-flash-lite-latest` | works, ~7s |
| `gemini-flash-latest` | works but ~22s, and intermittently 503 "high demand" |
| `gemini-2.5-flash`, `gemini-2.5-flash-lite` | **404** — not available to recently issued keys |

Do not pin a 2.5 model on a new key. See [the current Gemini model list](https://ai.google.dev/gemini-api/docs/models).

## Schedule Copilot (`POST /schedule/plan`) — the Planner/Coordinator workflow

The staff-facing workflow for assignment component 2.7. A manager states an objective in plain words
("Line up 6 property viewings for Thursday's buyers and leave time to drive between houses") plus explicit
constraints, and four agents turn it into a validated proposal. Called only by ASP.NET Core
(`POST /api/agent/workflow/plan-schedule`, Admin/Manager), used by the React **Schedule Copilot** page and the
Flutter owner app.

**Contract (spec 2.7).** Input `{ objective, constraints: { date_range, resource_ids[], priority_rules[] }, tenant_id }`;
the Planner returns `{ plan: Step[], assigned_agents[], predicted_conflicts[], confidence_score }`.
See `schemas/schedule_contracts.py`.

| Agent | Module | Model? | Allow-listed tools | Job |
| --- | --- | --- | --- | --- |
| Planner / Coordinator | `agents/schedule_planner.py` | Gemini, deterministic fallback | *none* | Reads the objective, writes the plan, predicts conflicts, extracts intent (rules, weekdays, "only" windows, gaps) |
| Domain Analysis | `agents/schedule_analyst.py` | no | `search_resources`, `check_staff_schedule`, `query_booking_history`, `predict_no_show_probability` | Ranks resources on open days, current load and 90-day no-show rate; estimates booking value |
| Action / Tool | `agents/schedule_action.py` | no | `query_resource_availability`, `calculate_travel_time`, `detect_conflicts` | Constraint-aware greedy optimiser over real open slots; explains every pick and every skip |
| Validation / Safety | `agents/schedule_safety.py` | no | `detect_conflicts`, `check_staff_schedule` | Nine named checks; decides reject / approve-required / ready |

**Least privilege is enforced, not documented.** Each agent only ever receives an `AgentToolbox` bound to its
row of `ALLOWED_TOOLS` (`tools/schedule_tools.py`); calling anything else raises `ToolPermissionError` and is
recorded in the trace. Every tool is a read made with the calling manager's own JWT — nothing here can book.

**The planner can only narrow.** It may add priority rules from a closed vocabulary, name weekdays, or ask for
fewer bookings. It cannot raise the count, invent a rule, give a step a tool its agent is not allowed, skip an
agent (such a plan is discarded for the deterministic one), or touch the approval thresholds.

**Business rules (Validation/Safety).** schema · count · future · duration ≤ 120 min · no double-booking ·
live re-verification · daily cap (the resource's `MaxDailyBookedHours`, default 8h) · lunch break ·
coverage (warn only). Any hard failure returns the whole plan for revision rather than trimming it.

**Human approval.** More than `APPROVAL_BOOKING_COUNT_THRESHOLD` (20) bookings, or an estimated revenue impact
above `APPROVAL_REVENUE_THRESHOLD` (500) **USD**. Revenue is the 90-day average of what this booking type actually
charged (falling back to hourly rates), converted from the tenant's currency with an approximate, labelled rate —
comparing rupees to 500 would escalate every Sri Lankan schedule.

**The lifecycle cannot route round the gate** (ASP.NET Core): only a *pending* workflow can be approved or revised;
a revision may only remove proposals the agents already validated, never add one; a plan the gate rejected, or one
that failed, cannot be applied.

**Tests.** `tests/test_schedule_copilot.py` runs the real tool client against an HTTP-level fake of the API
(`tests/schedule_fakes.py`): both spec golden cases, approval by count and by revenue, currency conversion, the
daily cap, lunch, time-of-day and weekday intent, load balancing, no-show avoidance, a slot stolen mid-workflow,
prompt injection, invalid model plans, model outage, tool permissions, backend outage and endpoint security.

## Resilience

A single model returning 503 used to abort the whole workflow, which made the
pipeline hostage to someone else's traffic spike. `gemini_client` now:

- **retries transient failures** (503, 429, 5xx, timeouts) on the same model,
  `GEMINI_MAX_ATTEMPTS` times with exponential backoff from
  `GEMINI_BACKOFF_SECONDS`;
- **falls back across models** listed in `GEMINI_MODEL_FALLBACKS` once a model
  is exhausted;
- **does not retry permanent failures** — a 404 (model not available to this
  key) or a 400/401/403 skips straight to the next model, because waiting
  cannot fix it;
- **still fails safely** when the whole chain is exhausted: `AgentSafeFailure`,
  which the caller turns into a 422 with a populated trace, never a crash.

## Observability

`WorkflowTrace` carries the auditable execution summary, and ASP.NET Core
persists it onto `AgentWorkflows` (`ToolResultsJson` / `ValidationResults`),
where the React Agent Workflow Monitor renders it under "Execution trace":

- `agent_steps` — each agent's wall-clock cost, recorded whether it succeeded
  or failed, so a failed run can say *which agent* it died in;
- `tool_calls` — every allow-listed tool invocation with its calling agent,
  duration and outcome, recorded by a decorator on the client so a tool cannot
  run without appearing in the trail, including when it raises;
- `llm_calls` — one entry per attempt per model. Several entries for one
  logical step is the retry/fallback layer working, not a fault.

These are folded into the trace *before* the response is serialized, not in a
`finally` block: `finally` runs after the return expression is evaluated, so
draining there shipped an empty trace on exactly the failure paths where it
matters. `tests/test_observability.py` pins that behaviour.

## Known limitations

- Inventory movement history is capped at the backend's latest 100 records, and the inventory snapshot at 100 items. The forecast counts explicit issue/sale/consumption and negative manual-adjustment movements as outflow; waste and positive corrections are excluded. When no such history is present, it clearly falls back to the item's reorder level and marks confidence lower. Supplier choice, lead time, and budget still need human review before creating a purchase order.

- The underlying `Resource`/`BookingType` schema in the backend was built during earlier clinic-focused work and still has a few clinic-shaped names (`Specialty`'s doc-comment literally says "Doctor/staff specialty"). This service's agents and tools stay generic (driven by `business_type`/`resource_type`/`extra_constraints`), but the DB schema itself wasn't reshaped in this pass.
- Domain Analysis's ranking quality depends on `Resource.CustomAttributes`/`LocationMetadata` (rating, cuisine, distance, etc.) actually being populated — there's no web UI for editing that JSON blob yet, only the API fields. Demo data needs it set directly via the API for ranking to show real differentiation instead of "first match wins."
- `/plan` requires the caller to already know which `BookingType` applies (`extra_constraints.booking_type_id`) — it doesn't infer the visit type from free text. A customer picks a booking type in the app before typing their objective, same as the rest of the booking flow.
