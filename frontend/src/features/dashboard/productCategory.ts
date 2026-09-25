import type { BookingType } from '../booking/types';

/* The `category` convention on BookingType.ConfigJson.
 *
 * ConfigJson already distinguishes which *kind of business* a product
 * belongs to (`subType`); this adds which *kind of product* it is, so a
 * whale-watching operator's dashboard can separate the trips it sells from
 * the extras it attaches to them.
 *
 * Purely additive jsonb - no migration, and every product written before
 * this key existed still resolves (to "tour", see below). */

export type ProductCategory = 'tour' | 'package' | 'addon';

export const PRODUCT_CATEGORIES: ProductCategory[] = ['tour', 'package', 'addon'];

export const PRODUCT_CATEGORY_LABELS: Record<ProductCategory, string> = {
  tour: 'Tour',
  package: 'Package',
  addon: 'Add-on',
};

/** Parsed shape of the ConfigJson keys the dashboard reads. Everything is
 *  optional: these are operator-authored config columns, not a schema. */
export interface ProductConfig {
  subType?: string;
  category?: string;
  /** The operator's own emoji for this product, where their site uses one. */
  icon?: string;
  includes?: string[];
  /** Age bands the operator publishes alongside each rate, e.g. adult 12+. */
  agePolicy?: { adultFromAge?: number; childUnderAge?: number };
  bookingUnit?: string;
  pricing?: { adult?: number; child?: number; infant?: number; currency?: string };
  seasonalPricing?: unknown[];
  capacity?: number;
  durationMinutes?: number;
}

/** Parses BookingType.configJson. Returns {} for null/blank/malformed JSON
 *  so one bad row degrades a single card rather than the whole section. */
export function parseProductConfig(configJson?: string | null): ProductConfig {
  if (!configJson) return {};
  try {
    const parsed = JSON.parse(configJson);
    return parsed && typeof parsed === 'object' ? (parsed as ProductConfig) : {};
  } catch {
    return {};
  }
}

/**
 * The product kind for a booking type.
 *
 * Defaults to "tour" when the key is absent or unrecognised, which is the
 * deliberate fallback: every product that predates this convention is a
 * thing the operator sells as a trip, and showing it under Packages & Tours
 * is right. Defaulting to "addon" would instead hide existing products in a
 * section the operator has never looked at.
 */
export function getProductCategory(configJson?: string | null): ProductCategory {
  const raw = parseProductConfig(configJson).category;
  return PRODUCT_CATEGORIES.includes(raw as ProductCategory) ? (raw as ProductCategory) : 'tour';
}

/** True for the products that belong under Services & Add-ons. */
export function isAddon(bookingType: Pick<BookingType, 'configJson'>): boolean {
  return getProductCategory(bookingType.configJson) === 'addon';
}

/** True for the products that belong under Packages & Tours - i.e. anything
 *  that is not an add-on, tours and packages alike. */
export function isTourOrPackage(bookingType: Pick<BookingType, 'configJson'>): boolean {
  return !isAddon(bookingType);
}

/** Splits a tenant's booking types into the two dashboard sections, keeping
 *  only the ones belonging to the given sub-type.
 *
 *  IMPORTANT: `subTypeKey` is the **config-key** form - `"whaleWatching"` -
 *  because that is what `BookingType.ConfigJson.subType` stores. It is NOT
 *  the `Tenant.SubType` label (`"Whale / dolphin watching"`). Passing the
 *  label matches nothing and silently empties both sections, which is
 *  exactly the bug this signature is named to prevent. Callers inside the
 *  dashboard should pass `config.subType` from the registry.
 *
 *  A product with no `subType` at all is included rather than dropped: a
 *  whale-watching tenant's own products are its own products whether or not
 *  someone remembered to tag them, and silently hiding them from the
 *  operator's dashboard would be worse than showing one too many. */
export function splitProducts(
  bookingTypes: BookingType[] | undefined,
  subTypeKey: string,
): { tours: BookingType[]; addons: BookingType[] } {
  const mine = (bookingTypes ?? []).filter((bt) => {
    const configured = parseProductConfig(bt.configJson).subType;
    return !configured || configured === subTypeKey;
  });

  return {
    tours: mine.filter(isTourOrPackage),
    addons: mine.filter(isAddon),
  };
}
