import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/public_tenant_model.dart';
import 'package:sme_mobile/models/resource_model.dart';
import 'package:sme_mobile/models/tenant_profile_model.dart';
import 'package:sme_mobile/models/tourism_subtype.dart';
import 'package:sme_mobile/providers/tenant_profile_provider.dart';
import 'package:sme_mobile/registry/tourism_dashboard_registry.dart';
import 'package:sme_mobile/screens/booking_dashboard_screen.dart';

void main() {
  const tenant = PublicTenant(id: 't1', businessName: 'Test Tourism Co', businessType: 'Tourism', subType: null);

  // BookingDashboardScreen now also reads tenantProfileProvider (Business
  // Profile header) - overridden here to a fixed value so these
  // pre-existing tests stay deterministic and don't hit the network.
  const fakeProfile = TenantProfile(
    tenantId: 't1',
    name: 'Test Tourism Co',
    businessType: 'Tourism',
    galleryImageUrls: [],
    amenities: [],
    socialLinks: {},
    businessHours: [],
    reviewCount: 0,
  );

  Future<void> pumpDashboard(
    WidgetTester tester,
    TourismSubType subType, {
    Future<List<Resource>> Function()? fetch,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tenantProfileProvider('t1').overrideWith((ref) async => fakeProfile)],
      child: MaterialApp(
        home: BookingDashboardScreen(
          tenant: tenant,
          address: null,
          subType: subType,
          fetchAvailableResources: fetch ?? () async => [],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('renders distinct dashboards per sub-type (proves registry lookup drives output)', () {
    for (final subType in [TourismSubType.diving, TourismSubType.accommodation, TourismSubType.vehicleRental]) {
      testWidgets('$subType: hero label and icon match the registry config', (tester) async {
        await pumpDashboard(tester, subType);
        final config = TourismDashboardRegistry.configFor(subType);

        expect(find.text(config.heroActionLabel), findsOneWidget);
        expect(find.byIcon(config.icon), findsWidgets);
      });
    }

    testWidgets('diving and accommodation render different hero labels', (tester) async {
      final divingConfig = TourismDashboardRegistry.configFor(TourismSubType.diving);
      final accommodationConfig = TourismDashboardRegistry.configFor(TourismSubType.accommodation);
      expect(divingConfig.heroActionLabel, isNot(equals(accommodationConfig.heroActionLabel)));

      await pumpDashboard(tester, TourismSubType.accommodation);
      expect(find.text(divingConfig.heroActionLabel), findsNothing);
      expect(find.text(accommodationConfig.heroActionLabel), findsOneWidget);
    });
  });

  testWidgets('empty state shows sub-type-aware text, not the old generic message', (tester) async {
    await pumpDashboard(tester, TourismSubType.diving);

    expect(find.text('No dive trips available right now.'), findsOneWidget);
    expect(find.text('Nothing available to book right now.'), findsNothing);
  });

  testWidgets('empty state text changes for a different sub-type', (tester) async {
    await pumpDashboard(tester, TourismSubType.accommodation);

    expect(find.text('No rooms available right now.'), findsOneWidget);
  });

  testWidgets('shows resource cards when fetchAvailableResources returns data', (tester) async {
    await pumpDashboard(
      tester,
      TourismSubType.diving,
      fetch: () async => [
        const Resource(
          id: 'r1',
          tenantId: 't1',
          name: 'Reef Explorer',
          category: 'Vehicle',
          status: 'Available',
          capacity: 8,
          customAttributes: '{"depth": 18}',
        ),
      ],
    );

    expect(find.text('Reef Explorer'), findsOneWidget);
    expect(find.text('No dive trips available right now.'), findsNothing);
  });

  testWidgets('shows an error state with retry when the fetch fails', (tester) async {
    await pumpDashboard(tester, TourismSubType.diving, fetch: () async => throw Exception('network down'));

    expect(find.text('Could not load availability. Pull down to retry.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
