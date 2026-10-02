-- ============================================================================
-- Demo data for the Disruption Recovery Copilot, on the Mirissa Jetliner
-- tenant (whale watching, Whale / dolphin watching sub-type).
--
-- The story it sets up: the Dawn Departure vessel fails its safety check
-- tomorrow morning. Ten guests across four bookings are stranded, with
-- different amounts at stake - a family of six who paid a deposit, a couple
-- due within the day, two solo travellers. The Morning Cruise vessel has room
-- later the same day, so there is a real recovery to find rather than an
-- empty answer.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-disruption.sql
--
-- Then in the web app: Bookings -> Disruption Recovery, choose
-- "Whale Watching Boat - Dawn Departure", set both dates to tomorrow, and
-- describe the outage. The agents read these bookings, propose a move each,
-- and wait for your approval.
--
-- Re-running is safe: it removes only the demo guests and bookings it
-- created (they carry the 'DisruptionDemo' source and a known e-mail suffix)
-- and recreates them relative to today, so the window is always "tomorrow".
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _seed_ctx;
CREATE TEMP TABLE _seed_ctx AS
SELECT 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid AS tenant_id;

-- ── Guard: nothing below makes sense without the base tenant ───────────────
DO $$
DECLARE missing int;
BEGIN
    SELECT count(*) INTO missing FROM "Tenants" t
     WHERE t."Id" = 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid;
    IF missing = 0 THEN
        RAISE EXCEPTION
          'Mirissa Jetliner tenant not found. Run scripts/seed-mirissa-jetliner.ps1 first.';
    END IF;
END $$;

-- ── The two vessels and the tour product ───────────────────────────────────
DROP TABLE IF EXISTS _seed_boats;
CREATE TEMP TABLE _seed_boats AS
SELECT
  (SELECT r."Id" FROM "resources" r, _seed_ctx ctx
    WHERE r."TenantId" = ctx.tenant_id
      AND r."Name" = 'Whale Watching Boat - Dawn Departure'
      AND r."DeletedAt" IS NULL
    LIMIT 1) AS dawn_id,
  (SELECT r."Id" FROM "resources" r, _seed_ctx ctx
    WHERE r."TenantId" = ctx.tenant_id
      AND r."Name" = 'Whale Watching Boat - Morning Cruise'
      AND r."DeletedAt" IS NULL
    LIMIT 1) AS morning_id,
  (SELECT r."BranchId" FROM "resources" r, _seed_ctx ctx
    WHERE r."TenantId" = ctx.tenant_id AND r."DeletedAt" IS NULL
      AND r."BranchId" IS NOT NULL
    LIMIT 1) AS branch_id,
  (SELECT bt."Id" FROM "booking_types" bt, _seed_ctx ctx
    WHERE bt."TenantId" = ctx.tenant_id
      AND COALESCE(bt."ConfigJson"->>'category', 'tour') = 'tour'
    ORDER BY bt."CreatedAt"
    LIMIT 1) AS tour_type_id;

DO $$
DECLARE b record;
BEGIN
    SELECT * INTO b FROM _seed_boats;
    IF b.dawn_id IS NULL OR b.morning_id IS NULL OR b.tour_type_id IS NULL THEN
        RAISE EXCEPTION
          'Expected both vessels and a tour product. Run scripts/seed-mirissa-jetliner.ps1 first.';
    END IF;
END $$;

-- ── Clean up a previous run of this script only ────────────────────────────
DELETE FROM "bookings" b
 USING _seed_ctx ctx
 WHERE b."TenantId" = ctx.tenant_id
   AND b."Source" = 'DisruptionDemo';

DELETE FROM "Users" u
 USING _seed_ctx ctx
 WHERE u."TenantId" = ctx.tenant_id
   AND u."Email" LIKE '%@disruption-demo.test';

-- ── The guests ─────────────────────────────────────────────────────────────
-- Password for all of them is Demo@12345, the same hash the other demo
-- tenants use, so you can sign in as one and watch the move arrive.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved")
SELECT gen_random_uuid(), now() - interval '30 days', now(), ctx.tenant_id, b.branch_id,
       v.email, '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       v.full_name, v.phone, 3, true, true
FROM _seed_ctx ctx, _seed_boats b,
(VALUES
  ('fernando@disruption-demo.test', 'Dilani Fernando',  '+94771234501'),
  ('okafor@disruption-demo.test',   'Chidi Okafor',     '+94771234502'),
  ('tanaka@disruption-demo.test',   'Yuki Tanaka',      '+94771234503'),
  ('muller@disruption-demo.test',   'Lena Müller',      '+94771234504')
) AS v(email, full_name, phone);

