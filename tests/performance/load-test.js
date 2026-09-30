// k6 load test for the deployed Unify API (SE3090 Assignment 1, Section 12:
// concurrent requests, response time, success/failure rate, database response
// and Agentic AI latency).
//
//   k6 run tests/performance/load-test.js
//
// Environment variables (all optional):
//   BASE_URL          API origin            (default https://sme-backend-lxsp.onrender.com)
//   VUS               peak concurrent users (default 20)
//   HOLD              time at peak          (default 2m)
//   K6_EMAIL / K6_PASSWORD
//                     a Manager or Admin demo account; enables the
//                     authenticated-read and agent-latency scenarios
//   K6_BOOKING_TYPE_ID  a booking type of that tenant; enables the agent run
//   AGENT_RUNS        Schedule Copilot runs to time (default 3; each one
//                     calls the language model, so keep it small)
//
// Results: a console summary plus tests/performance/results/summary-<time>.json
// and .md, which is what the performance report quotes.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE = (__ENV.BASE_URL || 'https://sme-backend-lxsp.onrender.com').replace(/\/$/, '');
const VUS = Number(__ENV.VUS || 20);
const HOLD = __ENV.HOLD || '2m';
const EMAIL = __ENV.K6_EMAIL;
const PASSWORD = __ENV.K6_PASSWORD;
const BOOKING_TYPE_ID = __ENV.K6_BOOKING_TYPE_ID;
const AGENT_RUNS = Number(__ENV.AGENT_RUNS || 3);
const authenticated = Boolean(EMAIL && PASSWORD);

const dbHealth = new Trend('db_health_ms', true);
const publicDirectory = new Trend('public_directory_ms', true);
const publicCatalog = new Trend('public_catalog_ms', true);
const authReads = new Trend('authenticated_reads_ms', true);
const agentLatency = new Trend('agent_schedule_copilot_ms', true);
const failures = new Rate('request_failures');
// Why a request failed: 0 = no response (timeout / connection reset),
// 429 = rate limited, 5xx = server or proxy error.
const failedNoResponse = new Counter('failed_no_response');
const failed429 = new Counter('failed_429_rate_limited');
const failed5xx = new Counter('failed_5xx');
const failedOther = new Counter('failed_other_status');

const rampingLoad = (exec) => ({
  executor: 'ramping-vus',
  exec,
  startVUs: 0,
  stages: [
    { duration: '30s', target: VUS },
    { duration: HOLD, target: VUS },
    { duration: '20s', target: 0 },
  ],
  gracefulRampDown: '10s',
});

const scenarios = {
  database_health: rampingLoad('databaseHealth'),
  public_reads: rampingLoad('publicReads'),
};
if (authenticated) {
  scenarios.authenticated_reads = rampingLoad('authenticatedReads');
}
if (authenticated && BOOKING_TYPE_ID) {
  // Sequential and small: this measures agent latency, it is not a load test
  // of the language model provider.
  scenarios.agent_latency = {
    executor: 'per-vu-iterations',
    exec: 'agentLatencyRun',
    vus: 1,
    iterations: AGENT_RUNS,
    startTime: '40s',
    maxDuration: '10m',
  };
}

export const options = {
  scenarios,
  thresholds: {
    request_failures: ['rate<0.01'],
    db_health_ms: ['p(95)<1500'],
    public_directory_ms: ['p(95)<1500'],
    public_catalog_ms: ['p(95)<2000'],
    ...(authenticated ? { authenticated_reads_ms: ['p(95)<2000'] } : {}),
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'max', 'count'],
};

// Free-tier hosts sleep when idle. Wake the API before timing anything, so a
// cold start is not reported as ordinary latency.
export function setup() {
  let awake = false;
  for (let i = 0; i < 12 && !awake; i++) {
    awake = http.get(`${BASE}/health`, { timeout: '90s' }).status === 200;
    if (!awake) sleep(5);
  }
  if (!awake) throw new Error(`API at ${BASE} did not become healthy`);

  const tenants = http.get(`${BASE}/api/tenant/public`).json();
  const tenantId = Array.isArray(tenants) && tenants.length > 0 ? tenants[0].id : null;

  let token = null;
  let tenantOfUser = null;
  if (authenticated) {
    const login = http.post(`${BASE}/api/auth/login`, JSON.stringify({ email: EMAIL, password: PASSWORD }), {
      headers: { 'Content-Type': 'application/json' },
    });
    if (login.status !== 200) throw new Error(`Login failed with ${login.status}`);
    token = login.json('accessToken');
    tenantOfUser = login.json('user.tenantId');
  }
  return { tenantId, token, tenantOfUser };
}

