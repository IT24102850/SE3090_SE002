# Architecture Decision Records — SE3090_SE002
## Unify

---

## ADR-001: React State Management

**Status:** Accepted

**Context:**
The React web application supports three independently-developed admin modules (Booking, 
Billing, Inventory) that all consume the same authenticated session, tenant context, and 
Agentic AI workflow data. Each module needs complex async data fetching (bookings, invoices, 
stock levels) alongside shared cross-cutting state (auth token, current tenant, role).

**Options Considered:**
1. **Context API** — built into React, no extra dependency, but causes unnecessary re-renders 
   across unrelated modules when shared state changes, and offers no structured pattern for 
   async API calls at this scale.
2. **Zustand** — lightweight and simple, but less structured for a 3-person team working in 
   parallel; weaker built-in devtools/async conventions than RTK.
3. **MobX** — powerful but has a steeper learning curve and less predictable data flow, which 
   makes it harder for three people to debug each other's modules during the viva.
4. **Redux Toolkit (chosen)** — predictable, centralized state with RTK Query for typed async 
   API calls, and Redux DevTools for live debugging during development and demo.

**Decision:**
We chose Redux Toolkit because it gives each team member an isolated "slice" (bookingSlice, 
billingSlice, inventorySlice) that can be developed independently without state collisions, 
while RTK Query standardizes how all three modules call the shared ASP.NET Core API (caching, 
loading/error states, automatic refetching on mutation).

**Consequences:**
- Positive: Predictable state flow, built-in caching reduces redundant API calls, DevTools 
  makes debugging live during the viva straightforward.
- Trade-off: More boilerplate than Context API for simple state; team needs to agree on slice 
  boundaries early to avoid duplicate logic.

---

## ADR-002: Flutter State Management

**Status:** Accepted

**Context:**
The Flutter mobile app needs to manage authenticated API calls, real-time status updates 
(booking confirmations, payment status, low-stock alerts), and device-feature-driven state 
(QR scans, camera uploads) across three independently-built modules, while keeping the app 
testable for the required Flutter widget tests.

**Options Considered:**
1. **Bloc** — powerful and testable, but introduces significant boilerplate (events, states, 
   bloc classes) that slows down a 9-week team project.
2. **Provider** — simple but weaker testability guarantees and less compile-time safety for 
   dependency injection across modules owned by different students.
3. **GetX** — fast to write but relies on "magic" (implicit dependency resolution, global 
   state) that makes code harder to explain individually during the viva.
4. **Riverpod (chosen)** — compile-safe, testable, and works well with async data (FutureProvider/
   StreamProvider) for the same kind of workflow-status polling every module needs.

**Decision:**
We chose Riverpod because its compile-time safety catches provider-wiring mistakes before 
runtime (important across three parallel codebases), and its `ProviderScope` overrides make 
Flutter widget tests straightforward to write and defend individually at the viva.

**Consequences:**
- Positive: Compile-safe DI, easy unit/widget testing, clean async state handling for agent-
  triggered UI updates (e.g. PO approval status).
- Trade-off: Slightly steeper learning curve than Provider for anyone new to Riverpod; requires 
  consistent naming conventions across three students' modules to stay organized.

---

## ADR-003: Agentic AI Framework and Orchestration Method

**Status:** Accepted (revised — an earlier revision of this ADR recorded LangGraph; the
implementation is a custom orchestration, and this record has been corrected to match the
code rather than the other way round.)

**Context:**
The system requires four distinct agents (Planner/Coordinator, Domain Analysis, Action/Tool,
Validation/Safety) with structured multi-step planning, delegation, persisted workflow state,
and human-in-the-loop approval pauses — all called internally from ASP.NET Core, never directly
from React or Flutter, per the assignment's mandatory backend rule.

Two facts about our design shaped this decision, and both only became clear once the approval
flow was built:

1. **The pipeline is a fixed sequence, not a graph.** Planner → Domain Analysis → Action/Tool →
   Validation/Safety runs in that order every time. There is no branching topology, no cyclic
   delegation and no dynamic agent selection for a graph runtime to express.
