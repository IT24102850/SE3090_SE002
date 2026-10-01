# Changes from the Group Task Assignment plan

The Group Task Assignment document was written in week 1. This page records
where the delivered system differs from it and why, so the plan and the
system can be read side by side. Where a change is an architectural decision
it has an ADR ([`ADR/ADR.md`](ADR/ADR.md)).

## Agentic AI ownership

| Plan | Delivered | Evidence |
|---|---|---|
| Hasiru: Planner/Coordinator agent. Student 2: Domain Analysis agent. Student 3: Action/Tool + Validation/Safety agents. | Each student owns a **complete agent workflow** in their own component instead of one agent of a single shared pipeline. Hasiru built the four-agent booking pipeline (Planner, Domain Analysis, Action/Tool, Validation/Safety), which serves Schedule Copilot and find-and-book. Oshadi built the Billing Copilot. Hasaranga built the StockSense inventory agents; the reorder workflow on top of them (safety gate, approval, persisted state) was prepared by Hasiru with Claude Code and reviewed by Hasaranga. | `git log --author=<id> -- agentic-ai-service/agents/` and the README "Team Members" table |

Why: each student needs a distinct, explainable Agentic AI contribution
(spec §3, rubric "Individual Agentic AI Contribution"). Splitting one pipeline
four ways would have made every student's agent depend on the others' code.
It would also have made "distinct" hard to show: an agent with no workflow of
its own has no visible participation of its own.

## Validation/Safety: one gate per workflow, not one shared agent

The plan described a single shared Validation/Safety agent guarding every
high-impact action in Booking, Billing and Inventory. What was built is a
deterministic gate inside each workflow, because each domain's rules and
approval thresholds are different and belong with the code that owns them:

| Workflow | Gate | Pauses for approval when |
|---|---|---|
| Find-and-book (customer) | `agents/validation_safety_agent.py` | more than 20 bookings, or estimated revenue impact above $500 |
| Schedule Copilot (staff) | `agents/schedule_safety.py` | more than 20 bookings or revenue impact above $500; rejects conflicts, over 8 h/day, lunch-break clashes, appointments over 2 h |
| Bulk / recurring booking changes | `BookingsController` → `AgentWorkflow` | a batch or recurring series creates more than 20 bookings |
| Billing Copilot | `Services/Billing/BillingAgentService.cs` + `BillingApprovalService` | an adjustment or claim above the tenant's configured thresholds; the planner cannot loosen them |
| Platform Operations Copilot | `agents/platform_safety.py` + API step-up | every intervention needs the owner's fresh authenticator code |
| StockSense reorders (inventory) | `Services/Inventory/ReorderSafetyGate.cs`, re-run on approval | order value above LKR 150,000 (≈ the plan's $500), more than 100 units, a supplier never received from, or an item without a unit cost; rejects inactive suppliers, non-positive or absurd quantities and items from another branch |

None of the gates calls a language model.

## Frameworks and platforms

| Plan | Delivered | Why | Record |
|---|---|---|---|
| LangGraph | Custom orchestration in FastAPI | A fixed, auditable sequence with a deterministic safety gate. A graph runtime added a dependency without adding control. | ADR-003 |
| Ollama local model | Gemini by default; Ollama supported through `LLM_PROVIDER=ollama` | Ollama needs a machine with enough RAM/GPU to run the model during the demo; Gemini's free tier runs anywhere. The provider switch keeps the local option. | ADR-003, `agentic-ai-service/llm_client.py` |
| Railway (API + DB) | Render (API + agent service), Supabase (PostgreSQL) | Railway's trial ended mid-project and required payment; the spec requires no-cost services. | ADR-005 |
| FullCalendar | Custom calendar (`features/booking/CalendarDashboardPage.tsx`) | The views needed (day/week, per-resource columns, status colours) did not justify the dependency. | — |
| PostgreSQL trigger for low stock | The API raises a "LowStock" notification on the stock movement that takes an item below its reorder level (`Services/Inventory/LowStockAlerts.cs`) | Business rules stay in the application layer, where they are tested and versioned with the code. | — |

## Cross-platform workflow

The plan's example was an AI-driven inventory reorder. The assessed
cross-platform workflow is **find-and-book**: a customer asks in Flutter,
ASP.NET Core runs the four-agent pipeline and stores the workflow in
PostgreSQL, a manager approves, rejects or asks for a revision in React's
Agent Workflow Monitor, and the result returns to the customer in Flutter.
It satisfies every step of the spec's minimum acceptance workflow (§9.1) and
cross-platform pattern (§10).

The plan's inventory reorder also runs end to end. Staff run StockSense in
Flutter and request a reorder from its recommendations. ASP.NET Core prices
the request from inventory records, runs `ReorderSafetyGate` and records the
workflow in PostgreSQL. A reorder over the limits pauses. A branch manager
approves, rejects or asks for a revision in React's Agent Workflow Monitor.
The purchase order is placed on approval, and the requester is notified on
their phone. Two differences from the plan: the requester picks the supplier,
because inventory items carry no supplier link; and there is no PostgreSQL
trigger (see below).

## Notifications

The plan assumed Firebase Cloud Messaging. FCM needs a Firebase project
compiled into the APK, which this project does not have. Instead the API
streams every notification to the signed-in user (Server-Sent Events,
`GET /api/notifications/stream`), and the Flutter app raises each one as an
Android system notification (`services/device_notification_service.dart`).
The limitation: notifications arrive while the app is running or in the
background, not after Android has killed it. That is the part FCM would add.
Every notification is also kept in the in-app list.

## Process

The plan said "no direct pushes to main; all changes via reviewed PRs" and
"3-5 commits per member per week". The Git history does not meet either
commitment for most of the project. From 30 September every change goes
through a pull request that a teammate reviews before merging (PR #24
onwards).
