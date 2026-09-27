-- ============================================================================
-- Booking-engine records for the "Mirissa JetLiner" whale-watching tenant,
-- covering the parts of component 2 that had no data at all:
--
--   * availability_slots  (spec 2.3) — the published capacity ledger. Until
--                         recently this table was never written to; the app
--                         computed availability on the fly and held nothing.
--   * recurring_patterns  (spec 2.3) — a repeating sailing as ONE series you
--                         can see and call off, not N unrelated bookings.
--   * bookings            — the sailings themselves, so the slots have
--                         something to be sold to and the ledger shows a
--                         real utilisation figure rather than 0%.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-booking-engine.sql
--
-- WHICH TENANT: several tenants are named some variant of "Mirissa
-- Jetliner". This one is pinned by Id to the tenant that actually owns the
-- two whale-watching vessels — NOT the same Id as
-- seed-mirissa-jetliner-billing.sql, which targets a different one. Change
-- tenant_id below to point it elsewhere.
--
-- SLOT SIZE is not a free choice. This operator sells one sailing per
-- window: the Dawn Departure is open 06:30-10:30 and the Morning Cruise
-- 10:00-14:00, both four hours. Generating 240-minute slots therefore
-- produces exactly one slot per vessel per day — the real sailing. Halving
-- it to get a fuller-looking ledger would invent an 08:30 departure this
-- business does not run.
--
-- TIME ZONE: resource_schedules stores wall-clock times with no zone, and
-- the app's SlotCalculator composes them against UTC dates, so a 06:30
-- schedule becomes a 06:30Z slot. This script follows that same convention
-- (the one seed-mirissa-jetliner-departures.sql already uses) so the slots
-- it writes line up exactly with what the app itself would generate. Worth
-- knowing: for a Colombo operator that is 06:30 UTC, not 06:30 local.
--
-- Everything here is DEMO DATA: guests, phone numbers and emails are
-- invented. Emails use the reserved example-demo.test domain and every
-- login created here has the password Passw0rd!
--
-- Idempotent: guests are guarded by email, bookings by (resource, start
-- time), slots by the table's own unique index, and the pattern by its
-- anchor. Re-running adds nothing. Wrapped in one transaction.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _mjb_ctx;
DROP TABLE IF EXISTS _mjb_guest;
DROP TABLE IF EXISTS _mjb_sail;

-- ── 0) Context ──────────────────────────────────────────────────────────────
CREATE TEMP TABLE _mjb_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT b."Id" FROM "Branches" b
         WHERE b."TenantId" = t."Id" AND b."IsActive"
         ORDER BY b."CreatedAt" LIMIT 1) AS branch_id,
       (SELECT r."Id" FROM resources r
         WHERE r."TenantId" = t."Id" AND r."Name" LIKE '%Dawn Departure%'
           AND r."DeletedAt" IS NULL LIMIT 1) AS dawn_id,
       (SELECT r."Id" FROM resources r
         WHERE r."TenantId" = t."Id" AND r."Name" LIKE '%Morning Cruise%'
           AND r."DeletedAt" IS NULL LIMIT 1) AS morning_id,
       (SELECT bt."Id" FROM booking_types bt
         WHERE bt."TenantId" = t."Id" AND bt."Name" = 'Whale Watching Tour'
           AND bt."DeletedAt" IS NULL LIMIT 1) AS tour_type_id
FROM "Tenants" t
WHERE t."Id" = 'd303c4ef-6eb9-4189-95e0-b537d2134ba9'::uuid;

DO $$
DECLARE c RECORD;
BEGIN
  SELECT * INTO c FROM _mjb_ctx;
  IF c IS NULL THEN
    RAISE EXCEPTION 'Tenant d303c4ef-6eb9-4189-95e0-b537d2134ba9 (Mirissa JetLiner) was not found - check the Id at the top of this script.';
  END IF;
  IF c.dawn_id IS NULL OR c.morning_id IS NULL THEN
    RAISE EXCEPTION 'The two whale-watching vessels were not found - run scripts/seed-mirissa-jetliner.ps1 first.';
  END IF;
  IF c.tour_type_id IS NULL THEN
    RAISE EXCEPTION 'Booking type "Whale Watching Tour" was not found - run scripts/seed-mirissa-jetliner.ps1 first.';
  END IF;
