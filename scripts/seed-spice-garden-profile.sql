-- ============================================================================
-- Business Profile for the "Spice Garden Restaurant" tenant - the public
-- listing shell TenantProfileController serves (cover, gallery, description,
-- hours, amenities, contact, social links).
--
-- Run after scripts/seed-demo-data.ps1 or seed-spice-garden-sample-records.sql
-- (either creates the tenant). Same shape as the Asia Medihealth profile
-- block in seed-asia-medihealth-weligama.sql.
--
-- Spice Garden is a DEMO business: every value below is invented. Photos
-- are Unsplash stock images (the same source shared/businessImagery.ts uses
-- for its default covers). Re-runnable: it is a single UPDATE.
--
--   psql "$DATABASE_URL" -f scripts/seed-spice-garden-profile.sql
-- ============================================================================

BEGIN;

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM "Tenants"
   WHERE "Name" = 'Spice Garden Restaurant' AND lower("BusinessType") = 'restaurant';
  IF n = 0 THEN
    RAISE EXCEPTION 'Tenant "Spice Garden Restaurant" not found - run seed-demo-data.ps1 or seed-spice-garden-sample-records.sql first.';
  ELSIF n > 1 THEN
    RAISE EXCEPTION '% tenants are named "Spice Garden Restaurant" - pin one by Id in the WHERE clause.', n;
  END IF;
END $$;

-- BusinessType 'Restaurant' is the exact value in RegisterPage.tsx
-- BUSINESS_TYPES. BusinessHours is PascalCase on purpose - ParseBusinessHours
-- reads it back case-sensitively.
UPDATE "Tenants" SET
  "BusinessType" = 'Restaurant',
  "IsActive"     = true,

  "ShortTagline" = 'Sri Lankan seafood & curry on Marine Drive - dine in, takeaway or delivered',
  "Description"  = 'Spice Garden is a family-run restaurant on Marine Drive, Colombo 06, serving Sri Lankan seafood and rice & curry since 2012. The kitchen works from a daily catch off the Wellawatte boats and spices ground in-house; the menu runs from lunch rice & curry plates to grilled jumbo prawns, crab curry and a seven-curry vegetarian set. Eat on the sea-facing garden terrace or in the dining room, book the private room for up to ten, collect from the counter, or have it delivered across Colombo 03-06 by our own riders, Uber Eats or PickMe Food. Open every day for lunch and dinner.',

  "ContactPhone" = '+94112987654',
  "ContactEmail" = 'hello@spicegarden.lk',
  "Website"      = 'https://www.spicegarden.lk/',

  -- Cover: the default restaurant cover from shared/businessImagery.ts, so
  -- the hero looks the same before and after this profile is applied.
  "CoverImageUrl" = 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=1600&q=70&auto=format&fit=crop',
  -- Logo: a simple mark checked in at frontend/public/logos/spice-garden.svg, referenced by
  -- a root-relative URL so it resolves on localhost and in production alike
  -- (the dashboards show it as the business's profile picture). Replace it
  -- by uploading a real logo under Settings -> Business Profile.
  "LogoUrl"       = COALESCE("LogoUrl", '/logos/spice-garden.svg'),

  "GalleryImageUrls" = jsonb_build_array(
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=1600&q=70&auto=format&fit=crop',  -- dining room
      'https://images.unsplash.com/photo-1559339352-11d035aa65de?w=1600&q=70&auto=format&fit=crop',  -- terrace tables
      'https://images.unsplash.com/photo-1596797038530-2c107229654b?w=1600&q=70&auto=format&fit=crop', -- rice & curry
      'https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=1600&q=70&auto=format&fit=crop', -- curry bowls
      'https://images.unsplash.com/photo-1559847844-5315695dadae?w=1600&q=70&auto=format&fit=crop'   -- grilled seafood
  ),

  "SocialLinks" = jsonb_build_object(
      'facebook',  'https://www.facebook.com/spicegardencolombo',
      'instagram', 'https://www.instagram.com/spicegardencolombo',
      'whatsapp',  'https://wa.me/94112987654',
      'ubereats',  'https://www.ubereats.com/lk/store/spice-garden-restaurant',
      'pickme',    'https://food.pickme.lk/restaurant/spice-garden'
  ),

  -- Open daily 11:00-22:00, matching the resource schedules in the sample
  -- records seed (lunch 11-16, dinner 17-22; the kitchen runs through).
  "BusinessHours" = (
      SELECT jsonb_agg(jsonb_build_object(
               'DayOfWeek', d, 'OpenTime', '11:00', 'CloseTime', '22:00', 'IsClosed', false
             ) ORDER BY ord)
      FROM (VALUES
        ('Sunday',1),('Monday',2),('Tuesday',3),('Wednesday',4),
        ('Thursday',5),('Friday',6),('Saturday',7)
      ) AS x(d, ord)
  ),

  "Amenities" = jsonb_build_array(
      'Open 7 Days',
      'Sea-facing Garden Terrace',
      'Private Dining Room (10 seats)',
      'Takeaway Counter',
      'Home Delivery (Colombo 03-06)',
      'Uber Eats & PickMe Food',
      'Online Table Reservations',
      'Vegetarian & Vegan Curries',
      'Halal Kitchen',
      'Air-conditioned Dining Room',
      'Card & QR Payments',
      'Street Parking'
  ),

  "ProfileUpdatedAt" = now(),
  "UpdatedAt"        = now()
  -- "AverageRating" / "ReviewCount" intentionally NOT set - no reviews
  -- feature exists to compute them, and a made-up rating would show as real.
WHERE "Name" = 'Spice Garden Restaurant' AND lower("BusinessType") = 'restaurant';

COMMIT;

-- Check:
--   SELECT "Name","ShortTagline","ContactPhone","Website",
--          jsonb_array_length("GalleryImageUrls") AS photos,
--          jsonb_array_length("Amenities") AS amenities,
--          "BusinessHours"->0 AS sunday
--   FROM "Tenants" WHERE "Name" = 'Spice Garden Restaurant';
