import 'dart:convert';

/// A scheduling agent workflow (GET /agent/workflow) — what the web app's
/// AI Planner and Agent Workflows screens propose, approve, revise and
/// apply. The plan itself arrives as a JSON *string*, so it is decoded here
/// once rather than in every widget that wants to read a step off it.
class AgentWorkflow {
  final String id;
  final String objective;
  final String status;
  final String? approvalStatus;
  final int currentStep;
  final String? finalOutcome;
  final String? errorLog;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final Map<String, dynamic> plan;

  const AgentWorkflow({
    required this.id,
    required this.objective,
    required this.status,
    this.approvalStatus,
    required this.currentStep,
    this.finalOutcome,
    this.errorLog,
    this.createdAt,
    this.completedAt,
    required this.plan,
  });

  bool get awaitingApproval => status == 'AwaitingApproval' || (approvalStatus ?? '') == 'Pending';
  bool get isTerminal => const {'Completed', 'Failed', 'Rejected', 'Cancelled'}.contains(status);

  /// The proposed bookings, when the plan carries a `steps` array.
  List<Map<String, dynamic>> get steps =>
      ((plan['steps'] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();

  double get estimatedRevenueImpact {
    final v = plan['estimatedRevenueImpact'];
    return v is num ? v.toDouble() : 0;
  }

  /// A workflow raised by the billing agent rather than the scheduler; the
  /// two share one table, and only the plan says which is which.
  bool get isBilling => (plan['agent'] ?? '').toString().contains('Billing');

  static Map<String, dynamic> _decodePlan(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // A plan we cannot read is not a reason to drop the whole row - the
        // status, objective and outcome are still worth showing.
      }
    }
    return <String, dynamic>{};
  }

  factory AgentWorkflow.fromJson(Map<String, dynamic> j) => AgentWorkflow(
        id: j['id'].toString(),
        objective: (j['objective'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        approvalStatus: j['approvalStatus']?.toString(),
        currentStep: j['currentStep'] is num ? (j['currentStep'] as num).toInt() : 0,
        finalOutcome: j['finalOutcome']?.toString(),
        errorLog: j['errorLog']?.toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString())?.toLocal(),
        completedAt: DateTime.tryParse((j['completedAt'] ?? '').toString())?.toLocal(),
        plan: _decodePlan(j['planJson'] ?? j['plan']),
      );
}
