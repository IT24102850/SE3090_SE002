# Test Plan

## 1. Purpose

This plan evaluates the actual SE3090 integrated system: ASP.NET Core Web API, PostgreSQL persistence, React web console, Flutter mobile application, and FastAPI Agentic AI service. The objective is to provide repeatable evidence for functional correctness, integration behavior, performance, security, and safe AI assistance.

## 2. Quality objectives and risks

| Risk | Quality objective | Priority |
|---|---|---|
| Double booking or invalid availability | Enforce slot, date-range, overlap, capacity, and cancellation rules | Critical |
| Cross-tenant data exposure | Reject unauthorized role, tenant, and resource access | Critical |
| Unsafe AI action | Validate structured output, tool allow-list, approval threshold, and prompt-injection resistance | Critical |
| Database constraint or migration failure | Verify schema, foreign keys, uniqueness, CHECK constraints, transactions, and rollback | High |
| Client/API contract drift | Validate React and Flutter request/response handling and error states | High |
| Slow or throttled public service | Measure latency, failure rate, and behavior under concurrent load | High |
| Vulnerable dependency | Run dependency security audit and remediate high/critical findings | High |
| Poor mobile or web usability | Test validation, loading, empty, error, protected-route, and responsive states | Medium |

## 3. Scope and tools

| Area | In scope | Tool/framework |
|---|---|---|
| Backend/API | Controllers, services, validation, auth, roles, tenant isolation, booking and approval workflows | xUnit, Moq, ASP.NET `WebApplicationFactory` |
| Database | EF Core mappings, migrations, PostgreSQL constraints, transactions, query translation | xUnit, EF Core, Testcontainers PostgreSQL |
| React | Components, forms, protected routes, API errors, dashboards, AI workflow states | Vitest, Testing Library, jsdom |
| Flutter | Unit, widget, validation, navigation, QR, API client and token refresh behavior | `flutter_test`, Dio adapter fakes |
| Agentic AI | Agent sequencing, tool permissions, contracts, safety, approval, injection, safe failure | pytest, Pydantic, deterministic fakes |
| Integration | API workflow and approval lifecycle; live cross-client disruption workflow | xUnit integration fixtures; deployed-system acceptance checklist |
| Performance | Public catalog, directory, health/database round trip, authenticated reads, AI latency | k6 |
| Security | Dependency advisories, authorization behavior, secret-handling review | `npm audit`, xUnit security tests, manual secret review |

## 4. Test environments

**Automated local environment:** Windows development machine, .NET 8, Node 22/npm, Python test environment, Flutter 3.32.5. Model calls are mocked for deterministic AI tests. Most API tests use in-memory EF Core; PostgreSQL tests require Docker and are skipped when unavailable.

**Deployed environment:** Vercel frontend, Render ASP.NET API and Agentic AI service, Supabase PostgreSQL. Live evidence must include the deployment URLs, timestamp, test data identifier, and sanitized response or screenshot.

## 5. Responsibilities

| Role | Contribution to demonstrate | Evidence |
|---|---|---|
| Hasiru Chamika | Booking engine, API integration, Schedule/Disruption Copilot and safety tests | Backend booking tests, agent tests, workflow trace, Git history |
| Oshadi | Billing, payments, dynamic forms and Billing Copilot tests | Billing xUnit/React/AI tests, defect and retest evidence |
| Hasaranga Abeyrathna | Inventory, StockSense, mobile inventory and security/performance evidence | Inventory tests, Flutter tests, k6/security outputs |

Replace names/ownership only if the group agrees and Git history supports it.

## 6. Schedule

| Phase | Activity | Exit evidence |
|---|---|---|
| Planning | Identify risks, select tools, define cases | This plan and traceability matrix |
| Implementation | Write or refine automated cases | Test source, review commit, CI check |
| Execution | Run all local suites and builds | TRX, JUnit, console logs, Flutter output |
| Non-functional | Run k6 and security checks | k6 JSON/summary and audit output |
| Defect cycle | Log, fix, rerun affected test | Defect log with before/after evidence |
| Demonstration | Execute integrated workflow and viva rehearsal | Screenshots, trace IDs, personal demo notes |

## 7. Entry and exit criteria

Entry: code builds, test data is isolated, services/configuration are available, and secrets are stored outside source control.

Exit: no unexplained functional failures; all skipped tests have a recorded prerequisite; required performance and security tests have evidence; every failed test has a defect decision; the integrated workflow has been demonstrated; each student can run and explain their own contribution.
