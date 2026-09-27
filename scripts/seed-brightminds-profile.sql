-- ============================================================================
-- Business Profile for the "BrightMinds Tuition Center" (Kadawatha) school
-- tenant - the public listing shell (cover, gallery, description, hours,
-- amenities, contact, social links) - plus the Scheduling and Attendance
-- module configs the school dashboard reads: terms and holidays, the
-- at-risk thresholds, the late threshold and the grade scale.
--
-- Run after scripts/seed-demo-data.ps1 or seed-brightminds-sample-records.sql
-- (either creates the tenant). BrightMinds is a DEMO business: every value
-- is invented; photos are Unsplash stock images. Re-runnable.
--
--   psql "$DATABASE_URL" -f scripts/seed-brightminds-profile.sql
-- ============================================================================

BEGIN;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM "Tenants"
   WHERE "Name" = 'BrightMinds Tuition Center' AND lower("BusinessType") IN ('school','tuition','education','academy');
  IF n = 0 THEN
    RAISE EXCEPTION 'Tenant "BrightMinds Tuition Center" not found - run seed-demo-data.ps1 or seed-brightminds-sample-records.sql first.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "BrightMinds Tuition Center" - pin one by Id in the WHERE clause.', n;
  END IF;
END $$;

-- BusinessType 'School' is the exact value in RegisterPage.tsx BUSINESS_TYPES.
-- BusinessHours is PascalCase on purpose - ParseBusinessHours reads it back
-- case-sensitively.
UPDATE "Tenants" SET
  "BusinessType" = 'School',
  "IsActive"     = true,

  "ShortTagline" = 'O/L & A/L tuition in Mathematics, Science, English and ICT - Kandy Road, Kadawatha',
  "Description"  = 'BrightMinds Tuition Center runs after-school classes for Grade 10 and Grade 11 students from a three-classroom centre on Kandy Road, Kadawatha. Small group classes (max 20) in Mathematics, Science, English and ICT run weekday afternoons and Saturday mornings, alongside one-to-one tutoring and O/L exam-prep sessions. Attendance is marked every lesson, marks and feedback go into the gradebook the same day, and parents get a term report card. Fees are billed monthly per grade package.',

  "ContactPhone" = '+94112654321',
  "ContactEmail" = 'hello@brightminds.lk',
  "Website"      = 'https://www.brightminds.lk/',

  -- Cover: the default school cover from shared/businessImagery.ts.
  "CoverImageUrl" = 'https://images.unsplash.com/photo-1580582932707-520aed937b7b?w=1600&q=70&auto=format&fit=crop',
  -- Logo: a simple mark checked in at frontend/public/logos/brightminds.svg;
  -- only used while no real logo has been uploaded under Settings.
  "LogoUrl"       = COALESCE("LogoUrl", '/logos/brightminds.svg'),

  "GalleryImageUrls" = jsonb_build_array(
      'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=1600&q=70&auto=format&fit=crop',  -- classroom
      'https://images.unsplash.com/photo-1509062522246-3755977927d7?w=1600&q=70&auto=format&fit=crop',  -- students at desks
      'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=1600&q=70&auto=format&fit=crop',  -- books
      'https://images.unsplash.com/photo-1531482615713-2afd69097998?w=1600&q=70&auto=format&fit=crop',  -- tutoring
      'https://images.unsplash.com/photo-1588072432836-e10032774350?w=1600&q=70&auto=format&fit=crop'   -- computer lab
  ),

  "SocialLinks" = jsonb_build_object(
      'facebook',  'https://www.facebook.com/brightmindskadawatha',
      'youtube',   'https://www.youtube.com/@brightmindslk',
      'whatsapp',  'https://wa.me/94112654321'
  ),

  -- Weekday afternoons and Saturday morning; closed Sunday.
  "BusinessHours" = jsonb_build_array(
      jsonb_build_object('DayOfWeek','Sunday',    'OpenTime','00:00','CloseTime','00:00','IsClosed',true),
      jsonb_build_object('DayOfWeek','Monday',    'OpenTime','14:00','CloseTime','19:00','IsClosed',false),
      jsonb_build_object('DayOfWeek','Tuesday',   'OpenTime','14:00','CloseTime','19:00','IsClosed',false),
      jsonb_build_object('DayOfWeek','Wednesday', 'OpenTime','14:00','CloseTime','19:00','IsClosed',false),
      jsonb_build_object('DayOfWeek','Thursday',  'OpenTime','14:00','CloseTime','19:00','IsClosed',false),
      jsonb_build_object('DayOfWeek','Friday',    'OpenTime','14:00','CloseTime','19:00','IsClosed',false),
      jsonb_build_object('DayOfWeek','Saturday',  'OpenTime','09:00','CloseTime','13:00','IsClosed',false)
  ),

  "Amenities" = jsonb_build_array(
      'Grade 10 & 11 (O/L) classes',
      'Small groups - max 20',
      'One-to-one tutoring',
      'O/L exam-prep sessions',
      'Three air-conditioned classrooms',
      'Computer lab (ICT)',
      'Attendance marked every lesson',
      'Online gradebook & term report cards',
      'Parent WhatsApp updates',
      'Monthly fee packages',
      'Free parking',
      'Bus route 245 stop outside'
  ),

  "ProfileUpdatedAt" = now(),
  "UpdatedAt"        = now()
