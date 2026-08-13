/// [startTime]/[endTime] are kept as the raw ISO-8601 strings the API
/// returned. Parse with `.toLocal()` only for display — when submitting a
/// booking, echo these strings back verbatim (see booking_flow_screen.dart).
class AvailableSlot {
  final String startTime;
  final String endTime;
  final bool isAvailable;

  const AvailableSlot({
    required this.startTime,
    required this.endTime,
    required this.isAvailable,
  });

  DateTime get startLocal => DateTime.parse(startTime).toLocal();
  DateTime get endLocal => DateTime.parse(endTime).toLocal();

  factory AvailableSlot.fromJson(Map<String, dynamic> json) {
    return AvailableSlot(
      startTime: json['startTime'].toString(),
      endTime: json['endTime'].toString(),
      isAvailable: json['isAvailable'] as bool? ?? false,
    );
  }
}

class SlotsResult {
  final bool isOpen;
  final List<AvailableSlot> slots;

  const SlotsResult({required this.isOpen, required this.slots});

  factory SlotsResult.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'] as List<dynamic>? ?? [];
    return SlotsResult(
      isOpen: json['isOpen'] as bool? ?? false,
      slots: rawSlots
          .map((s) => AvailableSlot.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
