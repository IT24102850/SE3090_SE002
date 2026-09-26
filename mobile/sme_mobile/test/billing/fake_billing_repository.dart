import 'dart:typed_data';

import 'package:sme_mobile/models/billing_models.dart';
import 'package:sme_mobile/services/billing_repository.dart';

/// An in-memory BillingRepository that records what the screens asked for.
class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository({
    List<Invoice>? invoices,
    this.providers = const AvailableProviders([]),
    this.confirmStatus = 'Succeeded',
    Receipt? receipt,
  })  : invoices = invoices ?? [sampleInvoice()],
        receiptValue = receipt ?? sampleReceipt();

  final List<Invoice> invoices;
  final AvailableProviders providers;
  String confirmStatus;
  final Receipt receiptValue;

  final checkouts = <Map<String, Object?>>[];
  final confirmations = <(String, bool)>[];
  int pdfRequests = 0;

  static Invoice sampleInvoice({
    String id = 'inv-1',
    String number = 'INV-20260923-ABC123',
    String status = 'Issued',
    double total = 4500,
    double paid = 0,
    bool overdue = false,
  }) =>
      Invoice(
        id: id,
        invoiceNumber: number,
        status: status,
        currency: 'LKR',
        totalAmount: total,
        discount: 0,
        tax: 0,
        finalAmount: total,
        amountPaid: paid,
        balanceDue: total - paid,
        isOverdue: overdue,
        dueDate: DateTime(2026, 10, 7),
        createdAt: DateTime(2026, 9, 23),
        items: [InvoiceItem(id: 'i1', description: 'Scale & polish', quantity: 1, unitPrice: total, amount: total)],
      );

  static Receipt sampleReceipt() => Receipt(
        receiptNumber: 'REC-INV-20260923-ABC123',
        invoiceId: 'inv-1',
        invoiceNumber: 'INV-20260923-ABC123',
        currency: 'LKR',
        totalAmount: 4500,
        discount: 500,
        tax: 360,
        finalAmount: 4360,
        totalPaid: 4360,
        balanceDue: 0,
        paymentStatus: 'Paid',
        issuedAt: DateTime(2026, 9, 23),
        dueDate: DateTime(2026, 10, 7),
        businessName: 'Smile Dental',
        customerName: 'Nimal Perera',
        customerEmail: 'nimal@example.com',
        items: const [
          InvoiceItem(id: 'a', description: 'Consultation', quantity: 1, unitPrice: 1500, amount: 1500),
          InvoiceItem(id: 'b', description: 'Scale & polish', quantity: 1, unitPrice: 3000, amount: 3000),
        ],
        payments: [PaymentRecord(id: 'p', amount: 4360, method: 'Card', status: 'Succeeded', paidAt: DateTime(2026, 9, 23, 10, 30))],
      );

  CheckoutSession _session(double amount) => CheckoutSession(
        paymentId: 'pay-${checkouts.length}',
        invoiceId: 'inv-1',
        provider: 'Manual',
        status: 'Pending',
        amount: amount,
        currency: 'LKR',
        externalReference: 'SIM-TEST',
        simulated: true,
      );

  @override
  Future<List<Invoice>> myInvoices() async => invoices;

  @override
  Future<Invoice> invoice(String id) async => invoices.firstWhere((i) => i.id == id);

  @override
  Future<Receipt> receipt(String invoiceId) async => receiptValue;

  @override
  Future<Uint8List> receiptPdf(String invoiceId) async {
    pdfRequests++;
    return Uint8List.fromList('%PDF-1.4 fake'.codeUnits);
  }

  @override
  Future<AvailableProviders> availableProviders() async => providers;

  @override
  Future<CheckoutSession> checkout(String invoiceId,
      {required String method, String? provider, double? amount, bool hostedPage = false, String? returnUrl}) async {
    final session = _session(amount ?? invoices.first.balanceDue);
    checkouts.add({'invoiceId': invoiceId, 'method': method, 'provider': provider, 'amount': amount, 'hostedPage': hostedPage});
    return session;
  }

  @override
  Future<PaymentConfirmation> confirmPayment(String paymentId, {bool simulateFailure = false}) async {
    confirmations.add((paymentId, simulateFailure));
    final status = simulateFailure ? 'Failed' : confirmStatus;
    final inv = invoices.first;
    return PaymentConfirmation(
      PaymentRecord(id: paymentId, amount: inv.balanceDue, method: 'Card', status: status),
      sampleInvoice(status: status == 'Succeeded' ? 'Paid' : 'Issued', paid: status == 'Succeeded' ? inv.finalAmount : 0),
    );
  }

  @override
  Future<List<Subscription>> mySubscriptions() async => [];

  @override
  Future<List<PlanOption>> planOptions() async => [];

  @override
  Future<Subscription> changePlan(String subscriptionId, {required String planName, required double amount}) =>
      throw UnimplementedError();

  @override
  Future<String> cancelSubscription(String subscriptionId, {String? reason, double refundAmount = 0}) async => 'Cancelled.';

  @override
  Future<List<Invoice>> subscriptionInvoices(String subscriptionId) async => [];

  @override
  Future<List<InsuranceClaim>> myClaims() async => [];

  @override
  Future<InsuranceClaim> createClaim(
          {required String invoiceId, required String provider, required String policyNumber, required double claimAmount, String? notes}) =>
      throw UnimplementedError();

  @override
  Future<InsuranceClaim> uploadClaimDocument(String claimId, Uint8List bytes, String fileName) => throw UnimplementedError();
}
