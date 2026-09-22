-- ============================================================================
-- Seed the Mirissa Jetliner product catalogue: departure vessels (Resources)
-- and the tour / package / add-on catalogue (BookingTypes).
--
-- Run once, as-is, in the Supabase SQL editor or via psql. Everything is in
-- one transaction: if anything fails, nothing is committed. Re-running is
-- safe - every INSERT is guarded by a NOT EXISTS on its unique Slug/Code.
--
--   psql "$DATABASE_URL" -f scripts/seed-mirissa-jetliner-packages.sql
--
-- ── WHY PACKAGES ARE booking_types, NOT resources ───────────────────────────
-- A `Resource` is the physical bookable thing - the boat. A `BookingType` is
-- the product sold against it, and it is what carries pricing (ConfigJson
-- pricing.adult / pricing.child) and the `category` key the admin dashboard
-- splits Packages & Tours from Services & Add-ons on.
--
-- Putting a package in `resources` would: list it under "Vessels & Crew" as
-- though it were a boat, offer it in the Schedule-Departures picker as
-- something departures can be created against (it filters Category='Vehicle'),
-- keep it OUT of the Packages & Tours section entirely (that section reads
-- booking_types), and leave its adult/child prices invisible to the ticket
-- pricing engine. So the two vessels below are Resources and everything
-- sellable is a BookingType. See docs/tourism-business-template.md §2 and §4.
--
-- ── PROVENANCE ──────────────────────────────────────────────────────────────
-- This is a REAL, identifiable operator, so per docs/tourism-business-template.md
-- §3 every value below is tagged. Sourced 2026-09-10 from:
--   - https://www.mirissajetliner.com/book-now.html   (prices, inclusions, slots)
--   - https://www.mirissajetliner.com/                (Our Activities, free 3km
--                                                      transfer, capacity)
--
-- SOURCED    -> taken verbatim from a page above.
-- ASSUMPTION -> NOT published by this operator.
--
-- IMPORTANT: the operator publishes SIX activities (Our Activities section) -
-- every name, emoji and description below is verbatim from the site. But only
-- ONE of them carries a published price: the whale watching tour, at LKR 7,500
-- adult / LKR 4,000 child. The other five show a "Book Now" button and no rate
-- card, so their prices are tagged ASSUMPTION and must be replaced with the
-- operator's real numbers before going live. Find them with:
--   SELECT "Name", "ConfigJson"->>'priceConfidence' FROM "booking_types"
--   WHERE "ConfigJson"->>'priceConfidence' LIKE 'ASSUMPTION%';
--
-- AverageRating / ReviewCount are deliberately left untouched: no rating was
-- sourced, and the template doc forbids inventing one for a real business.
-- ============================================================================

BEGIN;

-- ── Pin the tenant ──────────────────────────────────────────────────────────
-- Pinned by explicit id, NOT by admin email: this database carries two
-- tenants sharing wowwhales@gmail.com -
--   f15bae97-fa7e-42f5-95b7-b624db319ad2  "Mirissa JetLiner"  (created 2026-08-14)
--   d303c4ef-6eb9-4189-95e0-b537d2134ba9  "Mirissa Jetliner"  (created 2026-09-09)
-- and login resolves whichever user row matches first, so an email-based pin
-- would seed a coin toss.
--
-- List them yourself with:
--   SELECT t."Id", t."Name", t."SubType", t."CreatedAt"::date, u."Email"
--   FROM "Tenants" t JOIN "Users" u ON u."TenantId" = t."Id" AND u."Role" = 0
--   WHERE t."Name" ILIKE '%mirissa%' ORDER BY t."CreatedAt";
--
-- CHANGE THIS to the tenant you want to seed.
DROP TABLE IF EXISTS _seed_ctx;
CREATE TEMP TABLE _seed_ctx AS
SELECT 'f15bae97-fa7e-42f5-95b7-b624db319ad2'::uuid AS tenant_id;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM "Tenants" t JOIN _seed_ctx ctx ON t."Id" = ctx.tenant_id;
  IF n <> 1 THEN
    RAISE EXCEPTION
      'The tenant id in _seed_ctx matches % rows in "Tenants". Set it to a real tenant id - see the listing query above.', n;
  END IF;
