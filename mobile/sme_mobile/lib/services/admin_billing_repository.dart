import 'package:dio/dio.dart';

import '../models/admin_billing_models.dart';
import '../models/billing_models.dart';

/// The owner's side of the billing engine: every invoice rather than just
/// mine, the subscription book, the claim pipeline, commission rules,
/// gateways, form definitions, invoice templates and the domain-analysis
/// agent.
///
/// Kept apart from [BillingRepository], which is deliberately scoped to the
/// signed-in customer's own records — mixing the two would make it far too
/// easy to call an admin route from a customer screen.
class AdminBillingRepository {
  final Dio _dio;
  const AdminBillingRepository(this._dio);

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) from) {
    final raw = data is Map<String, dynamic> ? (data['items'] as List<dynamic>? ?? const []) : (data as List<dynamic>);
    return raw.map((e) => from(e as Map<String, dynamic>)).toList();
  }

  // ── Dashboard ─────────────────────────────────────────────────────────

  Future<BillingDashboard> dashboard(String tenantId, {String? branchId}) async {
    final response = await _dio.get('/billing/dashboard', queryParameters: {
      'tenantId': tenantId,
      if (branchId != null) 'branchId': branchId,
    });
    return BillingDashboard.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OutstandingReport> outstanding(String tenantId, {int agingDays = 30}) async {
    final response = await _dio.get('/reports/outstanding-payments', queryParameters: {
      'tenantId': tenantId,
      'agingDays': agingDays,
    });
    return OutstandingReport.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BillingCustomer>> customers() async {
    final response = await _dio.get('/billing/customers');
    return _list(response.data, BillingCustomer.fromJson);
  }

  // ── Invoices ──────────────────────────────────────────────────────────

  Future<List<Invoice>> invoices({
    required String tenantId,
    String? status,
    String? customerId,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final response = await _dio.get('/invoices', queryParameters: {
      'tenantId': tenantId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (customerId != null) 'customerId': customerId,
      if (from != null) 'from': iso(from),
      if (to != null) 'to': iso(to),
      'page': page,
      'pageSize': pageSize,
    });
    return _list(response.data, Invoice.fromJson);
  }

  Future<Invoice> invoice(String id) async =>
      Invoice.fromJson((await _dio.get('/invoices/$id')).data as Map<String, dynamic>);

  Future<Invoice> createInvoice({
    required String customerId,
    required DateTime dueDate,
    String currency = 'LKR',
    double? discountPercent,
    double? taxRatePercent,
    String? templateId,
    String? notes,
    required List<({String description, int quantity, double unitPrice, String category})> items,
  }) async {
    final response = await _dio.post('/invoices', data: {
      'customerId': customerId,
      'dueDate': dueDate.toIso8601String(),
      'currency': currency,
      if (discountPercent != null) 'discountPercent': discountPercent,
      if (taxRatePercent != null) 'taxRatePercent': taxRatePercent,
      if (templateId != null) 'templateId': templateId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'items': items
          .map((i) => {
                'description': i.description,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
                'category': i.category,
              })
          .toList(),
    });
    return Invoice.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> payInvoice(String id, {required double amount, required String method, String? transactionRef}) =>
      _dio.put('/invoices/$id/pay', data: {'amount': amount, 'method': method, 'transactionRef': transactionRef});

  /// Returns whether the change went through. A large adjustment comes back
  /// `applied: false` with an approval workflow instead, which is the gate
  /// the agent spec requires — the screen must say so rather than claim the
  /// invoice changed.
  Future<({bool applied, bool requiresApproval, String? message})> adjustInvoice(
    String id, {
    double? discount,
    double? tax,
    required String reason,
  }) async {
    final response = await _dio.put('/invoices/$id/adjust', data: {
      'discount': discount,
      'tax': tax,
      'reason': reason,
    });
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (
      applied: data['applied'] == true,
      requiresApproval: data['requiresApproval'] == true,
      message: data['message']?.toString(),
    );
  }

  Future<void> cancelInvoice(String id, {String? reason}) =>
      _dio.put('/invoices/$id/cancel', data: {'reason': reason});

  // ── Subscriptions ─────────────────────────────────────────────────────

  Future<List<Subscription>> subscriptions({required String tenantId, String? status, String? customerId}) async {
    final response = await _dio.get('/subscriptions', queryParameters: {
      'tenantId': tenantId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (customerId != null) 'customerId': customerId,
    });
    return _list(response.data, Subscription.fromJson);
  }

  Future<void> createSubscription({
    required String customerId,
    required String planName,
    required double amount,
    required String billingCycle,
    required DateTime startDate,
    required DateTime endDate,
    bool autoRenew = true,
    bool generateInvoice = false,
    String? notes,
  }) =>
      _dio.post('/subscriptions', data: {
        'customerId': customerId,
        'planName': planName,
        'amount': amount,
        'billingCycle': billingCycle,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'autoRenew': autoRenew,
        'generateInvoice': generateInvoice,
        'notes': notes,
      });

  Future<void> cancelSubscription(String id, {String? reason}) =>
      _dio.put('/subscriptions/$id/cancel', data: {'reason': reason});

  /// The renewal calendar the subscription manager shows above the list.
  Future<List<Map<String, dynamic>>> renewals(String tenantId, {int withinDays = 30}) async {
    final response = await _dio.get('/subscriptions/renewals', queryParameters: {
      'tenantId': tenantId,
      'withinDays': withinDays,
    });
    final data = response.data;
    final raw = data is Map<String, dynamic> ? (data['items'] ?? const []) : data;
    return ((raw as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  // ── Insurance claims ──────────────────────────────────────────────────

  Future<List<InsuranceClaim>> claims({required String tenantId, String? status}) async {
    final response = await _dio.get('/insurance-claims', queryParameters: {
      'tenantId': tenantId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _list(response.data, InsuranceClaim.fromJson);
  }

  /// Moving a claim on can itself need approval when the amount is large,
  /// so the caller is told which of the two happened.
  Future<({bool applied, bool requiresApproval, String? message})> setClaimStatus(
    String id, {
    required String status,
    String? rejectionReason,
    String? notes,
  }) async {
    final response = await _dio.put('/insurance-claims/$id/status', data: {
      'status': status,
      'rejectionReason': rejectionReason,
      'notes': notes,
    });
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (
      applied: data['applied'] != false,
      requiresApproval: data['requiresApproval'] == true,
      message: data['message']?.toString(),
    );
  }

  // ── Commission rules ──────────────────────────────────────────────────

  Future<List<CommissionRule>> commissionRules(String tenantId) async {
    final response = await _dio.get('/commission-rules', queryParameters: {'tenantId': tenantId});
    return _list(response.data, CommissionRule.fromJson);
  }

  Future<void> saveCommissionRule({
    String? id,
    required String name,
    required String ruleType,
    double rate = 0,
    double? fixedAmount,
    double? minAmount,
    double? maxAmount,
    String? role,
    String? description,
    bool isActive = true,
  }) {
    final body = {
      'name': name,
      'ruleType': ruleType,
      'rate': rate,
      'fixedAmount': fixedAmount,
      'minAmount': minAmount,
      'maxAmount': maxAmount,
      'role': role,
      'description': description,
      'isActive': isActive,
    };
    return id == null ? _dio.post('/commission-rules', data: body) : _dio.put('/commission-rules/$id', data: body);
  }

  Future<void> deleteCommissionRule(String id) => _dio.delete('/commission-rules/$id');

  /// What each role would earn on a given sale — the calculator the rules
  /// screen offers so a rule can be checked before it is saved.
  Future<Map<String, dynamic>> calculateSplit({required double amount, String? role}) async {
    final response = await _dio.post('/commission-rules/calculate', data: {
      'dealAmount': amount,
      if (role != null && role.isNotEmpty) 'roles': [role],
    });
    return (response.data as Map<String, dynamic>?) ?? const {};
  }

  // ── Payment gateways ──────────────────────────────────────────────────

  Future<List<PaymentGatewayConfig>> gateways(String tenantId) async {
    final response = await _dio.get('/payment-gateways', queryParameters: {'tenantId': tenantId});
    return _list(response.data, PaymentGatewayConfig.fromJson);
  }

  Future<void> saveGateway({
    String? id,
    required String name,
    required String provider,
    String currency = 'LKR',
    bool isActive = true,
    bool isTestMode = true,
    String? publicKey,
    String? apiKey,
    String? webhookSecret,
  }) {
    final body = {
      'name': name,
      'provider': provider,
      'currency': currency,
      'isActive': isActive,
      'isTestMode': isTestMode,
      'publicKey': publicKey,
      // Null keeps whatever is stored; an empty string clears it.
      if (apiKey != null) 'apiKey': apiKey,
      if (webhookSecret != null) 'webhookSecret': webhookSecret,
    };
    return id == null ? _dio.post('/payment-gateways', data: body) : _dio.put('/payment-gateways/$id', data: body);
  }

  Future<void> deleteGateway(String id) => _dio.delete('/payment-gateways/$id');

  Future<({bool ok, bool simulated, String message})> testGateway(String id) async {
    final response = await _dio.post('/payment-gateways/$id/test');
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (
      ok: data['ok'] == true,
      simulated: data['simulated'] == true,
      message: (data['message'] ?? '').toString(),
    );
  }

  // ── Dynamic forms ─────────────────────────────────────────────────────

  Future<List<DynamicFormDefinition>> forms() async {
    final response = await _dio.get('/dynamic-forms');
    return _list(response.data, DynamicFormDefinition.fromJson);
  }

  Future<void> saveForm(
    String formType, {
    required Map<String, dynamic> schema,
    Map<String, dynamic>? uiSchema,
    Map<String, dynamic>? validationRules,
  }) =>
      _dio.put('/dynamic-forms/$formType', data: {
        'schema': schema,
        'uiSchema': uiSchema ?? const <String, dynamic>{},
        'validationRules': validationRules ?? const <String, dynamic>{},
      });

  Future<void> deleteForm(String formType) => _dio.delete('/dynamic-forms/$formType');

  /// Runs the live schema against sample data — the builder's preview pane.
  Future<({bool isValid, List<String> errors})> validateForm(
    String formType,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post('/dynamic-forms/$formType/validate', data: data);
      final body = (response.data as Map<String, dynamic>?) ?? const {};
      return (isValid: body['isValid'] == true, errors: _errorsOf(body));
    } on DioException catch (e) {
      // A schema violation comes back as a 400 carrying the same body, and
      // that is the answer the preview wants, not an error to throw on.
      final body = e.response?.data;
      if (body is Map<String, dynamic> && body.containsKey('isValid')) {
        return (isValid: body['isValid'] == true, errors: _errorsOf(body));
      }
      rethrow;
    }
  }

  static List<String> _errorsOf(Map<String, dynamic> body) =>
      ((body['errors'] as List<dynamic>?) ?? const [])
          .map((e) => e is Map<String, dynamic> ? '${e['field']}: ${e['message']}' : e.toString())
          .toList();

  // ── Invoice templates ─────────────────────────────────────────────────

  Future<List<InvoiceTemplate>> templates(String tenantId) async {
    final response = await _dio.get('/invoice-templates', queryParameters: {'tenantId': tenantId});
    return _list(response.data, InvoiceTemplate.fromJson);
  }

  Future<void> saveTemplate({
    String? id,
    required String name,
    required List<String> blocks,
    String accentColor = '#2563eb',
    String? headerText,
    String? footerText,
    bool isDefault = false,
  }) {
    final body = {
      'name': name,
      // The API validates this as an ordered array of typed blocks.
      'layout': [for (final block in blocks) {'type': block}],
      'accentColor': accentColor,
      'headerText': headerText,
      'footerText': footerText,
      'isDefault': isDefault,
    };
    return id == null ? _dio.post('/invoice-templates', data: body) : _dio.put('/invoice-templates/$id', data: body);
  }

  Future<void> deleteTemplate(String id) => _dio.delete('/invoice-templates/$id');

  // ── Domain analysis agent ─────────────────────────────────────────────

  Future<BillingAnalysis> analyze({required String tenantId, String analysisType = 'full'}) async {
    final response = await _dio.post('/billing-agent/analyze', data: {
      'tenantId': tenantId,
      'analysisType': analysisType,
    });
    return BillingAnalysis.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<String>> agentTools() async {
    final response = await _dio.get('/billing-agent/tools');
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return ((data['tools'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();
  }

  Future<List<BillingAgentWorkflow>> agentWorkflows(String tenantId, {String? status}) async {
    final response = await _dio.get('/billing-agent/workflows', queryParameters: {
      'tenantId': tenantId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _list(response.data, BillingAgentWorkflow.fromJson);
  }

  Future<void> approveAgentWorkflow(String id) => _dio.post('/billing-agent/workflows/$id/approve');

  Future<void> rejectAgentWorkflow(String id, {String? reason}) =>
      _dio.post('/billing-agent/workflows/$id/reject', data: {'reason': reason});
}
