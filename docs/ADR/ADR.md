# Architecture Decision Records — SE3090_SE002
## Universal SME Management Platform

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

## ADR-003: Agentic AI Framework

**Status:** Accepted

**Context:**
The system requires four distinct agents (Planner/Coordinator, Domain Analysis, Action/Tool, 
Validation/Safety) with structured multi-step planning, delegation, persisted workflow state, 
and human-in-the-loop approval pauses — all called internally from ASP.NET Core, never directly 
from React or Flutter, per the assignment's mandatory backend rule.

**Options Considered:**
1. **Semantic Kernel (C#)** — would keep everything in one language, but has less mature 
   built-in support for human-in-the-loop pause/resume graph nodes compared to LangGraph.
2. **LlamaIndex agents** — strong for retrieval-augmented workflows, but its agent-orchestration 
   and multi-agent delegation patterns are less purpose-built for our planner-delegates-to-
   specialist-agents structure.
3. **Custom orchestration (Python or C#)** — full control, but reinventing state persistence, 
   retries, and approval-pause logic from scratch is high-risk for a 9-week deadline.
4. **LangGraph + FastAPI (chosen)** — used in labs, has built-in state persistence, explicit 
   human-approval graph nodes, and graph-based delegation that maps directly onto our four-
   agent architecture.

**Decision:**
We chose LangGraph running as an internal Python/FastAPI microservice, called only by ASP.NET 
Core, because its graph model lets us represent the Planner Agent's delegation to the Domain 
Analysis, Action/Tool, and Validation/Safety agents as explicit graph edges, with native support 
for pausing a node until a human approval endpoint is called.

**Consequences:**
- Positive: Matches the assignment's minimum-workflow requirements almost directly (plan → 
  delegate → tool call → validate → pause for approval → auditable result); reduces custom 
  state-management code.
- Trade-off: Adds a second language/runtime (Python) alongside the C# backend, requiring careful 
  process management (startup order, health checks) documented in our deployment instructions.

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