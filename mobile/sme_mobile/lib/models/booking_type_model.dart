import 'dart:convert';

class BookingType {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String colorHex;
  final String status;
  final int defaultDurationMinutes;
  final bool requiresApproval;
  final int? maxParticipants;
  final int bufferMinutesBefore;
  final int bufferMinutesAfter;

  /// "Slot" (fixed-duration time slot, the original/default shape) | "Night"
  /// (check-in/check-out) | "DateRange" (multi-day) | "Package" (multi-day
  /// itinerary). Defaults to "Slot" so existing/older API responses without
  /// this field keep working exactly as before.
  final String bookingUnit;
  final String? configJson;

  const BookingType({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.colorHex,
    required this.status,
    required this.defaultDurationMinutes,
    required this.requiresApproval,
    this.maxParticipants,
    required this.bufferMinutesBefore,
    required this.bufferMinutesAfter,
    this.bookingUnit = 'Slot',
    this.configJson,
  });

  /// Lazily-parsed config bag (capacity, weatherDependent, minNights,
  /// checkInTime/checkOutTime, itinerary, ...) - null if not set or invalid.
  Map<String, dynamic>? get config {
    if (configJson == null || configJson!.isEmpty) return null;
    try {
      return jsonDecode(configJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  factory BookingType.fromJson(Map<String, dynamic> json) {
    return BookingType(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString(),
      colorHex: json['colorHex']?.toString() ?? '#3B82F6',
      status: json['status']?.toString() ?? 'Active',
      defaultDurationMinutes: (json['defaultDurationMinutes'] as num?)?.toInt() ?? 60,
      requiresApproval: json['requiresApproval'] as bool? ?? false,
      maxParticipants: json['maxParticipants'] == null ? null : (json['maxParticipants'] as num).toInt(),
      bufferMinutesBefore: (json['bufferMinutesBefore'] as num?)?.toInt() ?? 0,
      bufferMinutesAfter: (json['bufferMinutesAfter'] as num?)?.toInt() ?? 0,
      bookingUnit: json['bookingUnit']?.toString() ?? 'Slot',
      configJson: json['configJson']?.toString(),
    );
  }
}
