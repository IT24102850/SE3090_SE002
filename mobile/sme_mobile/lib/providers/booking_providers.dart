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

/// Which date ranges are already booked on this resource, for
/// Night/DateRange/Package booking types - lets [DateRangePicker] grey out
/// taken dates. Deliberately not [availableSlotsProvider], which is
/// Slot-specific (fixed-duration sub-day windows).
typedef UnavailableRangesQuery = ({String resourceId, String from, String to});

final unavailableRangesProvider = FutureProvider.family<List<DateTimeRange>, UnavailableRangesQuery>((ref, q) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/bookings/unavailable-ranges', queryParameters: {
    'resourceId': q.resourceId,
    'from': q.from,
    'to': q.to,
  });
  final List<dynamic> data = response.data as List<dynamic>;
  return data.map((j) {
    final m = j as Map<String, dynamic>;
    return DateTimeRange(start: DateTime.parse(m['startTime'].toString()), end: DateTime.parse(m['endTime'].toString()));
  }).toList();
});

class DateTimeRange {
  final DateTime start;
  final DateTime end;
  const DateTimeRange({required this.start, required this.end});

  bool overlaps(DateTime dayStart, DateTime dayEnd) => start.isBefore(dayEnd) && end.isAfter(dayStart);
}

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
  String? formData,
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
      'formData': formData,
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

/// FR-B8: staff adds/edits an appointment's notes from their schedule.
Future<void> updateBookingNotes(Dio dio, String bookingId, String notes) async {
  try {
    await dio.put('/bookings/$bookingId', data: {'notes': notes});
  } on DioException catch (e) {
    throw BookingRequestException(_extractApiMessage(e) ?? 'Could not save notes.');
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

/// Outcome of the Gemini-powered agent pipeline (Planner -> Domain Analysis
/// -> Action/Tool -> Validation/Safety) behind POST /api/agent/find-and-book.
/// Mirrors AgentWorkflowController.FindAndBook's three possible outcomes:
/// booked outright, sent for manager approval (high-impact), or rejected/failed.
class AiPlanOutcome {
  final String status; // Completed | AwaitingApproval | Rejected | Failed
  final String message;
  final String? bookingId;
  final String? workflowId;

  const AiPlanOutcome({required this.status, required this.message, this.bookingId, this.workflowId});

  bool get isBooked => status == 'Completed' && bookingId != null;
}

/// Runs a customer's free-text objective ("find and book the best dive trip
/// this weekend") through the full agentic-ai-service pipeline. Success (200)
/// and awaiting-approval (202) both arrive as normal responses; the safety
/// gate's rejection and any pipeline failure arrive as a 422 DioException.
Future<AiPlanOutcome> findAndBook(
  Dio dio, {
  required String objective,
  required String bookingTypeId,
  DateTime? dateFrom,
  DateTime? dateTo,
}) async {
  try {
    final response = await dio.post('/agent/find-and-book', data: {
      'objective': objective,
      'dateFrom': dateFrom?.toUtc().toIso8601String(),
      'dateTo': dateTo?.toUtc().toIso8601String(),
      'extraConstraints': {'booking_type_id': bookingTypeId},
    });
    final data = response.data as Map<String, dynamic>;
    if (response.statusCode == 202) {
      return AiPlanOutcome(
        status: 'AwaitingApproval',
        message: data['message']?.toString() ?? 'This booking needs manager approval before it\'s confirmed.',
        workflowId: data['workflowId']?.toString(),
      );
    }
    return AiPlanOutcome(
      status: data['status']?.toString() ?? 'Completed',
      message: 'Booking confirmed!',
      bookingId: data['bookingId']?.toString(),
      workflowId: data['workflowId']?.toString(),
    );
  } on DioException catch (e) {
    final data = e.response?.data;
    final message = (data is Map ? data['message']?.toString() : null) ?? _extractApiMessage(e) ?? 'The AI planner could not complete this request.';
    return AiPlanOutcome(
      status: 'Rejected',
      message: message,
      workflowId: data is Map ? data['workflowId']?.toString() : null,
    );
  }
}

/// One of the caller's own agent-driven booking requests (GET
/// /agent/workflow/mine), across every status. Used by MyAiRequestsScreen so
/// a customer whose AI request went to AwaitingApproval has somewhere to
/// track it after the fact — see AgentWorkflowController's Approve/Reject/
/// Apply, which now notify (in-app + push) whoever's RequestedByUserId this
/// matches.
class MyAgentWorkflow {
  final String id;
  final String objective;
  final String status; // Pending | AwaitingApproval | Approved | Rejected | Completed | Failed
  final String? errorLog;
  final String? finalOutcome;
  final DateTime createdAt;
  final DateTime? completedAt;

  const MyAgentWorkflow({
    required this.id,
    required this.objective,
    required this.status,
    this.errorLog,
    this.finalOutcome,
    required this.createdAt,
    this.completedAt,
  });

  factory MyAgentWorkflow.fromJson(Map<String, dynamic> json) => MyAgentWorkflow(
        id: json['id'].toString(),
        objective: json['objective']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Pending',
        errorLog: json['errorLog']?.toString(),
        finalOutcome: json['finalOutcome']?.toString(),
        createdAt: DateTime.parse(json['createdAt'].toString()),
        completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'].toString()),
      );
}

final myAgentWorkflowsProvider = FutureProvider<List<MyAgentWorkflow>>((ref) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/agent/workflow/mine');
  final List<dynamic> items = response.data as List<dynamic>;
  return items.map((j) => MyAgentWorkflow.fromJson(j as Map<String, dynamic>)).toList();
});

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