END $$;

-- ── 1) Guests ───────────────────────────────────────────────────────────────
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved","Address")
SELECT gen_random_uuid(), now() - (v.days_ago || ' days')::interval, now(),
       ctx.tenant_id, ctx.branch_id, v.email,
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, 3, true, true, v.address
FROM _mjb_ctx ctx,
(VALUES
  ('iris.lindqvist@example-demo.test', 'Iris Lindqvist',   '+46701234567', 'Hotel - Mirissa Beach',    40),
  ('tomas.berger@example-demo.test',   'Tomas Berger',     '+491751234567','Villa - Weligama',         34),
  ('amara.wickrama@example-demo.test', 'Amara Wickrama',   '+94771450031', 'Matara',                   27),
  ('kenji.sato@example-demo.test',     'Kenji Sato',       '+819087654321','Hotel - Mirissa Bay',      21),
  ('claire.fontaine@example-demo.test','Claire Fontaine',  '+33698765432', 'Hostel - Mirissa Harbour', 16),
  ('deepak.raina@example-demo.test',   'Deepak Raina',     '+919845612378','Resort - Polwathumodara',  11),
  ('sanduni.rathnayake@example-demo.test','Sanduni Rathnayake','+94771450032','Galle',                  6),
  ('harry.whitfield@example-demo.test','Harry Whitfield',  '+447700900311','Surf camp - Midigama',      3)
) AS v(email, full_name, phone, address, days_ago)
WHERE NOT EXISTS (SELECT 1 FROM "Users" u WHERE lower(u."Email") = v.email);

CREATE TEMP TABLE _mjb_guest AS
SELECT u."Id" AS user_id,
       row_number() OVER (ORDER BY u."CreatedAt") AS n
FROM "Users" u JOIN _mjb_ctx ctx ON u."TenantId" = ctx.tenant_id
WHERE u."Role" = 3 AND u."Email" LIKE '%@example-demo.test';

-- ── 2) Sailings ─────────────────────────────────────────────────────────────
-- One row per sailing actually sold. Days are relative to today so the
-- ledger always has a live "sold ahead" figure; the past week is Completed,
-- the days ahead are Confirmed, with a couple of exceptions so the
-- utilisation and no-show numbers are not uniformly flattering.
--
-- The Dawn Departure sells most days; the Morning Cruise is the quieter
-- boat, which is exactly the gap the availability ledger exists to show.
CREATE TEMP TABLE _mjb_sail (
  day_offset int, vessel text, guest_n int, adults int, status text, note text
);

INSERT INTO _mjb_sail VALUES
 -- Last week: sailed and done.
 (-6, 'dawn',    1, 2, 'Completed', 'Blue whale sighted off the shelf'),
 (-5, 'dawn',    2, 4, 'Completed', 'Family of four'),
 (-5, 'morning', 3, 2, 'Completed', 'Late risers'),
 (-4, 'dawn',    4, 2, 'Completed', 'Repeat guests'),
 (-3, 'dawn',    5, 3, 'Completed', 'Hostel group'),
 (-3, 'morning', 6, 2, 'NoShow',    'Never made the jetty'),
 (-2, 'dawn',    7, 2, 'Completed', 'Calm seas, sperm whales'),
 (-1, 'dawn',    8, 6, 'Completed', 'Tour-operator block'),
 (-1, 'morning', 1, 2, 'Cancelled', 'Guest cancelled the night before'),
 -- Today onward: on the books.
 ( 0, 'dawn',    2, 4, 'Confirmed', 'Dawn departure - confirmed'),
 ( 0, 'morning', 3, 2, 'Confirmed', 'Morning cruise - confirmed'),
 ( 1, 'dawn',    4, 2, 'Confirmed', 'Tomorrow, dawn'),
 ( 2, 'dawn',    5, 5, 'Confirmed', 'Group of five'),
 ( 2, 'morning', 6, 2, 'Pending',   'Awaiting the desk'),
 ( 3, 'dawn',    7, 2, 'Confirmed', 'Honeymoon couple'),
 ( 5, 'dawn',    8, 3, 'Confirmed', 'Photography trip'),
 ( 6, 'morning', 1, 4, 'Confirmed', 'Later start for the children'),
 ( 8, 'dawn',    2, 2, 'Confirmed', 'Next week, dawn'),
 (11, 'dawn',    3, 2, 'Pending',   'Provisional - deposit not in'),
 (14, 'dawn',    4, 6, 'Confirmed', 'Agent allocation');

