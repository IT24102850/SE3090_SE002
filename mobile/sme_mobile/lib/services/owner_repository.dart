import 'package:dio/dio.dart';

import '../models/booking_model.dart';
import '../models/booking_type_model.dart';
import '../models/branch_model.dart';
import '../models/owner_models.dart';
import '../models/resource_model.dart';

/// Every owner-side call that is not billing, inventory or the agent — the
/// scheduling desk, the resource and staff registers, branches, tenant
/// settings and the operational reports.
///
/// One class rather than a provider per endpoint: these screens each need
/// several of them at once, and the write paths (create a resource, then
/// refresh the list) read much better against a single object.
class OwnerRepository {
  final Dio _dio;
  const OwnerRepository(this._dio);

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) from) {
    final raw = data is Map<String, dynamic> ? (data['items'] as List<dynamic>? ?? const []) : (data as List<dynamic>);
    return raw.map((e) => from(e as Map<String, dynamic>)).toList();
  }

  // ── Bookings ──────────────────────────────────────────────────────────

  /// The booking desk's own window. `pageSize` is deliberately generous:
  /// the manager screen derives its KPIs, its day filter and its "next up"
  /// list from one window so they cannot disagree with each other.
  Future<List<Booking>> bookings({
    required String tenantId,
    String? branchId,
    String? status,
    String? resourceId,
    DateTime? from,
    DateTime? to,
    int pageSize = 500,
  }) async {
    String? day(DateTime? d) => d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final response = await _dio.get('/bookings', queryParameters: {
      'tenantId': tenantId,
      if (branchId != null) 'branchId': branchId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (resourceId != null) 'resourceId': resourceId,
      if (from != null) 'dateFrom': day(from),
      if (to != null) 'dateTo': day(to),
      'pageSize': pageSize,
    });
    return _list(response.data, Booking.fromJson);
  }

  Future<void> setBookingStatus(String id, String status) =>
      _dio.put('/bookings/$id/status', data: {'status': status});

  Future<void> cancelBooking(String id) => _dio.put('/bookings/$id/cancel');

  Future<void> checkInBooking(String id) => _dio.post('/bookings/$id/checkin');

  Future<void> rescheduleBooking(String id, DateTime start, DateTime end) => _dio.put(
        '/bookings/$id/reschedule',
        data: {'newStartTime': start.toUtc().toIso8601String(), 'newEndTime': end.toUtc().toIso8601String()},
      );

  Future<void> deleteBooking(String id) => _dio.delete('/bookings/$id');

  Future<void> sendReminder(String id, String channel) =>
      _dio.post('/bookings/$id/remind', data: {'channel': channel});

  Future<List<ConflictPair>> conflicts(String tenantId) async {
    final response = await _dio.get('/bookings/conflicts', queryParameters: {'tenantId': tenantId});
    final data = response.data as Map<String, dynamic>;
    return ((data['conflicts'] as List<dynamic>?) ?? [])
        .map((e) => ConflictPair.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Booking types ─────────────────────────────────────────────────────

  Future<List<BookingType>> bookingTypes(String tenantId, {String? status}) async {
    final response = await _dio.get('/bookingtypes', queryParameters: {
      'tenantId': tenantId,
      if (status != null) 'status': status,
    });
    return _list(response.data, BookingType.fromJson);
  }

  Future<void> saveBookingType({
    String? id,
    required String tenantId,
    required String name,
    String? description,
    required String colorHex,
    required int defaultDurationMinutes,
    required bool requiresApproval,
    int? maxParticipants,
    required int bufferMinutesBefore,
    required int bufferMinutesAfter,
    required String status,
  }) {
    final body = {
      'tenantId': tenantId,
      'name': name,
      'description': description,
      'colorHex': colorHex,
      'defaultDurationMinutes': defaultDurationMinutes,
      'requiresApproval': requiresApproval,
      'maxParticipants': maxParticipants,
      'bufferMinutesBefore': bufferMinutesBefore,
      'bufferMinutesAfter': bufferMinutesAfter,
      'status': status,
    };
    return id == null ? _dio.post('/bookingtypes', data: body) : _dio.put('/bookingtypes/$id', data: body);
  }

  Future<void> deleteBookingType(String id) => _dio.delete('/bookingtypes/$id');

  // ── Resources ─────────────────────────────────────────────────────────

  Future<List<Resource>> resources({required String tenantId, String? branchId, String? category}) async {
    final response = await _dio.get('/resources', queryParameters: {
      'tenantId': tenantId,
      if (branchId != null) 'branchId': branchId,
      if (category != null) 'category': category,
      'pageSize': 200,
    });
    return _list(response.data, Resource.fromJson);
  }

  Future<void> saveResource({
    String? id,
    required String tenantId,
    String? branchId,
    required String name,
    String? code,
    required String category,
    required String status,
    String? description,
    int? capacity,
    double? hourlyRate,
    String? specialty,
  }) {
    final body = {
      'tenantId': tenantId,
      'branchId': branchId,
      'name': name,
      'code': code,
      'category': category,
      'status': status,
      'description': description,
      'capacity': capacity,
      'hourlyRate': hourlyRate,
      'specialty': specialty,
    };
    return id == null ? _dio.post('/resources', data: body) : _dio.put('/resources/$id', data: body);
  }

  Future<void> deleteResource(String id) => _dio.delete('/resources/$id');

  /// The weekly opening pattern for one resource (GET/PUT
  /// /resources/{id}/schedule). Days are 0 = Sunday, matching the backend.
  Future<List<Map<String, dynamic>>> resourceSchedule(String resourceId) async {
    final response = await _dio.get('/resources/$resourceId/schedule');
    final data = response.data;
    final raw = data is Map<String, dynamic> ? (data['days'] ?? data['items'] ?? const []) : data;
    return ((raw as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> setResourceSchedule(String resourceId, List<Map<String, dynamic>> days) =>
      _dio.put('/resources/$resourceId/schedule', data: {'days': days});

  // ── Staff ─────────────────────────────────────────────────────────────

  Future<List<StaffMember>> staff(String tenantId) async {
    final response = await _dio.get('/tenant/staff', queryParameters: {'tenantId': tenantId});
    return _list(response.data, StaffMember.fromJson);
  }

  Future<void> createStaff({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? branchId,
    required String role,
  }) =>
      _dio.post('/tenant/staff', data: {
        'email': email,
        'password': password,
        'fullName': fullName,
        'phone': phone,
        'branchId': branchId,
        'role': role,
      });

  Future<void> updateStaff(String id, {String? branchId, bool? isActive}) =>
      _dio.put('/tenant/staff/$id', data: {
        if (branchId != null) 'branchId': branchId,
        if (isActive != null) 'isActive': isActive,
      });

  // ── Branches ──────────────────────────────────────────────────────────

  Future<List<Branch>> branches(String tenantId) async {
    final response = await _dio.get('/branches', queryParameters: {'tenantId': tenantId});
    return _list(response.data, Branch.fromJson);
  }

  Future<void> createBranch({required String tenantId, required String name, String? address, String? phone}) =>
      _dio.post('/branches', data: {'tenantId': tenantId, 'name': name, 'address': address, 'phone': phone});

  Future<void> updateBranch(String id, {String? name, String? address, String? phone, bool? isActive}) =>
      _dio.put('/branches/$id', data: {
        if (name != null) 'name': name,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (isActive != null) 'isActive': isActive,
      });

  Future<void> deleteBranch(String id) => _dio.delete('/branches/$id');

  // ── Tenant settings ───────────────────────────────────────────────────

  Future<TenantSettings> tenant(String tenantId) async {
    final response = await _dio.get('/tenant', queryParameters: {'tenantId': tenantId});
    return TenantSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateTenant({String? name, int? rescheduleCutoffHours, int? cancellationCutoffHours, String? subType}) =>
      _dio.put('/tenant', data: {
        if (name != null) 'name': name,
        if (rescheduleCutoffHours != null) 'rescheduleCutoffHours': rescheduleCutoffHours,
        if (cancellationCutoffHours != null) 'cancellationCutoffHours': cancellationCutoffHours,
        if (subType != null) 'subType': subType,
      });

  // ── Reports ───────────────────────────────────────────────────────────

  Future<NoShowStats> noShowStats({required String tenantId, required DateTime from, required DateTime to}) async {
    final response = await _dio.get('/bookings/reports/no-shows', queryParameters: {
      'tenantId': tenantId,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
    });
    return NoShowStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<RevenueReport> revenue({required String tenantId, String? branchId}) async {
    final response = await _dio.get('/reports/revenue', queryParameters: {
      'tenantId': tenantId,
      if (branchId != null) 'branchId': branchId,
    });
    return RevenueReport.fromJson(response.data as Map<String, dynamic>);
  }
}
