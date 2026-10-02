/// One entry in a booking's audit trail (GET api/bookings/{id}/history).
///
/// The server writes these from EF Core's change tracker rather than from the
/// screen that made the change, so the trail shows what actually happened.
/// A background service — the hold sweeper, say — reports [actorRole] of
/// 'System' with no name, which is the honest answer rather than a gap.
class BookingEvent {
  final String id;

  /// Created | StatusChanged | Rescheduled | ResourceChanged | Deleted
  final String type;

  /// The previous value; null when the booking was created.
  final String? from;
  final String? to;
  final String? actorName;
  final String? actorRole;
  final String? reason;
  final DateTime? at;

  const BookingEvent({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.actorName,
    required this.actorRole,
    required this.reason,
    required this.at,
  });

  factory BookingEvent.fromJson(Map<String, dynamic> json) => BookingEvent(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        from: json['from'] as String?,
        to: json['to'] as String?,
        actorName: json['actorName'] as String?,
        actorRole: json['actorRole'] as String?,
        reason: json['reason'] as String?,
        at: json['at'] is String ? DateTime.tryParse(json['at'] as String)?.toLocal() : null,
      );

  /// Who did it, or 'System' for a background service.
  String get actor {
    if (actorName != null && actorName!.isNotEmpty) {
      return actorRole != null && actorRole!.isNotEmpty ? '$actorName ($actorRole)' : actorName!;
    }
    return actorRole == 'System' ? 'System' : 'Unknown';
  }
}
