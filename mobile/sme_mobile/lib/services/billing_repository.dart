import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../models/billing_models.dart';

/// Everything the billing screens need from the backend. An interface so
/// widget tests can hand the screens a fake instead of a live server.
abstract class BillingRepository {
  Future<List<Invoice>> myInvoices();
  Future<Invoice> invoice(String id);
  Future<Receipt> receipt(String invoiceId);
  Future<Uint8List> receiptPdf(String invoiceId);

  Future<AvailableProviders> availableProviders();
  Future<CheckoutSession> checkout(
    String invoiceId, {
    required String method,
    String? provider,
    double? amount,
    bool hostedPage = false,
    String? returnUrl,
  });
  Future<PaymentConfirmation> confirmPayment(String paymentId, {bool simulateFailure = false});

  Future<List<Subscription>> mySubscriptions();
  Future<List<PlanOption>> planOptions();
  Future<Subscription> changePlan(String subscriptionId, {required String planName, required double amount});
  Future<String> cancelSubscription(String subscriptionId, {String? reason, double refundAmount = 0});
  Future<List<Invoice>> subscriptionInvoices(String subscriptionId);

  Future<List<InsuranceClaim>> myClaims();
  Future<InsuranceClaim> createClaim({
    required String invoiceId,
    required String provider,
    required String policyNumber,
    required double claimAmount,
    String? notes,
  });
  Future<InsuranceClaim> uploadClaimDocument(String claimId, Uint8List bytes, String fileName);
}

/// Turns a DioException into the server's own message where there is one.
String billingErrorMessage(Object error, [String fallback = 'Something went wrong.']) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the server. Check your connection.';
    }
  }
  return fallback;
}

class DioBillingRepository implements BillingRepository {
  final Dio _dio;
  DioBillingRepository(this._dio);

  List<Invoice> _invoices(dynamic data) =>
      ((data as Map<String, dynamic>)['items'] as List<dynamic>).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();

  @override
  Future<List<Invoice>> myInvoices() async =>
      _invoices((await _dio.get('/invoices/mine', queryParameters: {'pageSize': 100})).data);

  @override
  Future<Invoice> invoice(String id) async => Invoice.fromJson((await _dio.get('/invoices/$id')).data as Map<String, dynamic>);

  @override
  Future<Receipt> receipt(String invoiceId) async =>
      Receipt.fromJson((await _dio.get('/invoices/$invoiceId/receipt')).data as Map<String, dynamic>);

  @override
  Future<Uint8List> receiptPdf(String invoiceId) async {
    final response = await _dio.get<List<int>>(
      '/invoices/$invoiceId/receipt.pdf',
      options: Options(responseType: ResponseType.bytes, headers: {'Accept': 'application/pdf'}),
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  @override
  Future<AvailableProviders> availableProviders() async =>
      AvailableProviders.fromJson((await _dio.get('/payment-gateways/available')).data as Map<String, dynamic>);

  @override
  Future<CheckoutSession> checkout(
    String invoiceId, {
    required String method,
    String? provider,
    double? amount,
    bool hostedPage = false,
    String? returnUrl,
  }) async {
    final response = await _dio.post('/invoices/$invoiceId/checkout', data: {
      'method': method,
      if (provider != null) 'provider': provider,
      if (amount != null) 'amount': amount,
      'hostedPage': hostedPage,
      if (returnUrl != null) 'returnUrl': returnUrl,
    });
    return CheckoutSession.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<PaymentConfirmation> confirmPayment(String paymentId, {bool simulateFailure = false}) async {
    final response = await _dio.post('/payments/confirm', data: {'paymentId': paymentId, 'simulateFailure': simulateFailure});
    return PaymentConfirmation.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<Subscription>> mySubscriptions() async {
    final data = (await _dio.get('/subscriptions', queryParameters: {'pageSize': 50})).data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>).map((e) => Subscription.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<PlanOption>> planOptions() async =>
      ((await _dio.get('/subscriptions/plans')).data as List<dynamic>).map((e) => PlanOption.fromJson(e as Map<String, dynamic>)).toList();

  @override
  Future<Subscription> changePlan(String subscriptionId, {required String planName, required double amount}) async {
    final response = await _dio.put('/subscriptions/$subscriptionId/change-plan', data: {'planName': planName, 'amount': amount});
    return Subscription.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<String> cancelSubscription(String subscriptionId, {String? reason, double refundAmount = 0}) async {
    final response = await _dio.put('/subscriptions/$subscriptionId/cancel', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'refundAmount': refundAmount,
    });
    return (response.data as Map<String, dynamic>)['message'] as String? ?? 'Done.';
  }

  @override
  Future<List<Invoice>> subscriptionInvoices(String subscriptionId) async =>
      _invoices((await _dio.get('/subscriptions/$subscriptionId/invoices')).data);

  @override
  Future<List<InsuranceClaim>> myClaims() async {
    final data = (await _dio.get('/insurance-claims', queryParameters: {'pageSize': 100})).data as Map<String, dynamic>;
    return (data['items'] as List<dynamic>).map((e) => InsuranceClaim.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<InsuranceClaim> createClaim({
    required String invoiceId,
    required String provider,
    required String policyNumber,
    required double claimAmount,
    String? notes,
  }) async {
    final response = await _dio.post('/insurance-claims', data: {
      'invoiceId': invoiceId,
      'provider': provider,
      'policyNumber': policyNumber,
      'claimAmount': claimAmount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return InsuranceClaim.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<InsuranceClaim> uploadClaimDocument(String claimId, Uint8List bytes, String fileName) async {
    final lower = fileName.toLowerCase();
    final mime = lower.endsWith('.pdf')
        ? DioMediaType('application', 'pdf')
        : lower.endsWith('.png')
            ? DioMediaType('image', 'png')
            : DioMediaType('image', 'jpeg');
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName, contentType: mime)});
    final response = await _dio.post('/insurance-claims/$claimId/documents', data: form);
    return InsuranceClaim.fromJson(response.data as Map<String, dynamic>);
  }
}
