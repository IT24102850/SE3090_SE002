-- ============================================================================
-- Seed "Weligama Bay Dive Center" business data against the tenant owned by
--   chaminda1990@gmail.com
--
-- Populates the Business Profile (contact, hours, socials, amenities), the
-- branch, the bookable Resources (dive boats / instructors / rental gear) and
-- the full course + dive catalogue as BookingTypes, so every tourism-subtype
-- screen (diving dashboard, business detail, booking flow) has real data.
--
-- Run once, as-is, in the Supabase SQL editor or via psql. Everything is in
-- one transaction: if anything fails, nothing is committed. Re-running is
-- safe - every INSERT is guarded by a NOT EXISTS on its unique Slug/Code, and
-- the profile UPDATE is idempotent.
--
--   psql "$DATABASE_URL" -f scripts/seed-weligama-bay-dive-center.sql
--
-- ── PROVENANCE ──────────────────────────────────────────────────────────────
-- This is a REAL, identifiable operator, so per docs/tourism-business-template.md
-- §3 ("don't fabricate a plausible-looking rating for a real business") every
-- value below is tagged. Sourced 2026-09-09 from:
--   - https://www.scubadivingweligama.com/           (contact, address, socials)
--   - https://www.scubadivingweligama.com/courses/   (the 13-course catalogue)
--   - https://www.scubadivingweligama.com/dive-sites/(5 dive sites + depths)
--   - https://www.padi.com/dive-center/sri-lanka/weligama-bay-diving-centre/
--                                                    (PADI 5 Star, languages)
--   - https://theabroadguide.com/weligama-discover-scuba-diving-in-sri-lanka/
--                                                    (the ONE published price)
--
-- SOURCED   -> taken verbatim from a page above.
-- ASSUMPTION-> NOT published by this operator. Typical Sri Lankan PADI-centre
--              rates, filled in so the booking flow has numbers to work with.
--              Every one is tagged "priceConfidence" in ConfigJson - replace
--              them with the operator's real rate card before going live.
--
-- Only ONE price is actually published anywhere: Discover Scuba Diving at
-- USD 70. Everything else is an ASSUMPTION. LKR figures use a stated
-- USD 1 = LKR 300 conversion, itself an assumption.
--
-- AverageRating / ReviewCount are deliberately left untouched (NULL): no
-- rating was sourced, and the template doc forbids inventing one.
-- ============================================================================

BEGIN;

-- ── 0) Locate the tenant by its owner's email ───────────────────────────────
-- Dropped first so the script can be re-run in the same psql/editor session -
-- temp tables outlive the transaction, and CREATE would otherwise error with
-- "relation _seed_ctx already exists" on the second run.
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;

-- One email can legitimately map to SEVERAL tenants here: "Users" has no
-- unique index on "Email" (only Id/BranchId/TenantId are indexed), and the
-- tenant-onboarding path in TenantService.cs creates its admin WITHOUT the
-- duplicate check that AuthController.Register does. wowwhales@gmail.com is
-- already duplicated across two tenants for exactly this reason.
--
-- So this does NOT silently pick one with LIMIT 1 - seeding an arbitrary
-- tenant would be worse than failing. If the email is ambiguous the script
-- aborts and you pin the tenant by hand below.
CREATE TEMP TABLE _seed_ctx AS
SELECT u."Id" AS admin_user_id, u."TenantId" AS tenant_id
FROM "Users" u
WHERE lower(u."Email") = 'chaminda1990@gmail.com';

