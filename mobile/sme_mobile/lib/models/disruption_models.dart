/// The Disruption Recovery Copilot's contracts — the mobile twin of
/// `frontend/src/features/booking/disruptionApi.ts`.
///
/// Every field is parsed defensively. The trace is produced by a Python
/// service and stored as free JSON on the workflow row, so a field the phone
/// expects can legitimately be absent on an older plan, and a plan that
/// failed part-way carries only the sections that ran. Parsing must degrade
/// to "that section is missing" rather than throwing, because the one screen
/// that shows a failed plan is the screen a manager opens to find out why.
library;

import 'dart:convert';

/// What the agents propose doing with one stranded booking.
enum RecoveryKind { moveResource, moveTime, moveBoth, cancel, noOptionFound }

RecoveryKind _kindFrom(String? raw) => switch (raw) {
      'MoveResource' => RecoveryKind.moveResource,
      'MoveTime' => RecoveryKind.moveTime,
      'MoveBoth' => RecoveryKind.moveBoth,
      'Cancel' => RecoveryKind.cancel,
      _ => RecoveryKind.noOptionFound,
    };

extension RecoveryKindLabel on RecoveryKind {
  /// Worded for the manager, matching the web app's labels exactly.
  String get label => switch (this) {
        RecoveryKind.moveResource => 'Same time, different resource',
        RecoveryKind.moveTime => 'Same day, later',
        RecoveryKind.moveBoth => 'Another day',
        RecoveryKind.cancel => 'Cancel',
        RecoveryKind.noOptionFound => 'No option found',
      };

  /// True where the proposal has somewhere to send the booking.
  bool get isActionable => this != RecoveryKind.noOptionFound && this != RecoveryKind.cancel;
}

