-- ============================================================================
-- Mirissa JetLiner — a live operating window for the day-scoped screens.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-operating-days.sql
--
-- WHY THIS EXISTS
-- Reservations / Manifest and Multi-Branch Schedule both answer "what is
-- happening on ONE day". The tenant had bookings, but none of them landed on
-- today, so every card on both pages read 0 while the database was not in fact
-- empty. This fills a rolling window around today so those screens have a real
-- day to show whenever they are opened.
--
-- It seeds one sailing per boat per day across the window, because that is how
-- these boats actually sell: Dawn Departure is open 06:30-10:30 and Morning
-- Cruise 10:00-14:00, and the Whale Watching type is 240 minutes. One slot each,
-- not four - inventing hourly departures would make every utilisation figure on
-- the page fiction.
--
-- STATUSES ARE CHOSEN SO THE KPI CARDS HAVE SOMETHING TRUE TO COUNT:
--   before today  -> Completed (it sailed)
--   today         -> one CheckedIn (guests aboard) + one Pending (needs a call)
--   after today   -> Confirmed, with one Pending every third day
-- A page whose cards are all zero and a page whose cards are all the same
-- number are equally useless for judging whether the screen works.
--
-- TIME ZONE: wall-clock times are written as UTC, matching resource_schedules
-- and every booking already in this tenant. The browser renders them at
-- +05:30, so a 06:30Z sailing reads as noon in Mirissa - consistent with the
-- rest of the data rather than correct in isolation.
--
-- Idempotent: guarded on (resource, start time), which is also what a double
-- booking would look like. Re-running adds only days that are still empty, and
-- it never touches a booking that already exists - including the recurring
-- series, whose Morning Cruise slots are simply skipped.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _day_params;

CREATE TEMP TABLE _day_params AS
SELECT
  'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid AS tenant_id,
  'Whale Watching'::text                       AS type_name,
  1::int                                       AS days_back,
  10::int                                      AS days_ahead;

INSERT INTO bookings (
  "Id","TenantId","BookedBy","BookedFor","BookingTypeId","ResourceId",
  "StartTime","EndTime","Status","Priority","Title","Notes",
  "AttendeeCount","TotalCost","TicketBreakdown","Source",
  "CheckInAt","Version","CreatedAt","UpdatedAt")
SELECT
  gen_random_uuid(), p.tenant_id, guest.id, guest.id, bt."Id", r."Id",
  (d::date + sch."StartTime") AT TIME ZONE 'UTC',
  (d::date + sch."EndTime")   AT TIME ZONE 'UTC',
  state.status,
  'Normal',
  guest.name || ' · ' || r.short_name,
  state.note,
  state.adults + state.children,
  -- Adult 7500, child 4000, infant free: the tenant's own ticket prices.
  (state.adults * 7500) + (state.children * 4000),
  jsonb_build_array(
    jsonb_build_object('type','Adult','qty',state.adults,'unitPrice',7500,'lineTotal',state.adults*7500),
    jsonb_build_object('type','Child','qty',state.children,'unitPrice',4000,'lineTotal',state.children*4000)),
  state.source,
  CASE WHEN state.status = 'CheckedIn'
       THEN (d::date + sch."StartTime" - interval '25 minutes') AT TIME ZONE 'UTC' END,
  1, now(), now()
FROM _day_params p
JOIN booking_types bt
  ON bt."TenantId" = p.tenant_id AND bt."Name" = p.type_name AND bt."DeletedAt" IS NULL
JOIN resources r_all ON r_all."TenantId" = p.tenant_id AND r_all."DeletedAt" IS NULL
CROSS JOIN LATERAL (
  SELECT r_all."Id",
         CASE WHEN r_all."Name" LIKE '%Dawn%' THEN 'dawn' ELSE 'cruise' END AS kind,
         split_part(r_all."Name", ' - ', 2)                                  AS short_name
) AS r
CROSS JOIN LATERAL generate_series(
       current_date - p.days_back, current_date + p.days_ahead, interval '1 day') AS d
JOIN resource_schedules sch
  ON sch."ResourceId" = r."Id"
 AND sch."IsAvailable"
 AND sch."DayOfWeek" = EXTRACT(dow FROM d)::int