2. **The approval pause does not live in the Python service.** The authoritative workflow record
   is the `AgentWorkflows` table in Postgres, and the approve/reject/revise endpoints are on
   ASP.NET Core because that is where role-based authorization (`Admin,Manager`) and the
   business data already are. A framework's human-in-the-loop node would have had to hold
   approval state in a second place, which is the split-brain problem ADR-004 exists to avoid.

**Options Considered:**
1. **Semantic Kernel (C#)** — would keep everything in one language. Rejected: the assignment's
   reference architecture and our lab experience are both Python-side, and it would not have
   removed the need for our own deterministic safety gate.
2. **LlamaIndex agents** — strong for retrieval-augmented workflows. Rejected: our problem is
   constraint-checked scheduling against a live API, not retrieval over a corpus.
3. **LangGraph + FastAPI** — used in labs; built-in state persistence and human-approval nodes.
   Rejected on the two facts above: its state persistence would duplicate `AgentWorkflows`, and
   its graph model would wrap a straight line. It also adds a substantial dependency whose
   internals every team member would have to be able to explain under §18.2.
4. **Custom orchestration in Python + FastAPI (chosen)** — a plain, readable call sequence with
   Pydantic contracts at every agent boundary.

**Decision:**
We implemented a custom four-agent orchestration as an internal Python/FastAPI microservice
(`agentic-ai-service`), called only by ASP.NET Core. Each agent is a module with an explicit
Pydantic input/output contract in `schemas/contracts.py`; `main.py:/plan` runs them in sequence
and assembles one `WorkflowTrace`. The Validation/Safety agent is deliberately **deterministic
Python with no LLM call**, so the gate that decides whether a booking is allowed or must be
escalated cannot be talked out of its decision by model output. Model access goes through one
`llm_client` seam, so the provider (Gemini by default, Ollama behind `LLM_PROVIDER`) can be
swapped without touching an agent.

**Consequences:**
- Positive: every element the assignment asks for is code we wrote and can explain — planning,
  delegation, allow-listed tools, deterministic validation, safe failure, and the execution
  trace. This directly serves the "explain, modify or debug your own contribution" requirement.
- Positive: one source of truth for workflow state (Postgres, via ASP.NET Core). The Python
  service's in-memory `_workflows` dict is explicitly a testing/introspection aid and is
  documented as not being the production approval path.
- Trade-off: we had to build retry, model fallback and the observability trace ourselves rather
  than inheriting them. That work is real — see `gemini_client._call_with_resilience` and
  `tests/test_observability.py` — and it was necessary regardless, because free-tier Gemini
  returns 503 on individual models under load and no framework would have chosen our fallback
  chain for us.
- Trade-off: adds a second language/runtime (Python) alongside the C# backend, requiring careful
  process management (startup order, health checks) documented in the deployment instructions.

---

## ADR-004: Database Strategy for Agent Workflow State

**Status:** Accepted

**Context:**
All four agents need to persist workflow ID, objective, plan, completed steps, tool results, 
validation results, approval status, and final outcome in a way that is auditable, queryable 
from the React Agent Workflow Monitor, and consistent with our existing PostgreSQL business 
data (Bookings, Invoices, Inventory).

**Options Considered:**
1. **JSONB columns on existing entities** — flexible, but harder to query and index for the 
   Agent Workflow Monitor's filtering/reporting needs, and blurs the boundary between business 
   data and agent execution history.
2. **MongoDB (separate store)** — good for unstructured workflow logs, but introduces a second 
   database technology, contradicting the assignment's single-database simplicity goal and 
   complicating backup/restore.
3. **Redis** — fast, but not durable enough by default for an audit trail that must survive 
   restarts and be reviewable weeks later during evaluation.
4. **Dedicated PostgreSQL `AgentWorkflows` table (chosen)** — a shared, structured table with 
   EF Core migrations, foreign keys to Users (ApprovedBy) and business entities, queried directly 
   by all three team members' controllers.

**Decision:**
We chose a dedicated `AgentWorkflows` table with columns for Objective, PlanJson, Status, 
CurrentStep, ToolResultsJson, ValidationResults, ApprovalStatus, and ApprovedBy, giving us ACID 
transactional consistency with the rest of our business data and a single source of truth 
queryable via standard EF Core LINQ from the Agent Workflow Monitor endpoints.

**Consequences:**
- Positive: One database technology to deploy/back up/document; relational consistency with 
  Users/Bookings/Invoices via foreign keys; straightforward to satisfy the observability 
  requirement (execution traces are just SQL rows).
- Trade-off: JSON columns (PlanJson, ToolResultsJson) trade some query-ability for flexibility, 
  since plan/tool-result shapes vary by agent — mitigated by keeping JSON schema-validated at 
  the application layer before persistence.

---

## ADR-005: Cloud Deployment Platform

**Status:** Accepted (revised August 2, 2026)

**Context:**
The assignment requires all components (ASP.NET Core API, PostgreSQL, React, Agentic AI 
service) to run on institution-provided or genuinely free-tier services, since paid 
subscriptions are explicitly not permitted. Our original choice (Railway for API + DB, Vercel 
for React) needed revisiting after Railway's trial period ended and began requiring payment 
before Week 1 was complete.

**Options Considered:**
1. **Railway (original choice) + Vercel** — Railway's trial expired days into the project and 
   now requires a paid plan to continue, which violates the assignment's no-cost requirement.
2. **Azure Free Tier** — generous compute, but requires a credit card on file and has a steeper 
   setup/configuration overhead for a 3-person team on a 9-week deadline.
3. **AWS Free Tier** — similarly capable but overkill in complexity and configuration time for 
   our scope, with a higher risk of accidentally exceeding free-tier limits.
4. **Supabase (PostgreSQL) + Render or Fly.io (API) + Vercel (React) (chosen)** — Supabase's 
   free tier is not trial-based, Render offers a genuinely free web-service tier without a card, 
   and Vercel remains the best fit for instant React deployments.

**Decision:**
We chose Supabase for PostgreSQL (already provisioned and migrated successfully), Render (or 
Fly.io, pending final team testing) for the ASP.NET Core API, and Vercel for the React 
frontend — all genuinely free tiers with no card-driven trial expiry risk before submission.

**Consequences:**
- Positive: No risk of a mid-project paywall like we hit with Railway; Supabase's pooler 
  connection (used for our EF Core migrations) is already working end-to-end.
- Trade-off: Splitting DB and API hosting across two providers instead of one adds a small 
  amount of extra configuration (two dashboards, two sets of environment variables) versus 
  Railway's single-platform convenience — documented clearly in our README to keep setup 
  reproducible for evaluators.

---

## ADR-006: Multi-Tenancy Strategy

**Status:** Accepted

**Context:**
The platform serves multiple SME business types (Clinic, Restaurant, Gym, Tuition, Real 
Estate, Tourism, General Business) as distinct tenants sharing one deployed system, and must 
guarantee that one tenant's data (bookings, invoices, inventory) is never visible to another, 
while keeping the assignment achievable for a 3-person team within 9 weeks.

**Options Considered:**
1. **Separate database per tenant** — the strongest isolation guarantee, but multiplies 
   deployment, migration, and backup complexity far beyond what three students can maintain 
   and demo reliably within the timeline.
2. **Separate schema per tenant** — better isolation than shared-schema, but EF Core's tooling 
   support for dynamic per-tenant schema switching is significantly more complex to implement 
   and test correctly than global query filters.
3. **Shared database, shared schema with TenantId (chosen)** — every table carries a `TenantId` 
   foreign key, with EF Core global query filters automatically scoping every query.

**Decision:**
We chose a shared database, shared schema design where every business entity (Bookings, 
Invoices, InventoryItems, etc.) includes a `TenantId` column, enforced via EF Core global query 
filters injected by tenant-context middleware, giving us tenant isolation without the 
operational overhead of managing multiple databases or schemas.

**Consequences:**
- Positive: Single migration history to maintain, simple backup/restore, cost-effective for 
  small-SME use cases where full physical isolation isn't a hard business requirement.
- Trade-off: Relies entirely on correct enforcement of the global query filter in every query 
  path — a missed filter could leak cross-tenant data, so we treat this as a security-critical 
  code-review checkpoint on every pull request touching a tenant-scoped entity.