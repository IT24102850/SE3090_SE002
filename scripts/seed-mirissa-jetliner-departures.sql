-- ============================================================================
-- Create the departure rows the operations board runs on, for the Mirissa
-- Jetliner tenant, and adopt any existing bookings that sit on one.
--
-- Departures are what the board, the manifest, the sighting success rate and
-- the capacity checks are all built around. A tenant with vessels and
-- products but no departures shows an empty board even when it has real
-- bookings - which is exactly what happens to a booking taken through the
-- customer app before this runs.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-departures.sql
--
-- Re-running is safe: departures are guarded by the unique
-- (ResourceId, ScheduledDeparture) index, and the adoption UPDATE only
-- touches bookings whose DepartureId is still null.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _seed_ctx;
CREATE TEMP TABLE _seed_ctx AS
SELECT 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid AS tenant_id;

-- One departure per vessel per day, at that vessel's own published time,
-- from 30 days back to 14 days ahead. The time comes from the vessel's
-- CustomAttributes.departureTime, so the two never drift apart.
INSERT INTO "departures"
  ("Id","TenantId","ResourceId","BookingTypeId","ScheduledDeparture","ScheduledReturn",
   "Status","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, r."Id", bt."Id",
       (d::date + (r."CustomAttributes"->>'departureTime')::time) AT TIME ZONE 'UTC',
       (d::date + (r."CustomAttributes"->>'departureTime')::time) AT TIME ZONE 'UTC'
         + make_interval(mins => bt."DefaultDurationMinutes"),
       -- Past sailings are marked Returned so they land in the sighting
       -- success-rate denominator; a past departure still "Scheduled" is
       -- stale data, not a trip that never happened.
       CASE WHEN d::date < current_date THEN 'Returned' ELSE 'Scheduled' END,
       now(), now()
FROM _seed_ctx ctx
CROSS JOIN generate_series(current_date - 30, current_date + 14, interval '1 day') AS d
JOIN "resources" r
  ON r."TenantId" = ctx.tenant_id
 AND r."DeletedAt" IS NULL
 AND r."Category" = 'Vehicle'
 AND r."CustomAttributes"->>'departureTime' IS NOT NULL
JOIN "booking_types" bt
  ON bt."TenantId" = ctx.tenant_id
 AND bt."DeletedAt" IS NULL
 AND bt."Slug" = 'mjl-whale-watching'
WHERE NOT EXISTS (
  SELECT 1 FROM "departures" dep
  WHERE dep."ResourceId" = r."Id"
    AND dep."ScheduledDeparture" = (d::date + (r."CustomAttributes"->>'departureTime')::time) AT TIME ZONE 'UTC'
);

-- ── Weekly schedule: make the customer app offer the real sailing times ─────
-- Without a ResourceSchedule row, GetAvailableSlots falls back to a
-- documented 9am-5pm default, so the customer app offered a 09:00 slot on a
-- boat that sails at 06:30 - a bookable time this operator never runs, and a
-- booking that can never sit on a departure. One row per weekday per vessel,
-- opening exactly on that vessel's published departure time and closing when
-- it returns, so the slot picker yields precisely that one sailing.
INSERT INTO "resource_schedules"
  ("Id","CreatedAt","UpdatedAt","ResourceId","DayOfWeek","StartTime","EndTime","IsAvailable")
SELECT gen_random_uuid(), now(), now(), r."Id", dow,
       (r."CustomAttributes"->>'departureTime')::time,
       (r."CustomAttributes"->>'departureTime')::time + make_interval(mins => bt."DefaultDurationMinutes"),
       true
FROM _seed_ctx ctx
CROSS JOIN generate_series(0, 6) AS dow
JOIN "resources" r
  ON r."TenantId" = ctx.tenant_id AND r."DeletedAt" IS NULL
 AND r."Category" = 'Vehicle'
 AND r."CustomAttributes"->>'departureTime' IS NOT NULL
JOIN "booking_types" bt
  ON bt."TenantId" = ctx.tenant_id AND bt."DeletedAt" IS NULL AND bt."Slug" = 'mjl-whale-watching'
WHERE NOT EXISTS (
  SELECT 1 FROM "resource_schedules" rs
  WHERE rs."ResourceId" = r."Id" AND rs."DayOfWeek" = dow
);

-- Adopt bookings that already sit exactly on a departure but were created
-- before the server started linking them (the customer app, the admin form).
-- Exact start-time match only: a 09:00 booking is not the 06:30 sailing.
UPDATE "bookings" b
SET "DepartureId" = dep."Id", "UpdatedAt" = now()
FROM "departures" dep, _seed_ctx ctx
WHERE b."TenantId" = ctx.tenant_id
  AND b."DepartureId" IS NULL
  AND b."DeletedAt" IS NULL
  AND dep."ResourceId" = b."ResourceId"
  AND dep."ScheduledDeparture" = b."StartTime";

COMMIT;

SELECT
  (SELECT count(*) FROM "departures" d JOIN _seed_ctx c ON d."TenantId" = c.tenant_id
     WHERE d."DeletedAt" IS NULL)                                   AS departures,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id
     WHERE b."DeletedAt" IS NULL AND b."DepartureId" IS NOT NULL)   AS bookings_linked,
  (SELECT count(*) FROM "bookings" b JOIN _seed_ctx c ON b."TenantId" = c.tenant_id
     WHERE b."DeletedAt" IS NULL AND b."DepartureId" IS NULL)       AS bookings_unlinked,
  (SELECT count(*) FROM "resource_schedules" rs JOIN "resources" r ON r."Id" = rs."ResourceId"
     JOIN _seed_ctx c ON r."TenantId" = c.tenant_id)                  AS schedule_rows;