-- ► To pin a specific tenant instead of looking it up, comment out the
--   CREATE above and use this, with the real UUIDs:
-- CREATE TEMP TABLE _seed_ctx AS
-- SELECT '00000000-0000-0000-0000-000000000000'::uuid AS admin_user_id,
--        '00000000-0000-0000-0000-000000000000'::uuid AS tenant_id;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM _seed_ctx;

  IF n = 0 THEN
    RAISE EXCEPTION
      'No user with email chaminda1990@gmail.com. Register that account first, or uncomment step 0b to create the tenant + admin outright.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION
      'Email chaminda1990@gmail.com maps to % users across different tenants. Refusing to guess which business to seed - pin the tenant explicitly using the commented CREATE above. To see them: SELECT "Id","FullName","TenantId" FROM "Users" WHERE lower("Email") = ''chaminda1990@gmail.com'';', n;
  END IF;
END $$;

-- ── 0b) OPTIONAL: create the tenant + admin if the account does not exist ───
-- Uncomment this whole block AND delete the RAISE EXCEPTION above to bootstrap
-- from nothing. Password for the created admin is  Passw0rd!  - the hash is a
-- real BCrypt.Net-compatible $2b$11 hash, already verified against
-- BCrypt.Net.Verify() (same hash used by seed-vihanga-bike-rental.sql).
--
-- WITH t AS (
--   INSERT INTO "Tenants"
--     ("Id","CreatedAt","UpdatedAt","Name","BusinessType","SubType","IsActive",
--      "CancellationCutoffHours","RescheduleCutoffHours","ReviewCount")
--   VALUES (gen_random_uuid(), now(), now(), 'Weligama Bay Dive Center',
--           'Tourism', 'Water sports / diving', true, 24, 24, 0)
--   RETURNING "Id"
-- )
-- INSERT INTO "Users"
--   ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName",
--    "Phone","Role","IsActive")
-- SELECT gen_random_uuid(), now(), now(), t."Id", 'chaminda1990@gmail.com',
--        '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
--        'Chaminda Kumara', '+94777367447', 0, true
-- FROM t;

-- ── 1) Business Profile ─────────────────────────────────────────────────────
-- Name/type/subtype: SubType must be the exact label the mobile dropdown and
-- TourismSubTypeParsing.fromTenantSubType expect, or the diving dashboard
-- silently falls back to the generic one.
--
-- BusinessHours is stored PascalCase on purpose: TenantProfileController
-- writes it with a bare JsonSerializer.Serialize (General defaults), and
-- ParseBusinessHours reads it back case-SENSITIVELY. camelCase here would
-- round-trip as an empty list.
UPDATE "Tenants" t SET
  "Name"         = 'Weligama Bay Dive Center',
  "BusinessType" = 'Tourism',
  "SubType"      = 'Water sports / diving',
  "IsActive"     = true,

  -- SOURCED: established 2013, PADI 5 Star, dual-season operation.
  "Description" = 'Weligama Bay Dive Center is a PADI 5 Star Dive Resort on Sri Lanka''s south coast, established in 2013 by IDC Staff Instructor Thaminda K. Kumara. The team runs the full PADI ladder - from Discover Scuba Diving for first-timers through to the Divemaster program - with instruction available in English, German, Chinese, French and Italian. Every course includes a qualified PADI instructor, equipment, logbook, snacks and transport. The centre follows the seasons: Weligama from October to April, Trincomalee from May to October.',
  "ShortTagline" = 'PADI 5 Star Dive Resort - Weligama Bay',

  -- SOURCED: identical phone/email/address on the operator's site and PADI.
  "ContactPhone" = '+94777367447',
  "ContactEmail" = 'chamindakh@sltnet.lk',
  "Website"      = 'https://www.scubadivingweligama.com/',

  -- SOURCED. Lowercase keys match the existing seed scripts and the mobile
  -- profile header's lookup.
  "SocialLinks" = jsonb_build_object(
      'facebook',  'https://www.facebook.com/ScubaDivingWeligama/',
      'instagram', 'https://www.instagram.com/weligama_bay_dive_center/',
      'whatsapp',  'https://wa.me/94777367447'
  ),

  -- ASSUMPTION: opening hours are not published anywhere. These mirror a
  -- normal south-coast dive day (first boat out early, last in mid-afternoon).
  "BusinessHours" = (
      SELECT jsonb_agg(jsonb_build_object(
               'DayOfWeek', d, 'OpenTime', '07:00', 'CloseTime', '17:00', 'IsClosed', false
             ) ORDER BY ord)
      FROM (VALUES
        ('Sunday',1),('Monday',2),('Tuesday',3),('Wednesday',4),
        ('Thursday',5),('Friday',6),('Saturday',7)
      ) AS x(d, ord)
  ),

  -- SOURCED: "All courses include qualified PADI Instructor, equipment free of
  -- charges, logbook, Snaks and transportation" + PADI's languages list.
  "Amenities" = jsonb_build_array(
      'PADI 5 Star Dive Resort',
      'Equipment Included',
      'Beginner Friendly',
      'Multilingual Instructors (EN/DE/ZH/FR/IT)',
      'Transport Included',
      'Logbook Provided',
      'Snacks Included'
  ),

  "ProfileUpdatedAt" = now(),
  "UpdatedAt"        = now()
  -- "AverageRating"/"ReviewCount" intentionally NOT set - no sourced number.
