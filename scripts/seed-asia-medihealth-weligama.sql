-- ============================================================================
-- Seed "Asia Medihealth Services" - a REAL private medical centre in Weligama
-- - as a Clinic tenant, with its branch, consultation rooms, the published
-- consultant roster as bookable Staff resources, and a BookingType catalogue
-- for OPD / channelling / lab / imaging.
--
-- Run once, as-is, in the Supabase SQL editor or via psql. Everything is in
-- one transaction: if anything fails, nothing is committed. Re-running is
-- safe - every INSERT is guarded by a NOT EXISTS on its Slug / (TenantId,Code),
-- and the profile UPDATE is idempotent.
--
--   psql "$DATABASE_URL" -f scripts/seed-asia-medihealth-weligama.sql
--
-- ── PROVENANCE ──────────────────────────────────────────────────────────────
-- This is a REAL, identifiable business, so (same rule as
-- seed-weligama-bay-dive-center.sql) every value is tagged. Sourced 2026-09-18
-- from:
--   - https://www.asiamedihealth.lk/          (name, address, phone, services,
--                                              "open daily", PCR/RAT prices)
--   - https://www.asiamedihealth.lk/doctors/  (the 14-consultant roster)
--
-- SOURCED    -> taken verbatim from a page above.
-- ASSUMPTION -> NOT published by this operator. Typical south-coast private
--               clinic figures so the booking flow has numbers to work with.
--               Tagged "priceConfidence" in ConfigJson - replace with the
--               clinic's real rate card before going live.
--
-- Only TWO prices are published: PCR test Rs 6,500 and Rapid Antigen Test
-- Rs 2,250. Every other price is an ASSUMPTION.
--
-- AverageRating / ReviewCount are deliberately left untouched: no rating was
-- sourced from the operator, and inventing one for a real business is wrong.
-- ============================================================================

BEGIN;

-- ── 0) Locate (or create) the tenant ────────────────────────────────────────
-- The clinic's real inbox is not used as a login here: the admin account is a
-- placeholder you own. Change ADMIN_EMAIL below if you already registered one.
DROP TABLE IF EXISTS _seed_ctx;
DROP TABLE IF EXISTS _seed_branch;

CREATE TEMP TABLE _seed_ctx AS
SELECT u."Id" AS admin_user_id, u."TenantId" AS tenant_id
FROM "Users" u
WHERE lower(u."Email") = 'admin.asiamedihealth@example.com';   -- ADMIN_EMAIL

-- "Users"."Email" has no unique index, so one email can map to several
-- tenants. Refuse to guess rather than seed the wrong business.
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM _seed_ctx;
  IF n > 1 THEN
    RAISE EXCEPTION
      'admin.asiamedihealth@example.com maps to % users across tenants. Pin the tenant explicitly: SELECT "Id","FullName","TenantId" FROM "Users" WHERE lower("Email") = ''admin.asiamedihealth@example.com'';', n;
  END IF;
END $$;

-- 0b) No such account yet -> bootstrap tenant + admin from nothing.
-- Password for the created admin is  Passw0rd!  (BCrypt.Net $2b$11 hash,
-- the same verified hash used by seed-weligama-bay-dive-center.sql).
DO $$
DECLARE t_id uuid; u_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _seed_ctx) THEN
    t_id := gen_random_uuid();
    u_id := gen_random_uuid();

    INSERT INTO "Tenants"
      ("Id","CreatedAt","UpdatedAt","Name","BusinessType","SubType","IsActive",
       "CancellationCutoffHours","RescheduleCutoffHours","ReviewCount")
    VALUES (t_id, now(), now(), 'Asia Medihealth Services',
            'Clinic', NULL, true, 2, 2, 0);

    INSERT INTO "Users"
      ("Id","CreatedAt","UpdatedAt","TenantId","Email","PasswordHash","FullName",
       "Phone","Role","IsActive","IsApproved")
    VALUES (u_id, now(), now(), t_id, 'admin.asiamedihealth@example.com',
            '$2b$11$s2W5yCxONBkOC22L0MEFw.TJK1IieYhOOCRwT1F8gR8wDCTJpmvxq',
            'Asia Medihealth Admin', '+94412253208', 0, true, true);   -- 0 = Admin

    INSERT INTO _seed_ctx (admin_user_id, tenant_id) VALUES (u_id, t_id);
  END IF;
