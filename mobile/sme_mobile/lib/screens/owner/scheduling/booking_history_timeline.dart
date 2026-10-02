import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/booking_event_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';

/// A booking's audit trail — the mobile twin of the web app's
/// BookingHistoryTimeline.
///
/// Every row is written by the server from EF Core's change tracker, so this
/// shows what actually happened rather than what a screen happened to report.
class BookingHistoryTimeline extends ConsumerWidget {
  const BookingHistoryTimeline({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(bookingHistoryProvider(bookingId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History'),
        history.when(
          loading: () => Text('Loading history…',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          error: (_, __) => Text('History could not be loaded.',
              style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          data: (events) => events.isEmpty
              ? Text('No changes recorded yet.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: events.map((e) => _EventRow(event: e)).toList(),
                ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final BookingEvent event;

  /// The server stores a reschedule as "<start>/<end>" in ISO 8601.
  static String _window(String? value) {
    if (value == null || value.isEmpty) return 'unknown';
    final parts = value.split('/');
    final start = DateTime.tryParse(parts.first)?.toLocal();
    if (start == null) return value;
    final end = parts.length > 1 ? DateTime.tryParse(parts[1])?.toLocal() : null;
    final from = '${formatDayMonth(start)} ${formatTimeOfDay(start)}';
    return end == null ? from : '$from – ${formatDayMonth(end)} ${formatTimeOfDay(end)}';
  }

  String get _description => switch (event.type) {
        'Created' => 'Booking created as ${event.to}',
        'StatusChanged' => 'Status changed from ${event.from} to ${event.to}',
        'Rescheduled' => 'Moved from ${_window(event.from)} to ${_window(event.to)}',
        'ResourceChanged' => 'Reassigned from ${event.from} to ${event.to}',
        'Deleted' => 'Booking removed',
        _ => event.type,
      };

  IconData get _icon => switch (event.type) {
        'Created' => Icons.add_circle_outline,
        'StatusChanged' => Icons.flag_outlined,
        'Rescheduled' => Icons.schedule_outlined,
        'ResourceChanged' => Icons.swap_horiz_rounded,
        'Deleted' => Icons.delete_outline,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 16, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_description, style: AppTextStyles.body),
                Text(
                  '${event.at == null ? '' : '${formatDayMonth(event.at!)} ${formatTimeOfDay(event.at!)} · '}'
                  'by ${event.actor}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
                if (event.reason != null && event.reason!.isNotEmpty)
                  Text('Reason: ${event.reason}',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
