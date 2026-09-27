import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/billing_models.dart';
import 'package:sme_mobile/providers/billing_providers.dart';
import 'package:sme_mobile/screens/billing/receipt_screen.dart';

import 'fake_billing_repository.dart';

class RecordingSharer implements ReceiptSharer {
  final pdfs = <(int, String, String)>[];
  final whatsApps = <String>[];
  final emails = <(String, String, String)>[];

  @override
  Future<void> sharePdf(Uint8List pdf, String fileName, String text) async => pdfs.add((pdf.length, fileName, text));

  @override
  Future<bool> whatsApp(String text) async {
    whatsApps.add(text);
    return true;
  }

  @override
  Future<bool> email(String to, String subject, String body) async {
    emails.add((to, subject, body));
    return true;
  }
}

void main() {
  late FakeBillingRepository repo;
  late RecordingSharer sharer;

  setUp(() {
    repo = FakeBillingRepository();
    sharer = RecordingSharer();
  });

  Future<void> pumpReceipt(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        billingRepositoryProvider.overrideWithValue(repo),
        receiptSharerProvider.overrideWithValue(sharer),
      ],
      child: const MaterialApp(home: ReceiptScreen(invoiceId: 'inv-1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows the business, customer, items, totals and payments', (tester) async {
    await pumpReceipt(tester);

    expect(find.text('Smile Dental'), findsOneWidget);
    expect(find.text('RECEIPT'), findsOneWidget);
    expect(find.text('REC-INV-20260923-ABC123'), findsOneWidget);
    expect(find.text('Nimal Perera'), findsOneWidget);
    expect(find.text('Consultation × 1'), findsOneWidget);
    expect(find.text('-LKR 500.00'), findsOneWidget);
    expect(find.text('LKR 4,360.00'), findsNWidgets(3)); // total, paid, and the card payment
    expect(find.text('LKR 0.00'), findsOneWidget);       // balance due
  });

  testWidgets('downloads the PDF and hands it to the share sheet', (tester) async {
    await pumpReceipt(tester);

    await tap(tester, const Key('share-pdf'));

    expect(repo.pdfRequests, 1);
    final (size, name, text) = sharer.pdfs.single;
    expect(size, greaterThan(0));
    expect(name, 'REC-INV-20260923-ABC123.pdf');
    expect(text, contains('Total: LKR 4,360.00'));
  });

  testWidgets('shares a summary on WhatsApp and by email', (tester) async {
    await pumpReceipt(tester);

    await tap(tester, const Key('share-whatsapp'));
    await tap(tester, const Key('share-email'));

    expect(sharer.whatsApps.single, contains('Smile Dental - Receipt REC-INV-20260923-ABC123'));
    final (to, subject, body) = sharer.emails.single;
    expect(to, 'nimal@example.com');
    expect(subject, 'Smile Dental - REC-INV-20260923-ABC123');
    expect(body, contains('• Consultation x1: LKR 1,500.00'));
  });

  test('an unpaid receipt is shown as an invoice with the balance in the share text', () {
    final r = FakeBillingRepository.sampleReceipt();
    final unpaid = Receipt(
      receiptNumber: r.receiptNumber, invoiceId: r.invoiceId, invoiceNumber: r.invoiceNumber, currency: 'LKR',
      totalAmount: 4500, discount: 0, tax: 0, finalAmount: 4500, totalPaid: 1000, balanceDue: 3500,
      paymentStatus: 'PartiallyPaid', issuedAt: r.issuedAt, dueDate: r.dueDate, businessName: 'Smile Dental',
    );
    expect(unpaid.isPaidInFull, isFalse);
    expect(unpaid.shareText(), contains('Balance due: LKR 3,500.00'));
    expect(formatMoney(1234567.891), 'LKR 1,234,567.89');
    expect(formatMoney(-50, 'USD'), '-USD 50.00');
  });
}