END $$;

-- ── 1) Business Profile ─────────────────────────────────────────────────────
-- BusinessType 'Clinic' is the exact value in RegisterPage.tsx BUSINESS_TYPES.
-- BusinessHours is PascalCase on purpose - ParseBusinessHours reads it back
-- case-sensitively.
UPDATE "Tenants" t SET
  "Name"         = 'Asia Medihealth Services',
  "BusinessType" = 'Clinic',
  "IsActive"     = true,

  -- SOURCED: services list from the operator's home page.
  "Description"  = 'Asia Medihealth Services (Private) Limited is a private medical centre on Matara Road, Weligama, open seven days a week. It runs an OPD and an Emergency Treatment Unit, an on-site laboratory, X-ray, ultrasound and echocardiography, a dental unit, eye care, a skin-care clinic, a pain-management centre and a mini theatre for minor procedures. The centre treats surf injuries, accepts medical insurance, offers home and hotel visits along the Weligama-Mirissa coast, and has Russian-speaking doctors for the area''s visitor community.',
  "ShortTagline" = 'Private medical centre & ETU - Matara Road, Weligama',

  -- SOURCED: phone and address on the operator site.
  "ContactPhone" = '+94412253208',
  "ContactEmail" = NULL,   -- the site hides its inbox behind an obfuscator; fill in by hand
  "Website"      = 'https://www.asiamedihealth.lk/',

  -- SOURCED: the operator's own logo, hot-linked from their site.
  "LogoUrl"      = 'https://www.asiamedihealth.lk/wp-content/uploads/2021/11/cropped-Logo-01.png',

  -- SOURCED: the Facebook URL is the one linked from the site's footer. The
  -- WhatsApp link is just the published landline - ASSUMPTION it is on WhatsApp.
  "SocialLinks"  = jsonb_build_object(
      'facebook', 'https://www.facebook.com/Asia-MediHealth-Services-104665958543449',
      'whatsapp', 'https://wa.me/94412253208'
  ),

  -- SOURCED: "open daily" / "seven days a week". Exact hours are NOT
  -- published - 08:00-20:00 is an ASSUMPTION for a south-coast OPD; the ETU
  -- is described as always open, which the profile model cannot express.
  "BusinessHours" = (
      SELECT jsonb_agg(jsonb_build_object(
               'DayOfWeek', d, 'OpenTime', '08:00', 'CloseTime', '20:00', 'IsClosed', false
             ) ORDER BY ord)
      FROM (VALUES
        ('Sunday',1),('Monday',2),('Tuesday',3),('Wednesday',4),
        ('Thursday',5),('Friday',6),('Saturday',7)
      ) AS x(d, ord)
  ),

  -- SOURCED: every item is named on the home page.
  "Amenities" = jsonb_build_array(
      'Open 7 Days',
      'Emergency Treatment Unit (ETU)',
      'On-site Laboratory',
      'X-ray & Ultrasound',
      'Echocardiogram',
      'Dental Care',
      'Eye Care',
      'Mini Theatre (minor procedures)',
      'Home & Hotel Visits',
      'Medical Insurance Accepted',
      'Russian-speaking Doctors',
      'Surf Injury Treatment'
  ),

  "ProfileUpdatedAt" = now(),
  "UpdatedAt"        = now()
  -- "AverageRating"/"ReviewCount" intentionally NOT set - no sourced number.
FROM _seed_ctx ctx
WHERE t."Id" = ctx.tenant_id;