FROM _seed_ctx ctx
WHERE t."Id" = ctx.tenant_id;

-- ── 2) Branch ───────────────────────────────────────────────────────────────
-- SOURCED address: "No 126 Kapparatota, Weligama, Sri Lanka" (PADI listing).
INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id,
       'Weligama Bay (Kapparatota)',
       'No. 126 Kapparatota, Weligama, Southern Province, Sri Lanka',
       '+94777367447', true
FROM _seed_ctx ctx
WHERE NOT EXISTS (
  SELECT 1 FROM "Branches" b
  WHERE b."TenantId" = ctx.tenant_id AND b."Name" = 'Weligama Bay (Kapparatota)'
);

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Name" = 'Weligama Bay (Kapparatota)'
LIMIT 1;

-- Every resource INSERT below cross-joins _seed_branch. If it were empty they
-- would all quietly insert zero rows, so fail loudly instead.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _seed_branch) THEN
    RAISE EXCEPTION 'Branch "Weligama Bay (Kapparatota)" was neither found nor created - aborting before the resource inserts silently no-op.';
  END IF;
END $$;

-- ── 3) Resources ────────────────────────────────────────────────────────────
-- Category/Status are the string forms of ResourceCategory/ResourceStatus
-- (both are .HasConversion<string>() in AppDbContext).
--
-- HourlyRate is left NULL on purpose. The mobile booking flow multiplies it by
-- the slot length (booking_flow_screen.dart) and business_detail_screen renders
-- it as "LKR x/hr" - neither is how a dive trip or a PADI course is actually
-- priced. Real per-trip / per-course prices live on the BookingTypes in step 4
-- and in CustomAttributes.pricing, per docs/tourism-business-template.md §3.
--
-- CustomAttributes keys: 'capacity' and 'depth' are what the diving dashboard's
-- cardFields render (registry/tourism_dashboard_registry.dart); the rest is the
-- template doc's superset schema, consumed by the Domain Analysis Agent.