function record(response, trend, name) {
  trend.add(response.timings.duration);
  const ok = check(response, { [`${name} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
  failures.add(!ok);
  if (!ok) {
    if (response.status === 0) failedNoResponse.add(1);
    else if (response.status === 429) failed429.add(1);
    else if (response.status >= 500) failed5xx.add(1);
    else failedOther.add(1);
  }
}

export function databaseHealth() {
  // /health runs a real round trip to PostgreSQL (Program.cs).
  record(http.get(`${BASE}/health`, { tags: { endpoint: 'health' } }), dbHealth, 'health');
  sleep(1);
}

export function publicReads(data) {
  record(http.get(`${BASE}/api/tenant/public`, { tags: { endpoint: 'tenant-public' } }), publicDirectory, 'directory');
  if (data.tenantId) {
    record(
      http.get(`${BASE}/api/public/booking/${data.tenantId}/catalog`, { tags: { endpoint: 'public-catalog' } }),
      publicCatalog,
      'catalog',
    );
  }
  sleep(1);
}

export function authenticatedReads(data) {
  const params = { headers: { Authorization: `Bearer ${data.token}` } };
  record(http.get(`${BASE}/api/auth/me`, { ...params, tags: { endpoint: 'auth-me' } }), authReads, 'me');
  record(
    http.get(`${BASE}/api/bookings?page=1&pageSize=20`, { ...params, tags: { endpoint: 'bookings-page' } }),
    authReads,
    'bookings',
  );
  sleep(1);
}

export function agentLatencyRun(data) {
  const today = new Date();
  const from = new Date(today.getTime() + 24 * 3600 * 1000).toISOString().slice(0, 10);
  const to = new Date(today.getTime() + 7 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const response = http.post(
    `${BASE}/api/agent/workflow/plan-schedule`,
    JSON.stringify({
      tenantId: data.tenantOfUser,
      objective: 'Schedule 3 appointments next week without conflicts',
      bookingTypeId: BOOKING_TYPE_ID,
      dateFrom: from,
      dateTo: to,
      targetCount: 3,
      resourceIds: [],
      priorityRules: [],
      branchId: null,
    }),
    {
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.token}` },
      timeout: '180s',
      tags: { endpoint: 'agent-plan-schedule' },
    },
  );
  record(response, agentLatency, 'agent run');
  sleep(2);
}

export function handleSummary(data) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const rows = Object.entries(data.metrics)
    .filter(([, m]) => m.type === 'trend' && m.values && m.values.count > 0)
    .map(([name, m]) => {
      const v = m.values;
      return `| ${name} | ${v.count} | ${v.avg.toFixed(0)} | ${v.med.toFixed(0)} | ${v['p(95)'].toFixed(0)} | ${v.max.toFixed(0)} |`;
    });
  const reqs = data.metrics.http_reqs ? data.metrics.http_reqs.values : { count: 0, rate: 0 };
  const failRate = data.metrics.request_failures ? data.metrics.request_failures.values.rate : 0;
  const counter = (name) => (data.metrics[name] ? data.metrics[name].values.count : 0);
  const thresholds = Object.entries(data.metrics)
    .filter(([, m]) => m.thresholds)
    .flatMap(([name, m]) => Object.entries(m.thresholds).map(([t, r]) => `| ${name} | \`${t}\` | ${r.ok ? 'pass' : 'FAIL'} |`));

  const md = [
    `# Load test results - ${new Date().toISOString()}`,
    '',
    `Target: ${BASE}  |  peak ${VUS} concurrent virtual users, ${HOLD} at peak  |  authenticated scenarios: ${authenticated ? 'yes' : 'no'}`,
    '',
    `Requests: ${reqs.count} (${reqs.rate.toFixed(1)}/s)  |  failure rate: ${(failRate * 100).toFixed(2)}%`,
    '',
    `Failures by cause: no response ${counter('failed_no_response')}, 429 ${counter('failed_429_rate_limited')}, 5xx ${counter('failed_5xx')}, other ${counter('failed_other_status')}`,
    '',
    '| Metric | Count | Avg ms | Median ms | p95 ms | Max ms |',
    '|---|---|---|---|---|---|',
    ...rows,
    '',
    '| Threshold | Rule | Result |',
    '|---|---|---|',
    ...thresholds,
    '',
  ].join('\n');

  return {
    stdout: md,
    [`tests/performance/results/summary-${stamp}.json`]: JSON.stringify(data, null, 2),
    [`tests/performance/results/summary-${stamp}.md`]: md,
  };
}