INSERT INTO bookings
  ("Id","CreatedAt","UpdatedAt","TenantId","ResourceId","BookingTypeId","BookedBy",
   "Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source","Version")
SELECT gen_random_uuid(),
       now() - ((14 - s.day_offset) || ' days')::interval, now(),
       ctx.tenant_id,
       CASE s.vessel WHEN 'dawn' THEN ctx.dawn_id ELSE ctx.morning_id END,
       ctx.tour_type_id,
       g.user_id,
       'Whale Watching Tour - ' || CASE s.vessel WHEN 'dawn' THEN 'Dawn Departure' ELSE 'Morning Cruise' END,
       s.note,
       -- The vessel's own published start time, composed against the date
       -- the same way SlotCalculator does it.
       ((current_date + s.day_offset)::date
          + CASE s.vessel WHEN 'dawn' THEN TIME '06:30' ELSE TIME '10:00' END) AT TIME ZONE 'UTC',
       ((current_date + s.day_offset)::date
          + CASE s.vessel WHEN 'dawn' THEN TIME '10:30' ELSE TIME '14:00' END) AT TIME ZONE 'UTC',
       s.status, 'Normal', s.adults, 'Website',
       -- Optimistic-concurrency counter; every row starts at 1, the same as
       -- a booking the API creates.
       1
FROM _mjb_sail s
JOIN _mjb_ctx ctx ON true
JOIN _mjb_guest g ON g.n = s.guest_n
WHERE NOT EXISTS (
  SELECT 1 FROM bookings b
   WHERE b."TenantId" = ctx.tenant_id
     AND b."ResourceId" = CASE s.vessel WHEN 'dawn' THEN ctx.dawn_id ELSE ctx.morning_id END
     AND b."StartTime" = ((current_date + s.day_offset)::date
          + CASE s.vessel WHEN 'dawn' THEN TIME '06:30' ELSE TIME '10:00' END) AT TIME ZONE 'UTC');

-- ── 3) The availability ledger ──────────────────────────────────────────────
-- 28 days of published capacity, one 240-minute slot per vessel per day,
-- exactly as AvailabilitySlotService.GenerateAsync would write it. A slot
-- whose window a live booking covers is written as taken, with that
-- booking's id - which is what makes the utilisation figure real rather
-- than decorative.
INSERT INTO availability_slots
  ("Id","CreatedAt","UpdatedAt","ResourceId","Date","StartTime","EndTime","IsBooked","BookingId")
SELECT gen_random_uuid(), now(), now(),
       v.resource_id,
       d::date AT TIME ZONE 'UTC',
       v.start_at,
       v.end_at,
       b."Id" IS NOT NULL,
       b."Id"