-- ── 1b) Admin avatar ────────────────────────────────────────────────────────
-- Cloudinary is not configured in dev, so the in-app upload cannot work.
-- The heart-and-stethoscope emblem from the logo above, cropped square, is
-- checked in at frontend/public/avatars/asia-medihealth.png and referenced
-- by a root-relative URL: it resolves against whatever origin serves the
-- web app, so it works on localhost:5173 and in production alike.
-- Only fills the field when it is empty - a photo someone uploaded wins.
UPDATE "Users" u SET
  "ProfilePictureUrl" = '/avatars/asia-medihealth.png',
  "UpdatedAt"         = now()
FROM _seed_ctx ctx
WHERE u."Id" = ctx.admin_user_id AND u."ProfilePictureUrl" IS NULL;

-- ── 2) Branch ───────────────────────────────────────────────────────────────
-- SOURCED address: "No 468, Matara Road, Weligama, Sri Lanka".
INSERT INTO "Branches" ("Id","CreatedAt","UpdatedAt","TenantId","Name","Address","Phone","IsActive")
SELECT gen_random_uuid(), now(), now(), ctx.tenant_id,
       'Weligama (Matara Road)',
       'No. 468, Matara Road, Weligama, Southern Province, Sri Lanka',
       '+94412253208', true
FROM _seed_ctx ctx
WHERE NOT EXISTS (
  SELECT 1 FROM "Branches" b
  WHERE b."TenantId" = ctx.tenant_id AND b."Name" = 'Weligama (Matara Road)'
);

CREATE TEMP TABLE _seed_branch AS
SELECT b."Id" AS branch_id
FROM "Branches" b JOIN _seed_ctx ctx ON b."TenantId" = ctx.tenant_id
WHERE b."Name" = 'Weligama (Matara Road)'
LIMIT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM _seed_branch) THEN
    RAISE EXCEPTION 'Branch "Weligama (Matara Road)" was neither found nor created - aborting before the resource inserts silently no-op.';
  END IF;
END $$;

-- ── 3) Resources ────────────────────────────────────────────────────────────
-- Category/Status are the string forms of ResourceCategory/ResourceStatus.
-- "Code" is unique per (TenantId, Code) since ScopeResourceCodeToTenant, so
-- the guards check both.
--
-- HourlyRate is set on rooms only, matching DevelopmentUserSeeder's clinic
-- demo (ROOM-01/02 at LKR 3,500/hr). Consultant fees live on the BookingTypes.

-- 3a) Rooms / units. The UNITS are SOURCED (OPD, ETU, lab, X-ray, US, dental,
--     eye, skin, pain, mini theatre). Room counts and hourly rates are NOT.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","HourlyRate","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, 'Room', v.specialty, 'Available', v.capacity, v.rate,
       v.description,
       jsonb_build_object(
         'unit', v.specialty,
         'confidence', 'Unit SOURCED from asiamedihealth.lk; room count and hourly rate are ASSUMPTIONS'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('OPD Consultation Room 1', 'AMS-OPD-01', 'OPD', 2, 3500,
   'General outpatient consultation room.'),
  ('OPD Consultation Room 2', 'AMS-OPD-02', 'OPD', 2, 3500,
   'Second outpatient consultation room, also used for specialist channelling.'),
  ('Channelling Room (Consultants)', 'AMS-CH-01', 'Channelling', 2, 4000,
   'Consultant channelling room for the visiting specialist roster.'),
  ('Emergency Treatment Unit', 'AMS-ETU-01', 'ETU', 4, NULL,
   'Emergency Treatment Unit - walk-in, not bookable through the customer flow.'),
  ('Laboratory', 'AMS-LAB-01', 'Laboratory', 3, NULL,
   'On-site laboratory: blood work, PCR and rapid antigen testing.'),
  ('X-ray Room', 'AMS-XR-01', 'Imaging', 1, NULL,
   'Plain-film X-ray.'),
  ('Ultrasound / Echo Room', 'AMS-US-01', 'Imaging', 1, NULL,
   'Ultrasound scanning and echocardiography.'),
  ('Dental Unit', 'AMS-DEN-01', 'Dental', 1, NULL,
   'Dental care chair.'),
  ('Eye Care Room', 'AMS-EYE-01', 'Ophthalmology', 1, NULL,
   'Eye examination room.'),
  ('Skin Care Clinic', 'AMS-SKIN-01', 'Dermatology', 1, NULL,
   'Skin-care clinic room.'),
  ('Pain Management Centre', 'AMS-PAIN-01', 'Pain Management', 1, NULL,
   'Pain-management treatment room.'),
  ('Mini Theatre', 'AMS-MT-01', 'Minor Procedures', 1, NULL,
   'Mini theatre for minor procedures, wound care and dressings.')
) AS v(name, code, specialty, capacity, rate, description)
WHERE NOT EXISTS (
  SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code
);

