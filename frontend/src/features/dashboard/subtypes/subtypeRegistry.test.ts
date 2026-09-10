import { describe, expect, it } from 'vitest';
import { ALL_SUBTYPE_CONFIGS, GENERIC_CONFIG, getSubtypeConfig } from './subtypeRegistry';
import {
  TOURISM_SUB_TYPE_KEYS,
  TOURISM_SUB_TYPE_LABELS,
  parseConfigSubType,
  parseTenantSubType,
} from './tourismSubTypes';
import { TOURISM_SUB_TYPES } from '../../booking/types';

/* Registry resolution is the load-bearing part of the whole feature: get it
 * wrong and either everybody drops to the generic dashboard, or a tenant
 * sees somebody else's terminology. */

describe('tenant sub-type resolution', () => {
  it('resolves whale watching to its own config', () => {
    const subType = parseTenantSubType('Whale / dolphin watching');
    expect(subType).toBe('whaleWatching');

    const config = getSubtypeConfig(subType);
    expect(config.subType).toBe('whaleWatching');
    expect(config.resourceTermSingular).toBe('Departure');
    expect(config.resourceTermPlural).toBe('Departures');
    expect(config.heroActionLabel).toBe("Manage today's departures");
    expect(config.modules.departures).toBe(true);
    expect(config.modules.weather).toBe(true);
    expect(config.modules.sightings).toBe(true);
    expect(config.modules.safety).toBe(true);
    expect(config.modules.ticketTypes).toBe(true);
  });

  it('falls back to the generic config for an unset or unknown sub-type', () => {
    // All four of these mean "render the dashboard that was already there".
    expect(parseTenantSubType(null)).toBeNull();
    expect(parseTenantSubType(undefined)).toBeNull();
    expect(parseTenantSubType('')).toBeNull();
    expect(parseTenantSubType('Dentistry')).toBeNull();

    for (const value of [null, undefined, '', 'Dentistry']) {
      expect(getSubtypeConfig(parseTenantSubType(value))).toBe(GENERIC_CONFIG);
    }
  });

  it('leaves the generic config with no operational modules on', () => {
    // The guarantee that a clinic or a restaurant sees no departure board,
    // no weather console and no ticket-type field.
    expect(Object.values(GENERIC_CONFIG.modules).every((v) => v === false)).toBe(true);
    expect(GENERIC_CONFIG.resourceTermPlural).toBe('Resources');
    expect(GENERIC_CONFIG.bookingTermPlural).toBe('Bookings');
  });

  it('resolves every one of the 12 tourism sub-types', () => {
    for (const key of TOURISM_SUB_TYPE_KEYS) {
      const label = TOURISM_SUB_TYPE_LABELS[key];
      expect(parseTenantSubType(label)).toBe(key);
      expect(getSubtypeConfig(key).subType).toBe(key);
    }
  });

  it('tolerates surrounding whitespace on the stored label', () => {
    expect(parseTenantSubType('  Whale / dolphin watching  ')).toBe('whaleWatching');
  });

  it('is case-sensitive, matching the mobile registry exactly', () => {
    // Deliberate: the label is a stored enum value, not user prose. Loose
    // matching here would diverge from mobile's fromTenantSubType.
    expect(parseTenantSubType('whale / dolphin watching')).toBeNull();
  });
});

describe('config sub-type keys (BookingType.ConfigJson.subType)', () => {
  it('round-trips every registry key', () => {
    for (const key of TOURISM_SUB_TYPE_KEYS) {
      expect(parseConfigSubType(key)).toBe(key);
    }
  });

  it('returns null for anything unrecognised', () => {
    expect(parseConfigSubType('WildlifeExcursion')).toBeNull();
    expect(parseConfigSubType(null)).toBeNull();
  });
});

