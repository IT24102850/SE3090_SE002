-- ============================================================================
-- Seed the 8 booking types for the Moonlit Bay (Weligama) tenant.
--
-- Source data and the reasoning behind every price/duration:
--   docs/moonlit-bay-booking-types.txt
--
-- Run once, as-is, in the Supabase SQL editor (or via psql). Everything is
-- inside one transaction - if any guard trips, nothing is committed.
--
-- WHAT THIS DOES NOT DO: it does not create resources (the 3 rooms) or the
-- tenant itself. Booking types are independent of resources in this schema,
-- so they can be seeded first and wired to rooms afterwards.
--
-- BEFORE YOU RUN - two values in here are assumptions, not facts:
--   * room rate LKR 4,000/night  (published range is LKR 2,823-6,333)
--   * cooking class LKR 4,500    (no published Weligama rate exists at all)
--   Both live in ConfigJson and are flagged inline below.
-- ============================================================================


-- ── STEP -1: run this FIRST, on its own, to confirm the tenant name ──────
-- (not part of the transaction; just look at the output)
--
--   SELECT "Id", "Name", "BusinessType", "SubType", "CreatedAt"
--   FROM "Tenants"
--   ORDER BY "CreatedAt" DESC;
--
-- Then adjust the ILIKE pattern in step 0 if the name is not 'Moonlit Bay'.


BEGIN;

-- ── 0) Locate the tenant (and an Admin to attribute the rows to) ─────────
CREATE TEMP TABLE _mb_ctx AS
SELECT t."Id" AS tenant_id,
       (SELECT u."Id" FROM "Users" u
         WHERE u."TenantId" = t."Id" AND u."Role" = 0
         ORDER BY u."CreatedAt" LIMIT 1) AS admin_user_id
FROM "Tenants" t
WHERE t."Name" ILIKE '%Moonlit%';

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _mb_ctx;
  IF n = 0 THEN
    RAISE EXCEPTION 'No tenant matching %%Moonlit%% found. Run the STEP -1 query and fix the WHERE clause in step 0.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION 'Found % tenants matching %%Moonlit%% - narrow the WHERE clause in step 0 to exactly one.', n;
  END IF;
END $$;

-- ── 0b) Guard: "Slug" is UNIQUE across the WHOLE table, not per tenant ───
-- (AppDbContext.cs: entity.HasIndex(bt => bt.Slug).IsUnique() - no tenant in
-- the key). Fail loudly now rather than half-inserting.
DO $$
DECLARE clashes text;
BEGIN
  SELECT string_agg("Slug", ', ') INTO clashes
  FROM "booking_types"
  WHERE "Slug" IN (
    'moonlit-room-night','moonlit-surf-lesson-group','moonlit-surf-lesson-private',
    'moonlit-surfboard-rental','moonlit-whale-watching-mirissa','moonlit-cooking-class',
    'moonlit-airport-transfer','moonlit-multi-day-package');
  IF clashes IS NOT NULL THEN
    RAISE EXCEPTION 'These slugs already exist: %. Either this script already ran, or another tenant took them. Delete those rows or rename the slugs below.', clashes;
  END IF;
END $$;

-- ── 1) The 8 booking types ──────────────────────────────────────────────
INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status",
   "DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit",
   "ConfigJson","CancellationPolicy","CreatedAt","UpdatedAt","CreatedBy")

-- BT1 - the core product. 1440 min = one night. 120 min after = turnover.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Room Night', 'moonlit-room-night',
       'One night in a double room with balcony, private bathroom and breakfast, 50 m from Weligama beach.',
       '#2563EB', 'Active', 1440, false, 2, 0, 120, 'Night',
       '{"checkInTime":"14:00","checkOutTime":"11:00","breakfastIncluded":true,"basePricePerNight":{"amount":4000,"currency":"LKR"},"priceConfidence":"ASSUMPTION - midpoint of published LKR 2823-6333"}'::jsonb,
       '{"freeCancellationHours":48,"refundPercent":100,"lateCancellationRefundPercent":0}'::jsonb,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT2 - group surf lesson. LKR 3,000 is a real Weligama market rate.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Beginner Surf Lesson', 'moonlit-surf-lesson-group',
       'Two-hour beginner group lesson on the Weligama beach break. Board, rash vest and instructor included. Suitable for absolute first-timers.',
       '#0EA5E9', 'Active', 120, false, 4, 0, 30, 'Slot',
       '{"pricing":{"adult":3000,"currency":"LKR"},"weatherDependent":true,"skillLevel":"Beginner","includes":["soft-top board","rash vest","instructor"],"season":{"note":"Weligama beach break works year-round"}}'::jsonb,
       NULL,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT3 - private lesson, LKR 6,000 (market range 5,000-7,000 incl. board).
