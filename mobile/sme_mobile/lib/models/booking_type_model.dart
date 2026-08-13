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
  });

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
    );
  }
}