-- 3b) Consultants. All 14 names + specialties are SOURCED verbatim from
--     /doctors/. Consultation days/times are NOT published, so no schedule
--     is seeded - set availability per consultant in the app.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, 'Staff', v.specialty, 'Available', 1,
       v.specialty || ' - visiting consultant at Asia Medihealth Services, Weligama.',
       jsonb_build_object(
         'role', 'Consultant',
         'specialty', v.specialty,
         'confidence', 'SOURCED - name and specialty published on asiamedihealth.lk/doctors; days and fees are not'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('Dr. Gamini Abeysinghe',     'AMS-DR-01', 'Consultant General Surgeon'),
  ('Dr. Peshala Dangalla',      'AMS-DR-02', 'Consultant Obstetrician & Gynaecologist'),
  ('Dr. Maithri Chandraratne',  'AMS-DR-03', 'Consultant Obstetrician & Gynaecologist'),
  ('Dr. Chamila Subasinghe',    'AMS-DR-04', 'Consultant Gastroenterologist'),
  ('Dr. Nilanga Gamage',        'AMS-DR-05', 'Consultant Psychiatrist'),
  ('Dr. Indika Dharmapriya',    'AMS-DR-06', 'Consultant Physician'),
  ('Dr. Vajira Gunawardena',    'AMS-DR-07', 'Consultant Cardiologist'),
  ('Dr. Rasika Disanayake',     'AMS-DR-08', 'Consultant Dermatologist'),
  ('Dr. Sajith Rupasinghe',     'AMS-DR-09', 'Consultant Radiologist'),
  ('Dr. Abhaya Jayasekara',     'AMS-DR-10', 'Consultant Ophthalmologist'),
  ('Dr. Milinda Jayawardana',   'AMS-DR-11', 'Consultant Paediatrician'),
  ('Dr. K.A.I.U. Imbulana',     'AMS-DR-12', 'Chest Diseases Specialist'),
  ('Dr. Zacky Haniffa',         'AMS-DR-13', 'Consultant Cardiologist'),
  ('Dr. Rasanga Gunawaedena',   'AMS-DR-14', 'Consultant Orthopaedic Surgeon')
) AS v(name, code, specialty)
WHERE NOT EXISTS (
  SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code
);

