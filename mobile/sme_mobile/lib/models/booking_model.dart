class Booking {
  final String id;
  final String tenantId;
  final String resourceId;
  final String resourceName;
  final String bookingTypeId;
  final String bookingTypeName;
  final String colorHex;
  final String bookedBy;
  final String? bookedFor;
  final String? title;
  final String? notes;
  final String startTime;
  final String endTime;
  final String status;
  final String priority;
  final int? attendeeCount;
  final double? totalCost;
  final String createdAt;

  const Booking({
    required this.id,
    required this.tenantId,
    required this.resourceId,
    required this.resourceName,
    required this.bookingTypeId,
    required this.bookingTypeName,
    required this.colorHex,
    required this.bookedBy,
    this.bookedFor,
    this.title,
    this.notes,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.priority,
    this.attendeeCount,
    this.totalCost,
    required this.createdAt,
  });

  DateTime get startLocal => DateTime.parse(startTime).toLocal();
  DateTime get endLocal => DateTime.parse(endTime).toLocal();

  bool get isUpcoming =>
      startLocal.isAfter(DateTime.now()) &&
      status != 'Cancelled' &&
      status != 'Completed' &&
      status != 'NoShow' &&
      status != 'Rejected';

  bool get isCancellable => status == 'Pending' || status == 'Confirmed';
  bool get isReschedulable => status == 'Pending' || status == 'Confirmed';

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'].toString(),
      tenantId: json['tenantId'].toString(),
      resourceId: json['resourceId'].toString(),
      resourceName: json['resourceName']?.toString() ?? '',
      bookingTypeId: json['bookingTypeId'].toString(),
      bookingTypeName: json['bookingTypeName']?.toString() ?? '',
      colorHex: json['colorHex']?.toString() ?? '#3B82F6',
      bookedBy: json['bookedBy'].toString(),
      bookedFor: json['bookedFor']?.toString(),
      title: json['title']?.toString(),
      notes: json['notes']?.toString(),
      startTime: json['startTime'].toString(),
      endTime: json['endTime'].toString(),
      status: json['status']?.toString() ?? 'Pending',
      priority: json['priority']?.toString() ?? 'Normal',
      attendeeCount: json['attendeeCount'] == null ? null : (json['attendeeCount'] as num).toInt(),
      totalCost: json['totalCost'] == null ? null : (json['totalCost'] as num).toDouble(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
