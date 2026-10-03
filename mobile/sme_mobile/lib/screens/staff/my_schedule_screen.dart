import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/booking_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import '../owner/owner_widgets.dart';
import '../owner/scheduling/scheduling_kit.dart';

/// FR-B8: one staff member's own day.
///
/// Deliberately narrower than the Booking Manager. This is the view someone
/// keeps open *while working*, so it leads with the appointment happening
/// right now, then what is next, and puts marking-off one tap away. The rest
/// of the week is there, but below the fold.
class MyScheduleScreen extends ConsumerStatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  ConsumerState<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends ConsumerState<MyScheduleScreen> {
  DateTime _day = DateTime.now();

  static DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(myScheduleProvider);

    return OwnerScaffold(
      title: 'My Schedule',
      subtitle: 'Your own appointments',
      body: scheduleAsync.when(
        loading: () => const ScheduleSkeleton(),
        error: (error, _) => ErrorState(
          message: 'Could not load your schedule.',
          onRetry: () => ref.invalidate(myScheduleProvider),
        ),
        data: (all) {
          final now = DateTime.now();
          final onDay = all.where((b) => _key(b.startLocal) == _key(_day)).toList()
            ..sort((a, b) => a.startLocal.compareTo(b.startLocal));

          final load = <DateTime, int>{};
          for (final booking in all.where((b) => !ScheduleStatus.of(b.status).isDropped)) {
            load.update(_key(booking.startLocal), (v) => v + 1, ifAbsent: () => 1);
          }

          final live = onDay.where((b) => !ScheduleStatus.of(b.status).isDropped).toList();
          final current = live
              .where((b) => b.startLocal.isBefore(now) && b.endLocal.isAfter(now))
              .cast<Booking?>()
              .firstWhere((_) => true, orElse: () => null);
          final next = live
              .where((b) => b.startLocal.isAfter(now))
              .cast<Booking?>()
              .firstWhere((_) => true, orElse: () => null);
          final done = live.where((b) => ScheduleStatus.of(b.status).isDone).length;

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(myScheduleProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                ScheduleHero(
                  eyebrow: _relativeDayLabel(_day),
                  headline: live.isEmpty ? 'Nothing on' : '${live.length} appointment${live.length == 1 ? '' : 's'}',
                  support: formatFullDate(_day),
                  accent: current != null ? AppColors.violet : AppColors.cyan,
                  chips: [
                    if (live.isNotEmpty)
                      HeroMetric(
                        icon: Icons.task_alt_rounded,
                        value: '$done/${live.length}',
                        label: 'done',
                        color: done == live.length ? AppColors.success : AppColors.textPrimary,
                      ),
                    if (!_isToday(_day))
                      HeroMetric(
                        icon: Icons.today_rounded,
                        value: 'Today',
                        label: '',
                        color: AppColors.cyan,
                        onTap: () => setState(() => _day = DateTime.now()),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // The one thing being worked on, raised above everything.
                if (current != null && _isToday(_day)) ...[
                  _FocusCard(
                    booking: current,
                    label: 'Happening now',
                    accent: AppColors.violet,
                    onStatus: (status) => _setStatus(current, status),
                    onNotes: () => _editNotes(current),
                  ),
                  const SizedBox(height: 12),
                ] else if (next != null && _isToday(_day)) ...[
                  _FocusCard(
                    booking: next,
                    label: 'Up next · ${_inWords(next.startLocal.difference(now))}',
                    accent: AppColors.cyan,
                    onStatus: (status) => _setStatus(next, status),
                    onNotes: () => _editNotes(next),
                  ),
                  const SizedBox(height: 12),
                ],

                WeekStrip(
                  anchor: DateTime.now().subtract(Duration(days: DateTime.now().weekday % 7)),
                  selected: _day,
                  load: load,
                  onSelected: (d) => setState(() => _day = d),
                ),
                const SizedBox(height: 18),

                if (onDay.isEmpty)
                  ScheduleEmpty(
                    icon: Icons.event_available_outlined,
                    title: 'A clear day',
                    detail: 'Nothing is booked against you on ${formatFullDate(_day)}.',
                  )
                else
                  for (final booking in onDay)
                    _ScheduleRow(
                      booking: booking,
                      isNow: booking == current,
                      onStatus: (status) => _setStatus(booking, status),
                      onNotes: () => _editNotes(booking),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isToday(DateTime d) => _key(d) == _key(DateTime.now());

  String _relativeDayLabel(DateTime day) {
    final diff = _key(day).difference(_key(DateTime.now())).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => diff > 0 ? 'In $diff days' : '${-diff} days ago',
    };
  }

  static String _inWords(Duration until) {
    if (until.inMinutes < 1) return 'now';
    if (until.inMinutes < 60) return 'in ${until.inMinutes} min';
    return 'in ${until.inHours}h';
  }

  Future<void> _setStatus(Booking booking, String status) async {
    try {
      await updateBookingStatus(ref.read(apiServiceProvider), booking.id, status);
      ref.invalidate(myScheduleProvider);
      if (mounted) AppSnackBar.success(context, 'Marked ${ScheduleStatus.of(status).label.toLowerCase()}.');
    } on BookingRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _editNotes(Booking booking) async {
    final controller = TextEditingController(text: booking.notes ?? '');
    final notes = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetGrip(),
                const SizedBox(height: 14),
                Text('Notes', style: AppTextStyles.title),
                const SizedBox(height: 4),
                Text('What happened, what to follow up.', style: AppTextStyles.caption),
                const SizedBox(height: 14),
                NeonInputField(controller: controller, maxLines: 5, hintText: 'Add a note for this appointment…'),
                const SizedBox(height: 16),
                NeonButton(
                  label: 'Save note',
                  height: 50,
                  onPressed: () => Navigator.of(sheetContext).pop(controller.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (notes == null || !mounted) return;

    try {
      await updateBookingNotes(ref.read(apiServiceProvider), booking.id, notes);
      ref.invalidate(myScheduleProvider);
      if (mounted) AppSnackBar.success(context, 'Note saved.');
    } on BookingRequestException catch (e) {
      if (mounted) AppSnackBar.error(context, e.message);
    }
  }
}

/// The appointment in hand, given the weight it deserves: bigger type, the
/// service's colour behind it, and its single next action as a real button.
class _FocusCard extends StatelessWidget {
  final Booking booking;
  final String label;
  final Color accent;
  final ValueChanged<String> onStatus;
  final VoidCallback onNotes;

  const _FocusCard({
    required this.booking,
    required this.label,
    required this.accent,
    required this.onStatus,
    required this.onNotes,
  });

  @override
  Widget build(BuildContext context) {
    final status = ScheduleStatus.of(booking.status);
    final next = _nextStep(booking.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: accent.withValues(alpha: .45)),
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: .2), AppColors.glassFill],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, size: 15, color: accent),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: AppTextStyles.label.copyWith(color: accent, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
            style: AppTextStyles.headlineSmall.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatTimeOfDay(booking.startLocal)} – ${formatTimeOfDay(booking.endLocal)} · ${booking.resourceName}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (next != null)
                Expanded(
                  flex: 2,
                  child: NeonButton(
                    label: next.$2,
                    icon: ScheduleStatus.of(next.$1).icon,
                    height: 48,
                    onPressed: () => onStatus(next.$1),
                  ),
                ),
              if (next != null) const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Note',
                  icon: Icons.edit_note_rounded,
                  height: 48,
                  onPressed: onNotes,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The status a booking should move to next, and the words for the button.
(String, String)? _nextStep(String status) => switch (status) {
      'Pending' => ('Confirmed', 'Confirm'),
      'Confirmed' => ('CheckedIn', 'Check in'),
      'CheckedIn' => ('InProgress', 'Start'),
      'InProgress' => ('Completed', 'Complete'),
      _ => null,
    };

class _ScheduleRow extends StatelessWidget {
  final Booking booking;
  final bool isNow;
  final ValueChanged<String> onStatus;
  final VoidCallback onNotes;

  const _ScheduleRow({
    required this.booking,
    required this.isNow,
    required this.onStatus,
    required this.onNotes,
  });

  @override
  Widget build(BuildContext context) {
    final accent = parseHexColor(booking.colorHex) ?? AppColors.cyan;
    final status = ScheduleStatus.of(booking.status);
    final next = _nextStep(booking.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: status.isDropped ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.row),
            border: Border.all(color: isNow ? AppColors.violet.withValues(alpha: .6) : AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 46,
                decoration: BoxDecoration(
                  color: status.isDropped ? AppColors.textMuted : accent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatTimeOfDay(booking.startLocal),
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                    Text(formatTimeOfDay(booking.endLocal), style: AppTextStyles.caption.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(booking.resourceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                    const SizedBox(height: 7),
                    StatusPill(status: booking.status, compact: true),
                  ],
                ),
              ),
              // One action per row, not a toolbar: the step this appointment
              // is actually waiting for.
              if (next != null)
                IconButton(
                  tooltip: next.$2,
                  onPressed: () => onStatus(next.$1),
                  icon: Icon(ScheduleStatus.of(next.$1).icon, color: AppColors.cyan),
                )
              else
                IconButton(
                  tooltip: 'Note',
                  onPressed: onNotes,
                  icon: const Icon(Icons.edit_note_rounded, color: AppColors.iconSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
