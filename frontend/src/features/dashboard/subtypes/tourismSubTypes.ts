/* The tourism sub-type vocabulary, mirroring
 * mobile/sme_mobile/lib/models/tourism_subtype.dart one-for-one.
 *
 * Three separate namings exist and are deliberately kept distinct:
 *   - TourismSubType      - the code-level key ("whaleWatching"), also what
 *                           BookingType.ConfigJson.subType stores, so the
 *                           Flutter app and this file agree on the string.
 *   - Tenant.SubType      - the human-readable label picked at registration
 *                           ("Whale / dolphin watching"), the only one
 *                           actually persisted on the tenant row.
 *   - the display label   - the same string, reused.
 *
 * Adding a sub-type means adding one entry here and one config in
 * subtypeRegistry.tsx. Nothing else changes.
 */

export const TOURISM_SUB_TYPE_KEYS = [
  'diving',
  'safari',
  'whaleWatching',
  'surfSchool',
  'trekking',
  'culturalTour',
  'multiDayPackage',
  'accommodation',
  'villaHotel',
  'vehicleRental',
  'wellness',
  'cyclingTour',
] as const;

export type TourismSubType = (typeof TOURISM_SUB_TYPE_KEYS)[number];

/* The exact Tenant.SubType strings, in the same order and spelling as
 * frontend/src/features/booking/types.ts TOURISM_SUB_TYPES and mobile's
 * kTourismSubTypeLabels. These are matched literally, so a change here
 * without a change there silently drops a tenant to the generic dashboard. */
export const TOURISM_SUB_TYPE_LABELS: Record<TourismSubType, string> = {
  diving: 'Water sports / diving',
  safari: 'Safari / wildlife',
  whaleWatching: 'Whale / dolphin watching',
  surfSchool: 'Surf schools',
  trekking: 'Hiking / trekking / adventure',
  culturalTour: 'Cultural / heritage tours',
  multiDayPackage: 'Multi-day packages',
  accommodation: 'Accommodation',
  villaHotel: 'Villa / Hotel',
  vehicleRental: 'Vehicle rental / transport',
  wellness: 'Wellness / Ayurveda',
  cyclingTour: 'Cycling tours',
};

const LABEL_TO_KEY: Record<string, TourismSubType> = Object.fromEntries(
  TOURISM_SUB_TYPE_KEYS.map((key) => [TOURISM_SUB_TYPE_LABELS[key], key]),
) as Record<string, TourismSubType>;

/* Resolves a Tenant.SubType string onto the registry's key.
 *
 * Returns null rather than throwing for a tenant with no SubType (seeded
 * before the column existed), an unrecognised value, or a non-tourism
 * business - all three mean "render the generic dashboard", which is the
 * same contract as mobile's TourismSubTypeParsing.fromTenantSubType. */
export function parseTenantSubType(value?: string | null): TourismSubType | null {
  if (!value) return null;
  return LABEL_TO_KEY[value.trim()] ?? null;
}

/* Resolves the code-level key stored in BookingType.ConfigJson.subType. */
export function parseConfigSubType(value?: string | null): TourismSubType | null {
  if (!value) return null;
  return (TOURISM_SUB_TYPE_KEYS as readonly string[]).includes(value)
    ? (value as TourismSubType)
    : null;
}

/* The 4 booking-unit patterns, matching the backend's
 * BookingType.BookingUnit column and mobile's BookingUnit enum. */
export type BookingUnit = 'slot' | 'night' | 'dateRange' | 'package';
