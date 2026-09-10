/* The shape of one tourism sub-type's dashboard definition.
 *
 * This is the React mirror of mobile's
 * lib/models/subtype_dashboard_config.dart, extended with the pieces an
 * *admin* dashboard needs that a customer app does not: KPI definitions,
 * resource table columns, and which shared operational modules apply.
 *
 * The renderer is shared; only these configs differ between a dive centre's
 * dashboard and a homestay's. */

import type { BookingUnit, TourismSubType } from './tourismSubTypes';

export type BookingFieldType =
  | 'dropdown'
  | 'numberStepper'
  | 'checkbox'
  | 'fileUpload'
  | 'textArea'
  | 'text'
  | 'date';

/** One extra field the booking form collects for this sub-type. The key
 *  matches what is written into Booking.FormData, so it must stay in step
 *  with the mobile registry's BookingFormField keys for shared ones. */
export interface BookingFormField {
  key: string;
  label: string;
  type: BookingFieldType;
  options?: string[];
  /** Shown under the field - why the operator is asking. */
  hint?: string;
}

/** One field on a resource card, e.g. "120 seats". `key` is looked up in
 *  Resource.CustomAttributes first, then on the Resource row itself. */
export interface ResourceCardField {
  key: string;
  icon: string;
  /** "{value} divers max" - {value} is substituted. */
  labelTemplate: string;
}

/** How a KPI card gets its number.
 *  - `bookings`  : derived client-side from the bookings already loaded.
 *  - `excursion` : a field on GET /api/reports/excursions/kpis.
 *  - `resources` : derived from the resource list.
 *  A card whose source has no data renders an em dash, never a fabricated
 *  zero that would read as a real measurement. */
export type KpiSource = 'bookings' | 'excursion' | 'resources';

export interface KpiDefinition {
  id: string;
  label: string;
  source: KpiSource;
  /** The field to read for `excursion`, or the derivation for the others. */
  field: string;
  format?: 'number' | 'percent' | 'currency';
  sub?: string;
  tone?: 'default' | 'good' | 'warning' | 'critical';
}

/** A sidebar entry renamed for this sub-type, keyed by route path.
 *  Only the label and icon change - never the path - so
 *  scripts/check-nav-parity.mjs still matches every route. */
export interface NavOverride {
  label: string;
  icon?: string;
}

/** A column in the sub-type's resource table. */
export interface ResourceColumn {
  key: string;
  label: string;
}

/** Which shared operational modules this sub-type gets. Only whaleWatching
 *  turns on the full departure-operations set in this iteration; the others
 *  declare what they need so the modules can be extended to them without
 *  touching the renderer. */
export interface SubtypeModules {
  /** Weather / sea-state console and weather badge. */
  weather: boolean;
  /** Departure operations board + manifest + check-in. */
  departures: boolean;
  /** Wildlife sightings log and success-rate analytics. */
  sightings: boolean;
  /** Safety equipment expiry + pre-departure checklist. */
  safety: boolean;
  /** Bookings route through an approval step. */
  approvals: boolean;
  /** Per-ticket-type (adult/child/infant) pricing in the booking form. */
  ticketTypes: boolean;
}

export interface SubtypeDashboardConfig {
  subType: TourismSubType | 'generic';
  /** Tenant.SubType label, or a generic heading for the fallback. */
  label: string;
  bookingUnit: BookingUnit;

  /* Terminology. Every admin label in the dashboard is driven from these,
   * so "Resources" becomes "Vessels & Departures" for whale watching and
   * "Rooms" for a homestay without a single conditional in the renderer. */
  resourceTermSingular: string;
  resourceTermPlural: string;
  bookingTermSingular: string;
  bookingTermPlural: string;
  equipmentTerm: string;
  heroActionLabel: string;

  icon: string;
  /** CSS colour for the sub-type accent. */
  themeColor: string;

  /** Sidebar renames for this sub-type, keyed by route path. Anything not
   *  listed keeps its default label; omit the field entirely and the
   *  sidebar falls back to the resource/booking/equipment terms above. */
  navOverrides?: Record<string, NavOverride>;

  kpis: KpiDefinition[];
  resourceColumns: ResourceColumn[];
  cardFields: ResourceCardField[];
  bookingFormFields: BookingFormField[];
  modules: SubtypeModules;
}

/** Every module off - the starting point for a sub-type that only needs
 *  terminology and KPIs. */
export const NO_MODULES: SubtypeModules = {
  weather: false,
  departures: false,
  sightings: false,
  safety: false,
  approvals: false,
  ticketTypes: false,
};