-- ── The stranded bookings ──────────────────────────────────────────────────
-- All on tomorrow's Dawn Departure (06:30 local, stored UTC). Each carries a
-- different mix of deposit, party size and lead time, which is exactly what
-- the Impact agent ranks on - so the demo shows a non-obvious ordering.
--
-- Why this is dynamic SQL: OccupiesResourceExclusively arrives with migration
-- AddBookingOverlapExclusion, and this script has to run on a database that
-- has it and on one that does not yet. Where the column exists it is set to
-- false here, at insert time rather than afterwards - a vessel sells seats
-- against a licensed capacity, so these four bookings legitimately overlap,
-- and the exclusion constraint would refuse the second guest on the sailing
-- before any later UPDATE could fix it.
DO $outer$
DECLARE
    has_exclusivity_flag boolean;
    extra_column text := '';
    extra_value  text := '';
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'bookings'
           AND column_name  = 'OccupiesResourceExclusively'
    ) INTO has_exclusivity_flag;

    IF has_exclusivity_flag THEN
        extra_column := ', "OccupiesResourceExclusively"';
        extra_value  := ', false';
    ELSE
        RAISE NOTICE 'bookings.OccupiesResourceExclusively is not present yet; '
                     'this database predates migration AddBookingOverlapExclusion. '
                     'The demo data is still created correctly.';
    END IF;

    EXECUTE format($q$
        INSERT INTO "bookings"
          ("Id","TenantId","ResourceId","BookingTypeId","BookedBy","Title","Notes",
           "StartTime","EndTime","Status","Priority","AttendeeCount","Source",
           "DepositAmount","TotalCost","ReminderSent","CreatedAt","UpdatedAt","Version"%s)
        SELECT gen_random_uuid(), ctx.tenant_id, b.dawn_id, b.tour_type_id, u."Id",
               v.title, v.notes,
               ((current_date + 1) + time '06:30') AT TIME ZONE 'Asia/Colombo',
               ((current_date + 1) + time '10:30') AT TIME ZONE 'Asia/Colombo',
               'Confirmed', 'Normal', v.guests, 'DisruptionDemo',
               v.deposit, v.total, false, now() - interval '6 days', now(), 1%s
        FROM _seed_ctx ctx
        CROSS JOIN _seed_boats b
        JOIN (VALUES
          ('fernando@disruption-demo.test', 'Fernando family - 6 guests', 6, 22500, 41000,
           'Deposit paid. Travelling from Colombo, grandparents in the party.'),
          ('okafor@disruption-demo.test',   'Okafor - honeymoon couple',  2,  7500, 15000,
           'Deposit paid. Flying out the following evening.'),
          ('tanaka@disruption-demo.test',   'Tanaka - solo photographer', 1,     0,  7500,
           'Wants the dawn light; happy to move days if the light is right.'),
          ('muller@disruption-demo.test',   'Muller - solo traveller',    1,     0,  7500,
           'Flexible.')
        ) AS v(email, title, guests, deposit, total, notes) ON TRUE
        JOIN "Users" u ON u."Email" = v.email AND u."TenantId" = ctx.tenant_id
    $q$, extra_column, extra_value);
END $outer$;

-- ── Make sure there is somewhere for them to go ────────────────────────────
-- The Morning Cruise sails at 10:00 the same day. Nothing else is seeded onto
-- it, so the Recovery agent finds real room there. If your tenant already has
-- bookings on it, that is fine - the agents work with whatever is free, and a
-- full boat is a legitimate "no option found" demo too.

-- ── Repair the exclusivity flag for this whole tenant ───────────────────────
-- Any booking on a vessel with a licensed capacity above one sells seats, so
-- it must stay exempt from the overlap constraint. Older seed scripts predate
-- the column and leave it at its default of true, which would make a second
-- passenger on the same sailing impossible. Skipped entirely on a database
-- that has not run the migration yet. Idempotent.
DO $repair$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'bookings'
           AND column_name  = 'OccupiesResourceExclusively'
    ) THEN
        UPDATE "bookings" b
           SET "OccupiesResourceExclusively" = false
          FROM _seed_ctx ctx
         WHERE b."TenantId" = ctx.tenant_id
           AND b."OccupiesResourceExclusively"
           AND COALESCE(
                 (SELECT d."LicensedCapacity" FROM "departures" d
                   WHERE d."Id" = b."DepartureId" AND d."LicensedCapacity" > 0),
                 (SELECT CASE
                           WHEN jsonb_typeof(r."CustomAttributes" -> 'capacity') = 'number'
                             THEN (r."CustomAttributes" ->> 'capacity')::int
                         END
                    FROM "resources" r WHERE r."Id" = b."ResourceId"),
                 (SELECT NULLIF(r."Capacity", 0) FROM "resources" r WHERE r."Id" = b."ResourceId"),
                 (SELECT NULLIF(t."MaxParticipants", 0) FROM "booking_types" t
                   WHERE t."Id" = b."BookingTypeId"),
                 1) > 1;
    END IF;
END $repair$;

COMMIT;

-- ── What you should see ────────────────────────────────────────────────────
--   4 bookings, 10 guests, LKR 71,000 at risk on tomorrow's Dawn Departure.
--
-- The Impact agent ranks them by deposit, lead time and party size, so the
-- Fernando family of six comes first and the flexible solo traveller last -
-- not the order they were booked in. The tourism policy requires equal
-- capacity and keeps a party together, and will not move a trip more than
-- five days.
SELECT u."FullName" AS guest,
       b."AttendeeCount" AS guests,
       b."DepositAmount" AS deposit,
       b."TotalCost" AS total,
       b."StartTime" AT TIME ZONE 'Asia/Colombo' AS departs_local
  FROM "bookings" b
  JOIN "Users" u ON u."Id" = b."BookedBy"
 WHERE b."Source" = 'DisruptionDemo'
 ORDER BY b."DepositAmount" DESC, b."AttendeeCount" DESC;