describe('registry completeness', () => {
  it('has a config for every key, with no orphans', () => {
    expect(Object.keys(ALL_SUBTYPE_CONFIGS).sort()).toEqual([...TOURISM_SUB_TYPE_KEYS].sort());
  });

  it('keeps its labels identical to the registration dropdown', () => {
    // TOURISM_SUB_TYPES drives the sign-up form; if the two ever diverge, a
    // tenant registers with a label the registry cannot resolve and silently
    // gets the generic dashboard. This test is what stops that.
    expect(Object.values(TOURISM_SUB_TYPE_LABELS)).toEqual(TOURISM_SUB_TYPES);
  });

  it('gives every sub-type terminology, KPIs and a booking unit', () => {
    for (const key of TOURISM_SUB_TYPE_KEYS) {
      const config = ALL_SUBTYPE_CONFIGS[key];
      expect(config.label).toBe(TOURISM_SUB_TYPE_LABELS[key]);
      expect(config.resourceTermSingular.length).toBeGreaterThan(0);
      expect(config.resourceTermPlural.length).toBeGreaterThan(0);
      expect(config.bookingTermPlural.length).toBeGreaterThan(0);
      expect(config.equipmentTerm.length).toBeGreaterThan(0);
      expect(config.heroActionLabel.length).toBeGreaterThan(0);
      expect(['slot', 'night', 'dateRange', 'package']).toContain(config.bookingUnit);
      // The task specifies 4-6 KPI cards per sub-type.
      expect(config.kpis.length).toBeGreaterThanOrEqual(3);
      expect(config.resourceColumns.length).toBeGreaterThan(0);
    }
  });

  it('gives every KPI a unique id and a known source', () => {
    for (const key of TOURISM_SUB_TYPE_KEYS) {
      const kpis = ALL_SUBTYPE_CONFIGS[key].kpis;
      expect(new Set(kpis.map((k) => k.id)).size).toBe(kpis.length);
      for (const kpi of kpis) {
        expect(['bookings', 'excursion', 'resources']).toContain(kpi.source);
        expect(kpi.field.length).toBeGreaterThan(0);
      }
    }
  });

  it('gives every booking form field a unique key and options where it needs them', () => {
    for (const key of TOURISM_SUB_TYPE_KEYS) {
      const fields = ALL_SUBTYPE_CONFIGS[key].bookingFormFields;
      expect(new Set(fields.map((f) => f.key)).size).toBe(fields.length);
      for (const field of fields) {
        if (field.type === 'dropdown') {
          expect(field.options?.length ?? 0).toBeGreaterThan(0);
        }
      }
    }
  });

  it('only turns the departures module on for whale watching in this iteration', () => {
    const withDepartures = TOURISM_SUB_TYPE_KEYS.filter(
      (k) => ALL_SUBTYPE_CONFIGS[k].modules.departures,
    );
    expect(withDepartures).toEqual(['whaleWatching']);
  });

  it('turns the weather module on for the weather-dependent sub-types', () => {
    const withWeather = TOURISM_SUB_TYPE_KEYS.filter((k) => ALL_SUBTYPE_CONFIGS[k].modules.weather);
    expect(withWeather.sort()).toEqual(
      ['whaleWatching', 'diving', 'safari', 'surfSchool', 'trekking', 'cyclingTour'].sort(),
    );
  });

  it('shares the sightings module with safari, not just whale watching', () => {
    // SightingsLog is deliberately generic - a leopard sighting uses the
    // same table and the same success-rate maths as a blue whale.
    expect(ALL_SUBTYPE_CONFIGS.safari.modules.sightings).toBe(true);
    expect(ALL_SUBTYPE_CONFIGS.whaleWatching.modules.sightings).toBe(true);
  });

  it('always requires approval for multi-day packages', () => {
    expect(ALL_SUBTYPE_CONFIGS.multiDayPackage.modules.approvals).toBe(true);
    expect(ALL_SUBTYPE_CONFIGS.multiDayPackage.bookingUnit).toBe('package');
  });

  it('uses the right booking unit per archetype', () => {
    expect(ALL_SUBTYPE_CONFIGS.accommodation.bookingUnit).toBe('night');
    expect(ALL_SUBTYPE_CONFIGS.villaHotel.bookingUnit).toBe('night');
    expect(ALL_SUBTYPE_CONFIGS.vehicleRental.bookingUnit).toBe('dateRange');
    expect(ALL_SUBTYPE_CONFIGS.whaleWatching.bookingUnit).toBe('slot');
  });

  it('names the sub-type-specific booking fields the task specifies', () => {
    const keysFor = (k: keyof typeof ALL_SUBTYPE_CONFIGS) =>
      ALL_SUBTYPE_CONFIGS[k].bookingFormFields.map((f) => f.key);

    expect(keysFor('diving')).toEqual(
      expect.arrayContaining(['certificationLevel', 'divesLogged', 'medicalDeclaration']),
    );
    expect(keysFor('safari')).toEqual(
      expect.arrayContaining(['parkPreference', 'entranceFeeIncluded', 'hotelPickup']),
    );
    expect(keysFor('accommodation')).toEqual(expect.arrayContaining(['mealPlan', 'extraBed', 'airportTransfer']));
    expect(keysFor('vehicleRental')).toEqual(
      expect.arrayContaining(['licenseNumber', 'licensePhoto', 'withDriver']),
    );
    expect(keysFor('wellness')).toEqual(
      expect.arrayContaining(['treatmentType', 'therapistGenderPreference', 'healthConditions']),
    );
    expect(keysFor('cyclingTour')).toEqual(expect.arrayContaining(['riderHeightCm', 'supportVehicle']));
  });
});