-- 3a) Dive boats. The 5 dive sites, their depths and boating times are SOURCED
--     from the operator's dive-sites page. Boat names/capacities are NOT
--     published - generic labels, flagged below.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       'Dive Boat 1', 'WBDC-BOAT-01', 'Vehicle', 'Diving', 'Available', 8,
       'Primary dive boat for reef and deep-site trips out of Kapparatota, Weligama Bay.',
       jsonb_build_object(
         'subtype',   'WatersportsLesson',
         'capacity',  8,                    -- ASSUMPTION: not published
         'depth',     32,                   -- SOURCED: Dispa Rock, deepest site
         'nameConfidence', 'ASSUMPTION - operator does not publish boat names or capacities',
         'languagesSpoken', jsonb_build_array('English','Sinhala','German','Chinese','French','Italian'),
         'season', jsonb_build_object(
            'months', jsonb_build_array('Oct','Nov','Dec','Jan','Feb','Mar','Apr'),
            'weatherDependent', true,
            'note', 'SOURCED - Weligama Oct-Apr; the operator moves to Trincomalee May-Oct'
         ),
         'diveSites', jsonb_build_array(
            jsonb_build_object('name','Dispa Rock',   'depthM',32,'boatingMinutes',30,'difficulty','Advanced'),
            jsonb_build_object('name','Yala Rock',    'depthM',24,'boatingMinutes',20,'difficulty','Intermediate to Advanced'),
            jsonb_build_object('name','Patch Point',  'depthM',20,'boatingMinutes',30,'difficulty','Intermediate'),
            jsonb_build_object('name','Noisy Rock',   'depthM',20,'boatingMinutes',20,'difficulty','Intermediate'),
            jsonb_build_object('name','Mirissa Point','depthM',12,'boatingMinutes',15,'difficulty','Beginner')
         )
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = 'WBDC-BOAT-01');

INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       'Dive Boat 2', 'WBDC-BOAT-02', 'Vehicle', 'Diving', 'Available', 6,
       'Second boat, used for training dives and small groups at the shallower sites.',
       jsonb_build_object(
         'subtype',  'WatersportsLesson',
         'capacity', 6,                     -- ASSUMPTION: not published
         'depth',    20,                    -- SOURCED: Patch Point / Noisy Rock
         'nameConfidence', 'ASSUMPTION - operator does not publish boat names or capacities',
         'diveSites', jsonb_build_array(
            jsonb_build_object('name','Mirissa Point','depthM',12,'boatingMinutes',15,'difficulty','Beginner'),
            jsonb_build_object('name','Noisy Rock',   'depthM',20,'boatingMinutes',20,'difficulty','Intermediate')
         )
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = 'WBDC-BOAT-02');

-- 3b) Instructors. Only the founder is named - that is SOURCED. The other two
--     are unnamed capacity slots, because the rest of the team is not public.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       'Thaminda K. Kumara - IDC Staff Instructor', 'WBDC-INS-01', 'Staff',
       'PADI IDC Staff Instructor', 'Available', 4,
       'Founder of the centre (2013). PADI IDC Staff Instructor since 2014, around 20 years in the dive industry.',
       jsonb_build_object(
         'subtype', 'WatersportsLesson',
         'capacity', 4,
         'certification', 'PADI IDC Staff Instructor',
         'languagesSpoken', jsonb_build_array('English','Sinhala'),
         'confidence', 'SOURCED - name, role and 2013 founding date are published'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = 'WBDC-INS-01');

INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, 'Staff', 'PADI Instructor', 'Available', 4,
       'PADI instructor slot. Rename to the real instructor once staffing is known.',
       jsonb_build_object(
         'subtype','WatersportsLesson','capacity',4,
         'certification','PADI Open Water Scuba Instructor',
         'confidence','ASSUMPTION - placeholder slot; team roster is not public'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br,
     (VALUES ('PADI Instructor 2','WBDC-INS-02'),
             ('PADI Instructor 3','WBDC-INS-03')) AS v(name, code)
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = v.code);