END $$;

-- Pin the branch too; resources hang off one.
DROP TABLE IF EXISTS _seed_branch;
CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b, _seed_ctx ctx
WHERE b."TenantId" = ctx.tenant_id
ORDER BY b."CreatedAt"
LIMIT 1;

-- ── Make sure the sub-type selects the whale dashboard ──────────────────────
-- Without this exact string the tenant renders the generic calendar dashboard.
UPDATE "Tenants" t
SET "SubType" = 'Whale / dolphin watching',
    "UpdatedAt" = now()
FROM _seed_ctx ctx
WHERE t."Id" = ctx.tenant_id
  AND (t."SubType" IS DISTINCT FROM 'Whale / dolphin watching');

-- ── Resources: the two daily departure slots ────────────────────────────────
-- SOURCED: both departure times are published on book-now.html. One Resource
-- per departure slot is the documented archetype-A pattern (template §2), so
-- each slot can carry its own ResourceSchedule window.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","HourlyRate","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, 'Vehicle', 'Whale and Dolphin Watching', 'Available',
       120, v.description, 7500,
       jsonb_build_object(
         'subtype',  'WildlifeExcursion',
         'capacity', 120,                       -- SOURCED: operator listings state max 120 pax
                                                --          (not restated on the book-now page)
         'departureTime', v.departure_time,     -- SOURCED: book-now.html
         'pricing', jsonb_build_object('adult', 7500, 'child', 4000, 'currency', 'LKR'),
         'includes', jsonb_build_array(         -- SOURCED: verbatim from book-now.html
            'Breakfast & refreshments','Life jacket & insurance','Free Wi-Fi & music'
         ),
         'pickup', jsonb_build_object(          -- SOURCED: free transfer within 3km
            'available', true, 'radiusKm', 3, 'free', true,
            'pointsOfDeparture', jsonb_build_array('Mirissa Harbour')
         ),
         'season', jsonb_build_object(
            'months', jsonb_build_array('Nov','Dec','Jan','Feb','Mar','Apr'),
            'weatherDependent', true
         ),
         'confidence', 'SOURCED - departure times, prices and inclusions published; capacity from operator listings'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br,
     (VALUES
        ('Whale Watching Boat - Dawn Departure',  'MJL-DEP-0630', '06:30',
         'Upper-deck vessel departing Mirissa Harbour at 06:30. Certified crew, international whale-watching approach guidelines.'),
        ('Whale Watching Boat - Morning Cruise',  'MJL-DEP-1000', '10:00',
         'Second daily sailing from Mirissa Harbour at 10:00. Same vessel class and inclusions as the dawn departure.')
     ) AS v(name, code, departure_time, description)
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = v.code);

-- ── Retire the invented demo bundles from this script's first revision ──────
-- Those two bundles and the standalone photo/gear add-ons were placeholders
-- written before the operator's real Activities list was known. Soft-deleted
-- rather than hard-deleted so any booking already pointing at one survives.
UPDATE "booking_types" bt
SET "DeletedAt" = now(), "Status" = 'Archived', "UpdatedAt" = now()
FROM _seed_ctx ctx
WHERE bt."TenantId" = ctx.tenant_id
  AND bt."DeletedAt" IS NULL
  AND bt."Slug" IN ('mjl-tour-lunch-transfer','mjl-private-charter-upper-deck',
                    'mjl-photo-package','mjl-snorkel-gear-rental',
                    -- superseded by 'mjl-whale-watching', named for the site's
                    -- own Activities entry rather than the booking-page heading
                    'mjl-whale-watching-tour');

