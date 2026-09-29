-- ============================================================================
-- Recurring Series — a repeating booking as ONE thing (spec 2.3).
--
-- Runs anywhere: the Supabase SQL editor, pgAdmin, DBeaver, or psql.
--   psql "$DATABASE_URL" -f scripts/seed-recurring-series.sql
--
-- (An earlier revision used psql's \set meta-command for its parameters.
-- That is not SQL — a browser SQL editor sends the text straight to the
-- server and fails on the backslash — so the parameters now live in a temp
-- table every statement reads.)
--
-- WHAT A SERIES IS HERE
-- The engine resolves a series by resource + booking type + CUSTOMER + time
-- of day. That definition matters: twenty different travellers on the same
-- dawn sailing are twenty bookings, not a series, and calling them one would
-- make the page claim a standing commitment nobody made. A series is one
-- customer holding the same slot over and over — a weekly class, a clinic's
-- standing review, a travel agent's daily allocation.
--
-- The recurring_patterns row is anchored on the FIRST occurrence. That is how
-- GET /bookings/{id}/series finds the rest of the series from any occurrence
-- in it, and how DELETE /bookings/series/{patternId} knows what to call off.
--
-- PARAMETERS live in the one SELECT below. Change them, nothing else.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS _series_ctx;

-- ── 0) Parameters and the ids they resolve to ───────────────────────────────
CREATE TEMP TABLE _series_ctx AS
WITH params AS (
  SELECT
    'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid   AS tenant_id,
    '%Morning Cruise%'::text                        AS resource_name,
    'Whale Watching'::text                          AS type_name,
    'ocean.breeze.mirissa@example-demo.test'::text  AS customer_email,
    'Ocean Breeze Travels (Galle)'::text            AS customer_name,
    '+94912234455'::text                            AS customer_phone,
    'Galle Fort'::text                              AS customer_address,
    TIME '10:00'                                    AS start_hhmm,
    240::int                                        AS duration_minutes,
    7::int                                          AS first_day_offset,
    20::int                                         AS last_day_offset,
    8::int                                          AS party_size
)
SELECT p.*,
       t."Id" AS resolved_tenant_id,
       (SELECT b."Id" FROM "Branches" b
         WHERE b."TenantId" = t."Id" AND b."IsActive"
         ORDER BY b."CreatedAt" LIMIT 1)                        AS branch_id,
       (SELECT r."Id" FROM resources r
         WHERE r."TenantId" = t."Id" AND r."Name" LIKE p.resource_name
           AND r."DeletedAt" IS NULL ORDER BY r."Name" LIMIT 1) AS resource_id,
       (SELECT bt."Id" FROM booking_types bt
         WHERE bt."TenantId" = t."Id" AND bt."Name" = p.type_name
           AND bt."DeletedAt" IS NULL LIMIT 1)                  AS type_id
FROM params p
JOIN "Tenants" t ON t."Id" = p.tenant_id;

DO $$
DECLARE c RECORD;
BEGIN
  SELECT * INTO c FROM _series_ctx;
  IF c IS NULL THEN RAISE EXCEPTION 'Tenant not found - check tenant_id in the params block.'; END IF;
  IF c.resource_id IS NULL THEN RAISE EXCEPTION 'No resource matched resource_name.'; END IF;
  IF c.type_id IS NULL THEN RAISE EXCEPTION 'No booking type matched type_name.'; END IF;
END $$;

-- ── 1) The customer who holds the series ────────────────────────────────────
-- Scoped to this tenant on purpose: the same email in another tenant is a
-- different person, and booking against them would cross the tenant boundary
-- the whole platform rests on.
INSERT INTO "Users"
  ("Id","CreatedAt","UpdatedAt","TenantId","BranchId","Email","PasswordHash",
   "FullName","Phone","Role","IsActive","IsApproved","Address")
SELECT gen_random_uuid(), now() - interval '90 days', now(),
       ctx.tenant_id, ctx.branch_id, ctx.customer_email,
       -- Demo login: Passw0rd!
       '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
       ctx.customer_name, ctx.customer_phone, 3, true, true, ctx.customer_address
FROM _series_ctx ctx
WHERE NOT EXISTS (
  SELECT 1 FROM "Users" u
   WHERE lower(u."Email") = lower(ctx.customer_email)
     AND u."TenantId" = ctx.tenant_id);

