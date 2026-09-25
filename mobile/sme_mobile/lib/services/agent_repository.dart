import 'package:dio/dio.dart';

import '../models/agent_workflow_model.dart';
import '../models/copilot_trace.dart';

/// The scheduling agents — the mobile twin of the web app's Schedule Copilot and
/// Agent Workflows screens. Every plan the agent produces is proposed, not
/// applied: a human approves it, and only then is it written as bookings.
class AgentRepository {
  final Dio _dio;
  const AgentRepository(this._dio);

  Future<List<AgentWorkflow>> workflows({required String tenantId, String? status}) async {
    final response = await _dio.get('/agent/workflow', queryParameters: {
      'tenantId': tenantId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final raw = response.data;
    final list = raw is Map<String, dynamic> ? (raw['items'] as List<dynamic>? ?? const []) : (raw as List<dynamic>);
    return list.map((e) => AgentWorkflow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AgentWorkflow> propose({
    required String tenantId,
    required String objective,
    required int count,
    required String bookingTypeId,
    String? branchId,
    int withinDays = 14,
  }) async {
    final response = await _dio.post('/agent/workflow/propose', data: {
      'tenantId': tenantId,
      'objective': objective,
      'count': count,
      'bookingTypeId': bookingTypeId,
      'branchId': branchId,
      'withinDays': withinDays,
    });
    return AgentWorkflow.fromJson(response.data as Map<String, dynamic>);
  }

  /// Schedule Copilot: runs the Planner, Domain Analysis, Action/Tool and
  /// Validation/Safety agents. Read-only - it returns a proposal, stored as a
  /// workflow, and nothing is booked until that workflow is applied.
  Future<({AgentWorkflow workflow, CopilotTrace? trace})> planSchedule({
    required String tenantId,
    required String objective,
    required String bookingTypeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    required int targetCount,
    List<String> priorityRules = const [],
    List<String> resourceIds = const [],
    String? branchId,
  }) async {
    String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final response = await _dio.post(
      '/agent/workflow/plan-schedule',
      data: {
        'tenantId': tenantId,
        'objective': objective,
        'bookingTypeId': bookingTypeId,
        'dateFrom': day(dateFrom),
        'dateTo': day(dateTo),
        'targetCount': targetCount,
        'priorityRules': priorityRules,
        if (resourceIds.isNotEmpty) 'resourceIds': resourceIds,
        if (branchId != null) 'branchId': branchId,
      },
      // The four agents run synchronously; a model retry can take a while.
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    final data = response.data as Map<String, dynamic>;
    return (
      workflow: AgentWorkflow.fromJson(data['workflow'] as Map<String, dynamic>),
      trace: CopilotTrace.tryParse(data['trace']),
    );
  }

  Future<void> approve(String id) => _dio.post('/agent/workflow/$id/approve');

  Future<void> reject(String id, String reason) =>
      _dio.post('/agent/workflow/$id/reject', data: {'reason': reason});

  /// Turns an approved plan into real bookings. Slots that went while the
  /// plan was waiting are skipped rather than forced, so the result says how
  /// many of each.
  Future<({int created, int skipped, String message})> apply(String id) async {
    final response = await _dio.post('/agent/workflow/$id/apply');
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (
      created: (data['created'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      message: (data['message'] ?? '').toString(),
    );
  }

  Future<void> revise(String id, Map<String, dynamic> plan) =>
      _dio.post('/agent/workflow/$id/revise', data: {'plan': plan});

  /// The workspace assistant behind the owner dashboard's ask box.
  Future<String> ask(String message) async {
    final response = await _dio.post('/workspace-assistant/chat', data: {'message': message});
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (data['answer'] ?? '').toString();
  }
}
