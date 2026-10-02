import 'package:dio/dio.dart';

import '../models/disruption_models.dart';
import 'api_service.dart';

/// The Disruption Recovery Copilot — the mobile twin of the web app's
/// Disruption Recovery screen (`api/agent/disruption`).
///
/// Only `plan` runs the agents, and it changes nothing: it returns a proposal
/// for a human to accept or refuse. `apply` is the manager's decision, and the
/// server re-checks every destination slot against the live database before it
/// moves anything, so a plan that has gone stale while it waited is skipped
/// rather than forced.
class DisruptionRepository {
  final Dio _dio;
  const DisruptionRepository(this._dio);

  Future<List<DisruptionWorkflow>> list({String? status}) async {
    final response = await _dio.get(
      '/agent/disruption',
      queryParameters: {if (status != null && status.isNotEmpty) 'status': status},
    );
    final raw = response.data;
    // The endpoint answers a bare array, but every other list in this API has
    // moved to a paged envelope at some point; accepting both costs a line.
    final list = raw is Map<String, dynamic>
        ? (raw['items'] as List<dynamic>? ?? const [])
        : (raw as List<dynamic>? ?? const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(DisruptionWorkflow.fromJson)
        .toList(growable: false);
  }

  /// Runs the four agents. Read-only: nothing moves until [apply].
  Future<({String workflowId, String status, DisruptionTrace? trace})> plan({
    required String objective,
    required String resourceId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? reason,
    String? branchId,
  }) async {
    String day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final response = await _dio.post(
      '/agent/disruption/plan',
      // Four agents, several model calls and a dozen tool calls back into this
      // same API: minutes, not the CRUD default.
      options: ApiService.aiPipelineOptions,
      data: {
        'objective': objective,
        'resourceId': resourceId,
        'dateFrom': day(dateFrom),
        'dateTo': day(dateTo),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      },
    );
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (
      workflowId: (data['workflowId'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      trace: DisruptionWorkflow.parseTrace(data['trace']),
    );
  }

  /// Moves the accepted bookings. Passing no ids accepts every proposal the
  /// safety gate did not already reject.
  Future<ApplyRecoveryResult> apply(String id, {List<String>? acceptedBookingIds}) async {
    final response = await _dio.post(
      '/agent/disruption/$id/apply',
      data: {
        if (acceptedBookingIds != null && acceptedBookingIds.isNotEmpty)
          'acceptedBookingIds': acceptedBookingIds,
      },
    );
    return ApplyRecoveryResult.fromJson((response.data as Map<String, dynamic>?) ?? const {});
  }

  Future<String> reject(String id, String reason) async {
    final response = await _dio.post('/agent/disruption/$id/reject', data: {'reason': reason});
    final data = (response.data as Map<String, dynamic>?) ?? const {};
    return (data['outcome'] ?? 'Rejected. Nothing was moved.').toString();
  }
}

/// Turns a failed call into something a manager can act on.
///
/// The two statuses worth naming are the ones that are not the operator's
/// fault and not a bug: a backend without the feature deployed, and a plan
/// that does not include the AI add-on. Everything else falls through to the
/// server's own message, which is written for this audience already.
String disruptionErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 404) {
      return 'This server does not have Disruption Recovery yet. Update the app or the API and try again.';
    }
    if (status == 402) {
      return 'Disruption Recovery is part of the AI features. Upgrade the plan to use it.';
    }
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (data is Map && data['title'] is String) return data['title'] as String;
  }
  return fallback;
}