-- 3c) OPD duty doctors. SOURCED: the OPD runs daily and has Russian-speaking
--     doctors; nobody is named. Two unnamed slots, flagged as placeholders.
INSERT INTO "resources"
  ("Id","TenantId","BranchId","Name","Code","Category","Specialty","Status",
   "Capacity","Description","CustomAttributes","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id, br.branch_id,
       v.name, v.code, 'Staff', 'General Practice (OPD)', 'Available', 1,
       'OPD duty doctor slot. Rename to the rostered doctor once known.',
       jsonb_build_object(
         'role', 'OPD Doctor',
         'languagesSpoken', v.langs,
         'confidence', 'ASSUMPTION - placeholder slot; OPD roster is not public'
       ),
       now(), now()
FROM _seed_ctx ctx, _seed_branch br,
(VALUES
  ('OPD Doctor 1',                    'AMS-GP-01', jsonb_build_array('English','Sinhala')),
  ('OPD Doctor 2 (Russian-speaking)', 'AMS-GP-02', jsonb_build_array('English','Sinhala','Russian'))
) AS v(name, code, langs)
WHERE NOT EXISTS (
  SELECT 1 FROM "resources" r WHERE r."TenantId" = ctx.tenant_id AND r."Code" = v.code
);

-- ── 4) BookingTypes: what a patient can book ────────────────────────────────
-- Service NAMES are SOURCED from the home page. PRICES: only PCR (Rs 6,500)
-- and RAT (Rs 2,250) are published; the rest are ASSUMPTIONS, each tagged.
-- Slug is globally UNIQUE across tenants, hence the ams- prefix.
-- The ETU is deliberately NOT a booking type - it is walk-in.
INSERT INTO "booking_types"
  ("Id","TenantId","Name","Slug","Description","ColorHex","Status",
   "DefaultDurationMinutes","RequiresApproval","MaxParticipants",
   "BufferMinutesBefore","BufferMinutesAfter","BookingUnit",
   "ConfigJson","CancellationPolicy","CreatedAt","UpdatedAt")
SELECT gen_random_uuid(), ctx.tenant_id,
       v.name, v.slug, v.description, v.color, 'Active',
       v.duration_minutes, v.requires_approval, 1,
       0, v.buffer_after, 'Slot',
       jsonb_build_object(
         'subType', 'clinic',
         'department', v.department,
         'basePrice', jsonb_build_object('amount', v.price_lkr, 'currency', 'LKR'),
         'priceConfidence', v.price_confidence,
         'insuranceAccepted', true,
         'insuranceConfidence', 'SOURCED - "accepts medical insurance" is stated on the site'
       )::jsonb,
       jsonb_build_object('freeCancellationHours', 2, 'refundPercent', 100,
                          'lateCancellationRefundPercent', 0,
                          'note', 'ASSUMPTION - no published cancellation policy')::jsonb,
       now(), now()