-- ── BookingTypes: the sellable catalogue ────────────────────────────────────
-- `category` (tour | package | addon) is what the admin dashboard splits
-- Packages & Tours from Services & Add-ons on. Absent = treated as 'tour'.
INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status",
   "DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit",
   "ConfigJson","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id,
       v.name, v.slug, v.description, v.color, 'Active',
       v.duration_minutes, v.requires_approval, v.max_participants,
       0, 30, v.booking_unit,
       jsonb_build_object(
         'subType',     'whaleWatching',
         'category',    v.category,
         'bookingUnit', v.booking_unit,
         'capacity',    v.max_participants,
         'pricing', jsonb_build_object(
            'adult',    v.adult_lkr,
            -- child 0 means this activity has no child rate at all (scuba is
            -- adult-only here), so the key is omitted rather than stored as a
            -- misleading zero - the template's null-not-zero rule.
            'child',    CASE WHEN v.child_lkr > 0 THEN to_jsonb(v.child_lkr) ELSE 'null'::jsonb END,
            'infant',   0,
            'currency', 'LKR'
         ),
         'priceConfidence', v.price_confidence,
         'includes',        v.includes,
         'icon',            v.icon,          -- SOURCED: the site's own activity emoji
         'agePolicy', jsonb_build_object(       -- SOURCED: book-now.html
            'adultFromAge', 12, 'childUnderAge', 12
         ),
         'maxPerBooking', jsonb_build_object(   -- SOURCED: the form caps each at 5
            'adult', 5, 'child', 5
         ),
         'season', jsonb_build_object(
            'months', jsonb_build_array('Nov','Dec','Jan','Feb','Mar','Apr'),
            'weatherDependent', true
         )
       ),
       now(), now()
FROM _seed_ctx ctx,
     (VALUES
        -- ── The six published activities ────────────────────────────────────
        -- Names, emoji and descriptions are verbatim from the Our Activities
        -- section. Only the first has a published price.
        ('Whale Watching',
         'mjl-whale-watching',
         'Daily dawn departures to spot blue whales, sperm whales, and dolphins. Upper-deck seating, expert crew, all-inclusive.',
         '#0891B2', 240, false, 120, 'Slot', 'tour', 7500, 4000, '🐋',
         'SOURCED - LKR 7,500 adult / LKR 4,000 child published on book-now.html',
         jsonb_build_array('Breakfast & refreshments','Life jacket & insurance','Free Wi-Fi & music')),

        ('Snorkeling',
         'mjl-snorkeling',
         'Explore vibrant coral reefs and swim alongside tropical fish in protected areas. Guided small-group tours with all gear included.',
         '#06B6D4', 180, false, 20, 'Slot', 'tour', 6000, 3500, '🤿',
         'ASSUMPTION - no price published for this activity; replace before going live',
         jsonb_build_array('All snorkel gear','Guided small group','Protected reef areas')),

        ('Scuba Diving',
         'mjl-scuba-diving',
         'Certified dive operators for beginners and experienced divers. Full equipment rental and guided dives available.',
         '#3B82F6', 240, false, 12, 'Slot', 'tour', 12000, 0, '🐠',
         'ASSUMPTION - no price published for this activity; replace before going live',
         jsonb_build_array('Full equipment rental','Certified dive operator','Guided dive')),

        ('Deep Sea Fishing',
         'mjl-deep-sea-fishing',
         'Half-day and full-day fishing charters with experienced crew, modern tackle, and expert fish handling.',
         '#F59E0B', 300, true, 10, 'Slot', 'tour', 18000, 9000, '🎣',
         'ASSUMPTION - no price published for this activity; replace before going live',
         jsonb_build_array('Experienced crew','Modern tackle','Expert fish handling')),

        ('Coastal Boat Tours',
         'mjl-coastal-boat-tours',
         'Leisurely cruises for birdwatching, sunset views, and family outings. Comfortable seating with refreshments on board.',
         '#8B5CF6', 150, false, 120, 'Slot', 'tour', 5000, 2500, '⛵',
         'ASSUMPTION - no price published for this activity; replace before going live',
         jsonb_build_array('Comfortable seating','Refreshments on board','Birdwatching & sunset views')),

        ('Photo Tours',
         'mjl-photo-tours',
         'Specialized photography excursions with expert guidance to capture the perfect shot of marine life and coastal landscapes.',
         '#EC4899', 240, false, 15, 'Slot', 'tour', 9500, 5000, '📸',
         'ASSUMPTION - no price published for this activity; replace before going live',
         jsonb_build_array('Expert photography guidance','Marine life & coastal landscapes')),

        -- ── The one published add-on, and it is free ─────────────────────────
        ('Hotel Pickup & Drop-off (within 3 km)',
         'mjl-hotel-pickup-3km',
         'Complimentary return transfer to Mirissa Harbour for guests staying within 3 km.',
         '#10B981', 45, false, 12, 'Slot', 'addon', 0, 0, '🚐',
         'SOURCED - operator states free transport within 3 km when you book',
         jsonb_build_array('Return transfer','Within 3 km of Mirissa Harbour'))
     ) AS v(name, slug, description, color, duration_minutes, requires_approval,
            max_participants, booking_unit, category, adult_lkr, child_lkr, icon,
            price_confidence, includes)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."Slug" = v.slug);

