import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/public_tenant_model.dart';
import 'package:sme_mobile/providers/public_tenant_provider.dart';
import 'package:sme_mobile/screens/customer/book_business_list_screen.dart';
import 'package:sme_mobile/widgets/ui/glass_card.dart';

void main() {
  testWidgets('customer can select a business for shopping', (tester) async {
    const business = PublicTenant(
      id: 'business-1',
      businessName: 'Town Pantry',
      businessType: 'Retail',
    );
    String? selectedBusinessId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicTenantsProvider.overrideWith((ref) async => [business]),
        ],
        child: MaterialApp(
          home: BookBusinessListScreen(
            onBusinessSelected: (tenant) async {
              selectedBusinessId = tenant.id;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('Town Pantry'),
        matching: find.byType(GlassCard),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shop this business'), findsOneWidget);

    await tester.tap(find.text('Shop this business'));
    await tester.pumpAndSettle();

    expect(selectedBusinessId, business.id);
    expect(tester.takeException(), isNull);
  });
}
