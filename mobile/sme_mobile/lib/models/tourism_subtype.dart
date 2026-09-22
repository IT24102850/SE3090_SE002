/// The 12 tourism sub-types this platform supports. Adding another sub-type
/// later means adding one enum value + one registry entry - nothing else
/// in the app changes.
enum TourismSubType {
  diving,
  safari,
  whaleWatching,
  surfSchool,
  trekking,
  culturalTour,
  multiDayPackage,
  accommodation,
  villaHotel,
  vehicleRental,
  wellness,
  cyclingTour,
}

/// The 12 human-readable Tenant.SubType labels, in the exact order/spelling
/// TourismSubTypeParsing.fromTenantSubType expects. Single source of truth
/// for the "which type of tourism business" dropdown shown at registration
/// (mirrors frontend/src/features/booking/types.ts's TOURISM_SUB_TYPES).
const List<String> kTourismSubTypeLabels = [
  'Water sports / diving',
  'Safari / wildlife',
  'Whale / dolphin watching',
  'Surf schools',
  'Hiking / trekking / adventure',
  'Cultural / heritage tours',
  'Multi-day packages',
  'Accommodation',
  'Villa / Hotel',
  'Vehicle rental / transport',
  'Wellness / Ayurveda',
  'Cycling tours',
];

extension TourismSubTypeParsing on TourismSubType {
  /// Matches the string stored in BookingType.ConfigJson.subType
  static TourismSubType fromConfigString(String value) {
    switch (value) {
      case 'diving':
        return TourismSubType.diving;
      case 'safari':
        return TourismSubType.safari;
      case 'whaleWatching':
        return TourismSubType.whaleWatching;
      case 'surfSchool':
        return TourismSubType.surfSchool;
      case 'trekking':
        return TourismSubType.trekking;
      case 'culturalTour':
        return TourismSubType.culturalTour;
      case 'multiDayPackage':
        return TourismSubType.multiDayPackage;
      case 'accommodation':
        return TourismSubType.accommodation;
      case 'villaHotel':
        return TourismSubType.villaHotel;
      case 'vehicleRental':
        return TourismSubType.vehicleRental;
      case 'wellness':
        return TourismSubType.wellness;
      case 'cyclingTour':
        return TourismSubType.cyclingTour;
      default:
        throw ArgumentError('Unknown tourism subType: $value');
    }
  }

  // Maps Tenant.SubType's human-readable strings (set at business
  // registration - see frontend/src/features/booking/types.ts's
  // TOURISM_SUB_TYPES and mobile RegisterScreen) onto this registry's enum.
  // Returns null rather than throwing for tenants with no SubType set yet
  // (e.g. seeded before this field existed) or an unrecognized value, so
  // callers can fall back to the generic resource list instead of crashing.
  static TourismSubType? fromTenantSubType(String? value) {
    switch (value) {
      case 'Water sports / diving':
        return TourismSubType.diving;
      case 'Safari / wildlife':
        return TourismSubType.safari;
      case 'Whale / dolphin watching':
        return TourismSubType.whaleWatching;
      case 'Surf schools':
        return TourismSubType.surfSchool;
      case 'Hiking / trekking / adventure':
        return TourismSubType.trekking;
      case 'Cultural / heritage tours':
        return TourismSubType.culturalTour;
      case 'Multi-day packages':
        return TourismSubType.multiDayPackage;
      case 'Accommodation':
        return TourismSubType.accommodation;
      case 'Villa / Hotel':
        return TourismSubType.villaHotel;
      case 'Vehicle rental / transport':
        return TourismSubType.vehicleRental;
      case 'Wellness / Ayurveda':
        return TourismSubType.wellness;
      case 'Cycling tours':
        return TourismSubType.cyclingTour;
      default:
        return null;
    }
  }
}

/// The 4 booking-unit patterns from the backend design - unchanged, shared
/// across all 11 sub-types above. This enum matches ConfigJson.bookingUnit.
enum BookingUnit { slot, night, dateRange, package }
