import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/tourism_subtype.dart';

void main() {
  group('TourismSubTypeParsing.fromConfigString', () {
    test('throws a clear ArgumentError on an unrecognized string, not a silent default', () {
      expect(
        () => TourismSubTypeParsing.fromConfigString('not-a-real-subtype'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('not-a-real-subtype'))),
      );
    });

    test('parses every known registry key without throwing', () {
      const known = [
        'diving', 'safari', 'whaleWatching', 'surfSchool', 'trekking', 'culturalTour',
        'multiDayPackage', 'accommodation', 'villaHotel', 'vehicleRental', 'wellness', 'cyclingTour',
      ];
      for (final value in known) {
        expect(() => TourismSubTypeParsing.fromConfigString(value), returnsNormally, reason: value);
      }
    });
  });

  group('TourismSubTypeParsing.fromTenantSubType', () {
    test('maps Tenant.SubType\'s human-readable strings onto the enum', () {
      expect(TourismSubTypeParsing.fromTenantSubType('Water sports / diving'), TourismSubType.diving);
      expect(TourismSubTypeParsing.fromTenantSubType('Accommodation'), TourismSubType.accommodation);
      expect(TourismSubTypeParsing.fromTenantSubType('Villa / Hotel'), TourismSubType.villaHotel);
      expect(TourismSubTypeParsing.fromTenantSubType('Vehicle rental / transport'), TourismSubType.vehicleRental);
    });

    test('returns null (not throw) for null or unrecognized input, so legacy tenants fall back gracefully', () {
      expect(TourismSubTypeParsing.fromTenantSubType(null), isNull);
      expect(TourismSubTypeParsing.fromTenantSubType('Something Unrecognized'), isNull);
    });
  });
}
