import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/booking_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart';

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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Schedule'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Today'), Tab(text: 'Upcoming')],
          ),
        ),
        body: scheduleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => _ErrorState(onRetry: () => ref.invalidate(myScheduleProvider)),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(emptyMessage, style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myScheduleProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked as $status.')));
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: booking.notes ?? '');
    final newNotes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Appointment notes'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Add notes for this appointment...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (newNotes == null || !context.mounted) return;

    try {
      await updateBookingNotes(ref.read(apiServiceProvider), booking.id, newNotes);
      ref.invalidate(myScheduleProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes saved.')));
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = parseHexColor(booking.colorHex) ?? AppColors.primary;

    return Container(
      decoration: GlassStyle.elevatedCard(radius: 16),
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
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text('${formatTimeOfDay(booking.startLocal)} – ${formatTimeOfDay(booking.endLocal)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
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

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.danger.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            const Text('Could not load your schedule.', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
