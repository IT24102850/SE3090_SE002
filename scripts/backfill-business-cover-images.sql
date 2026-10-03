-- Fill only missing business profile covers for the public customer directory.
-- Existing uploaded images are preserved. These Unsplash URLs are stable
-- source images and can be replaced later with the business's own uploads.
UPDATE "Tenants"
SET "CoverImageUrl" = CASE
    WHEN lower("BusinessType") IN ('school', 'education')
      THEN 'https://images.unsplash.com/photo-1580582932707-520aed937b7b?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('clinic', 'healthcare', 'medical')
      THEN 'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('fitness', 'gym')
      THEN 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('restaurant', 'cafe', 'food')
      THEN 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('tourism', 'travel', 'adventure')
      THEN 'https://images.unsplash.com/photo-1500534623283-312aade485b7?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('realestate', 'real estate', 'property')
      THEN 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=1600&q=80&auto=format&fit=crop'
    WHEN lower("BusinessType") IN ('retail', 'shop', 'general')
      THEN 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=1600&q=80&auto=format&fit=crop'
    ELSE 'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=1600&q=80&auto=format&fit=crop'
  END
WHERE "IsActive" = TRUE
  AND NULLIF(trim("CoverImageUrl"), '') IS NULL;