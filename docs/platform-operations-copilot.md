# Platform Operations Copilot — the platform owner's Agentic AI workflow

Written for: the SE3090 evaluators, and engineers working on this codebase.

The owner console shows 29 businesses and a revenue page. The hard question
it does not answer is *"which of these is about to leave, and what should I
do about each one?"* — which needs cross-tenant signals read, causes
distinguished, remedies with different costs chosen between, those remedies
checked against policy, and then an action that moves real money.

That is what this workflow does. It is the fourth agentic flow in the system
and the only one that reasons **across** tenants rather than inside one.

---

## The property the design is built on

**The agent cannot carry out a high-impact action. Not "is instructed not
to" — cannot.**

Applying an intervention means extending a paid term or comping a plan.
Both go through `POST /api/platform/copilot/{id}/approve`, which requires a
fresh TOTP code in `X-Platform-Otp` — the same step-up that guards suspending
a tenant or resetting a user's password.

The agent service has no database credentials, no write tool, and no way to
produce an authenticator code. So there is no sequence of model outputs —
however confident, however well injected — that moves money on this platform.
A human with the authenticator does it, or it does not happen.

This is why `requires_human_approval` is not a boolean a model could talk its
way past. It is enforced by something only a person holds.

---

## The four agents

| Agent | Responsibility | Tools | Model? |
|---|---|---|---|
| **PlatformPlannerAgent** | Objective → ordered plan; states its reading of the goal | none | yes |
| **PlatformAnalysisAgent** | Who is at risk of leaving, and on what evidence | `get_revenue_overview`, `list_subscriptions`, `list_open_invoices` | yes |
| **PlatformActionAgent** | One intervention per business, with cost and what it protects | `get_tenant_detail` | yes |
| **PlatformSafetyAgent** | Policy, spending caps, blast radius | none | **no — plain Python** |

Each has its own Pydantic input/output contract in
[`schemas/platform_contracts.py`](../agentic-ai-service/schemas/platform_contracts.py),
its own tool permissions, and a visible step in the trace. They are not one
prompt renamed four times: analysis decides *who and why* and says nothing
about remedies; action decides *what to do* and cannot re-rank. Splitting
diagnosis from remedy is what makes a trace arguable — an owner who disagrees
can see whether they disagree with the diagnosis or with the response to it.

### Why the safety agent has no model

It is the one stage whose behaviour must be identical on every run,
*including* the runs where the model upstream has been talked into something
by text it read in a tenant's name. A validator that can be argued with is
not a validator.

---

## The interventions

| Kind | What it does | Cost | Reversible |
|---|---|---|---|
| `extend_term` | Pushes a paid term out, clears past-due | low | yes |
| `comp_plan` | Gives the plan free for N months | real revenue | yes |
| `winback_offer` | Sends the lapsed-customer discount | discount if taken | yes |
| `contact_owner` | Flags that a person should get in touch | none | n/a |
| `no_action` | Risk is real, intervening is wrong | none | n/a |

There is deliberately **no suspend or delete**. Every reachable write is
additive for the tenant. The worst outcome of a fully compromised run is that
the platform gives something away — never that a business loses access.

---

## Policy, enforced deterministically

In [`agents/platform_safety.py`](../agentic-ai-service/agents/platform_safety.py):

- Only the five allow-listed kinds. An invented one (`delete_tenant`) is
  refused, not best-effort matched.
- **A business must be in the analysed at-risk set.** This is the important
  one: without it, a proposal naming any tenant id would be executed on the
  owner's approval — the most dangerous thing a prompt injection could
  achieve here.
- Extensions capped at 90 days; comps capped at the run's ceiling and a hard
  24 months. Over-long values are **trimmed and shown**, not silently
  rejected — the owner sees both numbers.
- A comp onto an unknown plan, or onto free Starter, is refused.
- **A dormant business is never comped.** A free month does not fix a
  business that is not using the product; that gets `contact_owner`.
- One intervention per business per run.
- The whole batch is refused if it gives up more than 3× what it protects.

Verdicts are per-intervention, not per-batch: a run with four sound proposals
and one out-of-policy proposal leaves the owner with four to approve.

---

## Defence in depth

The ceilings are enforced **three times**, deliberately:

1. In the agent service's safety gate.
2. In `PlatformCopilotService.StartAsync`, which clamps the request before it
   leaves ASP.NET Core — a spending control enforced only on the far side of
   an HTTP call is not a control.
3. At execution, in `ApplyOneAsync`, which re-clamps before writing. Tested:
   a stored 36 500-day extension still lands inside 90 days.

And the apply request carries **which** businesses, never **what to do** to
them. The interventions are re-read from the stored validation output, so a
tampered request can narrow the approved set but can never widen it or turn
an extension into a comp.

---

## Shared state

One row per run in `platform_agent_workflows` — objective, plan, each agent's
output in its own column, tool calls, model calls, per-agent timings,
verdicts, the approval decision, and the outcome per intervention including
failures.