FROM _seed_ctx ctx,
(VALUES
  -- name, slug, description, colour, minutes, approval, buffer, department, LKR, confidence
  ('OPD Consultation', 'ams-opd-consultation',
   'General outpatient consultation with the duty doctor. Open daily.',
   '#0EA5E9', 15, false, 5, 'OPD', 2500,
   'ASSUMPTION - typical south-coast private OPD fee; not published'),

  ('Specialist Channelling', 'ams-specialist-channelling',
   'Appointment with one of the visiting consultants (surgery, O&G, cardiology, dermatology, paediatrics, psychiatry, orthopaedics and more). Pick the consultant as the resource.',
   '#2563EB', 20, false, 5, 'Channelling', 4500,
   'ASSUMPTION - typical Sri Lankan consultant channelling fee; not published'),

  ('PCR Test (COVID-19)', 'ams-pcr-test',
   'RT-PCR swab at the on-site laboratory.',
   '#8B5CF6', 15, false, 0, 'Laboratory', 6500,
   'SOURCED - "Rs 6,500/-" on asiamedihealth.lk'),

  ('Rapid Antigen Test (RAT)', 'ams-rapid-antigen-test',
   'Rapid antigen swab with same-visit result.',
   '#8B5CF6', 15, false, 0, 'Laboratory', 2250,
   'SOURCED - "Rs 2,250/-" on asiamedihealth.lk'),

  ('Laboratory Blood Tests', 'ams-lab-blood-tests',
   'Blood draw for the on-site laboratory (FBC, lipid profile, glucose, etc.). Priced per test at the counter.',
   '#7C3AED', 15, false, 0, 'Laboratory', 1500,
   'ASSUMPTION - indicative single-test fee; the real lab price list is not published'),

  ('X-ray', 'ams-xray',
   'Plain-film X-ray with report.',
   '#F59E0B', 20, false, 5, 'Imaging', 3500,
   'ASSUMPTION - not published'),

  ('Ultrasound Scan', 'ams-ultrasound-scan',
   'Ultrasound scan with report.',
   '#F59E0B', 30, false, 5, 'Imaging', 5000,
   'ASSUMPTION - not published'),

  ('Echocardiogram', 'ams-echocardiogram',
   'Echocardiogram, read by a consultant cardiologist.',
   '#EF4444', 30, true, 10, 'Imaging', 9000,
   'ASSUMPTION - not published'),

  ('Dental Consultation', 'ams-dental-consultation',
   'Dental examination and consultation.',
   '#14B8A6', 30, false, 10, 'Dental', 3000,
   'ASSUMPTION - not published'),

  ('Eye Care Consultation', 'ams-eye-care-consultation',
   'Eye examination with the consultant ophthalmologist.',
   '#06B6D4', 20, false, 5, 'Ophthalmology', 4500,
   'ASSUMPTION - not published'),

  ('Skin Care Clinic', 'ams-skin-care-clinic',
   'Dermatology consultation at the skin-care clinic.',
   '#EC4899', 20, false, 5, 'Dermatology', 4500,
   'ASSUMPTION - not published'),

  ('Pain Management Session', 'ams-pain-management-session',
   'Assessment and treatment at the pain-management centre.',
   '#F97316', 45, true, 10, 'Pain Management', 6000,
   'ASSUMPTION - not published'),

  ('Wound Care / Dressing', 'ams-wound-care-dressing',
   'Wound cleaning and dressing, including surf injuries.',
   '#22C55E', 20, false, 5, 'Minor Procedures', 2000,
   'ASSUMPTION - not published'),

  ('Minor Procedure (Mini Theatre)', 'ams-minor-procedure',
   'Minor surgical procedure in the mini theatre - suturing, incision and drainage, foreign-body removal.',
   '#DC2626', 45, true, 15, 'Minor Procedures', 12000,
   'ASSUMPTION - not published'),

  ('Home / Hotel Visit', 'ams-home-hotel-visit',
   'Doctor visits you at your home, villa or hotel in the Weligama-Mirissa area.',
   '#0F766E', 60, true, 30, 'Home Visits', 8000,
   'ASSUMPTION - not published')
) AS v(name, slug, description, color, duration_minutes, requires_approval,
       buffer_after, department, price_lkr, price_confidence)
WHERE NOT EXISTS (SELECT 1 FROM "booking_types" bt WHERE bt."Slug" = v.slug);

COMMIT;

-- ── Summary ─────────────────────────────────────────────────────────────────
SELECT
  (SELECT t."Name"         FROM "Tenants" t  JOIN _seed_ctx c ON t."Id" = c.tenant_id)       AS tenant,
  (SELECT t."ContactPhone" FROM "Tenants" t  JOIN _seed_ctx c ON t."Id" = c.tenant_id)       AS phone,
  (SELECT count(*) FROM "Branches" b       JOIN _seed_ctx c ON b."TenantId" = c.tenant_id)   AS branches,
  (SELECT count(*) FROM "resources" r      JOIN _seed_ctx c ON r."TenantId" = c.tenant_id)   AS resources,
  (SELECT count(*) FROM "booking_types" bt JOIN _seed_ctx c ON bt."TenantId" = c.tenant_id)  AS booking_types;

-- Prices needing replacement with the clinic's real rate card:
--   SELECT "Name", "ConfigJson"->'basePrice'->>'amount' AS lkr,
--          "ConfigJson"->>'priceConfidence' AS confidence
--   FROM "booking_types"
--   WHERE "Slug" LIKE 'ams-%' AND "ConfigJson"->>'priceConfidence' LIKE 'ASSUMPTION%'
--   ORDER BY "Name";
