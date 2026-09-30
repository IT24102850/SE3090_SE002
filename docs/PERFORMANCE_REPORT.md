# Performance report

Load tests of the **deployed** system with [k6](https://k6.io), run on
2026-10-01 (Sri Lanka time) from one laptop in Sri Lanka against the Render
deployment. Script: [`tests/performance/load-test.js`](../tests/performance/load-test.js).
Raw results (full k6 JSON plus a Markdown summary per run):
[`tests/performance/results/`](../tests/performance/results/).

## What was measured

| Spec §12 item | How |
|---|---|
| Concurrent requests | `ramping-vus`: 0 → N virtual users over 30 s, N held for 2 min, 20 s ramp-down |
| Response time | Per-endpoint trends: average, median, p95, max |
| Success / failure rate | `request_failures` (any non-2xx); failures split into no response, 429, 5xx, other |
| Database response | `GET /health`, which runs a real round trip to PostgreSQL (`Program.cs`) |
| Agentic AI latency | `agent_latency` scenario: sequential Schedule Copilot runs (`POST /api/agent/workflow/plan-schedule`), each running all four agents and the language model |

Endpoints under load: `/health` (database round trip),
`GET /api/tenant/public` (business directory, one indexed query) and
`GET /api/public/booking/{tenantId}/catalog` (one business's services,
resources and hours, several queries). Each virtual user pauses 1 s between
iterations. Before timing starts, `setup()` wakes the service. The free tier
sleeps when idle, and a cold start of about 40 s must not be reported as
ordinary latency.

Pass criteria (k6 thresholds): failure rate < 1 %; p95 < 1.5 s for the
database check and the directory; p95 < 2 s for the catalog.

## Results

### Run 1 - 5 concurrent users (`summary-2026-09-30T22-44-33-802Z`)

1,014 requests (5.9/s) · **failure rate 0.99 %** (10 × 5xx) · **all thresholds passed**

| Endpoint | Requests | Avg ms | Median ms | p95 ms | Max ms |
|---|---|---|---|---|---|
| `/health` (DB round trip) | 374 | 926 | 916 | 1,015 | 1,307 |
| Business directory | 319 | 425 | 412 | 518 | 902 |
| Business catalog | 319 | 830 | 817 | 895 | 1,254 |

### Run 2 - 20 concurrent users (`summary-2026-09-30T22-40-49-346Z`)

2,156 requests (12.3/s) · **failure rate 9.29 %** · thresholds failed

| Endpoint | Requests | Avg ms | Median ms | p95 ms | Max ms |
|---|---|---|---|---|---|
| `/health` (DB round trip) | 1,044 | 1,769 | 1,707 | 2,656 | 3,800 |
| Business directory | 555 | 1,531 | 1,559 | 2,804 | 3,606 |
| Business catalog | 555 | 2,709 | 2,364 | 6,091 | 8,586 |

Failures by endpoint: health 105, directory 55, catalog 40. This run came
before the failure breakdown was added to the script, so causes were not
recorded for it.

### Run 3 - 20 concurrent users again (`summary-2026-09-30T22-47-41-083Z`)

3,780 requests (21.9/s) · **failure rate 45.63 %** - **1,458 × HTTP 429**,
266 × 5xx · thresholds failed

p95: `/health` 2,395 ms, directory 2,495 ms, catalog 3,380 ms. Averages and
medians from this run are not meaningful: they are pulled down by the 429s,
which the edge answers almost immediately.

## Analysis

1. **Five concurrent users is comfortable; twenty is beyond the free tier.**
   At 5 users every p95 is under 1.1 s and 99 % of requests succeed. At 20,
   p95 latency roughly triples and failures appear on every endpoint,
   including `/health`, which does no application work beyond one database
   query. The limit is the hosting tier - Render's free instance has a
   fraction of one CPU and 512 MB - not a particular endpoint.
2. **The 429s come from Render's edge, not from the application.** The API
   rate-limits only platform-console sign-in and one public booking POST
   (`[EnableRateLimiting]` in `PlatformAuthController` and
   `PublicBookingController`). None of the tested endpoints is limited, yet
   `/health` received 429s as often as the others. The responses come through
   Cloudflare (`Server: cloudflare` on every response), which Render puts in
   front of its services. Three load tests in ten minutes from one IP address
   were treated as abuse. Real users arrive from many addresses, so this
   throttling is a property of the test setup rather than of real traffic.
   It also means **a single-machine test cannot measure the server's own
   limit above about 5 users.**
3. **Database round trips dominate.** `/health` does nothing but check the
   database connection and costs ~0.9 s even at low load. The API (Render)
   and the database (Supabase) run with different providers, so every query
   crosses the public network between them. The directory, a single indexed
   query, answers in about half that.
4. **The catalog is the slowest endpoint** (p95 0.9 s at 5 users, 6.1 s at
   20). It issues several queries per request - booking types, resources,
   branches and profile.

## Improvements this points to

- Deploy the API in the same region as the database, or co-locate both, to
  remove most of the per-query network cost (the largest single factor).
- Cache the public catalog briefly (for example 30-60 s with `IMemoryCache`).
  It changes rarely and is read by every visitor to a booking page.
- A paid instance (more CPU) would move the saturation point; the free tier
  is what the spec requires us to use.
- To measure server capacity above 5 users, run k6 from several machines or
  use k6 Cloud, so a single IP address is not throttled.

## Not yet measured - to run before the viva

The authenticated-read and Agentic AI latency scenarios need a demo
account, so they did not run in the tests above. To run them:

```bash
K6_EMAIL=manager@sme-demo.local K6_PASSWORD='<password>' \
K6_BOOKING_TYPE_ID=<a booking type of that tenant> \
VUS=5 HOLD=1m AGENT_RUNS=3 \
k6 run tests/performance/load-test.js
```

Then add the `authenticated_reads_ms` and `agent_schedule_copilot_ms` rows to
this report. Every persisted workflow also records per-agent timings
(`agent_workflows.ToolResultsJson` → `agentSteps` and `toolCalls`, each
with its duration in milliseconds). Those give per-agent latency for runs made
through the apps, as a cross-check.
