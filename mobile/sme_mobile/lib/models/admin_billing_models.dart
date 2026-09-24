/// Owner-side billing models — the mobile twin of the web app's Billing
/// section. The customer-facing shapes (Invoice, Subscription,
/// InsuranceClaim, Receipt…) already live in `billing_models.dart` and are
/// reused as-is; only the admin-only reads and writes are added here.
library;

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
int _i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// One day on the billing dashboard's revenue series.
class RevenuePoint {
  final String date;
  final double invoiced;
  final double collected;

  const RevenuePoint({required this.date, required this.invoiced, required this.collected});

  factory RevenuePoint.fromJson(Map<String, dynamic> j) => RevenuePoint(
        date: (j['date'] ?? '').toString(),
        invoiced: _d(j['invoiced']),
        collected: _d(j['collected']),
      );
}

/// GET /billing/dashboard.
class BillingDashboard {
  final DateTime? from;
  final DateTime? to;
  final String currency;
  final double totalInvoiced;
  final double totalCollected;
  final double totalOutstanding;
  final double overdueAmount;
  final int overdueCount;
  final int activeSubscriptions;
  final double monthlyRecurringRevenue;
  final int pendingClaims;
  final double pendingClaimsAmount;
  final int pendingApprovals;
  final List<RevenuePoint> revenueSeries;

  const BillingDashboard({
    this.from,
    this.to,
    required this.currency,
    required this.totalInvoiced,
    required this.totalCollected,
    required this.totalOutstanding,
    required this.overdueAmount,
    required this.overdueCount,
    required this.activeSubscriptions,
    required this.monthlyRecurringRevenue,
    required this.pendingClaims,
    required this.pendingClaimsAmount,
    required this.pendingApprovals,
    required this.revenueSeries,
  });

  /// What share of what was billed has actually been banked.
  double get collectionRate => totalInvoiced <= 0 ? 0 : (totalCollected / totalInvoiced) * 100;

  factory BillingDashboard.fromJson(Map<String, dynamic> j) => BillingDashboard(
        from: _dt(j['from']),
        to: _dt(j['to']),
        currency: (j['currency'] ?? 'LKR').toString(),
        totalInvoiced: _d(j['totalInvoiced']),
        totalCollected: _d(j['totalCollected']),
        totalOutstanding: _d(j['totalOutstanding']),
        overdueAmount: _d(j['overdueAmount']),
        overdueCount: _i(j['overdueCount']),
        activeSubscriptions: _i(j['activeSubscriptions']),
        monthlyRecurringRevenue: _d(j['monthlyRecurringRevenue']),
        pendingClaims: _i(j['pendingClaims']),
        pendingClaimsAmount: _d(j['pendingClaimsAmount']),
        pendingApprovals: _i(j['pendingApprovals']),
        revenueSeries: ((j['revenueSeries'] as List<dynamic>?) ?? [])
            .map((e) => RevenuePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A person who can be invoiced (GET /billing/customers).
class BillingCustomer {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String? insuranceProvider;
  final String? insuranceNumber;

  const BillingCustomer({
    required this.id,
    required this.fullName,
    this.email,
    this.phone,
    this.insuranceProvider,
    this.insuranceNumber,
  });

  factory BillingCustomer.fromJson(Map<String, dynamic> j) => BillingCustomer(
        id: j['id'].toString(),
        fullName: (j['fullName'] ?? '').toString(),
        email: j['email']?.toString(),
        phone: j['phone']?.toString(),
        insuranceProvider: j['insuranceProvider']?.toString(),
        insuranceNumber: j['insuranceNumber']?.toString(),
      );
}

/// A payout rule (GET/POST/PUT /commission-rules).
class CommissionRule {
  final String id;
  final String name;
  final String role;
  final String ruleType;
  final double rate;
  final double? fixedAmount;
  final double? minAmount;
  final double? maxAmount;
  final String? description;
  final bool isActive;

  const CommissionRule({
    required this.id,
    required this.name,
    required this.role,
    required this.ruleType,
    required this.rate,
    this.fixedAmount,
    this.minAmount,
    this.maxAmount,
    this.description,
    required this.isActive,
  });

  bool get isPercentage => ruleType.toLowerCase() == 'percentage';

  String get summary => isPercentage
      ? '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}% of the sale'
      : 'Flat ${(fixedAmount ?? 0).toStringAsFixed(2)} per sale';

  factory CommissionRule.fromJson(Map<String, dynamic> j) => CommissionRule(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        ruleType: (j['ruleType'] ?? 'Percentage').toString(),
        rate: _d(j['rate']),
        fixedAmount: j['fixedAmount'] == null ? null : _d(j['fixedAmount']),
        minAmount: j['minAmount'] == null ? null : _d(j['minAmount']),
        maxAmount: j['maxAmount'] == null ? null : _d(j['maxAmount']),
        description: j['description']?.toString(),
        isActive: j['isActive'] != false,
      );
}

/// A configured gateway (GET/POST/PUT /payment-gateways). The secret key
/// itself never leaves the server — only whether one is stored and its
/// last few characters, which is all the screen needs to show.
class PaymentGatewayConfig {
  final String id;
  final String name;
  final String provider;
  final String currency;
  final bool isActive;
  final bool isTestMode;
  final String? publicKey;
  final bool hasApiKey;
  final String? apiKeyHint;
  final bool hasWebhookSecret;
  final String? webhookUrl;

  const PaymentGatewayConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.currency,
    required this.isActive,
    required this.isTestMode,
    this.publicKey,
    required this.hasApiKey,
    this.apiKeyHint,
    required this.hasWebhookSecret,
    this.webhookUrl,
  });

  factory PaymentGatewayConfig.fromJson(Map<String, dynamic> j) => PaymentGatewayConfig(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        provider: (j['provider'] ?? '').toString(),
        currency: (j['currency'] ?? 'LKR').toString(),
        isActive: j['isActive'] == true,
        isTestMode: j['isTestMode'] == true,
        publicKey: j['publicKey']?.toString(),
        hasApiKey: j['hasApiKey'] == true,
        apiKeyHint: j['apiKeyHint']?.toString(),
        hasWebhookSecret: j['hasWebhookSecret'] == true,
        webhookUrl: j['webhookUrl']?.toString(),
      );
}

/// A dynamic form definition (GET /dynamic-forms).
class DynamicFormDefinition {
  final String id;
  final String formType;
  final Map<String, dynamic> schema;
  final Map<String, dynamic> uiSchema;
  final Map<String, dynamic> validationRules;
  final int submissionCount;
  final DateTime? updatedAt;