-- 3c) Rental gear pool. SOURCED: equipment is included free with courses, so
--     this exists for standalone hire only.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       'Scuba Equipment Set (BCD, regulator, wetsuit)', 'WBDC-GEAR-01',
       'Equipment', 'Diving', 'Available', 12,
       'Pooled scuba sets. Included free with every course and dive - charged only for standalone hire.',
       jsonb_build_object(
         'subtype','EquipmentRental','capacity',12,
         'includes', jsonb_build_array('BCD','Regulator','Wetsuit','Mask','Fins','Tank','Weights'),
         'confidence','SOURCED - "equipment free of charges" is stated for all courses'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br
WHERE NOT EXISTS (SELECT 1 FROM "resources" r WHERE r."Code" = 'WBDC-GEAR-01');

-- ── 4) BookingTypes: the course + dive catalogue ────────────────────────────
-- The 13 names below are SOURCED verbatim from the operator's courses page.
-- Prices are NOT: only Discover Scuba Diving (USD 70) is published anywhere.
-- Each row carries its own "priceConfidence" so nothing here can be mistaken
-- for the operator's real rate card.
--
-- BookingUnit: 'Slot' for anything that finishes in one session, 'Package' for
-- the multi-day certifications (docs/tourism-business-template.md §4).
-- RequiresApproval: true for the multi-day / high-value programs.
-- Slug is globally UNIQUE across all tenants, hence the wbdc- prefix.
INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status",
   "DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit",
   "ConfigJson","CancellationPolicy","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id,
       v.name, v.slug, v.description, v.color, 'Active',
       v.duration_minutes, v.requires_approval, v.max_participants,
       0, 30, v.booking_unit,
       jsonb_build_object(
         'subType', 'diving',
         'weatherDependent', true,
         'basePrice', jsonb_build_object('amount', v.price_lkr, 'currency', 'LKR'),
         'priceConfidence', v.price_confidence,
         'includes', jsonb_build_array(
            'Qualified PADI instructor','Equipment','Logbook','Snacks','Transportation'
         ),
         'includesConfidence', 'SOURCED - stated for all courses on the operator site',
         'certificationRequired', v.prerequisite
       )::jsonb,
       jsonb_build_object('freeCancellationHours', 24, 'refundPercent', 100,
                          'lateCancellationRefundPercent', 0,
                          'note', 'ASSUMPTION - no published cancellation policy')::jsonb,
       now(), now()