String _str(Map<String, dynamic> json, String key, [String fallback = '']) {
  final value = json[key];
  return value is String ? value : (value?.toString() ?? fallback);
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  return value == 'true' || value == 1;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

List<String> _strings(dynamic raw) =>
    raw is List ? raw.map((e) => '$e').toList(growable: false) : const [];

List<Map<String, dynamic>> _records(dynamic raw) => raw is List
    ? raw.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

/// One booking the outage strands, with the Impact agent's ranking of it.
class AffectedBooking {
  final String bookingId;
  final String customerName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int attendeeCount;
  final bool depositPaid;
  final double priority;
  final String priorityReason;

  const AffectedBooking({
    required this.bookingId,
    required this.customerName,
    required this.startsAt,
    required this.endsAt,
    required this.attendeeCount,
    required this.depositPaid,
    required this.priority,
    required this.priorityReason,
  });

  factory AffectedBooking.fromJson(Map<String, dynamic> json) => AffectedBooking(
        bookingId: _str(json, 'booking_id'),
        customerName: _str(json, 'customer_name', 'Guest'),
        startsAt: _date(json, 'starts_at'),
        endsAt: _date(json, 'ends_at'),
        attendeeCount: _int(json, 'attendee_count'),
        depositPaid: _bool(json, 'deposit_paid'),
        priority: _double(json, 'priority'),
        priorityReason: _str(json, 'priority_reason'),
      );
}

/// Where the Recovery agent proposes to send one booking.
class RecoveryProposal {
  final String bookingId;
  final String customerName;
  final RecoveryKind kind;
  final DateTime? originalStartsAt;
  final String? proposedResourceId;
  final String? proposedResourceName;
  final DateTime? proposedStartsAt;
  final String explanation;
  final double confidence;

  const RecoveryProposal({
    required this.bookingId,
    required this.customerName,
    required this.kind,
    required this.originalStartsAt,
    required this.proposedResourceId,
    required this.proposedResourceName,
    required this.proposedStartsAt,
    required this.explanation,
    required this.confidence,
  });

  factory RecoveryProposal.fromJson(Map<String, dynamic> json) => RecoveryProposal(
        bookingId: _str(json, 'booking_id'),
        customerName: _str(json, 'customer_name', 'Guest'),
        kind: _kindFrom(json['kind'] as String?),
        originalStartsAt: _date(json, 'original_starts_at'),
        proposedResourceId: json['proposed_resource_id'] as String?,
        proposedResourceName: json['proposed_resource_name'] as String?,
        proposedStartsAt: _date(json, 'proposed_starts_at'),
        explanation: _str(json, 'explanation'),
        confidence: _double(json, 'confidence'),
      );
}

/// One rule the deterministic gate ran, and whether it held.
class SafetyCheck {
  final String rule;
  final bool passed;
  final String detail;

  const SafetyCheck({required this.rule, required this.passed, required this.detail});

  factory SafetyCheck.fromJson(Map<String, dynamic> json) => SafetyCheck(
        rule: _str(json, 'rule'),
        passed: _bool(json, 'passed'),
        detail: _str(json, 'detail'),
      );
}

/// What the Impact agent found: who is stranded and what it is worth.
class DisruptionImpact {
  final String resourceName;

  /// What this business calls the thing that broke — "doctor", "vessel or
  /// vehicle", "table". It comes from the business-type policy, so the phone
  /// can use the operator's own word instead of the generic "resource".
  final String resourceNoun;
  final List<AffectedBooking> affected;
  final int totalAttendees;
  final double revenueAtRisk;
  final List<String> warnings;

  const DisruptionImpact({
    required this.resourceName,
    required this.resourceNoun,
    required this.affected,
    required this.totalAttendees,
    required this.revenueAtRisk,
    required this.warnings,
  });

  factory DisruptionImpact.fromJson(Map<String, dynamic> json) => DisruptionImpact(
        resourceName: _str(json, 'resource_name', 'the resource'),
        resourceNoun: _str(json, 'resource_noun', 'resource'),
        affected: _records(json['affected']).map(AffectedBooking.fromJson).toList(),
        totalAttendees: _int(json, 'total_attendees'),
        revenueAtRisk: _double(json, 'revenue_at_risk'),
        warnings: _strings(json['warnings']),
      );
}

class DisruptionSafety {
  final bool isAllowed;
  final bool requiresHumanApproval;
  final String? rejectionReason;
  final List<SafetyCheck> checks;
  final List<String> rejectedBookingIds;

  const DisruptionSafety({
    required this.isAllowed,
    required this.requiresHumanApproval,
    required this.rejectionReason,
    required this.checks,
    required this.rejectedBookingIds,
  });

  factory DisruptionSafety.fromJson(Map<String, dynamic> json) => DisruptionSafety(
        isAllowed: _bool(json, 'is_allowed'),
        requiresHumanApproval: _bool(json, 'requires_human_approval'),
        rejectionReason: json['rejection_reason'] as String?,
        checks: _records(json['checks']).map(SafetyCheck.fromJson).toList(),
        rejectedBookingIds: _strings(json['rejected_booking_ids']),
      );

  int get failedCount => checks.where((c) => !c.passed).length;
}

/// One agent's turn in the pipeline, for the audit trail.
class DisruptionAgentStep {
  final String agent;
  final int durationMs;
  final bool ok;
  final String? error;

  const DisruptionAgentStep({
    required this.agent,
    required this.durationMs,
    required this.ok,
    required this.error,
  });

  factory DisruptionAgentStep.fromJson(Map<String, dynamic> json) => DisruptionAgentStep(
        agent: _str(json, 'agent'),
        durationMs: _int(json, 'duration_ms'),
        ok: _bool(json, 'ok'),
        error: json['error'] as String?,
      );
}

/// Everything the four agents did, as the manager's evidence.
class DisruptionTrace {
  final String status;
  final String businessType;
  final DisruptionImpact? impact;
  final List<RecoveryProposal> proposals;
  final List<String> unresolved;
  final DisruptionSafety? safety;
  final List<String> warnings;
  final String? error;
  final List<DisruptionAgentStep> agentSteps;
  final int toolCallCount;

  const DisruptionTrace({
    required this.status,
    required this.businessType,
    required this.impact,
    required this.proposals,
    required this.unresolved,
    required this.safety,
    required this.warnings,
    required this.error,
    required this.agentSteps,
    required this.toolCallCount,
  });

  factory DisruptionTrace.fromJson(Map<String, dynamic> json) {
    final action = json['action'];
    final impact = json['impact'];
    final safety = json['safety'];
    return DisruptionTrace(
      status: _str(json, 'status'),
      businessType: _str(json, 'business_type'),
      impact: impact is Map<String, dynamic> ? DisruptionImpact.fromJson(impact) : null,
      proposals: action is Map<String, dynamic>
          ? _records(action['proposals']).map(RecoveryProposal.fromJson).toList()
          : const [],
      unresolved: action is Map<String, dynamic> ? _strings(action['unresolved']) : const [],
      safety: safety is Map<String, dynamic> ? DisruptionSafety.fromJson(safety) : null,
      warnings: _strings(json['warnings']),
      error: json['error'] as String?,
      agentSteps: _records(json['agent_steps']).map(DisruptionAgentStep.fromJson).toList(),
      toolCallCount: json['tool_calls'] is List ? (json['tool_calls'] as List).length : 0,
    );
  }

  /// The resource word this business uses, defaulting to the generic one.
  String get resourceNoun => impact?.resourceNoun ?? 'resource';
}

/// A stored Disruption Copilot run.
class DisruptionWorkflow {
  final String id;
  final String objective;
  final String status;
  final String approvalStatus;
  final String? finalOutcome;
  final String? errorLog;
  final DateTime? createdAt;
  final DisruptionTrace? trace;

  const DisruptionWorkflow({
    required this.id,
    required this.objective,
    required this.status,
    required this.approvalStatus,
    required this.finalOutcome,
    required this.errorLog,
    required this.createdAt,
    required this.trace,
  });

  bool get awaitingApproval => status == 'AwaitingApproval';

  factory DisruptionWorkflow.fromJson(Map<String, dynamic> json) => DisruptionWorkflow(
        id: _str(json, 'id'),
        objective: _str(json, 'objective'),
        status: _str(json, 'status'),
        approvalStatus: _str(json, 'approvalStatus'),
        finalOutcome: json['finalOutcome'] as String?,
        errorLog: json['errorLog'] as String?,
        createdAt: _date(json, 'createdAt'),
        trace: parseTrace(json['trace']),
      );

  /// The trace arrives as a JSON *string* on the list endpoint and as an
  /// object from `plan`. Both are accepted so one model serves both calls.
  static DisruptionTrace? parseTrace(dynamic raw) {
    if (raw is Map<String, dynamic>) return DisruptionTrace.fromJson(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return DisruptionTrace.fromJson(decoded);
      } catch (_) {
        // A trace we cannot read must not take the whole list down with it.
        return null;
      }
    }
    return null;
  }
}

/// What applying a recovery actually changed.
class ApplyRecoveryResult {
  final List<String> movedBookingIds;
  final List<({String bookingId, String reason})> skipped;
  final String outcome;

  const ApplyRecoveryResult({
    required this.movedBookingIds,
    required this.skipped,
    required this.outcome,
  });

  factory ApplyRecoveryResult.fromJson(Map<String, dynamic> json) => ApplyRecoveryResult(
        movedBookingIds:
            _records(json['moved']).map((m) => _str(m, 'bookingId')).toList(growable: false),
        skipped: _records(json['skipped'])
            .map((s) => (bookingId: _str(s, 'bookingId'), reason: _str(s, 'reason')))
            .toList(growable: false),
        outcome: _str(json, 'outcome', 'The recovery was applied.'),
      );
}