  const DynamicFormDefinition({
    required this.id,
    required this.formType,
    required this.schema,
    required this.uiSchema,
    required this.validationRules,
    required this.submissionCount,
    this.updatedAt,
  });

  /// The field names the schema declares, in declaration order.
  List<String> get fieldNames {
    final props = schema['properties'];
    return props is Map<String, dynamic> ? props.keys.toList() : const [];
  }

  List<String> get requiredFields =>
      ((schema['required'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();

  static Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic> ? v : <String, dynamic>{};

  factory DynamicFormDefinition.fromJson(Map<String, dynamic> j) => DynamicFormDefinition(
        id: j['id'].toString(),
        formType: (j['formType'] ?? '').toString(),
        schema: _map(j['schema']),
        uiSchema: _map(j['uiSchema']),
        validationRules: _map(j['validationRules']),
        submissionCount: _i(j['submissionCount']),
        updatedAt: _dt(j['updatedAt']),
      );
}

/// An invoice template (GET/POST/PUT /invoice-templates).
///
/// `layout` is an ordered array of typed blocks on the wire
/// (`[{"type":"header"}, …]`); it is carried here as the list of type names,
/// because order and presence are the only things the designer changes and
/// a bare list is far easier to reorder than a list of one-key maps.
class InvoiceTemplate {
  /// Every block the server will accept, in the order an invoice reads.
  static const allBlocks = [
    'header',
    'businessInfo',
    'invoiceMeta',
    'customerInfo',
    'items',
    'totals',
    'payments',
    'notes',
    'footer',
  ];

  final String id;
  final String name;
  final bool isDefault;
  final String accentColor;
  final String? headerText;
  final String? footerText;
  final List<String> blocks;
  final DateTime? updatedAt;

  const InvoiceTemplate({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.accentColor,
    this.headerText,
    this.footerText,
    required this.blocks,
    this.updatedAt,
  });

  /// Back to the wire shape the API validates.
  List<Map<String, String>> get layoutJson => [for (final block in blocks) {'type': block}];

  factory InvoiceTemplate.fromJson(Map<String, dynamic> j) => InvoiceTemplate(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        isDefault: j['isDefault'] == true,
        accentColor: (j['accentColor'] ?? '#2563eb').toString(),
        headerText: j['headerText']?.toString(),
        footerText: j['footerText']?.toString(),
        blocks: ((j['layout'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((b) => (b['type'] ?? '').toString())
            .where((t) => t.isNotEmpty)
            .toList(),
        updatedAt: _dt(j['updatedAt']),
      );
}

/// One aging bucket on GET /reports/outstanding-payments.
class AgingBucket {
  final String label;
  final double amount;
  final int count;

  const AgingBucket({required this.label, required this.amount, required this.count});

  factory AgingBucket.fromJson(Map<String, dynamic> j) => AgingBucket(
        label: (j['label'] ?? '').toString(),
        amount: _d(j['amount']),
        count: _i(j['count']),
      );
}

class OutstandingReport {
  final double totalOutstanding;
  final int count;
  final List<AgingBucket> buckets;

  const OutstandingReport({required this.totalOutstanding, required this.count, required this.buckets});

  factory OutstandingReport.fromJson(Map<String, dynamic> j) => OutstandingReport(
        totalOutstanding: _d(j['totalOutstanding']),
        count: _i(j['count']),
        buckets: ((j['buckets'] as List<dynamic>?) ?? [])
            .map((e) => AgingBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Billing Domain Analysis Agent ───────────────────────────────────────

class BillingAnomaly {
  final String id;
  final String type;
  final String severity;
  final String entityLabel;
  final String description;
  final double amount;

  const BillingAnomaly({
    required this.id,
    required this.type,
    required this.severity,
    required this.entityLabel,
    required this.description,
    required this.amount,
  });

  factory BillingAnomaly.fromJson(Map<String, dynamic> j) => BillingAnomaly(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        severity: (j['severity'] ?? 'low').toString(),
        entityLabel: (j['entityLabel'] ?? j['entityId'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        amount: _d(j['amount']),
      );
}

class BillingInsight {
  final String type;
  final String title;
  final String detail;
  final double value;

  const BillingInsight({required this.type, required this.title, required this.detail, required this.value});

  factory BillingInsight.fromJson(Map<String, dynamic> j) => BillingInsight(
        type: (j['type'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        value: _d(j['value']),
      );
}

class BillingRecommendedAction {
  final String id;
  final String actionType;
  final String entityType;
  final String entityId;
  final String description;
  final double amount;
  final bool requiresApproval;
  final String? approvalReason;

  const BillingRecommendedAction({
    required this.id,
    required this.actionType,
    required this.entityType,
    required this.entityId,
    required this.description,
    required this.amount,
    required this.requiresApproval,
    this.approvalReason,
  });

  factory BillingRecommendedAction.fromJson(Map<String, dynamic> j) => BillingRecommendedAction(
        id: (j['id'] ?? '').toString(),
        actionType: (j['actionType'] ?? '').toString(),
        entityType: (j['entityType'] ?? '').toString(),
        entityId: (j['entityId'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        amount: _d(j['amount']),
        requiresApproval: j['requiresApproval'] == true,
        approvalReason: j['approvalReason']?.toString(),
      );
}

class BillingToolCall {
  final String tool;
  final String summary;

  const BillingToolCall({required this.tool, required this.summary});

  factory BillingToolCall.fromJson(Map<String, dynamic> j) => BillingToolCall(
        tool: (j['tool'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
      );
}

/// POST /billing-agent/analyze — the agent's full output contract.
class BillingAnalysis {
  final String workflowId;
  final String analysisType;
  final double confidenceScore;
  final List<BillingAnomaly> anomalies;
  final List<BillingInsight> insights;
  final List<BillingRecommendedAction> recommendedActions;
  final List<BillingToolCall> toolCalls;

  const BillingAnalysis({
    required this.workflowId,
    required this.analysisType,
    required this.confidenceScore,
    required this.anomalies,
    required this.insights,
    required this.recommendedActions,
    required this.toolCalls,
  });

  factory BillingAnalysis.fromJson(Map<String, dynamic> j) => BillingAnalysis(
        workflowId: (j['workflowId'] ?? '').toString(),
        analysisType: (j['analysisType'] ?? '').toString(),
        confidenceScore: _d(j['confidenceScore']),
        anomalies: ((j['anomalies'] as List<dynamic>?) ?? [])
            .map((e) => BillingAnomaly.fromJson(e as Map<String, dynamic>))
            .toList(),
        insights: ((j['insights'] as List<dynamic>?) ?? [])
            .map((e) => BillingInsight.fromJson(e as Map<String, dynamic>))
            .toList(),
        recommendedActions: ((j['recommendedActions'] as List<dynamic>?) ?? [])
            .map((e) => BillingRecommendedAction.fromJson(e as Map<String, dynamic>))
            .toList(),
        toolCalls: ((j['toolCalls'] as List<dynamic>?) ?? [])
            .map((e) => BillingToolCall.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A row of the agent's audit trail (GET /billing-agent/workflows).
class BillingAgentWorkflow {
  final String id;
  final String objective;
  final String kind;
  final String actionType;
  final String status;
  final String? approvalStatus;
  final double amount;
  final String? entityType;
  final String? reason;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final int anomalyCount;
  final double? confidenceScore;
  final String? finalOutcome;

  const BillingAgentWorkflow({
    required this.id,
    required this.objective,
    required this.kind,
    required this.actionType,
    required this.status,
    this.approvalStatus,
    required this.amount,
    this.entityType,
    this.reason,
    this.createdAt,
    this.completedAt,
    required this.anomalyCount,
    this.confidenceScore,
    this.finalOutcome,
  });

  bool get awaitingApproval => (approvalStatus ?? '').toLowerCase() == 'pending';

  factory BillingAgentWorkflow.fromJson(Map<String, dynamic> j) => BillingAgentWorkflow(
        id: j['id'].toString(),
        objective: (j['objective'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        actionType: (j['actionType'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        approvalStatus: j['approvalStatus']?.toString(),
        amount: _d(j['amount']),
        entityType: j['entityType']?.toString(),
        reason: j['reason']?.toString(),
        createdAt: _dt(j['createdAt']),
        completedAt: _dt(j['completedAt']),
        anomalyCount: _i(j['anomalyCount']),
        confidenceScore: j['confidenceScore'] == null ? null : _d(j['confidenceScore']),
        finalOutcome: j['finalOutcome']?.toString(),
      );
}