Not `AgentWorkflow`, which is `ITenantScoped`: this workflow belongs to the
platform, reads across every tenant and proposes actions *against* tenants.
Filing it under one tenant's id would hide it from the owner's console and
expose it to a tenant it merely mentions.

`ModelDriven` records whether a language model actually drove the run or the
deterministic fallbacks did. Without it, a trace produced during a Gemini
outage is indistinguishable from one the model reasoned through.

---

## Safe failure

| Failure | Behaviour |
|---|---|
| Model unreachable | Deterministic fallback per stage; run completes; trace marked not model-driven |
| Platform API unreadable | Run ends `Failed` with the agent recorded — never proposals built on a tenant base it could not read |
| Invented intervention kind | Refused with a recorded reason |
| Tenant vanishes between proposal and approval | That one fails, the rest apply, status `PartiallyApplied` |
| Unreadable stored validation | Applies nothing |
| Nothing at risk | `NothingToDo` — a good outcome on a healthy platform, not an error |

`PartiallyApplied` exists because "Applied" would overstate it and "Failed"
would understate it, and the owner needs to know which businesses changed.

---

## Security

- Tools are **read-only by construction** — there is no write method on
  `PlatformToolsClient`, so an injection saying "comp every tenant" reaches a
  client with nothing to comp with. Asserted by a test over the public
  surface, because one convenience method added later would quietly end it.
- Tools run as the **owner**, through a short-lived `platform_sessions` row
  minted per run and revoked when it returns. The console's own token is
  never forwarded.
- Objective, tenant names and all free text are treated as **data**. All
  three model agents are instructed that text resembling a command is to be
  ignored and reported.
- No tenant operational data enters a prompt — only subscription standing and
  activity counts, which is the least an intervention decision needs.
- Every tool call is recorded, including the ones that raise.
- Every run, decision and OTP failure lands in `platform_audit_logs`.

---

## Evaluation

**Python — 19 tests**
([`tests/test_platform_copilot.py`](../agentic-ai-service/tests/test_platform_copilot.py))
No language model is involved in any of them; that is the point of a
deterministic gate.

Golden cases · every surviving proposal requires approval · no path through
safety approves anything · out-of-set tenant refused · invented kind refused ·
unknown plan refused · over-long comp trimmed · over-long extension trimmed ·
run ceiling holds back the excess · spending more than it protects refused ·
dormant business not comped · win-back only for lapsed · duplicate
intervention dropped · tool surface is read-only · failed tool calls still
recorded · deterministic fallback ignores free and comped tenants · tool
outage fails safely · healthy platform reports nothing to do · trace never
carries the owner token.

**C# — 14 tests**
([`PlatformCopilotTests.cs`](../backend/SmeBackend.Tests/PlatformBilling/PlatformCopilotTests.cs))
The execution boundary: the stronger claim that even if the agents *did*
propose something out of policy, ASP.NET Core would not carry it out.

Extension applies and clears past-due · comp marks complimentary · history
written · request cannot widen the approved set · subset leaves others
untouched · intervention comes from storage not the caller · stored
over-long extension still clamped · unknown plan fails without touching the
subscription · one failure does not stop the others · unreadable validation
applies nothing · a run can only be decided once · rejection changes nothing ·
rejected run cannot then be applied · history newest first.

---

## How to demonstrate it

1. `/platform` → sign in (password + authenticator) → **Copilot**
2. Objective: *"Reduce churn risk this month"* → **Run the copilot**
3. The trace shows: the plan and the planner's reading of the goal; the
   ranked at-risk businesses with evidence; the proposed interventions with
   cost and protected value; what validation refused and why.
4. **Point out that nothing has happened.** The page says so.
5. Select a subset → **Apply** → it demands an authenticator code.
6. Enter it → interventions apply → outcome table shows per-business results.
7. `/platform/audit` shows `copilot.run` and `copilot.approve` against your
   account.

To show safe failure, stop the agent service and run again: a clear recorded
failure, no proposals. To show the fallback path, unset `GEMINI_API_KEY`: the
run completes, and the trace is marked **deterministic** rather than model.

---

## Spec traceability

| Requirement (§9.1) | Where |
|---|---|
| Domain objective | `POST /api/platform/copilot` |
| Structured multi-step plan | `PlatformPlannerOutput.plan` |
| Delegation to distinct agents | Four agents, separate contracts and tool permissions |
| Allow-listed tools, validated inputs, structured outputs | `PlatformToolsClient.ALLOWED_TOOLS`, Pydantic throughout |
| Persisted workflow state | `platform_agent_workflows` |
| Deterministic validation | `platform_safety.py` — no model |
| Human approval of a high-impact action | TOTP step-up on `/approve` |
| Auditable result or safe failure | `OutcomeJson`, `ErrorLog`, `platform_audit_logs` |
| Observability | Tool calls, model calls, per-agent timings, verdicts |
| Security | Read-only tools, owner-scoped short-lived session, injection handling, secret protection |
