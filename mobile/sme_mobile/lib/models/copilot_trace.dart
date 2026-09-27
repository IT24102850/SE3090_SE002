import 'dart:convert';

/// The Schedule Copilot's trace, as the agent service writes it and ASP.NET
/// Core stores it on AgentWorkflow.toolResultsJson. The same record the web
/// Copilot renders - read, never rebuilt, so the phone and the browser cannot
/// disagree about what the agents did.
class CopilotTrace {
  final String status; // Completed | AwaitingApproval | Rejected | Failed
  final String objective;
  final String? error;
  final CopilotPlanner? planner;
  final List<CopilotProposal> proposals;
  final List<CopilotSkip> skipped;
  final List<CopilotCheck> checks;
  final List<String> approvalReasons;
  final String? rejectionReason;
  final CopilotMetrics? metrics;
  final List<String> warnings;
  final List<CopilotAgentStep> agentSteps;
  final List<({String tool, String agent, int ms, bool ok})> toolCalls;
  final List<({String model, int attempt, bool ok})> llmCalls;
  final List<({String name, double utilisation, double noShowRate, int noShowSample, double score})> resources;

  const CopilotTrace({
    required this.status,
    required this.objective,
    this.error,
    this.planner,
    this.proposals = const [],
    this.skipped = const [],
    this.checks = const [],
    this.approvalReasons = const [],
    this.rejectionReason,
    this.metrics,
    this.warnings = const [],
    this.agentSteps = const [],
    this.toolCalls = const [],
    this.llmCalls = const [],
    this.resources = const [],
  });

  int get checksPassed => checks.where((c) => c.status == 'pass').length;

