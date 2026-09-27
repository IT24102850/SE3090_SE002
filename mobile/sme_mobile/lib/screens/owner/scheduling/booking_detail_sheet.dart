import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/booking_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'scheduling_kit.dart';

/// Opens the detail sheet for one booking.
Future<void> showBookingDetailSheet(BuildContext context, WidgetRef ref, Booking booking) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (_) => BookingDetailSheet(booking: booking),
    );

/// Everything about one booking, and everything a desk can do to it.
///
/// The design decision that matters here is the action hierarchy. A booking
/// has exactly one obvious next step at any moment — a pending one wants a
/// decision, a confirmed one wants checking in, one in progress wants
/// finishing — so that step is a full-width primary button and everything
/// else is quieter. Destructive actions sit apart, behind a confirmation,
/// where a thumb will not find them by accident.
class BookingDetailSheet extends ConsumerStatefulWidget {
  final Booking booking;
  const BookingDetailSheet({super.key, required this.booking});

  @override
  ConsumerState<BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends ConsumerState<BookingDetailSheet> {
  bool _busy = false;

  Booking get _booking => widget.booking;

  Future<void> _run(Future<void> Function() action, String done, {bool close = true}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(ownerBookingsProvider);
      ref.invalidate(ownerConflictsProvider);
      if (!mounted) return;
      if (close) Navigator.pop(context);
      AppSnackBar.success(context, done);
    } catch (error) {
      // The API refuses some of these by design — "cannot cancel within 1
      // hour(s) of the appointment" — and its wording is the useful one.
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'That did not go through.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final status = ScheduleStatus.of(b.status);
    final repo = ref.read(ownerRepositoryProvider);
    final minutes = b.endLocal.difference(b.startLocal).inMinutes;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrip(),
            const SizedBox(height: 14),

            // Identity: who and what, then the state.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(AppRadii.image),
                    border: Border.all(color: status.color.withValues(alpha: .4)),
                  ),
                  child: Icon(status.icon, color: status.color, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title?.isNotEmpty == true ? b.title! : b.bookingTypeName,
                        style: AppTextStyles.title,
                      ),
                      const SizedBox(height: 4),
                      StatusPill(status: b.status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // When and where, as one readable block rather than a table of
            // label/value pairs nobody scans.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(AppRadii.row),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                children: [
                  _Fact(
                    icon: Icons.schedule_rounded,
                    title: '${formatTimeOfDay(b.startLocal)} – ${formatTimeOfDay(b.endLocal)}',
                    detail: '${formatFullDate(b.startLocal)} · $minutes min',
                  ),
                  const Divider(color: AppColors.hairline, height: 20),
                  _Fact(
                    icon: Icons.meeting_room_outlined,
                    title: b.resourceName,
                    detail: b.bookingTypeName,
                  ),
                  if (b.attendeeCount != null) ...[
                    const Divider(color: AppColors.hairline, height: 20),
                    _Fact(
                      icon: Icons.groups_rounded,
                      title: '${b.attendeeCount} ${b.attendeeCount == 1 ? 'person' : 'people'}',
                      detail: b.priority == 'Normal' ? 'Standard priority' : '${b.priority} priority',
                    ),
                  ],
                  if (b.notes?.isNotEmpty == true) ...[
                    const Divider(color: AppColors.hairline, height: 20),
                    _Fact(icon: Icons.sticky_note_2_outlined, title: 'Note', detail: b.notes!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (_busy)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 18), child: AppLoader(size: 22)))
            else ...[
              // The one obvious next step.
              ..._primaryAction(b, repo),

              const SizedBox(height: 14),
              Text('Also', style: AppTextStyles.label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (b.isReschedulable)
                    _Secondary(
                      icon: Icons.event_repeat_rounded,
                      label: 'Move',
                      onTap: () => _reschedule(b),
                    ),
                  _Secondary(
                    icon: Icons.notifications_active_outlined,
                    label: 'Remind',
                    onTap: () => _run(() => repo.sendReminder(b.id, 'Email'), 'Reminder sent.', close: false),
                  ),
                  if (status.isOpen && b.status != 'Completed')
                    _Secondary(
                      icon: Icons.person_off_outlined,
                      label: 'No-show',
                      color: AppColors.warning,
                      onTap: () => _confirm(
                        'Mark as a no-show?',
                        'The guest did not arrive. This counts against the no-show rate.',
                        'Mark no-show',
                        () => _run(() => repo.setBookingStatus(b.id, 'NoShow'), 'Marked as a no-show.'),
                      ),
                    ),
                  if (b.isCancellable)
                    _Secondary(
                      icon: Icons.event_busy_rounded,
                      label: 'Cancel',
                      color: AppColors.error,
                      onTap: () => _confirm(
                        'Cancel this booking?',
                        'The guest is told straight away. Cancelling cannot be undone.',
                        'Cancel it',
                        () => _run(() => repo.cancelBooking(b.id), 'Booking cancelled.'),
                      ),
                    ),
                  _Secondary(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    color: AppColors.error,
                    onTap: () => _confirm(
                      'Delete this booking?',
                      'It disappears from the diary and the reports. Cancel it instead if the guest simply is not coming.',
                      'Delete',
                      () => _run(() => repo.deleteBooking(b.id), 'Booking deleted.'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One full-width button for whatever should happen next, plus the decline
  /// half of an approval, which is the only case with two equal answers.
  List<Widget> _primaryAction(Booking b, dynamic repo) {
    switch (b.status) {
      case 'Pending':
        return [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: NeonButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  height: 50,
                  onPressed: () => _run(() => repo.setBookingStatus(b.id, 'Confirmed'), 'Booking confirmed.'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Decline',
                  icon: Icons.close_rounded,
                  height: 50,
                  color: AppColors.error,
                  onPressed: () => _run(() => repo.setBookingStatus(b.id, 'Rejected'), 'Booking declined.'),
                ),
              ),
            ],
          ),
        ];
      case 'Confirmed':
        return [
          NeonButton(
            label: 'Check the guest in',
            icon: Icons.how_to_reg_rounded,
            height: 52,
            onPressed: () => _run(() => repo.checkInBooking(b.id), 'Checked in.'),
          ),
        ];
      case 'CheckedIn':
        return [
          NeonButton(
            label: 'Start',
            icon: Icons.play_arrow_rounded,
            height: 52,
            onPressed: () => _run(() => repo.setBookingStatus(b.id, 'InProgress'), 'Started.'),
          ),
        ];
      case 'InProgress':
        return [
          NeonButton(
            label: 'Mark complete',
            icon: Icons.task_alt_rounded,
            height: 52,
            onPressed: () => _run(() => repo.setBookingStatus(b.id, 'Completed'), 'Marked complete.'),
          ),
        ];
      default:
        // Finished, cancelled or declined: nothing is pending, so offering a
        // loud button would only invite an accident.
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              'Nothing left to do on this one.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ),
        ];
    }
  }

  Future<void> _confirm(String title, String detail, String confirmLabel, VoidCallback then) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
        title: Text(title, style: AppTextStyles.title),
        content: Text(detail, style: AppTextStyles.caption),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: AppTextStyles.caption.copyWith(color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true) then();
  }

  Future<void> _reschedule(Booking b) async {
    final date = await showDatePicker(
      context: context,
      initialDate: b.startLocal,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(b.startLocal));
    if (time == null) return;

    final duration = b.endLocal.difference(b.startLocal);
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _run(
      () => ref.read(ownerRepositoryProvider).rescheduleBooking(b.id, start, start.add(duration)),
      'Moved to ${formatDayMonth(start)} at ${formatTimeOfDay(start)}.',
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Fact({required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.iconSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _Secondary extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Secondary({required this.icon, required this.label, required this.onTap, this.color = AppColors.cyan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Container(
          // 44 high: the smallest target a thumb hits reliably.
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(color: color.withValues(alpha: .38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