-- ── 2) The occurrences ──────────────────────────────────────────────────────
-- One booking per day in the run, all at the same time of day so the engine
-- can recognise them as one series. A day another booking already holds is
-- skipped rather than double-booked.
INSERT INTO bookings
  ("Id","CreatedAt","UpdatedAt","TenantId","ResourceId","BookingTypeId","BookedBy",
   "Title","Notes","StartTime","EndTime","Status","Priority","AttendeeCount","Source","Version")
SELECT gen_random_uuid(), now(), now(),
       ctx.tenant_id, ctx.resource_id, ctx.type_id, holder."Id",
       bt."Name" || ' - standing allocation',
       ctx.customer_name || ' recurring booking',
       (d::date + ctx.start_hhmm) AT TIME ZONE 'UTC',
       (d::date + ctx.start_hhmm + make_interval(mins => ctx.duration_minutes)) AT TIME ZONE 'UTC',
       'Confirmed', 'Normal', ctx.party_size, 'Agent',
       -- Optimistic-concurrency counter; rows the API creates start at 1 too.
       1
FROM _series_ctx ctx
JOIN booking_types bt ON bt."Id" = ctx.type_id
JOIN "Users" holder
  ON lower(holder."Email") = lower(ctx.customer_email)
 AND holder."TenantId" = ctx.tenant_id
CROSS JOIN LATERAL generate_series(
       current_date + ctx.first_day_offset,
       current_date + ctx.last_day_offset,
       interval '1 day') AS d
WHERE NOT EXISTS (
  SELECT 1 FROM bookings b
   WHERE b."ResourceId" = ctx.resource_id
     AND b."DeletedAt" IS NULL
     AND b."StartTime" = (d::date + ctx.start_hhmm) AT TIME ZONE 'UTC');

-- ── 3) The pattern ──────────────────────────────────────────────────────────
-- Anchored on the earliest occurrence, which is where GetSeries looks.
INSERT INTO recurring_patterns
  ("Id","CreatedAt","UpdatedAt","BookingId","Frequency","EndDate","DaysOfWeek")
SELECT gen_random_uuid(), now(), now(),
       anchor.id,
       'Weekly',
       anchor.last_start,
       -- Which weekdays the run actually covers, 0 = Sunday, matching the
       -- backend. Derived rather than assumed, so a Mon/Wed/Fri run does not
       -- claim to be daily.
       anchor.dows
FROM (
  SELECT (array_agg(b."Id" ORDER BY b."StartTime"))[1]            AS id,
         array_agg(DISTINCT EXTRACT(dow FROM b."StartTime")::int) AS dows,
         max(b."StartTime")                                       AS last_start
    FROM bookings b
    JOIN _series_ctx ctx ON b."TenantId" = ctx.tenant_id
                        AND b."ResourceId" = ctx.resource_id
                        AND b."BookingTypeId" = ctx.type_id
    JOIN "Users" u ON u."Id" = b."BookedBy"
                  AND lower(u."Email") = lower(ctx.customer_email)
                  AND u."TenantId" = ctx.tenant_id
   WHERE b."DeletedAt" IS NULL
) AS anchor
WHERE anchor.id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM recurring_patterns p WHERE p."BookingId" = anchor.id);

-- Re-running with a longer run adds occurrences beyond the pattern's old end
-- date, and the engine resolves a series only up to that date — so without
-- this the new bookings exist but sit outside their own series. Extend it
-- (never shorten: that would silently drop occurrences already counted).
UPDATE recurring_patterns p
SET "EndDate" = latest.last_start, "UpdatedAt" = now()
FROM (
  SELECT (array_agg(b."Id" ORDER BY b."StartTime"))[1] AS anchor_id,
         max(b."StartTime")                            AS last_start
    FROM bookings b
    JOIN _series_ctx ctx ON b."TenantId" = ctx.tenant_id
                        AND b."ResourceId" = ctx.resource_id
                        AND b."BookingTypeId" = ctx.type_id
    JOIN "Users" u ON u."Id" = b."BookedBy"
                  AND lower(u."Email") = lower(ctx.customer_email)
                  AND u."TenantId" = ctx.tenant_id
   WHERE b."DeletedAt" IS NULL
) AS latest
WHERE p."BookingId" = latest.anchor_id
  AND p."EndDate" < latest.last_start;

