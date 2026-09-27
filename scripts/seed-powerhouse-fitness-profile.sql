-- ============================================================================
-- Business Profile for the "PowerHouse Fitness" (Nugegoda) tenant - the
-- public listing shell TenantProfileController serves (cover, gallery,
-- description, hours, amenities, contact, social links) - plus the
-- Memberships module config the gym dashboard reads its targets from.
--
-- Run after scripts/seed-demo-data.ps1 or seed-powerhouse-fitness-sample-
-- records.sql (either creates the tenant). Same shape as the Spice Garden
-- and Asia Medihealth profile scripts.
--
-- PowerHouse Fitness is a DEMO business: every value below is invented.
-- Photos are Unsplash stock images. Re-runnable.
--
--   psql "$DATABASE_URL" -f scripts/seed-powerhouse-fitness-profile.sql
-- ============================================================================

BEGIN;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM "Tenants"
   WHERE "Name" = 'PowerHouse Fitness' AND lower("BusinessType") IN ('gym','fitness');
  IF n = 0 THEN
    RAISE EXCEPTION 'Tenant "PowerHouse Fitness" not found - run seed-demo-data.ps1 or seed-powerhouse-fitness-sample-records.sql first.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "PowerHouse Fitness" - pin one by Id in the WHERE clause.', n;
  END IF;
END $$;

-- BusinessType 'Gym' is the exact value in RegisterPage.tsx BUSINESS_TYPES.
-- BusinessHours is PascalCase on purpose - ParseBusinessHours reads it back
-- case-sensitively.
UPDATE "Tenants" SET
  "BusinessType" = 'Gym',
  "IsActive"     = true,

  "ShortTagline" = '24-station strength & cardio floor, group classes and personal training - High Level Road, Nugegoda',
  "Description"  = 'PowerHouse Fitness is a members'' gym on High Level Road, Nugegoda, open 06:00-21:00 every day. The floor has a free-weights and rack area, a 30-station cardio zone, a functional / CrossFit box and two studios running HIIT, yoga and spin classes through the week. Members check in by RFID keycard, the mobile app or the fingerprint gate; Basic, Standard, Premium and Student plans are billed monthly, with an annual Premium option, and day passes are sold at the desk. Personal training with our three certified coaches is booked online.',

  "ContactPhone" = '+94112765432',
  "ContactEmail" = 'hello@powerhousefitness.lk',
  "Website"      = 'https://www.powerhousefitness.lk/',

  -- Cover: the default gym cover from shared/businessImagery.ts.
  "CoverImageUrl" = 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1600&q=70&auto=format&fit=crop',
  -- Logo: a simple mark checked in at frontend/public/logos/powerhouse-fitness.svg, referenced by
  -- a root-relative URL so it resolves on localhost and in production alike
  -- (the dashboards show it as the business's profile picture). Replace it
  -- by uploading a real logo under Settings -> Business Profile.
  "LogoUrl"       = COALESCE("LogoUrl", '/logos/powerhouse-fitness.svg'),

  "GalleryImageUrls" = jsonb_build_array(
      'https://images.unsplash.com/photo-1571902943202-507ec2618e8f?w=1600&q=70&auto=format&fit=crop',  -- weights floor
      'https://images.unsplash.com/photo-1540497077202-7c8a3999166f?w=1600&q=70&auto=format&fit=crop',  -- cardio zone
      'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=1600&q=70&auto=format&fit=crop',  -- group class
      'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=1600&q=70&auto=format&fit=crop',    -- yoga studio
      'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1600&q=70&auto=format&fit=crop'   -- rack area
  ),

  "SocialLinks" = jsonb_build_object(
      'facebook',  'https://www.facebook.com/powerhousefitnessnugegoda',
      'instagram', 'https://www.instagram.com/powerhousefitness.lk',
      'whatsapp',  'https://wa.me/94112765432',
      'youtube',   'https://www.youtube.com/@powerhousefitnesslk'
  ),

  -- Open daily 06:00-21:00 (15 hours - matches openHoursPerDay below).
  "BusinessHours" = (
      SELECT jsonb_agg(jsonb_build_object(
               'DayOfWeek', d, 'OpenTime', '06:00', 'CloseTime', '21:00', 'IsClosed', false
             ) ORDER BY ord)
      FROM (VALUES
        ('Sunday',1),('Monday',2),('Tuesday',3),('Wednesday',4),
        ('Thursday',5),('Friday',6),('Saturday',7)
      ) AS x(d, ord)
  ),

  "Amenities" = jsonb_build_array(
      'Open 7 Days, 06:00-21:00',
      'RFID Keycard & App Check-in',
      'Free Weights & Racks',
      '30-station Cardio Zone',
      'Functional / CrossFit Box',
      'Two Group-class Studios',
      'HIIT, Yoga & Spin Classes',
      'Certified Personal Trainers',
      'Changing Rooms & Showers',
      'Lockers',
      'Protein & Supplement Bar',
      'Parking'
  ),

  "ProfileUpdatedAt" = now(),
  "UpdatedAt"        = now()
  -- "AverageRating" / "ReviewCount" intentionally NOT set - no reviews
  -- feature exists to compute them.
WHERE "Name" = 'PowerHouse Fitness' AND lower("BusinessType") IN ('gym','fitness');

-- ── Memberships module config ───────────────────────────────────────────────
-- GymConfig.TargetsOf reads these: the facility capacity behind the live
-- occupancy figure, the revenue targets behind the MTD / YTD bars, the
-- opening hours the zone / equipment utilisation is measured against, and
-- the uses-between-services threshold for the maintenance scheduler.
INSERT INTO "TenantModules" ("Id","CreatedAt","UpdatedAt","TenantId","ModuleName","IsEnabled","ConfigJson")
SELECT gen_random_uuid(), now(), now(), t."Id", 'Memberships', true, '{}'
FROM "Tenants" t
WHERE t."Name" = 'PowerHouse Fitness'
  AND NOT EXISTS (SELECT 1 FROM "TenantModules" m WHERE m."TenantId" = t."Id" AND m."ModuleName" = 'Memberships');

UPDATE "TenantModules" m SET
  "ConfigJson" = ((CASE WHEN m."ConfigJson" ~ '^\s*\{' THEN m."ConfigJson"::jsonb ELSE '{}'::jsonb END) || jsonb_build_object(
      'facilityCapacity',     120,
      'monthlyRevenueTarget', 180000,
      'yearlyRevenueTarget',  2160000,
      'openHoursPerDay',      15,
      'maintenanceEveryUses', 200
  ))::text,
  "IsEnabled" = true,
  "UpdatedAt" = now()
FROM "Tenants" t
WHERE m."TenantId" = t."Id" AND t."Name" = 'PowerHouse Fitness' AND m."ModuleName" = 'Memberships';

COMMIT;

-- Check:
--   SELECT t."ShortTagline", jsonb_array_length(t."Amenities") AS amenities,
--          m."ConfigJson" FROM "Tenants" t
--   JOIN "TenantModules" m ON m."TenantId" = t."Id" AND m."ModuleName" = 'Memberships'
--   WHERE t."Name" = 'PowerHouse Fitness';
