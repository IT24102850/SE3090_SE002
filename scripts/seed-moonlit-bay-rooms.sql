-- ============================================================================
-- Seed the 3 room RESOURCES for the Moonlit Bay (Weligama) tenant.
--
-- WHY THIS EXISTS: the customer app's business detail screen shows
-- "No rooms available right now." because it lists RESOURCES, not booking
-- types. See lib/screens/customer/business_detail_screen.dart:44 - it calls
-- resourcesProvider(tenantId) and then filters to r.status == 'Available'.
-- Booking types are not read on that screen at all; they are only used later,
-- inside the booking flow (booking_flow_screen.dart:390). So seeding
-- booking_types alone can never make rooms appear - you need these rows.
--
-- Run after (or instead of) scripts/seed-moonlit-bay-booking-types.sql.
-- One transaction; nothing commits if a guard trips.
--
-- PRICING NOTE - this is the part that is easy to get wrong:
-- "HourlyRate" is NOT an hourly rate for night-based resources. In
-- booking_flow_screen.dart:626-628 the total is
--     hourlyRate * (isSlot ? hours : nights)
-- so for a BookingUnit of 'Night' this column holds the PER-NIGHT price.
-- It is set to 4000 below, matching the room rate assumed in
-- docs/moonlit-bay-booking-types.txt (published range LKR 2,823-6,333).
--
-- KNOWN COSMETIC BUG (pre-existing, not caused by this data):
-- business_detail_screen.dart:336 renders the suffix "/hr" unconditionally,
-- so these rooms will display as "LKR 4000/hr" instead of "/night". The
-- stored value and the computed booking total are both correct; only the
-- label is wrong. Fixing it means making that suffix depend on the booking
-- unit - say the word and I will do it as a separate change.
-- ============================================================================

BEGIN;

-- ── 0) Locate the tenant ────────────────────────────────────────────────
CREATE TEMP TABLE _mb_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u
         WHERE u."TenantId" = t."Id" AND u."Role" = 0
         ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id,
       (SELECT b."Id" FROM "Branches" b
         WHERE b."TenantId" = t."Id"
         ORDER BY b."CreatedAt" LIMIT 1) AS branch_id
FROM "Tenants" t
WHERE t."Name" ILIKE '%Moonlit%';

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _mb_ctx;
  IF n = 0 THEN
    RAISE EXCEPTION 'No tenant matching %%Moonlit%% found. List them with: SELECT "Id","Name" FROM "Tenants";';
  ELSIF n > 1 THEN
    RAISE EXCEPTION 'Found % tenants matching %%Moonlit%% - narrow the WHERE clause in step 0.', n;
  END IF;
END $$;

-- ── 0b) Guard: resources have no unique key on Name, so a second run
-- would silently create duplicate rooms. Stop instead.
DO $$
DECLARE existing int;
BEGIN
  SELECT count(*) INTO existing
  FROM "resources" r JOIN _mb_ctx ctx ON r."TenantId" = ctx.tenant_id
  WHERE r."Name" IN ('Sea View Double - Room 1','Sea View Double - Room 2','Sea View Double - Room 3');
  IF existing > 0 THEN
    RAISE EXCEPTION 'Found % existing Moonlit Bay room(s) with these names. This script has already run - delete them first or rename below.', existing;
  END IF;
END $$;

-- ── 1) The 3 rooms ──────────────────────────────────────────────────────
-- Category 'Room' and Status 'Available' are both stored as STRINGS
-- (varchar(20)), not enum ints. 'Available' is what the customer screen
-- filters on - any other status and the room stays hidden.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Status","Description",
   "Capacity","HourlyRate","Specialty","CustomAttributes",
   "CreatedAt","UpdatedAt","CreatedBy")
SELECT gen_random_uuid(), ctx.tenant_id, ctx.branch_id,
       v.name, v.code, 'Room', 'Available',
       'Double room with balcony and private bathroom, breakfast included. About 50 m from Weligama beach.',
       2, 4000.00, 'Sea view',
       ('{"subtype":"Accommodation","capacity":2,"bedCount":1,'
        || '"pricing":{"adult":4000,"currency":"LKR","basis":"per night"},'
        || '"includes":["breakfast","private bathroom","balcony"],'
        || '"languagesSpoken":["English","Sinhala"],'
        || '"rating":9.1,'
        || '"priceConfidence":"ASSUMPTION - midpoint of published LKR 2823-6333"}')::jsonb,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
CROSS JOIN (VALUES
  ('Sea View Double - Room 1', 'MB-R1'),
  ('Sea View Double - Room 2', 'MB-R2'),
  ('Sea View Double - Room 3', 'MB-R3')
) AS v(name, code);

-- NOTE: docs/moonlit-bay-booking-types.txt also proposed a "Package
-- Coordinator" resource (Category=Other) to hang multi-day packages off.
-- It is deliberately NOT created here: the customer screen lists every
-- resource regardless of category, so it would appear to guests as a
-- bookable item under "Select your room". Add it only if/when the package
-- flow actually needs it, and filter it out of that list first.

-- ── 2) Verify before committing ─────────────────────────────────────────
SELECT r."Name", r."Code", r."Category", r."Status", r."Capacity", r."HourlyRate"
FROM "resources" r
JOIN _mb_ctx ctx ON r."TenantId" = ctx.tenant_id
ORDER BY r."Name";
-- Expect the 3 rooms, Category=Room, Status=Available.
-- If it looks wrong, run ROLLBACK; instead of COMMIT;

COMMIT;


-- ============================================================================
-- AFTER RUNNING: hot-restart the Flutter app (press R in the flutter run
-- terminal, or just reload the browser tab). resourcesProvider caches its
-- result, so the rooms will not appear until the provider refetches.
--
-- UNDO:
--   DELETE FROM "resources"
--   WHERE "Code" IN ('MB-R1','MB-R2','MB-R3');
-- Hard delete - if a booking already references a room, set "DeletedAt" =
-- now() instead (there is a global query filter on DeletedAt).
-- ============================================================================