-- ── 4) Take the slots, if this resource publishes any ───────────────────────
-- A resource still on computed availability has no rows here and is
-- unaffected; one with a published ledger must show the series as sold.
UPDATE availability_slots s
SET "IsBooked" = true, "BookingId" = b."Id", "UpdatedAt" = now()
FROM bookings b
JOIN _series_ctx ctx ON b."ResourceId" = ctx.resource_id
JOIN "Users" u ON u."Id" = b."BookedBy"
             AND lower(u."Email") = lower(ctx.customer_email)
             AND u."TenantId" = ctx.tenant_id
WHERE s."ResourceId" = ctx.resource_id
  AND b."DeletedAt" IS NULL
  AND b."Status" NOT IN ('Cancelled','Rejected','WeatherCancelled')
  AND b."StartTime" < (s."Date"::date + s."EndTime") AT TIME ZONE 'UTC'
  AND b."EndTime"   > (s."Date"::date + s."StartTime") AT TIME ZONE 'UTC'
  AND NOT s."IsBooked";

COMMIT;

-- ── What landed ─────────────────────────────────────────────────────────────
-- One row per series, shaped the way the Recurring Series page reads it.
SELECT bt."Name"                                                       AS booking_type,
       r."Name"                                                        AS resource,
       u."FullName"                                                    AS held_by,
       p."Frequency",
       p."DaysOfWeek",
       to_char(anchor."StartTime", 'HH24:MI')                          AS time_of_day,
       p."EndDate"::date                                               AS runs_until,
       count(occ.*)                                                    AS total,
       count(occ.*) FILTER (WHERE occ."StartTime" > now()
              AND occ."Status" NOT IN ('Cancelled','Rejected'))        AS remaining,
       count(occ.*) FILTER (WHERE occ."Status" IN ('Cancelled','Rejected')) AS cancelled
FROM recurring_patterns p
JOIN bookings anchor  ON anchor."Id" = p."BookingId"
JOIN resources r      ON r."Id" = anchor."ResourceId"
JOIN booking_types bt ON bt."Id" = anchor."BookingTypeId"
JOIN "Users" u        ON u."Id" = anchor."BookedBy"
-- The occurrences: same resource, type, customer and time of day, up to the
-- pattern's end. Exactly how the API resolves them.
LEFT JOIN bookings occ
       ON occ."ResourceId" = anchor."ResourceId"
      AND occ."BookingTypeId" = anchor."BookingTypeId"
      AND occ."BookedBy" = anchor."BookedBy"
      AND occ."DeletedAt" IS NULL
      AND occ."StartTime" >= anchor."StartTime"
      AND occ."StartTime" <= p."EndDate" + interval '1 day'
      AND occ."StartTime"::time = anchor."StartTime"::time
WHERE anchor."TenantId" = 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid
GROUP BY bt."Name", r."Name", u."FullName", p."Frequency", p."DaysOfWeek",
         anchor."StartTime", p."EndDate"
ORDER BY r."Name";

-- ── Cancel the remaining occurrences of a series ────────────────────────────
-- Past ones keep their history: a class that ran is a class that ran.
-- Uncomment and set the pattern id to use.
--
-- WITH target AS (
--   SELECT b."ResourceId", b."BookingTypeId", b."BookedBy",
--          b."StartTime"::time AS tod
--     FROM recurring_patterns p JOIN bookings b ON b."Id" = p."BookingId"
--    WHERE p."Id" = '00000000-0000-0000-0000-000000000000'::uuid
-- ), cancelled AS (
--   UPDATE bookings b SET "Status" = 'Cancelled', "UpdatedAt" = now()
--     FROM target t
--    WHERE b."ResourceId" = t."ResourceId" AND b."BookingTypeId" = t."BookingTypeId"
--      AND b."BookedBy" = t."BookedBy" AND b."StartTime"::time = t.tod
--      AND b."StartTime" > now() AND b."DeletedAt" IS NULL
--      AND b."Status" NOT IN ('Cancelled','Rejected')
--   RETURNING b."Id"
-- )
-- UPDATE availability_slots s SET "IsBooked" = false, "BookingId" = NULL, "UpdatedAt" = now()
--  WHERE s."BookingId" IN (SELECT "Id" FROM cancelled);
