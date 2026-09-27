/// Models for the owner-side screens (Admin / Manager / Staff) — the mobile
/// twin of the web app's admin workspace. Customer-facing shapes stay in
/// their own files; nothing here is used by the customer tabs.
library;

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
int _i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

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

  const RevenueReport({this.from, this.to, required this.totalRevenue, required this.buckets});

  factory RevenueReport.fromJson(Map<String, dynamic> j) => RevenueReport(
        from: _dt(j['from']),
        to: _dt(j['to']),
        totalRevenue: _d(j['totalRevenue']),
        buckets: ((j['buckets'] as List<dynamic>?) ?? [])
            .map((b) => SeriesPoint(
                  label: ((b as Map<String, dynamic>)['label'] ?? '').toString(),
                  value: _d(b['revenue']),
                ))
            .toList(),
      );
}