SELECT gen_random_uuid(), ctx.tenant_id,
       'Private Surf Lesson', 'moonlit-surf-lesson-private',
       '90-minute one-to-one lesson with board hire included. Faster progress than the group session.',
       '#0284C7', 'Active', 90, false, 1, 0, 15, 'Slot',
       '{"pricing":{"adult":6000,"currency":"LKR"},"weatherDependent":true,"skillLevel":"Any"}'::jsonb,
       NULL,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT4 - DateRange, not Slot: a rental spans days, it is not a time slot.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Surfboard Rental', 'moonlit-surfboard-rental',
       'Soft-top 8-9 ft foam board hired by the day. Self-guided, no instructor.',
       '#38BDF8', 'Active', 1440, false, 1, 0, 15, 'DateRange',
       '{"pricing":{"perDay":1000,"perHour":800,"currency":"LKR"},"boardType":"soft-top 8-9ft"}'::jsonb,
       NULL,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT5 - 300 min is the REAL door-to-door duration (template s.4: never
-- leave this at the 60 default or SlotCalculator chops it into bad slots).
-- 60 min before = pre-dawn transfer to Mirissa harbour.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Mirissa Whale Watching Excursion', 'moonlit-whale-watching-mirissa',
       'Early-morning blue whale and dolphin cruise from Mirissa harbour. Includes breakfast pack, water, life jacket, government tax and harbour fees.',
       '#1D4ED8', 'Active', 300, true, 6, 60, 0, 'Slot',
       '{"pricing":{"adult":16000,"child":10000,"currency":"LKR"},"childAgeRange":"4-10","departureTime":"06:00","pointsOfDeparture":["Mirissa Harbour"],"weatherDependent":true,"season":{"months":["Nov","Dec","Jan","Feb","Mar","Apr"],"note":"peak Dec-Apr; sightings drop sharply off-season"},"includes":["breakfast pack","water","life jacket","government tax"],"pricingNote":"foreign-tourist rate; local rate is typically much lower"}'::jsonb,
       '{"freeCancellationHours":24,"refundPercent":100,"lateCancellationRefundPercent":0,"note":"weather cancellation by the operator is always fully refunded"}'::jsonb,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT6 - WARNING: 4500 is a placeholder. No published Weligama cooking class
-- price was found anywhere. Replace before this is customer-visible.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Sri Lankan Cooking Class', 'moonlit-cooking-class',
       'Hands-on evening class cooking rice and curry with the family, eaten together afterwards.',
       '#F59E0B', 'Active', 180, false, 6, 0, 0, 'Slot',
       '{"pricing":{"adult":4500,"currency":"LKR"},"priceConfidence":"UNVERIFIED PLACEHOLDER - no published Weligama rate found","startTime":"17:00"}'::jsonb,
       NULL,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT7 - priced per vehicle, not per person. Market 17,000-20,000.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Airport Transfer', 'moonlit-airport-transfer',
       'Private air-conditioned car between Bandaranaike International (CMB) and the guesthouse. About a 3-hour drive each way.',
       '#64748B', 'Active', 180, true, 3, 0, 0, 'Slot',
       '{"pricing":{"perVehicle":18000,"currency":"LKR"},"pricingBasis":"per vehicle, not per person","direction":["arrival","departure"],"note":"market range LKR 17000-20000"}'::jsonb,
       '{"freeCancellationHours":24,"refundPercent":100,"lateCancellationRefundPercent":50}'::jsonb,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx
UNION ALL

-- BT8 - umbrella type for the 5 packages. 4320 = 3 nights (the shortest);
-- override per booking. RequiresApproval because operators are pre-paid.
SELECT gen_random_uuid(), ctx.tenant_id,
       'Multi-Day Package', 'moonlit-multi-day-package',
       'Bundled stay plus activities, booked as one reservation and confirmed by the host.',
       '#7C3AED', 'Active', 4320, true, 6, 0, 0, 'Package',
       '{"packages":[{"code":"PKG-1","name":"Surf and Stay","nights":3,"price":21000,"currency":"LKR","components":["3 room nights","3 group surf lessons","2 days board rental"]},{"code":"PKG-2","name":"Weligama Surf Camp","nights":5,"price":35000,"currency":"LKR","components":["5 room nights","5 group surf lessons","5 days board rental"]},{"code":"PKG-3","name":"Whale and Wave","nights":2,"price":25500,"currency":"LKR","seasonal":"Nov-Apr only","components":["2 room nights","1 whale watching","1 group surf lesson"]},{"code":"PKG-4","name":"South Coast Explorer","nights":7,"price":85000,"currency":"LKR","components":["7 room nights","2 airport transfers","1 whale watching","3 group surf lessons","1 cooking class"],"variant":{"name":"without transfers","price":52000}},{"code":"PKG-5","name":"Slow Mornings","nights":3,"price":30000,"currency":"LKR","pricingBasis":"for two people together","components":["3 room nights","2 private surf lessons","2 cooking classes"]}]}'::jsonb,
       '{"freeCancellationHours":168,"refundPercent":100,"lateCancellationRefundPercent":50,"note":"7-day cutoff - activity operators are pre-paid"}'::jsonb,
       now(), now(), ctx.admin_user_id
FROM _mb_ctx ctx;

-- ── 2) Verify before committing ─────────────────────────────────────────
SELECT bt."Name", bt."Slug", bt."BookingUnit", bt."DefaultDurationMinutes",
       bt."RequiresApproval", bt."MaxParticipants", bt."Status"
FROM "booking_types" bt
JOIN _mb_ctx ctx ON bt."TenantId" = ctx.tenant_id
ORDER BY bt."Name";
-- Expect exactly 8 rows. If it looks wrong, run ROLLBACK; instead of COMMIT;

COMMIT;


-- ============================================================================
-- UNDO (only if you need to back this out)
--
--   DELETE FROM "booking_types"
--   WHERE "Slug" IN (
--     'moonlit-room-night','moonlit-surf-lesson-group','moonlit-surf-lesson-private',
--     'moonlit-surfboard-rental','moonlit-whale-watching-mirissa','moonlit-cooking-class',
--     'moonlit-airport-transfer','moonlit-multi-day-package');
--
-- Note this is a HARD delete. The app soft-deletes via "DeletedAt" (there is
-- a global query filter on it), so if any booking already references one of
-- these rows, set "DeletedAt" = now() instead of deleting.
-- ============================================================================