FROM _mjb_ctx ctx
CROSS JOIN generate_series(current_date - 7, current_date + 20, interval '1 day') AS d
CROSS JOIN LATERAL (VALUES
  (ctx.dawn_id,    TIME '06:30'::interval, TIME '10:30'::interval),
  (ctx.morning_id, TIME '10:00'::interval, TIME '14:00'::interval)
) AS v(resource_id, start_at, end_at)
LEFT JOIN LATERAL (
  SELECT b."Id"
    FROM bookings b
   WHERE b."ResourceId" = v.resource_id
     AND b."DeletedAt" IS NULL
     -- Cancelled and rejected sailings hand their slot back, so they must
     -- not hold one here either.
     AND b."Status" NOT IN ('Cancelled','Rejected','WeatherCancelled')
     AND b."StartTime" < (d::date + v.end_at) AT TIME ZONE 'UTC'
     AND b."EndTime"   > (d::date + v.start_at) AT TIME ZONE 'UTC'
   LIMIT 1
) b ON true
WHERE NOT EXISTS (
  SELECT 1 FROM availability_slots s
   WHERE s."ResourceId" = v.resource_id
     AND s."Date" = d::date AT TIME ZONE 'UTC'
     AND s."StartTime" = v.start_at
     AND s."EndTime" = v.end_at);

-- An earlier revision guarded the agent account on email alone. Another seed
-- creates the same address for a different tenant, so the allocation was
-- booked against somebody else's customer. Clear those before rebuilding.
DELETE FROM recurring_patterns p
USING bookings b, "Users" u, _mjb_ctx ctx
WHERE p."BookingId" = b."Id" AND u."Id" = b."BookedBy"
  AND b."TenantId" = ctx.tenant_id AND u."TenantId" <> ctx.tenant_id;

UPDATE availability_slots s
SET "IsBooked" = false, "BookingId" = NULL, "UpdatedAt" = now()
FROM bookings b, "Users" u, _mjb_ctx ctx
WHERE s."BookingId" = b."Id" AND u."Id" = b."BookedBy"
  AND b."TenantId" = ctx.tenant_id AND u."TenantId" <> ctx.tenant_id;

DELETE FROM bookings b
USING "Users" u, _mjb_ctx ctx
WHERE u."Id" = b."BookedBy"
  AND b."TenantId" = ctx.tenant_id AND u."TenantId" <> ctx.tenant_id;

-- ── 4) The recurring series ─────────────────────────────────────────────────
-- A series in this engine is ONE customer holding the same slot repeatedly:
-- GetSeries resolves the occurrences by resource, type, customer and time of
-- day. The individual guest sailings above are therefore not a series - each
-- is a different traveller - and treating them as one would make the page
-- claim a commitment nobody made.
--
-- What a whale-watching operator really runs repeatedly is a TRADE
-- ALLOCATION: an agent holding the quieter boat every day for its own
-- clients. That is what this creates, on the Morning Cruise, on days no
-- individual guest has taken.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved","Address")
SELECT gen_random_uuid(), now() - interval '90 days', now(),
       ctx.tenant_id, ctx.branch_id, 'ocean.breeze.mirissa@example-demo.test',
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       'Ocean Breeze Travels (Galle)', '+94912234455', 3, true, true, 'Galle Fort'
FROM _mjb_ctx ctx
-- Scoped to this tenant: a user with the same address in another tenant is
-- somebody else entirely, and booking against them would cross the tenant
-- boundary the whole platform rests on.
WHERE NOT EXISTS (
  SELECT 1 FROM "Users" u
   WHERE lower(u."Email") = 'ocean.breeze.mirissa@example-demo.test'
     AND u."TenantId" = ctx.tenant_id);

-- Fourteen consecutive mornings, one agent, one boat, one time of day.
INSERT INTO bookings
  ("Id","CreatedAt","UpdatedAt","TenantId","ResourceId","BookingTypeId","BookedBy",
   "Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source","Version")
SELECT gen_random_uuid(), now() - interval '5 days', now(),
       ctx.tenant_id, ctx.morning_id, ctx.tour_type_id, agent."Id",
       'Whale Watching Tour - Morning Cruise (agent allocation)',
       'Ocean Breeze Travels standing allocation',
       (d::date + TIME '10:00') AT TIME ZONE 'UTC',
       (d::date + TIME '14:00') AT TIME ZONE 'UTC',
       'Confirmed', 'Normal', 8, 'Agent', 1
