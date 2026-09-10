import { describe, expect, it } from 'vitest';
import type { BookingType } from '../booking/types';
import {
  getProductCategory,
  isAddon,
  isTourOrPackage,
  parseProductConfig,
  splitProducts,
} from './productCategory';

/* The config-key form, which is what ConfigJson.subType stores. Deliberately
 * not the exported WHALE_WATCHING_SUBTYPE constant - that is the
 * Tenant.SubType *label* ("Whale / dolphin watching"), and passing it to
 * splitProducts matches nothing. */
const WHALE_KEY = 'whaleWatching';

/* The category filter is what keeps a hotel-pickup add-on out of the
 * Packages & Tours section, and - more importantly - keeps a real tour from
 * vanishing into a section the operator never opens. */

function product(name: string, config?: Record<string, unknown>): BookingType {
  return {
    id: name,
    name,
    slug: name.toLowerCase().replace(/\s+/g, '-'),
    colorHex: '#000000',
    status: 'Active',
    defaultDurationMinutes: 240,
    requiresApproval: false,
    bufferMinutesBefore: 0,
    bufferMinutesAfter: 0,
    bookingUnit: 'Slot',
    configJson: config === undefined ? null : JSON.stringify(config),
  };
}

describe('getProductCategory', () => {
  it('reads an explicit category', () => {
    expect(getProductCategory(JSON.stringify({ category: 'tour' }))).toBe('tour');
    expect(getProductCategory(JSON.stringify({ category: 'package' }))).toBe('package');
    expect(getProductCategory(JSON.stringify({ category: 'addon' }))).toBe('addon');
  });

  it('defaults to tour when the key is missing', () => {
    // The backward-compatibility guarantee: every product written before
    // this convention existed keeps showing up under Packages & Tours.
    expect(getProductCategory(JSON.stringify({ subType: 'whaleWatching' }))).toBe('tour');
    expect(getProductCategory(null)).toBe('tour');
    expect(getProductCategory(undefined)).toBe('tour');
    expect(getProductCategory('')).toBe('tour');
  });

  it('defaults to tour for an unrecognised or malformed value', () => {
    // Never silently reclassify as addon: hiding a real product the
    // operator sells is a worse failure than showing one in the wrong place.
    expect(getProductCategory(JSON.stringify({ category: 'extras' }))).toBe('tour');
    expect(getProductCategory(JSON.stringify({ category: 42 }))).toBe('tour');
    expect(getProductCategory('{not json')).toBe('tour');
  });
});

describe('parseProductConfig', () => {
  it('returns an empty object rather than throwing on bad jsonb', () => {
    expect(parseProductConfig('{not json')).toEqual({});
    expect(parseProductConfig(null)).toEqual({});
    expect(parseProductConfig('"a string"')).toEqual({});
  });

  it('exposes the pricing block', () => {
    const config = parseProductConfig(
      JSON.stringify({ pricing: { adult: 7500, child: 4000, currency: 'LKR' } }),
    );
    expect(config.pricing?.adult).toBe(7500);
    expect(config.pricing?.currency).toBe('LKR');
  });
});

describe('isAddon / isTourOrPackage', () => {
  it('splits the two groups without overlap', () => {
    const tour = product('Whale Watching Tour', { category: 'tour' });
    const pkg = product('Tour + Lunch', { category: 'package' });
    const addon = product('Hotel Pickup', { category: 'addon' });

    expect(isTourOrPackage(tour)).toBe(true);
    expect(isTourOrPackage(pkg)).toBe(true);
    expect(isTourOrPackage(addon)).toBe(false);

    expect(isAddon(addon)).toBe(true);
    expect(isAddon(tour)).toBe(false);
    expect(isAddon(pkg)).toBe(false);
  });
});

describe('splitProducts', () => {
  const catalogue = [
    product('Whale Watching Tour', { subType: 'whaleWatching', category: 'tour' }),
    product('Sunset Dolphin Cruise', { subType: 'whaleWatching', category: 'tour' }),
    product('Tour + Lunch + Transfer', { subType: 'whaleWatching', category: 'package' }),
    product('Hotel Pickup', { subType: 'whaleWatching', category: 'addon' }),
    product('Photo Package', { subType: 'whaleWatching', category: 'addon' }),
    product('Legacy Untagged Tour'),
  ];

  it('puts add-ons only in the add-ons list', () => {
    const { tours, addons } = splitProducts(catalogue, WHALE_KEY);

    expect(addons.map((p) => p.name)).toEqual(['Hotel Pickup', 'Photo Package']);
    expect(tours.map((p) => p.name)).not.toContain('Hotel Pickup');
    expect(tours.map((p) => p.name)).not.toContain('Photo Package');
  });

  it('groups tours and packages together', () => {
    const { tours } = splitProducts(catalogue, WHALE_KEY);

    expect(tours.map((p) => p.name)).toEqual([
      'Whale Watching Tour',
      'Sunset Dolphin Cruise',
      'Tour + Lunch + Transfer',
      'Legacy Untagged Tour',
    ]);
  });

  it('keeps every product accounted for exactly once', () => {
    const { tours, addons } = splitProducts(catalogue, WHALE_KEY);
    expect(tours.length + addons.length).toBe(catalogue.length);
  });

  it('excludes products belonging to another sub-type', () => {
    const mixed = [
      ...catalogue,
      product('PADI Open Water Course', { subType: 'diving', category: 'tour' }),
    ];
    const { tours, addons } = splitProducts(mixed, WHALE_KEY);

    expect([...tours, ...addons].map((p) => p.name)).not.toContain('PADI Open Water Course');
  });

  it('includes untagged products rather than hiding them', () => {
    // A product with no subType is still this tenant's product; dropping it
    // would make it invisible everywhere on the dashboard.
    const { tours } = splitProducts([product('Untagged')], WHALE_KEY);
    expect(tours.map((p) => p.name)).toEqual(['Untagged']);
  });

  it('matches on the config key, not the tenant label', () => {
    // The regression guard for the label/key mix-up that emptied both
    // dashboard sections: every product is tagged "whaleWatching", so
    // passing the human-readable Tenant.SubType matches none of them.
    const { tours, addons } = splitProducts(catalogue, 'Whale / dolphin watching');
    expect(tours.map((p) => p.name)).toEqual(['Legacy Untagged Tour']);
    expect(addons).toHaveLength(0);
  });

  it('handles an undefined product list', () => {
    expect(splitProducts(undefined, WHALE_KEY)).toEqual({ tours: [], addons: [] });
  });
});
