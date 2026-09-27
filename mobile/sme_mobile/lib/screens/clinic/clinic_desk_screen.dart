import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/clinic_models.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../providers/clinic_providers.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/ui/ui.dart';

/// The clinic operations desk on mobile: the same three jobs the web
/// dashboard does, sized for a phone at the reception counter.
///
///   Today     - alerts, the waiting room from check-in to discharge, and
///               the one action that moves each patient forward;
///   Reports   - the KPI set (patients, doctors, appointments, revenue,
///               completion / no-show rates, wait time) over the daily,
///               weekly or monthly window, filterable by branch, doctor,
///               treatment and insurer, with the breakdowns behind them;
///   Reminders - who still needs a reminder for the next two days and
///               who was seen recently with no follow-up booked.
///
/// Backed by ClinicReportsController; the Today tab re-polls every minute
/// so a check-in from the QR scanner shows up without a pull to refresh.
class ClinicDeskScreen extends ConsumerStatefulWidget {
  const ClinicDeskScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<ClinicDeskScreen> createState() => _ClinicDeskScreenState();
}

class _ClinicDeskScreenState extends ConsumerState<ClinicDeskScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.invalidate(clinicFlowProvider);
      ref.invalidate(clinicAlertsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: const AppBackgroundScaffold(
        appBar: GlassAppBar(
          title: 'Clinic desk',
          bottom: TabBar(
            tabs: [Tab(text: 'Today'), Tab(text: 'Reports'), Tab(text: 'Reminders')],
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            children: [_TodayTab(), _ReportsTab(), _RemindersTab()],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Today
// ═════════════════════════════════════════════════════════════════════

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowAsync = ref.watch(clinicFlowProvider);
    final alertsAsync = ref.watch(clinicAlertsProvider);

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async {
        ref.invalidate(clinicFlowProvider);
        ref.invalidate(clinicAlertsProvider);
        await ref.read(clinicFlowProvider.future);
      },
      child: flowAsync.when(
        loading: () => const AppLoader(message: 'Loading the waiting room…'),
        error: (err, _) => ErrorState(
          message: 'Could not load today\'s patient flow.',
          onRetry: () => ref.invalidate(clinicFlowProvider),
        ),
        data: (flow) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _StageStrip(flow: flow),
            const SizedBox(height: 14),
            _FlowMeta(flow: flow),
            const SizedBox(height: 20),
            SectionHeader(
              'Alerts',
              trailing: alertsAsync.maybeWhen(
                data: (a) => Text('${a.length} open'),
                orElse: () => null,
              ),
            ),
            alertsAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(12), child: AppLoader(size: 20)),
              error: (_, __) => const _Muted('Alerts are unavailable right now.'),
              data: (alerts) => alerts.isEmpty
                  ? const _ClearRow('No operational alerts - queue, arrivals, approvals, reminders and stock are within limits.')
                  : Column(children: [for (final a in alerts) _AlertCard(alert: a)]),
            ),
            const SizedBox(height: 20),
            const SectionHeader('Patient flow'),
            if (flow.queue.isEmpty)
              const EmptyState(icon: Icons.event_available_outlined, message: 'No appointments today.')
            else ...[
              for (final entry in flow.queue.where((q) => !q.isDone)) _QueueCard(entry: entry),
              if (flow.queue.any((q) => q.isDone)) ...[
                const SizedBox(height: 8),
                SectionHeader('Done today', trailing: Text('${flow.queue.where((q) => q.isDone).length}')),
                for (final entry in flow.queue.where((q) => q.isDone)) _QueueCard(entry: entry),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.flow});
  final ClinicFlow flow;

  @override
  Widget build(BuildContext context) {
    final longWait = (flow.longestWaitMinutes ?? 0) >= 20;
    final tiles = <(String, int, Color, String?)>[
      ('Scheduled', flow.scheduled, AppColors.cyan, null),
      ('Waiting', flow.waiting, longWait ? AppColors.danger : AppColors.violet, flow.longestWaitMinutes == null ? null : 'longest ${_minutes(flow.longestWaitMinutes)}'),
      ('In consult', flow.inConsultation, AppColors.violet, null),
      ('Discharged', flow.completed, AppColors.success, null),
      ('No-show', flow.noShow, AppColors.danger, null),
      ('Cancelled', flow.cancelled, AppColors.textMuted, null),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 86),
      itemCount: tiles.length,
      itemBuilder: (context, i) {
        final (label, value, color, sub) = tiles[i];
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          borderRadius: AppRadii.row,
          borderColor: color.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(label.toUpperCase(), style: AppTextStyles.label.copyWith(fontSize: 9.5), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
              Text('$value', style: AppTextStyles.stat.copyWith(fontSize: 22, color: color == AppColors.textMuted ? AppColors.textPrimary : color)),
              if (sub != null) Text(sub, style: AppTextStyles.caption.copyWith(fontSize: 10), overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }
}

class _FlowMeta extends StatelessWidget {
  const _FlowMeta({required this.flow});
  final ClinicFlow flow;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      'Doctors on duty ${flow.doctorsOnDuty}',
      if (flow.doctorsInConsultation > 0) '${flow.doctorsInConsultation} consulting',
      'Patients ${flow.patientsToday}',
      if (flow.patientsPerDoctor != null) '${flow.patientsPerDoctor} per doctor',
      'Avg wait ${_minutes(flow.avgWaitMinutesToday?.round())}',
      if (flow.roomsTotal > 0) 'Rooms ${flow.roomsOccupied}/${flow.roomsTotal}',
      if (flow.overdue > 0) '${flow.overdue} overdue',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.endsWith('overdue') ? AppColors.warning.withValues(alpha: 0.16) : AppColors.glassFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(c, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, fontSize: 11.5)),
          ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final ClinicAlert alert;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (alert.severity) {
      'critical' => (AppColors.danger, Icons.priority_high_rounded),
      'warning' => (AppColors.warning, Icons.warning_amber_rounded),
      _ => (AppColors.cyan, Icons.info_outline_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        borderRadius: AppRadii.row,
        borderColor: color.withValues(alpha: 0.4),
        child: Row(
          children: [
            IconWell(icon: icon, color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title, style: AppTextStyles.subtitle.copyWith(fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(alert.detail, style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${alert.count}', style: AppTextStyles.stat.copyWith(fontSize: 20, color: color)),
          ],
        ),
      ),
    );
  }
}

class _QueueCard extends ConsumerStatefulWidget {
  const _QueueCard({required this.entry});
  final ClinicQueueEntry entry;

  @override
  ConsumerState<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends ConsumerState<_QueueCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(clinicFlowProvider);
      ref.invalidate(clinicAlertsProvider);
      ref.invalidate(myScheduleProvider);
      if (mounted) AppSnackBar.success(context, done);
    } on BookingRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } on ClinicRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final dio = ref.read(apiServiceProvider);
    final accent = parseHexColor(e.colorHex) ?? AppColors.violet;
    final waited = e.waitedMinutes;

    final actions = <Widget>[];
    if (!_busy) {
      switch (e.stage) {
        case 'scheduled':
          actions.add(_Action(label: 'Check in', icon: Icons.how_to_reg_rounded, onTap: () => _run(() => checkInBooking(dio, e.bookingId), '${e.patientName} checked in.')));
          if (e.isOverdue) {
            actions.add(_Action(label: 'No-show', icon: Icons.person_off_outlined, color: AppColors.danger, onTap: () => _run(() => updateBookingStatus(dio, e.bookingId, 'NoShow'), 'Marked as a no-show.')));
          } else if (!e.reminderSent) {
            actions.add(_Action(label: 'Remind', icon: Icons.notifications_active_outlined, color: AppColors.textSecondary, onTap: () => _run(() => sendBookingReminder(dio, e.bookingId), 'Reminder sent.')));
          }
        case 'waiting':
          actions.add(_Action(label: 'Start consult', icon: Icons.play_arrow_rounded, color: AppColors.violet, onTap: () => _run(() => updateBookingStatus(dio, e.bookingId, 'InProgress'), '${e.patientName} is with ${e.doctorName}.')));
        case 'inConsultation':
          actions.add(_Action(label: 'Complete', icon: Icons.task_alt_rounded, color: AppColors.success, onTap: () => _run(() => updateBookingStatus(dio, e.bookingId, 'Completed'), 'Visit completed.')));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: e.isDone ? 0.7 : 1,
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          borderRadius: AppRadii.row,
          borderColor: e.isLongWait ? AppColors.danger.withValues(alpha: 0.5) : accent.withValues(alpha: 0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTimeOfDay(e.startLocal), style: AppTextStyles.subtitle.copyWith(fontSize: 13)),
                        if (e.isOverdue) Text('overdue', style: AppTextStyles.caption.copyWith(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.patientName, style: AppTextStyles.subtitle.copyWith(fontSize: 14), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Row(children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${e.treatment} · ${e.doctorName}', style: AppTextStyles.caption.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                        ]),
                        if ((e.patientPhone ?? '').isNotEmpty || (e.insuranceProvider ?? '').isNotEmpty)
                          Text([e.patientPhone, e.insuranceProvider].where((s) => (s ?? '').isNotEmpty).join(' · '), style: AppTextStyles.caption.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusBadge(status: e.status),
                      if (waited != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          e.waitingMinutes != null ? 'waiting ${_minutes(waited)}' : 'waited ${_minutes(waited)}',
                          style: AppTextStyles.caption.copyWith(fontSize: 10.5, color: e.isLongWait ? AppColors.danger : AppColors.textSecondary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: AppLoader(size: 18)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.icon, required this.onTap, this.color = AppColors.cyan});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.button.copyWith(fontSize: 12.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Reports
// ═════════════════════════════════════════════════════════════════════

enum _Preset { today, week, month, daily, weekly, monthly }

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  _Preset _preset = _Preset.month;
  String? _branchId;
  String? _resourceId;
  String? _bookingTypeId;
  String? _insurance;

  ClinicOverviewQuery get _query {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (from, groupBy) = switch (_preset) {
      _Preset.today => (today, 'day'),
      _Preset.week => (today.subtract(const Duration(days: 6)), 'day'),
      _Preset.month => (today.subtract(const Duration(days: 29)), 'day'),
      _Preset.daily => (today.subtract(const Duration(days: 13)), 'day'),
      _Preset.weekly => (today.subtract(const Duration(days: 7 * 12 - 1)), 'week'),
      _Preset.monthly => (DateTime(today.year, today.month - 11, 1), 'month'),
    };
    return (
      from: toApiDateString(from),
      to: toApiDateString(today),
      groupBy: groupBy,
      branchId: _branchId,
      resourceId: _resourceId,
      bookingTypeId: _bookingTypeId,
      insuranceProvider: _insurance,
    );
  }

  bool get _hasFilter => _branchId != null || _resourceId != null || _bookingTypeId != null || _insurance != null;

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final overviewAsync = ref.watch(clinicOverviewProvider(query));

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async {
        ref.invalidate(clinicOverviewProvider(query));
        await ref.read(clinicOverviewProvider(query).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const SectionHeader('Window'),
          _Segmented<_Preset>(
            value: _preset,
            onChanged: (p) => setState(() => _preset = p),
            options: const [
              (_Preset.today, 'Today'),
              (_Preset.week, '7 days'),
              (_Preset.month, '30 days'),
            ],
          ),
          const SizedBox(height: 8),
          _Segmented<_Preset>(
            value: _preset,
            onChanged: (p) => setState(() => _preset = p),
            options: const [
              (_Preset.daily, 'Daily report'),
              (_Preset.weekly, 'Weekly report'),
              (_Preset.monthly, 'Monthly report'),
            ],
          ),
          const SizedBox(height: 16),
          overviewAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: AppLoader(message: 'Building the report…')),
            error: (err, _) => ErrorState(
              message: 'Could not load the clinic report.',
              onRetry: () => ref.invalidate(clinicOverviewProvider(query)),
            ),
            data: (o) => _ReportBody(
              overview: o,
              branchId: _branchId,
              resourceId: _resourceId,
              bookingTypeId: _bookingTypeId,
              insurance: _insurance,
              hasFilter: _hasFilter,
              onBranch: (v) => setState(() => _branchId = v),
              onDoctor: (v) => setState(() => _resourceId = v),
              onTreatment: (v) => setState(() => _bookingTypeId = v),
              onInsurance: (v) => setState(() => _insurance = v),
              onClear: () => setState(() {
                _branchId = null;
                _resourceId = null;
                _bookingTypeId = null;
                _insurance = null;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.overview,
    required this.branchId,
    required this.resourceId,
    required this.bookingTypeId,
    required this.insurance,
    required this.hasFilter,
    required this.onBranch,
    required this.onDoctor,
    required this.onTreatment,
    required this.onInsurance,
    required this.onClear,
  });

  final ClinicOverview overview;
  final String? branchId;
  final String? resourceId;
  final String? bookingTypeId;
  final String? insurance;
  final bool hasFilter;
  final ValueChanged<String?> onBranch;
  final ValueChanged<String?> onDoctor;
  final ValueChanged<String?> onTreatment;
  final ValueChanged<String?> onInsurance;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final k = overview.kpis;
    String money(double v) => '${k.currency} ${v.round()}';
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Filters',
          trailing: hasFilter ? GestureDetector(onTap: onClear, child: const Text('Clear all')) : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (overview.branches.length > 1)
              _FilterDropdown(hint: 'All branches', value: branchId, options: overview.branches, onChanged: onBranch),
            _FilterDropdown(hint: 'All doctors', value: resourceId, options: overview.doctors, onChanged: onDoctor),
            _FilterDropdown(hint: 'All treatments', value: bookingTypeId, options: overview.treatments, onChanged: onTreatment),
            _FilterDropdown(
              hint: 'All insurers',
              value: insurance,
              options: [for (final p in overview.insuranceProviders) ClinicFilterOption(id: p, name: p)],
              onChanged: onInsurance,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SectionHeader('Key indicators'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.75,
          children: [
            _Kpi('Patients', '${k.totalPatients}', '${k.newPatients} new · ${k.activePatients} seen'),
            _Kpi('Doctors', '${k.totalDoctors}', '${k.doctorsOnDutyToday} on duty today'),
            _Kpi('Appointments', '${k.totalAppointments}', '${k.appointmentsToday} today · ${k.pending} pending'),
            _Kpi('Revenue', money(k.revenueRealised), '${money(k.revenueBooked)} booked'),
            _Kpi('Completion', pct(k.completionRate), '${k.completed} completed', color: AppColors.success),
            _Kpi('No-show', pct(k.noShowRate), '${k.noShows} no-show · ${k.cancelled} cancelled', color: AppColors.danger),
            _Kpi('Avg wait', _minutes(k.avgWaitMinutes?.round()), k.waitSamples > 0 ? 'check-in to consult' : 'measured once consults start', color: AppColors.warning),
            _Kpi('Per doctor', k.patientsPerDoctorToday?.toString() ?? '—', 'today · visit ${_minutes(k.avgVisitMinutes?.round())}'),
          ],
        ),
        const SizedBox(height: 18),
        _Breakdown(
          title: 'Appointment trend',
          subtitle: 'by ${overview.groupBy}',
          rows: [for (final t in overview.trend) ClinicBreakdownRow(key: t.label, label: t.label, value: t.appointments, sub: '${t.completed} done${t.noShows > 0 ? ' · ${t.noShows} no-show' : ''}')],
          emptyText: 'No appointments in this window.',
        ),
        _Breakdown(title: 'Appointment status', rows: overview.statusMix, colorFor: (r) => _statusColor(r.key)),
        _Breakdown(
          title: 'Doctor performance',
          subtitle: 'tap to filter',
          rows: overview.byDoctor,
          active: resourceId,
          onSelect: (key) => onDoctor(resourceId == key ? null : key),
        ),
        _Breakdown(
          title: 'Treatment demand',
          subtitle: 'tap to filter',
          rows: overview.byTreatment,
          active: bookingTypeId,
          onSelect: (key) => onTreatment(bookingTypeId == key ? null : key),
        ),
        if (overview.byBranch.length > 1 || branchId != null)
          _Breakdown(
            title: 'Branch comparison',
            subtitle: 'tap to filter',
            rows: overview.byBranch,
            active: branchId,
            onSelect: (key) => onBranch(branchId == key || key == 'none' ? null : key),
          ),
        _Breakdown(
          title: 'Insurance providers',
          subtitle: 'patients · tap to filter',
          rows: overview.byInsurance,
          active: insurance,
          onSelect: (key) => onInsurance(insurance == key ? null : key),
          emptyText: 'No patients registered yet.',
        ),
        _Breakdown(title: 'Booking channels', rows: overview.bySource),
        _Breakdown(title: 'Peak hours', rows: overview.byHour.where((h) => h.value > 0).toList(), emptyText: 'No appointments in this window.'),
      ],
    );
  }
}

Color _statusColor(String status) => BookingStatusVisual.of(status).color;

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.sub, {this.color});
  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      borderRadius: AppRadii.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.label.copyWith(fontSize: 10), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppTextStyles.stat.copyWith(fontSize: 22, color: color ?? AppColors.textPrimary))),
          const SizedBox(height: 2),
          Text(sub, style: AppTextStyles.caption.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.rows,
    this.subtitle,
    this.active,
    this.onSelect,
    this.colorFor,
    this.emptyText = 'Nothing in this window.',
  });

  final String title;
  final String? subtitle;
  final List<ClinicBreakdownRow> rows;
  final String? active;
  final ValueChanged<String>? onSelect;
  final Color Function(ClinicBreakdownRow row)? colorFor;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(1, (m, r) => r.value > m ? r.value : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: AppTextStyles.subtitle.copyWith(fontSize: 14))),
              if (subtitle != null) Text(subtitle!, style: AppTextStyles.caption.copyWith(fontSize: 11)),
            ]),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              _Muted(emptyText)
            else
              for (final r in rows) ...[
                _BarRow(
                  row: r,
                  fraction: r.value / max,
                  color: colorFor?.call(r) ?? AppColors.electricBlue,
                  isActive: active != null && active == r.key,
                  onTap: onSelect == null ? null : () => onSelect!(r.key),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.row, required this.fraction, required this.color, required this.isActive, this.onTap});
  final ClinicBreakdownRow row;
  final double fraction;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isActive ? AppColors.cyan : color;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.sub == null ? row.label : '${row.label} · ${row.sub}',
                    style: AppTextStyles.caption.copyWith(fontSize: 12, color: isActive ? AppColors.cyan : AppColors.textBody, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${row.value}', style: AppTextStyles.subtitle.copyWith(fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    Container(color: AppColors.glassBorder),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(row.value > 0 ? 0.02 : 0, 1),
                      child: Container(color: fill),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({required this.hint, required this.value, required this.options, required this.onChanged});
  final String hint;
  final String? value;
  final List<ClinicFilterOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = options.any((o) => o.id == value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: known == null ? AppColors.inputBorder : AppColors.cyan.withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: known,
          hint: Text(hint, style: AppTextStyles.caption.copyWith(fontSize: 12.5, color: AppColors.textPrimary)),
          dropdownColor: AppColors.overlaySurface,
          iconEnabledColor: AppColors.iconSecondary,
          isDense: true,
          style: AppTextStyles.caption.copyWith(fontSize: 12.5, color: AppColors.textPrimary),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(hint)),
            for (final o in options) DropdownMenuItem<String?>(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: v == value ? AppColors.cyan : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: AppTextStyles.button.copyWith(fontSize: 12, color: v == value ? AppColors.onPrimary : AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Reminders
// ═════════════════════════════════════════════════════════════════════

class _RemindersTab extends ConsumerStatefulWidget {
  const _RemindersTab();

  @override
  ConsumerState<_RemindersTab> createState() => _RemindersTabState();
}

class _RemindersTabState extends ConsumerState<_RemindersTab> {
  String? _busy;

  Future<void> _remind(String bookingId, String name) async {
    setState(() => _busy = bookingId);
    try {
      await sendBookingReminder(ref.read(apiServiceProvider), bookingId);
      ref.invalidate(clinicRemindersProvider);
      ref.invalidate(clinicAlertsProvider);
      if (mounted) AppSnackBar.success(context, 'Reminder sent to $name.');
    } on ClinicRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remindAll(List<ClinicReminderItem> unsent) async {
    setState(() => _busy = 'all');
    var ok = 0;
    final dio = ref.read(apiServiceProvider);
    for (final item in unsent) {
      try {
        await sendBookingReminder(dio, item.bookingId);
        ok++;
      } on ClinicRequestException {
        // Counted below; one failure should not stop the rest.
      }
    }
    ref.invalidate(clinicRemindersProvider);
    ref.invalidate(clinicAlertsProvider);
    if (mounted) {
      setState(() => _busy = null);
      if (ok == unsent.length) {
        AppSnackBar.success(context, '$ok reminder${ok == 1 ? '' : 's'} sent.');
      } else {
        AppSnackBar.error(context, '$ok of ${unsent.length} reminders sent.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(clinicRemindersProvider);

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async {
        ref.invalidate(clinicRemindersProvider);
        await ref.read(clinicRemindersProvider.future);
      },
      child: remindersAsync.when(
        loading: () => const AppLoader(message: 'Loading reminders…'),
        error: (err, _) => ErrorState(
          message: 'Could not load the reminder list.',
          onRetry: () => ref.invalidate(clinicRemindersProvider),
        ),
        data: (r) {
          final unsent = r.items.where((i) => !i.reminderSent).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              SectionHeader(
                'Next ${r.withinHours}h · ${r.items.length} appointments',
                trailing: unsent.isEmpty || _busy != null
                    ? null
                    : GestureDetector(onTap: () => _remindAll(unsent), child: Text('Remind all (${unsent.length})')),
              ),
              if (_busy == 'all') const Padding(padding: EdgeInsets.all(12), child: AppLoader(size: 20, message: 'Sending reminders…')),
              if (r.items.isEmpty)
                const _Muted('Nothing scheduled in the next two days.')
              else
                for (final item in r.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassListTile(
                      title: item.patientName,
                      subtitle: '${formatDayMonth(item.startLocal)} ${formatTimeOfDay(item.startLocal)} · ${item.doctorName} · ${item.treatment}',
                      icon: item.reminderSent ? Icons.mark_email_read_outlined : Icons.notifications_active_outlined,
                      iconColor: item.reminderSent ? AppColors.success : AppColors.warning,
                      showChevron: false,
                      trailing: _busy == item.bookingId
                          ? const AppLoader(size: 18)
                          : TextButton(
                              onPressed: _busy == null ? () => _remind(item.bookingId, item.patientName) : null,
                              child: Text(item.reminderSent ? 'Again' : 'Send', style: AppTextStyles.button.copyWith(fontSize: 12.5, color: AppColors.cyan)),
                            ),
                    ),
                  ),
              const SizedBox(height: 16),
              const SectionHeader('Follow-up candidates', trailing: Text('seen in 30 days, nothing booked')),
              if (r.followUps.isEmpty)
                const _ClearRow('Every patient seen recently has a next visit booked.')
              else
                for (final f in r.followUps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassListTile(
                      title: f.patientName,
                      subtitle: '${f.daysSince == 0 ? 'Seen today' : '${f.daysSince} day${f.daysSince == 1 ? '' : 's'} ago'} · ${f.doctorName} · ${f.treatment}${(f.patientPhone ?? '').isNotEmpty ? ' · ${f.patientPhone}' : ''}',
                      icon: Icons.event_repeat_rounded,
                      iconColor: AppColors.violet,
                      showChevron: false,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Shared bits
// ═════════════════════════════════════════════════════════════════════

String _minutes(int? value) {
  if (value == null) return '—';
  if (value < 60) return '$value min';
  final h = value ~/ 60;
  final m = value % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, style: AppTextStyles.bodyMuted.copyWith(fontSize: 13)),
      );
}

class _ClearRow extends StatelessWidget {
  const _ClearRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(12),
        borderRadius: AppRadii.row,
        borderColor: AppColors.success.withValues(alpha: 0.35),
        child: Row(children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.caption.copyWith(fontSize: 12.5, color: AppColors.textBody))),
        ]),
      );
}
