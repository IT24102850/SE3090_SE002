import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/clinic_models.dart';
import 'api_service_provider.dart';
import 'auth_provider.dart';
import 'tenant_profile_provider.dart';

// ─────────────────────────────────────────────────────────
// The clinic operations desk - reads from api/reports/clinic/*.
//
// Same shape as booking_providers.dart: FutureProviders for reads, plain
// functions taking a Dio for mutations. The screen invalidates the flow
// and alerts providers after every action, and polls them on a timer,
// so a check-in from the QR scanner or the web console shows up here.
// ─────────────────────────────────────────────────────────

/// Whether the signed-in user's business is a clinic - decides whether the
/// clinic desk appears on the dashboard at all. Resolved from the tenant
/// profile (anonymous endpoint, already cached for the profile editor), so
/// it costs nothing extra. Unknown while loading, and on error, is "no".
final isClinicTenantProvider = Provider<bool>((ref) {
  final tenantId = ref.watch(authProvider).user?.tenantId;
  if (tenantId == null || tenantId.isEmpty) return false;
  final profile = ref.watch(tenantProfileProvider(tenantId));
  return profile.maybeWhen(
    data: (p) => p.businessType.trim().toLowerCase() == 'clinic',
    orElse: () => false,
  );
});

final clinicFlowProvider = FutureProvider<ClinicFlow>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/reports/clinic/flow');
  return ClinicFlow.fromJson(response.data as Map<String, dynamic>);
});

final clinicAlertsProvider = FutureProvider<List<ClinicAlert>>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/reports/clinic/alerts');
  final data = response.data as Map<String, dynamic>;
  final alerts = data['alerts'] as List<dynamic>? ?? const [];
  return alerts.map((a) => ClinicAlert.fromJson(a as Map<String, dynamic>)).toList();
});

final clinicRemindersProvider = FutureProvider<ClinicReminders>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/reports/clinic/reminders', queryParameters: {'withinHours': 48});
  return ClinicReminders.fromJson(response.data as Map<String, dynamic>);
});

/// The report window. `groupBy` is what the trend is bucketed by, so the
/// daily / weekly / monthly presets are just three values of this record.
typedef ClinicOverviewQuery = ({
  String from,
  String to,
  String groupBy,
  String? branchId,
  String? resourceId,
  String? bookingTypeId,
  String? insuranceProvider,
});

final clinicOverviewProvider = FutureProvider.family<ClinicOverview, ClinicOverviewQuery>((ref, q) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/reports/clinic/overview', queryParameters: {
    'from': q.from,
    'to': q.to,
    'groupBy': q.groupBy,
    if (q.branchId != null) 'branchId': q.branchId,
    if (q.resourceId != null) 'resourceId': q.resourceId,
    if (q.bookingTypeId != null) 'bookingTypeId': q.bookingTypeId,
    if (q.insuranceProvider != null) 'insuranceProvider': q.insuranceProvider,
  });
  return ClinicOverview.fromJson(response.data as Map<String, dynamic>);
});

class ClinicRequestException implements Exception {
  final String message;
  ClinicRequestException(this.message);
}

String? _message(DioException e) {
  final data = e.response?.data;
  if (data is Map) return data['message']?.toString() ?? data['title']?.toString();
  return null;
}

/// On-demand reminder for one appointment (POST /bookings/{id}/remind).
/// The backend's scheduler already sends one 24h out; this is the early
/// nudge from the reminders tab.
Future<void> sendBookingReminder(Dio dio, String bookingId, {String channel = 'Email'}) async {
  try {
    await dio.post('/bookings/$bookingId/remind', data: {'channel': channel});
  } on DioException catch (e) {
    throw ClinicRequestException(_message(e) ?? 'Could not send the reminder.');
  }
}
