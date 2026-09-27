import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/public_tenant_model.dart';
import 'package:sme_mobile/providers/public_tenant_provider.dart';
import 'package:sme_mobile/screens/customer/book_business_list_screen.dart';

/// The business grid sized its cards with childAspectRatio, which ties their
/// height to the column width. At two columns on a phone that left 70px for a
/// card whose icon well alone is 52px inside 28px of padding, and every card
/// in the list wore a "BOTTOM OVERFLOWED BY 10 PIXELS" stripe.
///
/// These pump the real screen at real phone widths and fail on any overflow,
/// so the card and the cell cannot drift apart again.
void main() {
  final tenants = List.generate(
    8,
    (i) => PublicTenant(
      id: 't$i',
      businessName: 'Mirissa JetLiner $i',
      businessType: i.isEven ? 'Tourism' : 'Healthcare',
    ),
  );

  Future<void> pumpAt(WidgetTester tester, Size size, {double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicTenantsProvider.overrideWith((ref) async => tenants),
        ],
        child: MaterialApp(
          // copyWith, not a fresh MediaQueryData: a bare one would drop the
          // size the test view just set and lay everything out at zero.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const BookBusinessListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cards fit their cell on a narrow phone', (tester) async {
    // The width from the report: two columns, 462 logical pixels.
    await pumpAt(tester, const Size(462, 740));

    expect(find.text('Mirissa JetLiner 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards fit on a very narrow phone', (tester) async {
    // Narrower still: with an aspect ratio this is where it got worse, because
    // a thinner column means a shorter card. A fixed height does not care.
    await pumpAt(tester, const Size(320, 640));

    expect(tester.takeException(), isNull);
  });

  testWidgets('cards fit on a tablet, where the grid goes to three columns',
      (tester) async {
    await pumpAt(tester, const Size(900, 700));

    expect(tester.takeException(), isNull);
  });

  testWidgets('cards grow for a reader using large text', (tester) async {
    // At 1.6x the name and type pill overtake the icon well, so the card has
    // to get taller rather than clip the text.
    await pumpAt(tester, const Size(462, 740), textScale: 1.6);

    expect(tester.takeException(), isNull);
  });
}
