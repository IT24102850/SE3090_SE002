-- ============================================================================
-- Availability Slots — publish a resource's capacity as rows (spec 2.3).
--
-- Runs anywhere: the Supabase SQL editor, pgAdmin, DBeaver, or psql.
--   psql "$DATABASE_URL" -f scripts/seed-availability-slots.sql
--
-- (An earlier revision used psql's \set meta-command for its parameters.
-- That is not SQL — a browser SQL editor sends the text straight to the
-- server and fails on the backslash — so the parameters now live in a temp
-- table every statement reads.)
--
-- WHAT IT DOES
-- Reads each resource's weekly resource_schedules and writes one
-- availability_slots row per bookable window, exactly as the app's
-- AvailabilitySlotService.GenerateAsync would. A slot whose window a live
-- booking already covers is written as taken, with that booking's id, so
-- the utilisation figure the Availability Slots page shows is real rather
-- than decorative.
--
-- WHY IT EXISTS
-- Availability used to be computed on the fly and held nowhere, so a
-- business could not publish next month, withdraw a wet Tuesday, or say how
-- much of what it opened actually sold. A materialised slot is a row the
-- business owns.
--
-- SLOT LENGTH IS NOT A FREE CHOICE. It should divide the way the business
-- actually sells. A whale-watching boat open 06:30-10:30 sells ONE four-hour
-- sailing, so 240 gives one true slot; 120 would invent an 08:30 departure
-- that does not exist. A dentist open 09:00-17:00 in 30-minute appointments
-- wants 30. Match the product, not the calendar.
--
-- TIME ZONE: resource_schedules holds wall-clock times with no zone and the
-- app composes them against UTC dates, so a 06:30 schedule becomes a 06:30Z
-- slot. This follows the same convention so the rows line up with what the
-- app itself generates.
--
-- Idempotent: guarded by (resource, date, start), which is also the table's
-- own unique index. Re-running adds nothing and never double-books.
--
-- PARAMETERS live in the one SELECT below. Change them, nothing else.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _slot_params;

CREATE TEMP TABLE _slot_params AS
SELECT
  'd303c4ef-6eb9-4189-95e0-b537d2134ba9'::uuid AS tenant_id,
  -- '%' for every resource, or a LIKE pattern for one.
  '%'::text                                    AS resource_name,
  7::int                                       AS days_back,
  20::int                                      AS days_ahead,
  240::int                                     AS slot_minutes;

INSERT INTO availability_slots
  ("Id","CreatedAt","UpdatedAt","ResourceId","Date","StartTime","EndTime","IsBooked","BookingId")
SELECT gen_random_uuid(), now(), now(),
       r."Id",
       d::date AT TIME ZONE 'UTC',
       slot.start_at,
       slot.start_at + make_interval(mins => p.slot_minutes),
       taken."Id" IS NOT NULL,
       taken."Id"
FROM _slot_params p
JOIN resources r
  ON r."TenantId" = p.tenant_id
 AND r."DeletedAt" IS NULL
 AND r."Name" LIKE p.resource_name
JOIN resource_schedules rs
  ON rs."ResourceId" = r."Id"
 AND rs."IsAvailable"
CROSS JOIN LATERAL generate_series(
       current_date - p.days_back,
       current_date + p.days_ahead,
       interval '1 day') AS d
-- Step across the open window the same way SlotCalculator does: a slot is
-- only produced while it still finishes before closing time.
CROSS JOIN LATERAL generate_series(
       0,
       (EXTRACT(EPOCH FROM (rs."EndTime" - rs."StartTime")) / 60)::int - p.slot_minutes,
       p.slot_minutes) AS offset_minutes
CROSS JOIN LATERAL (
       SELECT rs."StartTime" + make_interval(mins => offset_minutes) AS start_at
) AS slot
LEFT JOIN LATERAL (
  SELECT b."Id"
    FROM bookings b
   WHERE b."ResourceId" = r."Id"
     AND b."DeletedAt" IS NULL
     -- A cancelled or rejected booking hands its slot back, so it must not
     -- be shown holding one here either.
     AND b."Status" NOT IN ('Cancelled','Rejected','WeatherCancelled')
     AND b."StartTime" < (d::date + slot.start_at + make_interval(mins => p.slot_minutes)) AT TIME ZONE 'UTC'
     AND b."EndTime"   > (d::date + slot.start_at) AT TIME ZONE 'UTC'
   LIMIT 1
) AS taken ON true
-- The weekly pattern is keyed 0 = Sunday, matching the backend.
WHERE rs."DayOfWeek" = EXTRACT(dow FROM d)::int
  -- A one-off closure (holiday, dry dock) beats the weekly pattern.
  AND NOT EXISTS (
    SELECT 1 FROM resource_schedule_exceptions e
     WHERE e."ResourceId" = r."Id" AND e."Date"::date = d::date)
  AND NOT EXISTS (
    SELECT 1 FROM availability_slots s
     WHERE s."ResourceId" = r."Id"
       AND s."Date" = d::date AT TIME ZONE 'UTC'
       AND s."StartTime" = slot.start_at);

COMMIT;

-- ── What landed ─────────────────────────────────────────────────────────────
SELECT r."Name"                                             AS resource,
       count(s.*)                                           AS published,
       count(s.*) FILTER (WHERE s."IsBooked")               AS sold,
       count(s.*) FILTER (WHERE NOT s."IsBooked")           AS still_open,
       round(100.0 * count(s.*) FILTER (WHERE s."IsBooked")
             / NULLIF(count(s.*), 0), 1)                     AS utilisation_pct,
       min(s."Date")::date                                   AS from_date,
       max(s."Date")::date                                   AS to_date
FROM availability_slots s
JOIN resources r ON r."Id" = s."ResourceId"
WHERE r."TenantId" = 'd303c4ef-6eb9-4189-95e0-b537d2134ba9'::uuid
GROUP BY r."Name"
ORDER BY r."Name";

-- ── Withdraw a range (unbooked only) ────────────────────────────────────────
-- Booked slots are deliberately left alone: removing one would orphan a
-- customer's reservation. Uncomment to use.
--
-- DELETE FROM availability_slots s
-- USING resources r
-- WHERE r."Id" = s."ResourceId"
--   AND r."TenantId" = 'd303c4ef-6eb9-4189-95e0-b537d2134ba9'::uuid
--   AND s."Date" BETWEEN (current_date - 7) AND (current_date + 20)
--   AND NOT s."IsBooked";