-- A different guest per day and boat, so the manifest is not one name repeated.
CROSS JOIN LATERAL (
  SELECT u."Id" AS id, u."FullName" AS name
    FROM "Users" u
   WHERE u."TenantId" = p.tenant_id AND u."Role" = 3
     AND u."Email" <> 'ocean.breeze.mirissa@example-demo.test'  -- holds the standing allocation
   ORDER BY md5(u."Id"::text || d::text || r.kind)
   LIMIT 1
) AS guest
CROSS JOIN LATERAL (
  SELECT
    -- "Today" covers current_date AND the next day. The server stores UTC and
    -- the browser renders at +05:30, so for most of the UTC evening the screen's
    -- idea of today is already the server's tomorrow. Treating both as the
    -- operating day means the day-scoped cards are populated either way,
    -- whichever side of midnight UTC the demo happens on.
    CASE
      WHEN d::date <  current_date THEN 'Completed'
      WHEN d::date <= current_date + 1 THEN CASE WHEN r.kind = 'dawn' THEN 'CheckedIn' ELSE 'Pending' END
      WHEN (d::date - current_date) % 3 = 0 THEN 'Pending'
      ELSE 'Confirmed'
    END AS status,
    CASE
      WHEN d::date <  current_date THEN 'Sailed. Sightings logged at the jetty.'
      WHEN d::date <= current_date + 1 AND r.kind = 'dawn' THEN 'Guests aboard, safety brief done.'
      WHEN d::date <= current_date + 1 THEN 'Hotel pickup to confirm before the 10:00 cruise.'
      ELSE 'Booked through the website.'
    END AS note,
    -- Deterministic but varied: the same day always produces the same manifest.
    2 + (('x' || substr(md5(d::text || r.kind), 1, 4))::bit(16)::int % 4) AS adults,
    (('x' || substr(md5(r.kind || d::text), 1, 4))::bit(16)::int % 3)     AS children,
    CASE WHEN (('x' || substr(md5(d::text), 1, 2))::bit(8)::int % 2) = 0
         THEN 'Website' ELSE 'Walk-in' END AS source
) AS state
WHERE NOT EXISTS (
  SELECT 1 FROM bookings b
   WHERE b."ResourceId" = r."Id"
     AND b."DeletedAt" IS NULL
     AND b."StartTime" = (d::date + sch."StartTime") AT TIME ZONE 'UTC');

-- Availability slots are a published ledger, so a new booking has to be
-- reflected in the slot it fills. Only unbooked slots are touched; a slot
-- already marked sold keeps the booking it points at.
UPDATE availability_slots s
   SET "IsBooked" = TRUE,
       "BookingId" = b."Id",
       "UpdatedAt" = now()
  FROM _day_params p, resources r, bookings b
 WHERE r."Id" = s."ResourceId"
   AND r."TenantId" = p.tenant_id
   AND NOT s."IsBooked"
   AND b."ResourceId" = r."Id"
   AND b."DeletedAt" IS NULL
   AND b."Status" NOT IN ('Cancelled','Rejected','WeatherCancelled')
   AND b."StartTime" <  (s."Date"::date + s."EndTime")   AT TIME ZONE 'UTC'
   AND b."EndTime"   >  (s."Date"::date + s."StartTime") AT TIME ZONE 'UTC';

COMMIT;

-- ── What the day-scoped screens will now show ───────────────────────────────
SELECT (b."StartTime" AT TIME ZONE 'UTC')::date       AS sailing_date,
       count(*)                                        AS sailings,
       sum(b."AttendeeCount")                          AS guests,
       count(*) FILTER (WHERE b."Status" = 'Pending')  AS awaiting_approval,
       count(*) FILTER (WHERE b."Status" = 'CheckedIn') AS checked_in,
       sum(b."TotalCost")                              AS revenue_lkr
FROM bookings b
WHERE b."TenantId" = 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid
  AND b."DeletedAt" IS NULL
  AND b."StartTime" >= (current_date - 2)
GROUP BY 1 ORDER BY 1;
