import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/billing_models.dart';
import 'package:sme_mobile/providers/billing_providers.dart';
import 'package:sme_mobile/screens/billing/insurance_tracker_screen.dart';
import 'package:sme_mobile/screens/billing/my_bills_screen.dart';

import 'fake_billing_repository.dart';

void main() {
  Future<void> pumpBills(WidgetTester tester, FakeBillingRepository repo) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [billingRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: MyBillsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('lists open bills with their status and the total owed', (tester) async {
    await pumpBills(tester, FakeBillingRepository(invoices: [
      FakeBillingRepository.sampleInvoice(id: 'a', number: 'INV-A', total: 3000),
      FakeBillingRepository.sampleInvoice(id: 'b', number: 'INV-B', total: 1500, status: 'Overdue', overdue: true),
      FakeBillingRepository.sampleInvoice(id: 'c', number: 'INV-C', total: 800, status: 'Paid', paid: 800),
    ]));

    expect(find.text('INV-A'), findsOneWidget);
    expect(find.text('INV-B'), findsOneWidget);
    expect(find.text('INV-C'), findsNothing); // paid bills are on the Paid tab
    expect(tester.widget<Text>(find.byKey(const Key('total-owed'))).data, 'LKR 4,500.00');
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('the Paid tab shows settled bills', (tester) async {
    await pumpBills(tester, FakeBillingRepository(invoices: [
      FakeBillingRepository.sampleInvoice(id: 'c', number: 'INV-C', total: 800, status: 'Paid', paid: 800),
    ]));

    expect(find.text('You are all paid up.'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Paid'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('INV-C'), findsOneWidget);
    expect(find.text('Paid in full'), findsOneWidget);
  });

  test('bill states map to Paid / Pending / Overdue', () {
    expect(FakeBillingRepository.sampleInvoice(status: 'Paid', paid: 4500).billState, 'Paid');
    expect(FakeBillingRepository.sampleInvoice(status: 'PartiallyPaid', paid: 100).billState, 'Pending');
    expect(FakeBillingRepository.sampleInvoice(overdue: true).billState, 'Overdue');
  });

  testWidgets('claim progress marks the stage a claim has reached', (tester) async {
    Future<void> show(String status, {String? reason}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ClaimProgress(
            claim: InsuranceClaim(id: 'c', provider: 'AIA', policyNumber: 'AIA-1', claimAmount: 100, status: status, rejectionReason: reason),
          ),
        ),
      ));
    }

    await show('Submitted');
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);

    await show('UnderReview');
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await show('Rejected', reason: 'Not covered');
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
  });
}
