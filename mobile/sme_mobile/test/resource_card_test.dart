import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/tourism_subtype.dart';
import 'package:sme_mobile/registry/tourism_dashboard_registry.dart';
import 'package:sme_mobile/widgets/resource_card.dart';

void main() {
  testWidgets('renders only the cardFields present in the resource data', (tester) async {
    // Diving's config declares two cardFields: capacity and depth.
    final config = TourismDashboardRegistry.configFor(TourismSubType.diving);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResourceCard(
          // Deliberately omits 'depth' - only 'capacity' is present.
          resource: const {'name': 'Reef Explorer', 'capacity': 8},
          config: config,
          onBook: () {},
        ),
      ),
    ));

    expect(find.textContaining('divers max'), findsOneWidget);
    expect(find.textContaining('Max depth'), findsNothing);
  });

  testWidgets('renders all cardFields when all are present', (tester) async {
    final config = TourismDashboardRegistry.configFor(TourismSubType.diving);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResourceCard(
          resource: const {'name': 'Wreck Diver', 'capacity': 6, 'depth': 30},
          config: config,
          onBook: () {},
        ),
      ),
    ));

    expect(find.textContaining('divers max'), findsOneWidget);
    expect(find.textContaining('Max depth 30m'), findsOneWidget);
  });

  testWidgets('shows the weather badge only when config.showWeatherBadge is true', (tester) async {
    final divingConfig = TourismDashboardRegistry.configFor(TourismSubType.diving); // showWeatherBadge: true
    final accommodationConfig = TourismDashboardRegistry.configFor(TourismSubType.accommodation); // false

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ResourceCard(resource: const {'name': 'A'}, config: divingConfig, onBook: () {}),
            ResourceCard(resource: const {'name': 'B'}, config: accommodationConfig, onBook: () {}),
          ],
        ),
      ),
    ));

    expect(find.text('Weather dependent'), findsOneWidget);
  });
}
