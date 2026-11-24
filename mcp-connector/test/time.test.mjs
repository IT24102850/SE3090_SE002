import { test } from "node:test";
import assert from "node:assert/strict";
import { toUtcIso, toLocalDate, formatLocal } from "../src/time.ts";

test("local, offset and date-only inputs", () => {
  assert.equal(toUtcIso("2026-11-25T10:00", "Asia/Colombo"), "2026-11-25T04:30:00.000Z");
  assert.equal(toUtcIso("2026-11-25T10:00:00+05:30", "UTC"), "2026-11-25T04:30:00.000Z");
  assert.equal(toUtcIso("2026-11-25T04:30:00Z", "Asia/Colombo"), "2026-11-25T04:30:00.000Z");
  assert.equal(toUtcIso("2026-11-25", "Asia/Colombo", { endOfDay: true }), "2026-11-25T18:29:59.999Z");
  assert.throws(() => toUtcIso("next tuesday", "UTC"), /Could not read/);
});

test("DST-aware conversion", () => {
  assert.equal(toUtcIso("2026-07-01T09:00", "America/New_York"), "2026-07-01T13:00:00.000Z");
  assert.equal(toUtcIso("2026-12-01T09:00", "America/New_York"), "2026-12-01T14:00:00.000Z");
  assert.equal(toUtcIso("2026-03-29T12:00", "Europe/London"), "2026-03-29T11:00:00.000Z");
});

test("local dates and formatting", () => {
  assert.equal(toLocalDate("2026-11-24T20:00:00Z", "Asia/Colombo"), "2026-11-25");
  assert.equal(formatLocal("2026-11-25T04:30:00Z", "Asia/Colombo"), "2026-11-25 10:00");
});
