import 'package:dio/dio.dart';

import '../models/unify_plan_models.dart';

/// Everything the Unify-plan screen needs. An interface so widget tests can
/// hand the screen a fake instead of a live server, matching
/// [BillingRepository] in `billing_repository.dart`.
abstract class UnifyPlanRepository {
  Future<PricingCatalog> catalog({String? currency});
  Future<UnifySubscription> current();
  Future<List<UnifyInvoice>> invoices();
  Future<PlanQuote> quote({
    required String planCode,
    required String period,
    String? currency,
    String? promotionCode,
  });
  Future<PlanCheckout> checkout({
    required String planCode,
    required String period,
    String? currency,
    String? promotionCode,
    String? provider,
    String? returnUrl,
  });
  Future<PlanCheckout> buyAddOn(String addOnCode, {int quantity, String? currency, String? provider});
  Future<PlanCheckout> payInvoice(String invoiceId, {String? provider, String? returnUrl});
  Future<UnifyInvoice> confirm(String paymentId, {bool simulateFailure});
  Future<UnifySubscription> startTrial({String? planCode});
  Future<UnifySubscription> cancel({String? reason, bool immediate});
  Future<UnifySubscription> resume();
}

class DioUnifyPlanRepository implements UnifyPlanRepository {
  final Dio _dio;
  DioUnifyPlanRepository(this._dio);

  Map<String, dynamic> _map(dynamic data) => data as Map<String, dynamic>;

  @override
  Future<PricingCatalog> catalog({String? currency}) async {
    final response = await _dio.get<dynamic>(
      '/subscription/plans',
      queryParameters: currency == null ? null : {'currency': currency},
    );
    return PricingCatalog.fromJson(_map(response.data));
  }

  @override
  Future<UnifySubscription> current() async {
    final response = await _dio.get<dynamic>('/subscription');
    return UnifySubscription.fromJson(_map(response.data));
  }

  @override
  Future<List<UnifyInvoice>> invoices() async {
    final response = await _dio.get<dynamic>('/subscription/invoices');
    return (response.data as List<dynamic>)
        .map((e) => UnifyInvoice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PlanQuote> quote({
    required String planCode,
    required String period,
    String? currency,
    String? promotionCode,
  }) async {
    final response = await _dio.post<dynamic>('/subscription/quote', data: {
      'planCode': planCode,
      'period': period,
      if (currency != null) 'currency': currency,
      if (promotionCode != null && promotionCode.isNotEmpty) 'promotionCode': promotionCode,
    });
    return PlanQuote.fromJson(_map(response.data));
  }

  @override
  Future<PlanCheckout> checkout({
    required String planCode,
    required String period,
    String? currency,
    String? promotionCode,
    String? provider,
    String? returnUrl,
  }) async {
    final response = await _dio.post<dynamic>('/subscription/checkout', data: {
      'planCode': planCode,
      'period': period,
      if (currency != null) 'currency': currency,
      if (promotionCode != null && promotionCode.isNotEmpty) 'promotionCode': promotionCode,
      if (provider != null) 'provider': provider,
      if (returnUrl != null) 'returnUrl': returnUrl,
    });
    return PlanCheckout.fromJson(_map(response.data));
  }

  @override
  Future<PlanCheckout> buyAddOn(String addOnCode, {int quantity = 1, String? currency, String? provider}) async {
    final response = await _dio.post<dynamic>('/subscription/addons/checkout', data: {
      'addOnCode': addOnCode,
      'quantity': quantity,
      if (currency != null) 'currency': currency,
      if (provider != null) 'provider': provider,
    });
    return PlanCheckout.fromJson(_map(response.data));
  }

  @override
  Future<PlanCheckout> payInvoice(String invoiceId, {String? provider, String? returnUrl}) async {
    final response = await _dio.post<dynamic>('/subscription/invoices/$invoiceId/pay', data: {
      if (provider != null) 'provider': provider,
      if (returnUrl != null) 'returnUrl': returnUrl,
    });
    return PlanCheckout.fromJson(_map(response.data));
  }

  @override
  Future<UnifyInvoice> confirm(String paymentId, {bool simulateFailure = false}) async {
    final response = await _dio.post<dynamic>('/subscription/confirm', data: {
      'paymentId': paymentId,
      'simulateFailure': simulateFailure,
    });
    return UnifyInvoice.fromJson(_map(response.data));
  }

  @override
  Future<UnifySubscription> startTrial({String? planCode}) async {
    final response = await _dio.post<dynamic>('/subscription/trial', data: {
      if (planCode != null) 'planCode': planCode,
    });
    return UnifySubscription.fromJson(_map(response.data));
  }

  @override
  Future<UnifySubscription> cancel({String? reason, bool immediate = false}) async {
    final response = await _dio.post<dynamic>('/subscription/cancel', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      'immediate': immediate,
    });
    return UnifySubscription.fromJson(_map(response.data));
  }

  @override
  Future<UnifySubscription> resume() async {
    final response = await _dio.post<dynamic>('/subscription/resume');
    return UnifySubscription.fromJson(_map(response.data));
  }
}

/// The paywall body the backend attaches to every 402 (see PlanGate on the
/// server). Anything in the app that walks into a plan limit gets one of
/// these, and the sheet in `unify_plan_screen.dart` renders it.
class PlanPaywall {
  final String reason;
  final String? feature;
  final String? metric;
  final int? used;
  final int? limit;
  final String currentPlan;
  final String? requiredPlan;
  final String? requiredPlanName;
  final String? addOnCode;
  final String message;

  const PlanPaywall({
    required this.reason,
    required this.feature,
    required this.metric,
    required this.used,
    required this.limit,
    required this.currentPlan,
    required this.requiredPlan,
    required this.requiredPlanName,
    required this.addOnCode,
    required this.message,
  });

  /// Returns the paywall a failed request carried, or null if it was an
  /// ordinary error.
  static PlanPaywall? of(Object error) {
    if (error is! DioException || error.response?.statusCode != 402) return null;
    final data = error.response?.data;
    if (data is! Map) return null;
    final body = data['paywall'];
    if (body is! Map) return null;
    return PlanPaywall(
      reason: body['reason'] as String? ?? 'feature',
      feature: body['feature'] as String?,
      metric: body['metric'] as String?,
      used: (body['used'] as num?)?.toInt(),
      limit: (body['limit'] as num?)?.toInt(),
      currentPlan: body['currentPlan'] as String? ?? 'starter',
      requiredPlan: body['requiredPlan'] as String?,
      requiredPlanName: body['requiredPlanName'] as String?,
      addOnCode: body['addOnCode'] as String?,
      message: data['message'] as String? ?? 'This is part of a paid plan.',
    );
  }
}
