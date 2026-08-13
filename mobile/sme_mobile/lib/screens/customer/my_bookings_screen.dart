import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/available_slot_model.dart';
import '../../models/booking_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../providers/public_tenant_provider.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/booking_qr_code.dart';
import '../../widgets/date_slot_picker.dart';
import '../../widgets/status_badge.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);
    final tenantsAsync = ref.watch(publicTenantsProvider);
    final Map<String, String> tenantNames = {
      for (final t in tenantsAsync.valueOrNull ?? const []) t.id: t.businessName,
    };

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past')],
          ),
        ),
        body: bookingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => _ErrorState(onRetry: () => ref.invalidate(myBookingsProvider)),
          data: (bookings) {
            final upcoming = bookings.where((b) => b.isUpcoming).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            final past = bookings.where((b) => !b.isUpcoming).toList()
              ..sort((a, b) => b.startTime.compareTo(a.startTime));

            return TabBarView(
              children: [
                _BookingList(bookings: upcoming, tenantNames: tenantNames, showActions: true, emptyMessage: 'No upcoming bookings yet.'),
                _BookingList(bookings: past, tenantNames: tenantNames, showActions: false, emptyMessage: 'No past bookings.'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BookingList extends ConsumerWidget {
  final List<Booking> bookings;
  final Map<String, String> tenantNames;
  final bool showActions;
  final String emptyMessage;

  const _BookingList({
    required this.bookings,
    required this.tenantNames,
    required this.showActions,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(emptyMessage, style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myBookingsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _BookingCard(
          booking: bookings[i],
          tenantName: tenantNames[bookings[i].tenantId] ?? 'Business',
          showActions: showActions,
        ),
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  final Booking booking;
  final String tenantName;
  final bool showActions;

  const _BookingCard({required this.booking, required this.tenantName, required this.showActions});

  void _showQr(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${booking.resourceName} check-in', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            BookingQrCode(bookingId: booking.id),
            const SizedBox(height: 12),
            Text('Show this to reception on arrival', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await cancelBooking(ref.read(apiServiceProvider), booking.id);
      ref.invalidate(myBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final duration = booking.endLocal.difference(booking.startLocal).inMinutes;
    AvailableSlot? picked;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reschedule ${booking.resourceName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: DateSlotPicker(
                      resourceId: booking.resourceId,
                      bookingTypeId: booking.bookingTypeId,
                      durationMinutes: duration,
                      accentColor: parseHexColor(booking.colorHex) ?? AppColors.primary,
                      onSlotSelected: (date, slot) {
                        picked = slot;
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !context.mounted) return;

    try {
      await rescheduleBooking(
        ref.read(apiServiceProvider),
        booking.id,
        newStartTimeIso: picked!.startTime,
        newEndTimeIso: picked!.endTime,
      );
      ref.invalidate(myBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking rescheduled.')));
      }
    } on BookingConflictException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on BookingRequestException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = parseHexColor(booking.colorHex) ?? AppColors.primary;

    return Container(
      decoration: GlassStyle.elevatedCard(radius: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 6, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tenantName, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                      Text('${booking.resourceName} · ${booking.bookingTypeName}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(formatDayMonth(booking.startLocal), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                const SizedBox(width: 14),
                Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('${formatTimeOfDay(booking.startLocal)} – ${formatTimeOfDay(booking.endLocal)}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              ],
            ),
            if (showActions) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showQr(context),
                  icon: const Icon(Icons.qr_code_rounded, size: 16),
                  label: const Text('Show check-in QR'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
              ),
            ],
            if (showActions && (booking.isCancellable || booking.isReschedulable)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (booking.isReschedulable)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reschedule(context, ref),
                        icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                        label: const Text('Reschedule'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                  if (booking.isReschedulable && booking.isCancellable) const SizedBox(width: 10),
                  if (booking.isCancellable)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _cancel(context, ref),
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                        label: const Text('Cancel', style: TextStyle(color: AppColors.danger)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: const BorderSide(color: AppColors.danger),
                        ),
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
            const Text('Could not load your bookings.', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
