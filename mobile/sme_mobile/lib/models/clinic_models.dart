/// Read models for the clinic operations desk, mirroring the shapes served
/// by backend ClinicReportsController (api/reports/clinic/*) and the React
/// types in frontend/src/features/booking/types.ts.
///
/// Rates and averages are nullable on purpose: the backend sends null when
/// there is nothing to measure yet, and the screens render a dash for it
/// rather than a zero that would read as a real result.
library;

int _int(Object? v) => v == null ? 0 : (v as num).toInt();
double _double(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _doubleOrNull(Object? v) => v == null ? null : (v as num).toDouble();
int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();
String? _str(Object? v) => v?.toString();
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

class ClinicKpis {
  final int totalPatients;
  final int newPatients;
  final int activePatients;
  final int totalDoctors;
  final int doctorsOnDutyToday;
  final int rooms;
  final int totalAppointments;
  final int completed;
  final int noShows;
  final int cancelled;
  final int pending;
  final double? completionRate;
  final double? noShowRate;
  final double? cancellationRate;
  final double revenueRealised;
  final double revenueBooked;
  final String currency;
  final double? avgWaitMinutes;
  final double? avgVisitMinutes;
  final int waitSamples;
  final int appointmentsToday;
  final int patientsToday;
  final double? patientsPerDoctorToday;

  const ClinicKpis({
    required this.totalPatients,
    required this.newPatients,
    required this.activePatients,
    required this.totalDoctors,
    required this.doctorsOnDutyToday,
    required this.rooms,
    required this.totalAppointments,
    required this.completed,
    required this.noShows,
    required this.cancelled,
    required this.pending,
    required this.completionRate,
    required this.noShowRate,
    required this.cancellationRate,
    required this.revenueRealised,
    required this.revenueBooked,
    required this.currency,
    required this.avgWaitMinutes,
    required this.avgVisitMinutes,
    required this.waitSamples,
    required this.appointmentsToday,
    required this.patientsToday,
    required this.patientsPerDoctorToday,
  });

  factory ClinicKpis.fromJson(Map<String, dynamic> j) => ClinicKpis(
        totalPatients: _int(j['totalPatients']),
        newPatients: _int(j['newPatients']),
        activePatients: _int(j['activePatients']),
        totalDoctors: _int(j['totalDoctors']),
        doctorsOnDutyToday: _int(j['doctorsOnDutyToday']),
        rooms: _int(j['rooms']),
        totalAppointments: _int(j['totalAppointments']),
        completed: _int(j['completed']),
        noShows: _int(j['noShows']),
        cancelled: _int(j['cancelled']),
        pending: _int(j['pending']),
        completionRate: _doubleOrNull(j['completionRate']),
        noShowRate: _doubleOrNull(j['noShowRate']),
        cancellationRate: _doubleOrNull(j['cancellationRate']),
        revenueRealised: _double(j['revenueRealised']),
        revenueBooked: _double(j['revenueBooked']),
        currency: _str(j['currency']) ?? 'LKR',
        avgWaitMinutes: _doubleOrNull(j['avgWaitMinutes']),
        avgVisitMinutes: _doubleOrNull(j['avgVisitMinutes']),
        waitSamples: _int(j['waitSamples']),
        appointmentsToday: _int(j['appointmentsToday']),
        patientsToday: _int(j['patientsToday']),
        patientsPerDoctorToday: _doubleOrNull(j['patientsPerDoctorToday']),
      );
}

/// One labelled magnitude - a doctor's load, a treatment's demand, an
/// insurer's patient count. The breakdown lists are all rendered by the
/// same bar widget, so they all reduce to this.
class ClinicBreakdownRow {
  final String key;
  final String label;
  final String? sub;
  final int value;
  final double revenue;

  const ClinicBreakdownRow({
    required this.key,
    required this.label,
    required this.value,
    this.sub,
    this.revenue = 0,
  });
}

class ClinicTrendBucket {
  final String label;
  final int appointments;
  final int completed;
  final int noShows;
  final int cancelled;
  final double revenue;

  const ClinicTrendBucket({
    required this.label,
    required this.appointments,
    required this.completed,
    required this.noShows,
    required this.cancelled,
    required this.revenue,
  });

  factory ClinicTrendBucket.fromJson(Map<String, dynamic> j) => ClinicTrendBucket(
        label: _str(j['label']) ?? '',
        appointments: _int(j['appointments']),
        completed: _int(j['completed']),
        noShows: _int(j['noShows']),
        cancelled: _int(j['cancelled']),
        revenue: _double(j['revenue']),
      );
}

class ClinicFilterOption {
  final String id;
  final String name;
  const ClinicFilterOption({required this.id, required this.name});
}

class ClinicOverview {
  final String groupBy;
  final ClinicKpis kpis;
  final List<ClinicTrendBucket> trend;
  final List<ClinicBreakdownRow> statusMix;
  final List<ClinicBreakdownRow> byDoctor;
  final List<ClinicBreakdownRow> byTreatment;
  final List<ClinicBreakdownRow> byBranch;
  final List<ClinicBreakdownRow> byInsurance;
  final List<ClinicBreakdownRow> bySource;
  final List<ClinicBreakdownRow> byHour;
  final List<ClinicFilterOption> branches;
  final List<ClinicFilterOption> doctors;
  final List<ClinicFilterOption> treatments;
  final List<String> insuranceProviders;

  const ClinicOverview({
    required this.groupBy,
    required this.kpis,
    required this.trend,
    required this.statusMix,
    required this.byDoctor,
    required this.byTreatment,
    required this.byBranch,
    required this.byInsurance,
    required this.bySource,
    required this.byHour,
    required this.branches,
    required this.doctors,
    required this.treatments,
    required this.insuranceProviders,
  });

  factory ClinicOverview.fromJson(Map<String, dynamic> j) {
    final currency = _str((j['kpis'] as Map<String, dynamic>?)?['currency']) ?? 'LKR';
    String money(Object? v) => '$currency ${_double(v).round()}';
    final options = j['filterOptions'] as Map<String, dynamic>? ?? const {};

    return ClinicOverview(
      groupBy: _str(j['groupBy']) ?? 'day',
      kpis: ClinicKpis.fromJson(j['kpis'] as Map<String, dynamic>),
      trend: _list(j['trend']).map(ClinicTrendBucket.fromJson).toList(),
      statusMix: _list(j['statusMix'])
          .map((m) => ClinicBreakdownRow(key: _str(m['status']) ?? '', label: _statusLabel(_str(m['status']) ?? ''), value: _int(m['count'])))
          .toList(),
      byDoctor: _list(j['byDoctor'])
          .map((m) => ClinicBreakdownRow(
                key: _str(m['resourceId']) ?? '',
                label: _str(m['name']) ?? '',
                sub: [
                  '${_int(m['completed'])} done',
                  if (_int(m['noShows']) > 0) '${_int(m['noShows'])} no-show',
                  if (m['avgWaitMinutes'] != null) 'wait ${_double(m['avgWaitMinutes']).round()} min',
                ].join(' · '),
                value: _int(m['appointments']),
                revenue: _double(m['revenue']),
              ))
          .toList(),
      byTreatment: _list(j['byTreatment'])
          .map((m) => ClinicBreakdownRow(
                key: _str(m['bookingTypeId']) ?? '',
                label: _str(m['name']) ?? '',
                sub: _double(m['revenue']) > 0 ? money(m['revenue']) : null,
                value: _int(m['appointments']),
                revenue: _double(m['revenue']),
              ))
          .toList(),
      byBranch: _list(j['byBranch'])
          .map((m) => ClinicBreakdownRow(
                key: _str(m['branchId']) ?? 'none',
                label: _str(m['name']) ?? 'Unassigned',
                sub: '${_int(m['patients'])} patients · ${money(m['revenue'])}',
                value: _int(m['appointments']),
                revenue: _double(m['revenue']),
              ))
          .toList(),
      byInsurance: _list(j['byInsurance'])
          .map((m) => ClinicBreakdownRow(
                key: _str(m['provider']) ?? '',
                label: _str(m['provider']) ?? '',
                sub: _int(m['appointments']) > 0 ? '${_int(m['appointments'])} appt · ${money(m['revenue'])}' : null,
                value: _int(m['patients']),
                revenue: _double(m['revenue']),
              ))
          .toList(),
      bySource: _list(j['bySource'])
          .map((m) => ClinicBreakdownRow(key: _str(m['source']) ?? '', label: _str(m['source']) ?? '', value: _int(m['appointments'])))
          .toList(),
      byHour: _list(j['byHour'])
          .map((m) => ClinicBreakdownRow(
                key: '${_int(m['hour'])}',
                label: '${_int(m['hour']).toString().padLeft(2, '0')}:00',
                value: _int(m['appointments']),
              ))
          .toList(),
      branches: _list(options['branches']).map((m) => ClinicFilterOption(id: _str(m['id']) ?? '', name: _str(m['name']) ?? '')).toList(),
      doctors: _list(options['doctors']).map((m) => ClinicFilterOption(id: _str(m['id']) ?? '', name: _str(m['name']) ?? '')).toList(),
      treatments: _list(options['treatments']).map((m) => ClinicFilterOption(id: _str(m['id']) ?? '', name: _str(m['name']) ?? '')).toList(),
      insuranceProviders: (options['insuranceProviders'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'CheckedIn':
      return 'Checked in';
    case 'InProgress':
      return 'In consultation';
    case 'NoShow':
      return 'No-show';
    case 'WeatherCancelled':
      return 'Weather-cancelled';
    default:
      return status;
  }
}

class ClinicQueueEntry {
  final String bookingId;
  final String patientName;
  final String? patientPhone;
  final String? insuranceProvider;
  final String doctorName;
  final String treatment;
  final String colorHex;
  final DateTime startLocal;
  final String status;
  final String priority;
  final String stage; // scheduled | waiting | inConsultation | completed | noShow | cancelled
  final DateTime? checkInAt;
  final DateTime? consultationStartedAt;
  final int? waitingMinutes;
  final bool isLongWait;
  final bool isOverdue;
  final bool reminderSent;

  const ClinicQueueEntry({
    required this.bookingId,
    required this.patientName,
    required this.patientPhone,
    required this.insuranceProvider,
    required this.doctorName,
    required this.treatment,
    required this.colorHex,
    required this.startLocal,
    required this.status,
    required this.priority,
    required this.stage,
    required this.checkInAt,
    required this.consultationStartedAt,
    required this.waitingMinutes,
    required this.isLongWait,
    required this.isOverdue,
    required this.reminderSent,
  });

  bool get isDone => stage == 'completed' || stage == 'noShow' || stage == 'cancelled';

  /// Minutes the patient waited before the consultation, once both stamps
  /// exist; the live waiting figure otherwise.
  int? get waitedMinutes {
    if (waitingMinutes != null) return waitingMinutes;
    if (checkInAt != null && consultationStartedAt != null) {
      return consultationStartedAt!.difference(checkInAt!).inMinutes;
    }
    return null;
  }

  factory ClinicQueueEntry.fromJson(Map<String, dynamic> j) => ClinicQueueEntry(
        bookingId: _str(j['bookingId']) ?? '',
        patientName: _str(j['patientName']) ?? 'Patient',
        patientPhone: _str(j['patientPhone']),
        insuranceProvider: _str(j['insuranceProvider']),
        doctorName: _str(j['doctorName']) ?? '',
        treatment: _str(j['treatment']) ?? '',
        colorHex: _str(j['colorHex']) ?? '#3B82F6',
        startLocal: DateTime.parse(j['startTime'].toString()).toLocal(),
        status: _str(j['status']) ?? 'Pending',
        priority: _str(j['priority']) ?? 'Normal',
        stage: _str(j['stage']) ?? 'scheduled',
        checkInAt: j['checkInAt'] == null ? null : DateTime.parse(j['checkInAt'].toString()),
        consultationStartedAt: j['consultationStartedAt'] == null ? null : DateTime.parse(j['consultationStartedAt'].toString()),
        waitingMinutes: _intOrNull(j['waitingMinutes']),
        isLongWait: j['isLongWait'] == true,
        isOverdue: j['isOverdue'] == true,
        reminderSent: j['reminderSent'] == true,
      );
}

class ClinicFlow {
  final int scheduled;
  final int waiting;
  final int inConsultation;
  final int completed;
  final int noShow;
  final int cancelled;
  final int? longestWaitMinutes;
  final double? avgWaitMinutesToday;
  final int overdue;
  final int doctorsOnDuty;
  final int doctorsInConsultation;
  final int patientsToday;
  final double? patientsPerDoctor;
  final int roomsTotal;
  final int roomsOccupied;
  final List<ClinicQueueEntry> queue;

  const ClinicFlow({
    required this.scheduled,
    required this.waiting,
    required this.inConsultation,
    required this.completed,
    required this.noShow,
    required this.cancelled,
    required this.longestWaitMinutes,
    required this.avgWaitMinutesToday,
    required this.overdue,
    required this.doctorsOnDuty,
    required this.doctorsInConsultation,
    required this.patientsToday,
    required this.patientsPerDoctor,
    required this.roomsTotal,
    required this.roomsOccupied,
    required this.queue,
  });

  int get remaining => scheduled + waiting + inConsultation;

  factory ClinicFlow.fromJson(Map<String, dynamic> j) {
    final stages = j['stages'] as Map<String, dynamic>? ?? const {};
    final rooms = j['rooms'] as Map<String, dynamic>? ?? const {};
    return ClinicFlow(
      scheduled: _int(stages['scheduled']),
      waiting: _int(stages['waiting']),
      inConsultation: _int(stages['inConsultation']),
      completed: _int(stages['completed']),
      noShow: _int(stages['noShow']),
      cancelled: _int(stages['cancelled']),
      longestWaitMinutes: _intOrNull(j['longestWaitMinutes']),
      avgWaitMinutesToday: _doubleOrNull(j['avgWaitMinutesToday']),
      overdue: _int(j['overdue']),
      doctorsOnDuty: _int(j['doctorsOnDuty']),
      doctorsInConsultation: _int(j['doctorsInConsultation']),
      patientsToday: _int(j['patientsToday']),
      patientsPerDoctor: _doubleOrNull(j['patientsPerDoctor']),
      roomsTotal: _int(rooms['total']),
      roomsOccupied: _int(rooms['occupied']),
      queue: _list(j['queue']).map(ClinicQueueEntry.fromJson).toList(),
    );
  }
}

class ClinicAlert {
  final String id;
  final String severity; // critical | warning | info
  final String category;
  final String title;
  final String detail;
  final int count;

  const ClinicAlert({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.detail,
    required this.count,
  });

  factory ClinicAlert.fromJson(Map<String, dynamic> j) => ClinicAlert(
        id: _str(j['id']) ?? '',
        severity: _str(j['severity']) ?? 'info',
        category: _str(j['category']) ?? '',
        title: _str(j['title']) ?? '',
        detail: _str(j['detail']) ?? '',
        count: _int(j['count']),
      );
}

class ClinicReminderItem {
  final String bookingId;
  final String patientName;
  final String? patientPhone;
  final String doctorName;
  final String treatment;
  final DateTime startLocal;
  final bool reminderSent;

  const ClinicReminderItem({
    required this.bookingId,
    required this.patientName,
    required this.patientPhone,
    required this.doctorName,
    required this.treatment,
    required this.startLocal,
    required this.reminderSent,
  });

  factory ClinicReminderItem.fromJson(Map<String, dynamic> j) => ClinicReminderItem(
        bookingId: _str(j['bookingId']) ?? '',
        patientName: _str(j['patientName']) ?? 'Patient',
        patientPhone: _str(j['patientPhone']),
        doctorName: _str(j['doctorName']) ?? '',
        treatment: _str(j['treatment']) ?? '',
        startLocal: DateTime.parse(j['startTime'].toString()).toLocal(),
        reminderSent: j['reminderSent'] == true,
      );
}

class ClinicFollowUp {
  final String patientId;
  final String patientName;
  final String? patientPhone;
  final String doctorName;
  final String treatment;
  final int daysSince;

  const ClinicFollowUp({
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.doctorName,
    required this.treatment,
    required this.daysSince,
  });

  factory ClinicFollowUp.fromJson(Map<String, dynamic> j) => ClinicFollowUp(
        patientId: _str(j['patientId']) ?? '',
        patientName: _str(j['patientName']) ?? 'Patient',
        patientPhone: _str(j['patientPhone']),
        doctorName: _str(j['doctorName']) ?? '',
        treatment: _str(j['treatment']) ?? '',
        daysSince: _int(j['daysSince']),
      );
}

class ClinicReminders {
  final int withinHours;
  final int unsent;
  final List<ClinicReminderItem> items;
  final List<ClinicFollowUp> followUps;

  const ClinicReminders({
    required this.withinHours,
    required this.unsent,
    required this.items,
    required this.followUps,
  });

  factory ClinicReminders.fromJson(Map<String, dynamic> j) => ClinicReminders(
        withinHours: _int(j['withinHours']),
        unsent: _int(j['unsent']),
        items: _list(j['items']).map(ClinicReminderItem.fromJson).toList(),
        followUps: _list(j['followUps']).map(ClinicFollowUp.fromJson).toList(),
      );
}
