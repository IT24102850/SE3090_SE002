import 'dart:convert';

import 'copilot_trace.dart';

/// A scheduling agent workflow (GET /agent/workflow) — what the web app's
/// Schedule Copilot and Agent Workflows screens propose, approve, revise and
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

  /// Set only for workflows the Schedule Copilot produced.
  final CopilotTrace? copilot;

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
    this.copilot,
  });

  bool get awaitingApproval => status == 'AwaitingApproval' || (approvalStatus ?? '') == 'Pending';
  bool get isTerminal => const {'Completed', 'Failed', 'Rejected', 'Cancelled'}.contains(status);

  /// The proposed bookings, flattened for display.
  ///
  /// ASP.NET Core serialises the plan with default (PascalCase) names -
  /// `Steps`, `Action`, `Parameters` - while plans written by other paths use
  /// camelCase. Reading only `steps` made every scheduling plan show "0 steps"
  /// on the phone, so both spellings are accepted and each step's nested
  /// parameters are lifted up beside its action.
  List<Map<String, dynamic>> get steps {
    final raw = (plan['steps'] ?? plan['Steps']) as List<dynamic>? ?? const [];
    return [
      for (final step in raw.whereType<Map<String, dynamic>>())
        {
          for (final e in step.entries)
            if (e.key.toLowerCase() != 'parameters') _camel(e.key): e.value,
          for (final e in ((step['parameters'] ?? step['Parameters']) as Map<String, dynamic>? ?? const {}).entries)
            _camel(e.key): e.value,
        },
    ];
  }

  static String _camel(String key) => key.isEmpty ? key : key[0].toLowerCase() + key.substring(1);

  double get estimatedRevenueImpact {
    final v = plan['estimatedRevenueImpact'] ?? plan['EstimatedRevenueImpact'];
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
        copilot: CopilotTrace.tryParse(j['toolResultsJson']),
      );
}
