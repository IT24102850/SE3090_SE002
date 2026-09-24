import 'package:dio/dio.dart';

import '../models/agent_workflow_model.dart';

/// The scheduling agent — the mobile twin of the web app's AI Planner and
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
