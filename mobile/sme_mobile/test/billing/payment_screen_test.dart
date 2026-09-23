import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/billing_models.dart';
import 'package:sme_mobile/providers/billing_providers.dart';
import 'package:sme_mobile/screens/billing/payment_flow_screen.dart';
import 'package:sme_mobile/services/payment_flow.dart';
import 'package:sme_mobile/services/payment_method_store.dart';

import 'fake_billing_repository.dart';

void main() {
  group('payment flow logic', () {
    const stripe = AvailableProviders([ProviderOption(provider: 'Stripe', name: 'Stripe')]);
    const none = AvailableProviders([]);

    test('card goes to Stripe when configured, otherwise the sandbox; cash never hits a gateway', () {
      expect(providerFor(PayMethod.card, stripe), 'Stripe');
      expect(providerFor(PayMethod.card, none), 'Manual');
      expect(providerFor(PayMethod.qr, stripe), 'Manual');
      expect(providerFor(PayMethod.cash, stripe), isNull);
    });

    test('a typed amount must be positive and within the balance', () {
      expect(validatePayAmount('', 100), isNull);
      expect(validatePayAmount('40', 100), isNull);
      expect(validatePayAmount('0', 100), contains('greater than 0'));
      expect(validatePayAmount('100.01', 100), contains('at most 100.00'));
      expect(amountToPay('', 100), 100);
      expect(amountToPay('25.5', 100), 25.5);
    });
  });

  group('PaymentFlowScreen', () {
    late FakeBillingRepository repo;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      repo = FakeBillingRepository();
    });

    Future<void> pumpScreen(WidgetTester tester, {Invoice? invoice}) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          billingRepositoryProvider.overrideWithValue(repo),
          paymentMethodStoreProvider.overrideWithValue(PaymentMethodStore(userId: 'test-user')),
        ],
        child: MaterialApp(home: PaymentFlowScreen(invoice: invoice ?? FakeBillingRepository.sampleInvoice())),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('offers card, QR and cash, with card selected first', (tester) async {
      await pumpScreen(tester);

      expect(find.text('LKR 4,500.00'), findsOneWidget);
      expect(find.byKey(const Key('method-card')), findsOneWidget);
      expect(find.byKey(const Key('method-qr')), findsOneWidget);
      expect(find.byKey(const Key('method-cash')), findsOneWidget);
      expect(find.text('Pay LKR 4,500.00'), findsOneWidget);
    });

    testWidgets('QR payment: choose method -> checkout -> QR code -> confirm -> success', (tester) async {
      await pumpScreen(tester);

      await tapAndSettle(tester, find.byKey(const Key('method-qr')));
      await tapAndSettle(tester, find.byKey(const Key('pay-button')));

      expect(repo.checkouts.single, containsPair('method', 'QR'));
      expect(repo.checkouts.single, containsPair('provider', 'Manual'));
      expect(find.byKey(const Key('payment-qr')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('complete-payment')));

      expect(repo.confirmations.single, ('pay-0', false));
      expect(find.text('Payment received - your receipt is ready.'), findsOneWidget);
      expect(find.text('View receipt'), findsOneWidget);
    });

    testWidgets('a declined payment says so and offers another try', (tester) async {
      await pumpScreen(tester);

      await tapAndSettle(tester, find.byKey(const Key('pay-button')));
      await tapAndSettle(tester, find.byKey(const Key('simulate-decline')));

      expect(repo.confirmations.single.$2, isTrue);
      expect(find.textContaining('did not go through'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('pays part of the balance when an amount is typed', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(const Key('amount-field')), '1500');
      await tester.pump();
      expect(find.text('Pay LKR 1,500.00'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('pay-button')));
      expect(repo.checkouts.single['amount'], 1500);
    });

    testWidgets('refuses an amount above the balance', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byKey(const Key('amount-field')), '9000');
      await tester.pump();

      expect(find.textContaining('at most 4500.00'), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('pay-button')));
      expect(repo.checkouts, isEmpty);
    });

    testWidgets('cash shows counter instructions without starting a checkout', (tester) async {
      await pumpScreen(tester);

      await tapAndSettle(tester, find.byKey(const Key('method-cash')));
      await tapAndSettle(tester, find.byKey(const Key('pay-button')));

      expect(find.byKey(const Key('cash-instructions')), findsOneWidget);
      expect(repo.checkouts, isEmpty);
    });

    testWidgets('"remember this method" saves it to secure storage', (tester) async {
      await pumpScreen(tester);

      await tapAndSettle(tester, find.byKey(const Key('method-qr')));
      await tapAndSettle(tester, find.byKey(const Key('remember-method')));
      await tapAndSettle(tester, find.byKey(const Key('pay-button')));

      final saved = await PaymentMethodStore(userId: 'test-user').load();
      expect(saved.single.type, 'QR');
      expect(saved.single.isDefault, isTrue);
    });
  });
}
