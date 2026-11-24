import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { startMockBackend } from "./mock-backend.mjs";

let mock, client;
const call = async (name, args = {}) => {
  const r = await client.callTool({ name, arguments: args });
  const text = r.content[0].text;
  let data; try { data = JSON.parse(text.replace(/^[^\n{[]*\n\n/, "")); } catch { data = text; }
  return { isError: !!r.isError, text, data };
};
const last = (pred) => [...mock.log].reverse().find(pred);

before(async () => {
  mock = await startMockBackend();
  client = new Client({ name: "e2e", version: "1" });
  await client.connect(new StdioClientTransport({
    command: "node", args: ["dist/index.js"],
    env: { ...process.env, UNIFY_API_URL: mock.url + "/api/", UNIFY_EMAIL: "﻿admin@clinic.lk ", UNIFY_PASSWORD: "secret", UNIFY_TIMEZONE: "Asia/Colombo" },
    stderr: "ignore",
  }));
});
after(async () => { await client?.close(); mock?.close(); });

test("whoami signs in and returns user, business and connector info", async () => {
  const r = await call("unify_whoami");
  assert.equal(r.isError, false, r.text);
  assert.equal(r.data.user.role, "Admin");
  assert.equal(r.data.business.businessType, "Clinic");
  assert.equal(r.data.connector.timeZone, "Asia/Colombo");
  const login = mock.log.find((l) => l.path === "/api/auth/login");
  assert.equal(login.body.email, "admin@clinic.lk", "BOM and whitespace stripped");
});

test("list_bookings scopes to tenant and converts local dates to UTC", async () => {
  const r = await call("unify_list_bookings", { dateFrom: "2026-11-25", dateTo: "2026-11-25" });
  assert.equal(r.isError, false, r.text);
  const req = last((l) => l.path === "/api/bookings" && l.method === "GET");
  assert.equal(req.query.tenantId, "22222222-2222-4222-8222-222222222222");
  assert.equal(req.query.dateFrom, "2026-11-24T18:30:00.000Z");
  assert.equal(req.query.dateTo, "2026-11-25T18:29:59.999Z");
  assert.equal(r.data.items[0].startTimeLocal, "2026-11-25 10:00", "timestamps get a Local twin");
});

test("expired token is refreshed transparently", async () => {
  mock.state.expireNext = true;
  const r = await call("unify_list_bookings", {});
  assert.equal(r.isError, false, r.text);
  assert.ok(mock.log.some((l) => l.path === "/api/auth/refresh"), "refresh was called");
});

test("create_booking converts local time and defaults bookedBy to the user", async () => {
  const r = await call("unify_create_booking", {
    resourceId: "33333333-3333-4333-8333-333333333333", bookingTypeId: "44444444-4444-4444-8444-444444444444",
    startTime: "2026-11-25T10:00", durationMinutes: 30, attendeeCount: 2,
  });
  assert.equal(r.isError, false, r.text);
  const req = last((l) => l.path === "/api/bookings" && l.method === "POST");
  assert.equal(req.body.startTime, "2026-11-25T04:30:00.000Z");
  assert.equal(req.body.endTime, "2026-11-25T05:00:00.000Z");
  assert.equal(req.body.bookedBy, "11111111-1111-4111-8111-111111111111");
  assert.equal(req.body.tenantId, "22222222-2222-4222-8222-222222222222");
  assert.equal(req.body.priority, "Normal");
});

test("reschedule keeps the original length when no end is given", async () => {
  const r = await call("unify_reschedule_booking", { bookingId: "66666666-6666-4666-8666-666666666666", newStartTime: "2026-11-26T09:00" });
  assert.equal(r.isError, false, r.text);
  const req = last((l) => l.path.endsWith("/reschedule"));
  assert.equal(req.body.newStartTime, "2026-11-26T03:30:00.000Z");
  assert.equal(req.body.newEndTime, "2026-11-26T04:15:00.000Z", "original 45-minute length kept");
  const bad = await call("unify_reschedule_booking", { bookingId: "not-a-uuid", newStartTime: "2026-11-26T09:00" });
  assert.equal(bad.isError, true, "non-UUID ids are rejected");
});

test("dashboard auto-detects the clinic dashboard and sends tz offset", async () => {
  const r = await call("unify_get_dashboard", { from: "2026-11-01", to: "2026-11-24" });
  assert.equal(r.isError, false, r.text);
  assert.match(r.text, /Dashboard: clinic \/ overview/);
  const req = last((l) => l.path.startsWith("/api/reports/clinic"));
  assert.equal(req.path, "/api/reports/clinic/overview");
  assert.equal(req.query.tz, "330");
});

test("invalid dashboard view gives a helpful error", async () => {
  const r = await call("unify_get_dashboard", { dashboard: "gym", view: "flow" });
  assert.equal(r.isError, true);
  assert.match(r.text, /overview, live, attendance, alerts/);
});

test("API errors are reported with the backend's message", async () => {
  const r = await call("unify_api_get", { path: "/bookings/forbidden/history" });
  assert.equal(r.isError, true);
  assert.match(r.text, /not allowed.*Cancellation cutoff has passed/);
});

test("generic tool refuses platform-owner and auth endpoints", async () => {
  const r = await call("unify_api_get", { path: "/platform/tenants" });
  assert.equal(r.isError, true);
  assert.match(r.text, /not available/);
});

test("204 responses become ok:true; 404s are reported", async () => {
  const r = await call("unify_cancel_booking", { bookingId: "66666666-6666-4666-8666-666666666666" });
  assert.equal(r.isError, false, r.text);
  assert.equal(r.data.ok, true);
  const missing = await call("unify_cancel_booking", { bookingId: "55555555-5555-4555-8555-555555555555" });
  assert.equal(missing.isError, true);
  assert.match(missing.text, /Not found/);
});

test("get_booking includes history with local times", async () => {
  const r = await call("unify_get_booking", { bookingId: "66666666-6666-4666-8666-666666666666" });
  assert.equal(r.isError, false, r.text);
  assert.equal(r.data.history[0].atLocal, "2026-11-20 15:30");
});

test("tools carry safety annotations", async () => {
  const { tools } = await client.listTools();
  const byName = Object.fromEntries(tools.map((t) => [t.name, t]));
  assert.equal(byName.unify_list_bookings.annotations.readOnlyHint, true);
  assert.equal(byName.unify_cancel_booking.annotations.destructiveHint, true);
  assert.equal(byName.unify_create_booking.annotations.readOnlyHint, false);
});

test("directory rules: titles, read/write annotations, short names, no catch-all", async () => {
  const { tools } = await client.listTools();
  for (const t of tools) {
    assert.ok(t.name.length <= 64, t.name);
    assert.ok(t.title || t.annotations?.title, `${t.name} has a title`);
    const a = t.annotations ?? {};
    assert.ok(a.readOnlyHint === true || a.destructiveHint === true, `${t.name}: readOnlyHint or destructiveHint`);
    assert.ok(!(a.readOnlyHint && a.destructiveHint), `${t.name}: not both`);
    assert.ok(!("method" in (t.inputSchema.properties ?? {})), `${t.name}: no HTTP method parameter`);
    assert.doesNotMatch(t.description, /confirm with the user|call this first|before calling/i, `${t.name}: no behavioural instructions`);
  }
  const get = tools.find((t) => t.name === "unify_api_get");
  assert.match(get.description, /swagger/i, "free-form tool names the API reference");
});

test("update_booking_type merges prices and config, keeps other settings", async () => {
  const r = await call("unify_update_booking_type", { bookingTypeId: "77777777-7777-4777-8777-777777777777",
    adultPrice: 6500, configPatch: { priceConfidence: "CONFIRMED by owner" } });
  assert.equal(r.isError, false, r.text);
  const req = [...mock.log].reverse().find((l) => l.method === "PUT" && l.path.startsWith("/api/bookingtypes/"));
  const cfg = JSON.parse(req.body.configJson);
  assert.equal(cfg.pricing.adult, 6500);
  assert.equal(cfg.pricing.child, 3500, "untouched price kept");
  assert.deepEqual(cfg.season, { months: ["Nov"] }, "other settings kept");
  assert.equal(cfg.priceConfidence, "CONFIRMED by owner");
  assert.ok(!("name" in req.body), "fields not given are not sent");
});

test("status-only booking type update does not touch config", async () => {
  const r = await call("unify_update_booking_type", { bookingTypeId: "77777777-7777-4777-8777-777777777777", status: "Inactive" });
  assert.equal(r.isError, false, r.text);
  const req = [...mock.log].reverse().find((l) => l.method === "PUT" && l.path.startsWith("/api/bookingtypes/"));
  assert.deepEqual(req.body, { status: "Inactive" });
});

test("resource create, update and delete", async () => {
  const c = await call("unify_create_resource", { name: "Private Speed Boat", category: "Vehicle", capacity: 8, customAttributes: { engines: "2x Suzuki 200" } });
  assert.equal(c.isError, false, c.text);
  const post = [...mock.log].reverse().find((l) => l.method === "POST" && l.path === "/api/resources");
  assert.equal(post.body.tenantId, "22222222-2222-4222-8222-222222222222");
  assert.equal(JSON.parse(post.body.customAttributes).engines, "2x Suzuki 200");
  const u = await call("unify_update_resource", { resourceId: "88888888-8888-4888-8888-888888888888", status: "UnderMaintenance" });
  assert.equal(u.isError, false, u.text);
  const put = [...mock.log].reverse().find((l) => l.method === "PUT" && l.path.startsWith("/api/resources/"));
  assert.deepEqual(put.body, { status: "UnderMaintenance" });
  const d = await call("unify_delete_resource", { resourceId: "88888888-8888-4888-8888-888888888888" });
  assert.equal(d.isError, false, d.text);
});
