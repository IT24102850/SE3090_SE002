/* Photographic identity for a tenant, keyed to what the business actually
   does. Used by the dashboard hero.
 *
 * Precedence is deliberate:
 *   1. the tenant's own cover image (Business Profile -> CoverImageUrl),
 *   2. its Tourism sub-type, which is far more specific than "Tourism",
 *   3. its business type,
 *   4. a generic fallback.
 *
 * The URLs are Unsplash CDN links with explicit width/quality parameters, so
 * they are cheap and cache well. Every id below was checked to return 200;
 * the five marked (seen) were also opened and confirmed to show the subject.
 * If a link ever rots the hero degrades to the scrim gradient alone, which
 * still reads correctly — nothing depends on the image loading. */

const UNSPLASH = (id: string, w = 1600) =>
  `https://images.unsplash.com/photo-${id}?w=${w}&q=70&auto=format&fit=crop`;

/** Tourism sub-type -> image. Keys are the exact TOURISM_SUB_TYPES strings. */
const SUB_TYPE_IMAGE: Record<string, string> = {
  'Water sports / diving': UNSPLASH('1544551763-46a013bb70d5'),
  'Safari / wildlife': UNSPLASH('1516426122078-c23e76319801'),
  'Whale / dolphin watching': UNSPLASH('1518877593221-1f28583780b4'), // (seen)
  'Surf schools': UNSPLASH('1502680390469-be75c86b636f'), // (seen)
  'Hiking / trekking / adventure': UNSPLASH('1551632811-561732d1e306'),
  'Cultural / heritage tours': UNSPLASH('1524492412937-b28074a5d7da'),
  'Multi-day packages': UNSPLASH('1476514525535-07fb3b4ae5f1'),
  'Accommodation': UNSPLASH('1566073771259-6a8506099945'),
  'Villa / Hotel': UNSPLASH('1613490493576-7fde63acd811'), // (seen)
  'Vehicle rental / transport': UNSPLASH('1449965408869-eaa3f722e40d'),
  'Wellness / Ayurveda': UNSPLASH('1540555700478-4be289fbecef'),
  'Cycling tours': UNSPLASH('1541625602330-2277a4c46182'),
};

const BUSINESS_TYPE_IMAGE: Record<string, string> = {
  Clinic: UNSPLASH('1519494026892-80bbd2d6fd0d'),
  Restaurant: UNSPLASH('1517248135467-4c7edcad34c4'),
  Gym: UNSPLASH('1534438327276-14e5300c3a48'),
  School: UNSPLASH('1580582932707-520aed937b7b'), // (seen)
  RealEstate: UNSPLASH('1560518883-ce09059eeffa'),
  Tourism: UNSPLASH('1507525428034-b723cf961d3e'),
  General: UNSPLASH('1497366216548-37526070297c'),
};

const FALLBACK = BUSINESS_TYPE_IMAGE.General;

export interface BusinessImageInput {
  businessType?: string | null;
  subType?: string | null;
  coverImageUrl?: string | null;
}

/** The hero background for a tenant. Never returns empty. */
export function businessHeroImage({ businessType, subType, coverImageUrl }: BusinessImageInput): string {
  if (coverImageUrl) return coverImageUrl;
  if (subType && SUB_TYPE_IMAGE[subType]) return SUB_TYPE_IMAGE[subType];
  if (businessType && BUSINESS_TYPE_IMAGE[businessType]) return BUSINESS_TYPE_IMAGE[businessType];
  return FALLBACK;
}

/** Short line describing what the tenant does, for the hero eyebrow. */
export function businessDescriptor({ businessType, subType }: BusinessImageInput): string {
  if (subType) return subType;
  if (businessType) return businessType;
  return 'Business';
}