FROM _mjb_ctx ctx
CROSS JOIN generate_series(current_date + 7, current_date + 20, interval '1 day') AS d
JOIN "Users" agent ON lower(agent."Email") = 'ocean.breeze.mirissa@example-demo.test'
                 AND agent."TenantId" = ctx.tenant_id
WHERE NOT EXISTS (
  SELECT 1 FROM bookings b
   WHERE b."ResourceId" = ctx.morning_id
     AND b."StartTime" = (d::date + TIME '10:00') AT TIME ZONE 'UTC');

-- An earlier revision of this script anchored the pattern on a dawn sailing,
-- where every occurrence has a different guest, so the series resolved to a
-- single booking. Clear that before writing the correct one, so re-running
-- converges rather than leaving both.
DELETE FROM recurring_patterns p
USING bookings b, _mjb_ctx ctx
WHERE p."BookingId" = b."Id"
  AND b."TenantId" = ctx.tenant_id
  AND b."ResourceId" = ctx.dawn_id;

INSERT INTO recurring_patterns
  ("Id","CreatedAt","UpdatedAt","BookingId","Frequency","EndDate","DaysOfWeek")
SELECT gen_random_uuid(), now(), now(),
       anchor.id,
       'Weekly',
       (current_date + 20)::date AT TIME ZONE 'UTC',
       -- The allocation runs every day; 0 = Sunday, matching the backend.
       ARRAY[0,1,2,3,4,5,6]
FROM (
  SELECT b."Id" AS id
    FROM bookings b
    JOIN _mjb_ctx ctx ON b."TenantId" = ctx.tenant_id AND b."ResourceId" = ctx.morning_id
    JOIN "Users" u ON u."Id" = b."BookedBy"
   WHERE b."DeletedAt" IS NULL
     AND lower(u."Email") = 'ocean.breeze.mirissa@example-demo.test'
     AND u."TenantId" = ctx.tenant_id
   ORDER BY b."StartTime"
   LIMIT 1
) anchor
WHERE NOT EXISTS (
  SELECT 1 FROM recurring_patterns p WHERE p."BookingId" = anchor.id);

-- The new agent bookings take their slots, exactly as the app would.
UPDATE availability_slots s
SET "IsBooked" = true, "BookingId" = b."Id", "UpdatedAt" = now()
FROM bookings b, _mjb_ctx ctx
WHERE s."ResourceId" = ctx.morning_id
  AND b."ResourceId" = ctx.morning_id
  AND b."DeletedAt" IS NULL
  AND b."Status" NOT IN ('Cancelled','Rejected','WeatherCancelled')
  AND b."StartTime" < (s."Date"::date + s."EndTime") AT TIME ZONE 'UTC'
  AND b."EndTime"   > (s."Date"::date + s."StartTime") AT TIME ZONE 'UTC'
  AND NOT s."IsBooked";

COMMIT;

-- ── What landed ─────────────────────────────────────────────────────────────
-- Re-run this block on its own any time to see the engine's own position.
WITH ctx AS (
  SELECT 'd303c4ef-6eb9-4189-95e0-b537d2134ba9'::uuid AS tenant_id
)
SELECT r."Name" AS vessel,
       count(s.*)                                              AS slots_published,
       count(s.*) FILTER (WHERE s."IsBooked")                  AS sold,
       count(s.*) FILTER (WHERE NOT s."IsBooked")               AS still_open,
       round(100.0 * count(s.*) FILTER (WHERE s."IsBooked")
             / NULLIF(count(s.*), 0), 1)                        AS utilisation_pct
FROM availability_slots s
JOIN resources r ON r."Id" = s."ResourceId"
JOIN ctx ON r."TenantId" = ctx.tenant_id
GROUP BY r."Name"
ORDER BY r."Name";