-- ── Backfill config keys onto rows an earlier run already created ───────────
-- The INSERT above is guarded by NOT EXISTS on Slug, so a row that already
-- exists keeps whatever ConfigJson it was created with. This tops up the keys
-- added after that row was first written, without touching its pricing.
UPDATE "booking_types" bt
SET "ConfigJson" = bt."ConfigJson" || jsonb_build_object('icon', v.icon),
    "UpdatedAt" = now()
FROM _seed_ctx ctx,
     (VALUES ('mjl-hotel-pickup-3km', '🚐')) AS v(slug, icon)
WHERE bt."TenantId" = ctx.tenant_id
  AND bt."Slug" = v.slug
  AND bt."DeletedAt" IS NULL
  AND bt."ConfigJson"->>'icon' IS NULL;

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT t."Name"    FROM "Tenants" t   JOIN _seed_ctx c ON t."Id" = c.tenant_id)      AS tenant,
  (SELECT t."SubType" FROM "Tenants" t   JOIN _seed_ctx c ON t."Id" = c.tenant_id)      AS sub_type,
  (SELECT count(*) FROM "resources" r     JOIN _seed_ctx c ON r."TenantId" = c.tenant_id
     WHERE r."DeletedAt" IS NULL)                                                          AS resources,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx c ON bt."TenantId" = c.tenant_id
     WHERE bt."DeletedAt" IS NULL AND coalesce(bt."ConfigJson"->>'category','tour') <> 'addon') AS tours_and_packages,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx c ON bt."TenantId" = c.tenant_id
     WHERE bt."DeletedAt" IS NULL AND bt."ConfigJson"->>'category' =  'addon')            AS addons;

-- What the dashboard will show, split the way it splits it:
--   SELECT "ConfigJson"->>'category' AS category, "Name",
--          "ConfigJson"->'pricing'->>'adult' AS adult_lkr,
--          "ConfigJson"->>'priceConfidence'  AS confidence
--   FROM "booking_types"
--   WHERE "TenantId" = (SELECT tenant_id FROM _seed_ctx) AND "DeletedAt" IS NULL
--   ORDER BY category, "Name";
--
-- Everything still needing the operator's real numbers:
--   SELECT "Name", "ConfigJson"->>'priceConfidence'
--   FROM "booking_types"
--   WHERE "ConfigJson"->>'priceConfidence' LIKE 'ASSUMPTION%' ORDER BY "Name";