  /// Returns null for anything that is not a Copilot trace - older workflows
  /// store a different shape, and a trace we cannot read must not take the
  /// whole card down with it.
  static CopilotTrace? tryParse(dynamic raw) {
    Map<String, dynamic>? j;
    if (raw is Map<String, dynamic>) {
      j = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) j = decoded;
      } on FormatException {
        return null;
      }
    }
    if (j == null || j['workflow_type'] != 'schedule-copilot') return null;
    try {
      return CopilotTrace.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  factory CopilotTrace.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(dynamic v) => (v as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final action = j['action'] as Map<String, dynamic>?;
    final safety = j['safety'] as Map<String, dynamic>?;
    final analysis = j['analysis'] as Map<String, dynamic>?;
    return CopilotTrace(
      status: (j['status'] ?? '').toString(),
      objective: (j['objective'] ?? '').toString(),
      error: j['error']?.toString(),
      planner: j['planner'] is Map<String, dynamic> ? CopilotPlanner.fromJson(j['planner'] as Map<String, dynamic>) : null,
      proposals: list(action?['proposals']).map(CopilotProposal.fromJson).toList(),
      skipped: list(action?['skipped']).map(CopilotSkip.fromJson).toList(),
      checks: list(safety?['checks']).map(CopilotCheck.fromJson).toList(),
      approvalReasons: (safety?['approval_reasons'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      rejectionReason: safety?['rejection_reason']?.toString(),
      metrics: j['metrics'] is Map<String, dynamic> ? CopilotMetrics.fromJson(j['metrics'] as Map<String, dynamic>) : null,
      warnings: (j['warnings'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      agentSteps: list(j['agent_steps']).map(CopilotAgentStep.fromJson).toList(),
      toolCalls: [
        for (final c in list(j['tool_calls']))
          (tool: c['tool'].toString(), agent: c['agent'].toString(), ms: _int(c['duration_ms']), ok: c['success'] == true),
      ],
      llmCalls: [
        for (final c in list(j['llm_calls'])) (model: c['model'].toString(), attempt: _int(c['attempt']), ok: c['ok'] == true),
      ],
      resources: [
        for (final r in list(analysis?['resources']))
          (
            name: (r['resource_name'] ?? '').toString(),
            utilisation: _num(r['utilisation_pct']),
            noShowRate: _num(r['no_show_rate']),
            noShowSample: _int(r['no_show_sample']),
            score: _num(r['score']),
          ),
      ],
    );
  }
}

class CopilotPlanner {
  final List<({int order, String action, String agent, String description, List<String> tools})> plan;
  final List<({String kind, String description, double likelihood})> predictedConflicts;
  final double confidence;
  final bool usedFallback;
  final String summary;
  final List<String> rules;
  final List<int> weekdays;
  final String timeWindow;

  const CopilotPlanner({
    required this.plan,
    required this.predictedConflicts,
    required this.confidence,
    required this.usedFallback,
    required this.summary,
    required this.rules,
    required this.weekdays,
    required this.timeWindow,
  });

  factory CopilotPlanner.fromJson(Map<String, dynamic> j) {
    final intent = (j['intent'] as Map<String, dynamic>?) ?? const {};
    return CopilotPlanner(
      plan: [
        for (final s in (j['plan'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          (
            order: _int(s['order']),
            action: (s['action'] ?? '').toString(),
            agent: (s['assigned_agent'] ?? '').toString(),
            description: (s['description'] ?? '').toString(),
            tools: (s['tools'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
          ),
      ],
      predictedConflicts: [
        for (final c in (j['predicted_conflicts'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          (kind: (c['kind'] ?? '').toString(), description: (c['description'] ?? '').toString(), likelihood: _num(c['likelihood'])),
      ],
      confidence: _num(j['confidence_score']),
      usedFallback: j['used_fallback'] == true,
      summary: (j['summary'] ?? '').toString(),
      rules: (intent['priority_rules'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      weekdays: (intent['weekdays'] as List<dynamic>? ?? const []).map(_int).toList(),
      timeWindow: (intent['time_window'] ?? 'any').toString(),
    );
  }
}

class CopilotProposal {
  final String resourceName;
  final DateTime start;
  final DateTime end;
  final double score;
  final List<String> reasons;

  const CopilotProposal({required this.resourceName, required this.start, required this.end, required this.score, required this.reasons});

  factory CopilotProposal.fromJson(Map<String, dynamic> j) => CopilotProposal(
        resourceName: (j['resource_name'] ?? '').toString(),
        start: DateTime.parse(j['start'].toString()).toLocal(),
        end: DateTime.parse(j['end'].toString()).toLocal(),
        score: _num(j['score']),
        reasons: (j['reasons'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      );
}

class CopilotSkip {
  final String resourceName;
  final DateTime? start;
  final String reason;
  const CopilotSkip({required this.resourceName, required this.start, required this.reason});
  factory CopilotSkip.fromJson(Map<String, dynamic> j) => CopilotSkip(
        resourceName: (j['resource_name'] ?? '').toString(),
        start: DateTime.tryParse((j['start'] ?? '').toString())?.toLocal(),
        reason: (j['reason'] ?? '').toString(),
      );
}

class CopilotCheck {
  final String rule;
  final String status; // pass | warn | fail
  final String detail;
  const CopilotCheck({required this.rule, required this.status, required this.detail});
  factory CopilotCheck.fromJson(Map<String, dynamic> j) =>
      CopilotCheck(rule: (j['rule'] ?? '').toString(), status: (j['status'] ?? '').toString(), detail: (j['detail'] ?? '').toString());
}

class CopilotAgentStep {
  final String agent;
  final int durationMs;
  final bool ok;
  const CopilotAgentStep({required this.agent, required this.durationMs, required this.ok});
  factory CopilotAgentStep.fromJson(Map<String, dynamic> j) =>
      CopilotAgentStep(agent: (j['agent'] ?? '').toString(), durationMs: _int(j['duration_ms']), ok: j['ok'] == true);
}

class CopilotMetrics {
  final int requested;
  final int proposed;
  final double coverage;
  final int resourcesUsed;
  final int daysUsed;
  final double expectedNoShows;
  final double? revenue;
  final String currency;
  final double utilisationBefore;
  final double utilisationAfter;

  const CopilotMetrics({
    required this.requested,
    required this.proposed,
    required this.coverage,
    required this.resourcesUsed,
    required this.daysUsed,
    required this.expectedNoShows,
    required this.revenue,
    required this.currency,
    required this.utilisationBefore,
    required this.utilisationAfter,
  });

  factory CopilotMetrics.fromJson(Map<String, dynamic> j) => CopilotMetrics(
        requested: _int(j['requested']),
        proposed: _int(j['proposed']),
        coverage: _num(j['coverage_pct']),
        resourcesUsed: _int(j['resources_used']),
        daysUsed: _int(j['days_used']),
        expectedNoShows: _num(j['expected_no_shows']),
        revenue: j['estimated_revenue'] is num ? (j['estimated_revenue'] as num).toDouble() : null,
        currency: (j['currency'] ?? 'USD').toString(),
        utilisationBefore: _num(j['utilisation_before_pct']),
        utilisationAfter: _num(j['utilisation_after_pct']),
      );
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
