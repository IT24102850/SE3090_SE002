import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/available_slot_model.dart';
import '../models/booking_model.dart';
import '../models/booking_type_model.dart';
import '../models/branch_model.dart';
import '../models/resource_model.dart';
import 'api_service_provider.dart';
import 'auth_provider.dart';

// ─────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────
final branchesProvider = FutureProvider.family<List<Branch>, String>((ref, tenantId) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/branches', queryParameters: {'tenantId': tenantId});
  final List<dynamic> data = response.data as List<dynamic>;
  return data.map((j) => Branch.fromJson(j as Map<String, dynamic>)).toList();
});

typedef ResourcesQuery = ({String tenantId, String? branchId});

final resourcesProvider = FutureProvider.family<List<Resource>, ResourcesQuery>((ref, q) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/resources', queryParameters: {
    'tenantId': q.tenantId,
    if (q.branchId != null) 'branchId': q.branchId,
    'pageSize': 100,
  });
  final data = response.data as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>;
  return items.map((j) => Resource.fromJson(j as Map<String, dynamic>)).toList();
});

final bookingTypesProvider = FutureProvider.family<List<BookingType>, String>((ref, tenantId) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/bookingtypes', queryParameters: {
    'tenantId': tenantId,
    'status': 'Active',
  });
  final List<dynamic> data = response.data as List<dynamic>;
  return data.map((j) => BookingType.fromJson(j as Map<String, dynamic>)).toList();
});

typedef SlotsQuery = ({String resourceId, String date, int duration, String bookingTypeId});

final availableSlotsProvider = FutureProvider.family<SlotsResult, SlotsQuery>((ref, q) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/bookings/available-slots', queryParameters: {
    'resourceId': q.resourceId,
    'date': q.date,
    'duration': q.duration,
    'bookingTypeId': q.bookingTypeId,
  });
  return SlotsResult.fromJson(response.data as Map<String, dynamic>);
});

/// The current customer's own bookings, across every business they've
/// booked with. Requires `bookedBy` support on GET /api/bookings.
final myBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null) return [];

  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/bookings', queryParameters: {
    'bookedBy': user.id,
    'pageSize': 100,
  });
  final data = response.data as Map<String, dynamic>;
  final items = data['items'] as List<dynamic>;
  return items.map((j) => Booking.fromJson(j as Map<String, dynamic>)).toList();
});

/// A Staff (doctor) user's own schedule — the resource(s) linked to their
/// login via Resource.LinkedUserId (FR-B8). Same Booking shape as
/// [myBookingsProvider] since the backend projection now matches GetAll's.
final myScheduleProvider = FutureProvider<List<Booking>>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/bookings/my-schedule');
  final List<dynamic> items = response.data as List<dynamic>;
  return items.map((j) => Booking.fromJson(j as Map<String, dynamic>)).toList();
});

// ─────────────────────────────────────────────────────────
// Mutations — plain functions, called with `ref.read(apiServiceProvider)`
// from the screen, matching how auth_provider.dart calls ApiService.dio
// directly rather than going through a repository layer.
// ─────────────────────────────────────────────────────────

class BookingConflictException implements Exception {
  final String message;
  BookingConflictException(this.message);
}

class BookingRequestException implements Exception {
  final String message;
  BookingRequestException(this.message);
}

String? _extractApiMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    return data['message']?.toString() ?? data['title']?.toString();
  }
  return null;
}

/// Creates a booking, echoing the exact [startTimeIso]/[endTimeIso] strings
/// returned by [availableSlotsProvider] — never a locally reconstructed
/// DateTime (see the date/time handling note in the plan).
Future<String> createBooking(
  Dio dio, {
  required String tenantId,
  required String resourceId,
  required String bookingTypeId,
  required String bookedBy,
  required String startTimeIso,
  required String endTimeIso,
  String? title,
  String? notes,
  int? attendeeCount,
}) async {
  try {
    final response = await dio.post('/bookings', data: {
      'tenantId': tenantId,
      'resourceId': resourceId,
      'bookingTypeId': bookingTypeId,
      'bookedBy': bookedBy,
      'startTime': startTimeIso,
      'endTime': endTimeIso,
      'title': title,
      'notes': notes,
      'priority': 'Normal',
      'attendeeCount': attendeeCount,
    });
    return (response.data as Map<String, dynamic>)['id'].toString();
  } on DioException catch (e) {
    if (e.response?.statusCode == 409) {
      throw BookingConflictException(_extractApiMessage(e) ?? 'This time slot is already booked.');
    }
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not create the booking. Please try again.');
  }
}

Future<void> cancelBooking(Dio dio, String bookingId) async {
  try {
    await dio.put('/bookings/$bookingId/cancel');
  } on DioException catch (e) {
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not cancel this booking.');
  }
}

Future<void> rescheduleBooking(
  Dio dio,
  String bookingId, {
  required String newStartTimeIso,
  required String newEndTimeIso,
}) async {
  try {
    await dio.put('/bookings/$bookingId/reschedule', data: {
      'newStartTime': newStartTimeIso,
      'newEndTime': newEndTimeIso,
    });
  } on DioException catch (e) {
    if (e.response?.statusCode == 409) {
      throw BookingConflictException(_extractApiMessage(e) ?? 'That slot conflicts with an existing booking.');
    }
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not reschedule this booking.');
  }
}

/// FR-B7: staff scans the patient's QR (the raw booking ID) to check them in.
Future<void> checkInBooking(Dio dio, String bookingId) async {
  try {
    await dio.post('/bookings/$bookingId/checkin');
  } on DioException catch (e) {
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not check in this booking.');
  }
}

/// FR-B8: doctor marks an appointment's outcome from their schedule.
Future<void> updateBookingStatus(Dio dio, String bookingId, String status) async {
  try {
    await dio.put('/bookings/$bookingId/status', data: {'status': status});
  } on DioException catch (e) {
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not update this booking.');
  }
}

/// FR-B9: creates a weekly recurring series. Echoes the same startTimeIso
/// convention as [createBooking] — pass the exact slot ISO string, not a
/// locally reconstructed DateTime.
Future<RecurringBookingResult> createRecurringBooking(
  Dio dio, {
  required String tenantId,
  required String resourceId,
  required String bookingTypeId,
  required String bookedBy,
  required String firstStartTimeIso,
  required int durationMinutes,
  required String endDate,
  List<int>? daysOfWeek,
  String? title,
  String? notes,
}) async {
  try {
    final response = await dio.post('/bookings/recurring', data: {
      'tenantId': tenantId,
      'resourceId': resourceId,
      'bookingTypeId': bookingTypeId,
      'bookedBy': bookedBy,
      'title': title,
      'notes': notes,
      'firstStartTime': firstStartTimeIso,
      'durationMinutes': durationMinutes,
      'daysOfWeek': daysOfWeek,
      'endDate': endDate,
    });
    final data = response.data as Map<String, dynamic>;
    return RecurringBookingResult(
      requiresApproval: response.statusCode == 202,
      created: (data['created'] as num?)?.toInt() ?? 0,
      totalRequested: (data['totalRequested'] as num?)?.toInt() ?? (data['totalOccurrences'] as num?)?.toInt() ?? 0,
    );
  } on DioException catch (e) {
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not create the recurring series.');
  }
}

class RecurringBookingResult {
  final bool requiresApproval;
  final int created;
  final int totalRequested;

  const RecurringBookingResult({
    required this.requiresApproval,
    required this.created,
    required this.totalRequested,
  });
}
