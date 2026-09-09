import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/booking_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/ui/ui.dart';

/// FR-B8: a doctor's own daily/weekly schedule, with the ability to mark an
/// appointment's outcome. Backed by GET /bookings/my-schedule, which is
/// filtered server-side to the Resource(s) linked to this login.
class MyScheduleScreen extends ConsumerWidget {
  const MyScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(myScheduleProvider);

    return DefaultTabController(
      length: 2,
      child: AppBackgroundScaffold(
        appBar: const GlassAppBar(
          title: 'My Schedule',
          bottom: TabBar(
            tabs: [Tab(text: 'Today'), Tab(text: 'Upcoming')],
          ),
        ),
        child: SafeArea(
          child: scheduleAsync.when(
          loading: () => const AppLoader(),
          error: (err, stack) => ErrorState(
            message: 'Could not load your schedule.',
            onRetry: () => ref.invalidate(myScheduleProvider),
          ),
          data: (bookings) {
            final now = DateTime.now();
            final today = bookings.where((b) => _isSameDay(b.startLocal, now)).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            final upcoming = bookings.where((b) => b.startLocal.isAfter(now) && !_isSameDay(b.startLocal, now)).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));

            return TabBarView(
              children: [
                _ScheduleList(bookings: today, emptyMessage: 'Nothing scheduled today.'),
                _ScheduleList(bookings: upcoming, emptyMessage: 'Nothing else coming up.'),
              ],
            );
          },
        ),
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _ScheduleList extends ConsumerWidget {
  final List<Booking> bookings;
  final String emptyMessage;

  const _ScheduleList({required this.bookings, required this.emptyMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return EmptyState(icon: Icons.event_available_outlined, message: emptyMessage);
    }

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async => ref.invalidate(myScheduleProvider),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ScheduleCard(booking: bookings[i]),
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  final Booking booking;
  const _ScheduleCard({required this.booking});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, String status) async {
    try {
      await updateBookingStatus(ref.read(apiServiceProvider), booking.id, status);
      ref.invalidate(myScheduleProvider);
      if (context.mounted) {
        AppSnackBar.success(context, 'Marked as $status.');
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, e.message);
      }
    }
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: booking.notes ?? '');
    final newNotes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Appointment notes', style: AppTextStyles.title),
        content: NeonInputField(
          controller: controller,
          maxLines: 4,
          hintText: 'Add notes for this appointment...',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: AppTextStyles.subtitle.copyWith(color: AppColors.cyan)),
          ),
        ],
      ),
    );
    if (newNotes == null || !context.mounted) return;

    try {
      await updateBookingNotes(ref.read(apiServiceProvider), booking.id, newNotes);
      ref.invalidate(myScheduleProvider);
      if (context.mounted) {
        AppSnackBar.success(context, 'Notes saved.');
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = parseHexColor(booking.colorHex) ?? AppColors.cyan;

    return GlassCard(
      borderRadius: AppRadii.row,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 6, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.title?.isNotEmpty == true ? booking.title! : '${booking.resourceName} · ${booking.bookingTypeName}',
                    style: AppTextStyles.subtitle.copyWith(fontSize: 14.5),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 13, color: AppColors.iconDisabled),
                      const SizedBox(width: 4),
                      Text('${formatTimeOfDay(booking.startLocal)} – ${formatTimeOfDay(booking.endLocal)}', style: AppTextStyles.caption),
                    ],
                  ),
                  const SizedBox(height: 8),
                  StatusBadge(status: booking.status),
                  if (booking.notes != null && booking.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      booking.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => value == 'notes' ? _editNotes(context, ref) : _setStatus(context, ref, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'InProgress', child: Text('Mark In progress')),
                const PopupMenuItem(value: 'Completed', child: Text('Mark Completed')),
                const PopupMenuItem(value: 'NoShow', child: Text('Mark No-show')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'notes', child: Text('Add/edit notes')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