WHERE "Name" = 'BrightMinds Tuition Center' AND lower("BusinessType") IN ('school','tuition','education','academy');

-- ── Module configs ──────────────────────────────────────────────────────────
-- Scheduling: the term calendar (SchoolConfig.CalendarOf). Dates are demo
-- choices around "now" so the current term shows in progress. Attendance:
-- the at-risk thresholds, the late threshold and the grade scale
-- (SchoolConfig.ThresholdsOf) - the Sri Lankan O/L bands.
INSERT INTO "TenantModules" ("Id","CreatedAt","UpdatedAt","TenantId","ModuleName","IsEnabled","ConfigJson")
SELECT gen_random_uuid(), now(), now(), t."Id", v.module, true, '{}'
FROM "Tenants" t, (VALUES ('Scheduling'), ('Attendance')) AS v(module)
WHERE t."Name" = 'BrightMinds Tuition Center'
  AND NOT EXISTS (SELECT 1 FROM "TenantModules" m WHERE m."TenantId" = t."Id" AND m."ModuleName" = v.module);

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'terms', jsonb_build_array(
        jsonb_build_object('name', 'Term 1', 'from', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-01-06', 'to', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-04-10'),
        jsonb_build_object('name', 'Term 2', 'from', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-04-28', 'to', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-08-08'),
        jsonb_build_object('name', 'Term 3', 'from', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-08-25', 'to', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-12-05')
      ),
      'holidays', jsonb_build_array(
        jsonb_build_object('date', to_char((now() AT TIME ZONE 'Asia/Colombo')::date + 1, 'YYYY-MM-DD'), 'name', 'Poya day'),
        jsonb_build_object('date', to_char((now() AT TIME ZONE 'Asia/Colombo')::date + 12, 'YYYY-MM-DD'), 'name', 'Staff training day'),
        jsonb_build_object('date', to_char((now() AT TIME ZONE 'Asia/Colombo')::date + 33, 'YYYY-MM-DD'), 'name', 'Deepavali'),
        jsonb_build_object('date', to_char(date_trunc('year', now() AT TIME ZONE 'Asia/Colombo'), 'YYYY') || '-12-25', 'name', 'Christmas Day')
      )
  ))::text,
  "IsEnabled" = true, "UpdatedAt" = now()
FROM "Tenants" t
WHERE m."TenantId" = t."Id" AND t."Name" = 'BrightMinds Tuition Center' AND m."ModuleName" = 'Scheduling';

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'atRiskAttendancePercent', 75,
      'atRiskGradePercent',      50,
      'lateAfterMinutes',        10,
      'gradeScale', jsonb_build_array(
        jsonb_build_object('grade','A','min',75), jsonb_build_object('grade','B','min',65),
        jsonb_build_object('grade','C','min',55), jsonb_build_object('grade','S','min',40),
        jsonb_build_object('grade','F','min',0)
      )
  ))::text,
  "IsEnabled" = true, "UpdatedAt" = now()
FROM "Tenants" t
WHERE m."TenantId" = t."Id" AND t."Name" = 'BrightMinds Tuition Center' AND m."ModuleName" = 'Attendance';

COMMIT;

-- Check:
--   SELECT m."ModuleName", m."ConfigJson" FROM "TenantModules" m JOIN "Tenants" t ON t."Id" = m."TenantId"
--   WHERE t."Name" = 'BrightMinds Tuition Center' AND m."ModuleName" IN ('Scheduling','Attendance');
