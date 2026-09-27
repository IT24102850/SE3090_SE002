/// Models for the owner-side screens (Admin / Manager / Staff) — the mobile
/// twin of the web app's admin workspace. Customer-facing shapes stay in
/// their own files; nothing here is used by the customer tabs.
library;

double _d(dynamic v) => v == null
    ? 0
    : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
int _i(dynamic v) =>
    v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A member of staff as GET /tenant/staff returns them.
class StaffMember {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? branchId;
  final bool isActive;
  final String role;

  const StaffMember({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.branchId,
    required this.isActive,
    required this.role,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'].toString(),
        fullName: (j['fullName'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        phone: j['phone']?.toString(),
        branchId: j['branchId']?.toString(),
        isActive: j['isActive'] == true,
        role: (j['role'] ?? 'Staff').toString(),
      );
}

/// A supplier contact from GET/POST /suppliers.
class Supplier {
  final String id;
  final String name;
  final String email;
  final String phone;
  final DateTime? createdAt;

  const Supplier(
      {required this.id,
      required this.name,
      required this.email,
      required this.phone,
      this.createdAt});

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        createdAt: _dt(j['createdAt']),
      );
}

class AvailabilityDay {
  final String date;
  final int total;
  final int booked;
  final List<AvailabilitySlot> slots;

  const AvailabilityDay(
      {required this.date,
      required this.total,
      required this.booked,
      required this.slots});

  factory AvailabilityDay.fromJson(Map<String, dynamic> j) => AvailabilityDay(
        date: (j['date'] ?? '').toString(),
        total: _i(j['total']),
        booked: _i(j['booked']),
        slots: ((j['slots'] as List<dynamic>?) ?? [])
            .map((slot) =>
                AvailabilitySlot.fromJson(slot as Map<String, dynamic>))
            .toList(),
      );
}

class AvailabilitySlot {
  final String id;
  final String startTime;
  final String endTime;
  final bool isBooked;

  const AvailabilitySlot(
      {required this.id,
      required this.startTime,
      required this.endTime,
      required this.isBooked});

  factory AvailabilitySlot.fromJson(Map<String, dynamic> j) => AvailabilitySlot(
        id: (j['id'] ?? '').toString(),
        startTime: (j['startTime'] ?? '').toString(),
        endTime: (j['endTime'] ?? '').toString(),
        isBooked: j['isBooked'] == true,
      );
}

class AvailabilityLedger {
  final int total;
  final int booked;
  final int free;
  final double utilisationPercent;
  final List<AvailabilityDay> days;

  const AvailabilityLedger(
      {required this.total,
      required this.booked,
      required this.free,
      required this.utilisationPercent,
      required this.days});

  factory AvailabilityLedger.fromJson(Map<String, dynamic> j) =>
      AvailabilityLedger(
        total: _i(j['total']),
        booked: _i(j['booked']),
        free: _i(j['free']),
        utilisationPercent: _d(j['utilisationPercent']),
        days: ((j['days'] as List<dynamic>?) ?? [])
            .map((day) => AvailabilityDay.fromJson(day as Map<String, dynamic>))
            .toList(),
      );
}

class RecurringSeries {
  final String patternId;
  final String title;
  final String resourceName;
  final String frequency;
  final String endDate;
  final String startTime;
  final int total;
  final int remaining;
  final int cancelled;
  final bool isActive;

  const RecurringSeries(
      {required this.patternId,
      required this.title,
      required this.resourceName,
      required this.frequency,
      required this.endDate,
      required this.startTime,
      required this.total,
      required this.remaining,
      required this.cancelled,
      required this.isActive});

  factory RecurringSeries.fromJson(Map<String, dynamic> j) => RecurringSeries(
        patternId: (j['patternId'] ?? '').toString(),
        title: (j['title'] ?? j['bookingTypeName'] ?? 'Recurring booking')
            .toString(),
        resourceName: (j['resourceName'] ?? 'Unassigned').toString(),
        frequency: (j['frequency'] ?? '').toString(),
        endDate: (j['endDate'] ?? '').toString(),
        startTime: (j['startTime'] ?? '').toString(),
        total: _i(j['total']),
        remaining: _i(j['remaining']),
        cancelled: _i(j['cancelled']),
        isActive: j['isActive'] == true,
      );
}

/// The tenant's own settings row (GET/PUT /tenant).
class TenantSettings {
  final String name;
  final String businessType;
  final String? subType;
  final String? logoUrl;
  final bool isActive;
  final int rescheduleCutoffHours;
  final int cancellationCutoffHours;

  const TenantSettings({
    required this.name,
    required this.businessType,
    this.subType,
    this.logoUrl,
    required this.isActive,
    required this.rescheduleCutoffHours,
    required this.cancellationCutoffHours,
  });

  factory TenantSettings.fromJson(Map<String, dynamic> j) => TenantSettings(
        name: (j['name'] ?? '').toString(),
        businessType: (j['businessType'] ?? '').toString(),
        subType: j['subType']?.toString(),
        logoUrl: j['logoUrl']?.toString(),
        isActive: j['isActive'] != false,
        rescheduleCutoffHours: _i(j['rescheduleCutoffHours']),
        cancellationCutoffHours: _i(j['cancellationCutoffHours']),
      );
}

/// One pair of bookings the conflict report flags as overlapping on the
/// same resource (GET /bookings/conflicts).
class ConflictPair {
  final String resourceName;
  final String firstTitle;
  final String secondTitle;
  final DateTime? firstStart;
  final DateTime? secondStart;

  const ConflictPair({
    required this.resourceName,
    required this.firstTitle,
    required this.secondTitle,
    this.firstStart,
    this.secondStart,
  });

  factory ConflictPair.fromJson(Map<String, dynamic> j) {
    final a = (j['bookingA'] as Map<String, dynamic>?) ?? const {};
    final b = (j['bookingB'] as Map<String, dynamic>?) ?? const {};
    return ConflictPair(
      resourceName: (j['resourceName'] ?? '—').toString(),
      firstTitle: (a['title'] ?? 'Booking').toString(),
      secondTitle: (b['title'] ?? 'Booking').toString(),
      firstStart: _dt(a['startTime']),
      secondStart: _dt(b['startTime']),
    );
  }
}

/// GET /bookings/reports/no-shows — the reliability tiles on Reports.
class NoShowStats {
  final int total;
  final int noShows;
  final int completed;
  final int cancelled;
  final double noShowRate;
  final double utilizationRate;

  const NoShowStats({
    required this.total,
    required this.noShows,
    required this.completed,
    required this.cancelled,
    required this.noShowRate,
    required this.utilizationRate,
  });

  factory NoShowStats.fromJson(Map<String, dynamic> j) => NoShowStats(
        total: _i(j['total']),
        noShows: _i(j['noShows']),
        completed: _i(j['completed']),
        cancelled: _i(j['cancelled']),
        noShowRate: _d(j['noShowRate']),
        utilizationRate: _d(j['utilizationRate']),
      );
}

/// One point on a dated series (revenue, bookings, usage).
class SeriesPoint {
  final String label;
  final double value;
  const SeriesPoint({required this.label, required this.value});
}

/// GET /reports/revenue.
class RevenueReport {
  final DateTime? from;
  final DateTime? to;
  final double totalRevenue;
  final List<SeriesPoint> buckets;

  const RevenueReport(
      {this.from, this.to, required this.totalRevenue, required this.buckets});

  factory RevenueReport.fromJson(Map<String, dynamic> j) => RevenueReport(
        from: _dt(j['from']),
        to: _dt(j['to']),
        totalRevenue: _d(j['totalRevenue']),
        buckets: ((j['buckets'] as List<dynamic>?) ?? [])
            .map((b) => SeriesPoint(
                  label:
                      ((b as Map<String, dynamic>)['label'] ?? '').toString(),
                  value: _d(b['revenue']),
                ))
            .toList(),
      );
}