FROM _seed_ctx ctx,
(VALUES
  -- name, slug, description, colour, minutes, approval, max, unit, LKR, confidence, prerequisite
  ('Scuba Review', 'wbdc-scuba-review',
   'Refresher for certified divers who have been out of the water a while. Skills review in shallow water, then one guided dive.',
   '#0EA5E9', 120, false, 4, 'Slot', 12000,
   'ASSUMPTION - typical Sri Lankan refresher rate; not published by this operator',
   'Any prior scuba certification'),

  ('PADI Discover Scuba Diving', 'wbdc-padi-discover-scuba-diving',
   'No certification needed. Around 3.5 hours: briefing, shallow-water skills, then one real ocean dive with a PADI instructor. Equipment included.',
   '#22C55E', 210, false, 4, 'Slot', 21000,
   'SOURCED - USD 70 published (theabroadguide.com), converted at the assumed USD 1 = LKR 300',
   'None'),

  ('PADI Scuba Diver', 'wbdc-padi-scuba-diver',
   'Half of the Open Water course. Certifies you to dive to 12 m under the direct supervision of a PADI professional.',
   '#3B82F6', 1440, true, 4, 'Package', 75000,
   'ASSUMPTION - not published by this operator',
   'None'),

  ('PADI Scuba Diver Upgrade', 'wbdc-padi-scuba-diver-upgrade',
   'Completes the remaining Open Water modules, upgrading a Scuba Diver to independent diving to 18 m.',
   '#3B82F6', 1440, true, 4, 'Package', 45000,
   'ASSUMPTION - not published by this operator',
   'PADI Scuba Diver'),

  ('PADI Open Water Diver', 'wbdc-padi-open-water-diver',
   'The core entry-level certification. Knowledge development, confined-water skills and four open-water dives to 18 m, over three to four days.',
   '#2563EB', 2880, true, 4, 'Package', 120000,
   'ASSUMPTION - not published by this operator',
   'None'),

  ('PADI Adventure Dive', 'wbdc-padi-adventure-dive',
   'A single Adventure Dive - one specialty sampler dive (deep, navigation, wreck or night) with an instructor.',
   '#8B5CF6', 180, false, 4, 'Slot', 15000,
   'ASSUMPTION - not published by this operator',
   'PADI Open Water Diver'),

  ('PADI Adventure Diver', 'wbdc-padi-adventure-diver',
   'Three Adventure Dives of your choosing, earning the Adventure Diver certification.',
   '#8B5CF6', 1440, false, 4, 'Package', 48000,
   'ASSUMPTION - not published by this operator',
   'PADI Open Water Diver'),

  ('PADI Advanced Open Water Diver', 'wbdc-padi-advanced-open-water',
   'Five Adventure Dives including deep and underwater navigation. Extends your limit to 30 m - Dispa Rock territory.',
   '#1D4ED8', 2880, true, 4, 'Package', 95000,
   'ASSUMPTION - not published by this operator',
   'PADI Open Water Diver'),

  ('Emergency First Response', 'wbdc-emergency-first-response',
   'Primary and Secondary Care. CPR and first aid training - the prerequisite for Rescue Diver. Runs as a one-day classroom and practical course.',
   '#EF4444', 480, false, 6, 'Slot', 35000,
   'ASSUMPTION - not published by this operator',
   'None'),

  ('PADI Rescue Diver', 'wbdc-padi-rescue-diver',
   'Self-rescue, recognising and managing diver stress, and emergency management. Widely considered the most rewarding PADI course.',
   '#F97316', 2880, true, 4, 'Package', 120000,
   'ASSUMPTION - not published by this operator',
   'PADI Advanced Open Water Diver + EFR within 24 months'),

  ('PADI Dive Master', 'wbdc-padi-dive-master',
   'The first professional rating. Dive theory, skills demonstration and supervised internship with the centre. Duration varies with the candidate.',
   '#0F766E', 10080, true, 2, 'Package', 350000,
   'ASSUMPTION - not published by this operator',
   'PADI Rescue Diver, 40+ logged dives'),

  ('Fun Dive', 'wbdc-fun-dive',
   'Guided single-tank boat dive for certified divers at Yala Rock, Patch Point, Noisy Rock or Mirissa Point.',
   '#06B6D4', 180, false, 8, 'Slot', 12000,
   'ASSUMPTION - not published by this operator',
   'PADI Open Water Diver or equivalent'),

  ('Night Dive', 'wbdc-night-dive',
   'Guided dive after dark with torches, for certified divers. Different marine life entirely at the shallower sites.',
   '#1E1B4B', 180, false, 6, 'Slot', 15000,
   'ASSUMPTION - not published by this operator',
   'PADI Open Water Diver or equivalent')
) AS v(name, slug, description, color, duration_minutes, requires_approval,
       max_participants, booking_unit, price_lkr, price_confidence, prerequisite)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."Slug" = v.slug);

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT t."Name"        FROM "Tenants" t  JOIN _seed_ctx c ON t."Id" = c.tenant_id)        AS tenant,
  (SELECT t."ContactPhone" FROM "Tenants" t JOIN _seed_ctx c ON t."Id" = c.tenant_id)        AS phone,
  (SELECT count(*) FROM "Branches" b      JOIN _seed_ctx c ON b."TenantId" = c.tenant_id)    AS branches,
  (SELECT count(*) FROM "resources" r     JOIN _seed_ctx c ON r."TenantId" = c.tenant_id)    AS resources,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx c ON bt."TenantId" = c.tenant_id)  AS booking_types;

-- Prices needing replacement with the operator's real rate card:
--   SELECT "Name", "ConfigJson"->'basePrice'->>'amount' AS lkr,
--          "ConfigJson"->>'priceConfidence' AS confidence
--   FROM "booking_types"
--   WHERE "ConfigJson"->>'priceConfidence' LIKE 'ASSUMPTION%'
--   ORDER BY "Name";
