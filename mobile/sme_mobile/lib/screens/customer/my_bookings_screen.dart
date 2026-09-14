import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/available_slot_model.dart';
import '../../models/booking_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../providers/public_tenant_provider.dart';
import '../../shared/color_utils.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/booking_qr_code.dart';
import '../../widgets/date_slot_picker.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/ui/ui.dart';

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
      length: 3,
      child: AppBackgroundScaffold(
        appBar: const GlassAppBar(
          title: 'My Bookings',
          bottom: TabBar(
            tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past'), Tab(text: 'Cancelled')],
          ),
        ),
        child: SafeArea(
          child: bookingsAsync.when(
          loading: () => const AppLoader(),
          error: (err, stack) => ErrorState(
            message: 'Could not load your bookings.',
            onRetry: () => ref.invalidate(myBookingsProvider),
          ),
          data: (bookings) {
            final upcoming = bookings.where((b) => b.isUpcoming).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            final cancelled = bookings.where((b) => b.status == 'Cancelled').toList()
              ..sort((a, b) => b.startTime.compareTo(a.startTime));
            final past = bookings.where((b) => !b.isUpcoming && b.status != 'Cancelled').toList()
              ..sort((a, b) => b.startTime.compareTo(a.startTime));

            return TabBarView(
              children: [
                _BookingList(bookings: upcoming, tenantNames: tenantNames, showActions: true, emptyMessage: 'No upcoming bookings yet.'),
                _BookingList(bookings: past, tenantNames: tenantNames, showActions: false, emptyMessage: 'No past bookings.'),
                _BookingList(bookings: cancelled, tenantNames: tenantNames, showActions: false, emptyMessage: 'No cancelled bookings.'),
              ],
            );
          },
        ),
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
      return EmptyState(icon: Icons.event_note_outlined, message: emptyMessage);
    }

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async => ref.invalidate(myBookingsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${booking.resourceName} check-in', style: AppTextStyles.subtitle),
              const SizedBox(height: 20),
              BookingQrCode(bookingId: booking.id),
              const SizedBox(height: 14),
              Text('Show this to reception on arrival', style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel booking?', style: AppTextStyles.title),
        content: Text('This cannot be undone.', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it', style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Cancel booking',
              style: AppTextStyles.subtitle.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await cancelBooking(ref.read(apiServiceProvider), booking.id);
      ref.invalidate(myBookingsProvider);
      if (context.mounted) {
        AppSnackBar.success(context, 'Booking cancelled.');
      }
    } on BookingRequestException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final duration = booking.endLocal.difference(booking.startLocal).inMinutes;
    AvailableSlot? picked;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
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
                Text('Reschedule ${booking.resourceName}', style: AppTextStyles.title.copyWith(fontSize: 16)),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: DateSlotPicker(
                      resourceId: booking.resourceId,
                      bookingTypeId: booking.bookingTypeId,
                      durationMinutes: duration,
                      accentColor: parseHexColor(booking.colorHex) ?? AppColors.cyan,
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
        AppSnackBar.success(context, 'Booking rescheduled.');
      }
    } on BookingConflictException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    } on BookingRequestException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
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
                      Text(tenantName, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                      Text('${booking.resourceName} · ${booking.bookingTypeName}', style: AppTextStyles.subtitle),
                    ],
                  ),
                ),
                StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  booking.bookingUnit == 'Slot' ? Icons.access_time_rounded : Icons.calendar_today_outlined,
                  size: 14,
                  color: AppColors.iconDisabled,
                ),
                const SizedBox(width: 6),
                Text(booking.scheduleSummary, style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
              ],
            ),
            if (showActions) ...[
              const SizedBox(height: 14),
              GhostButton(
                label: 'Show check-in QR',
                icon: Icons.qr_code_rounded,
                height: 44,
                onPressed: () => _showQr(context),
              ),
            ],
            if (showActions && (booking.isCancellable || (booking.isReschedulable && booking.bookingUnit == 'Slot'))) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (booking.isReschedulable && booking.bookingUnit == 'Slot')
                    Expanded(
                      child: GhostButton(
                        label: 'Reschedule',
                        icon: Icons.edit_calendar_outlined,
                        height: 44,
                        onPressed: () => _reschedule(context, ref),
                      ),
                    ),
                  if (booking.isReschedulable && booking.bookingUnit == 'Slot' && booking.isCancellable) const SizedBox(width: 10),
                  if (booking.isCancellable)
                    Expanded(
                      child: GhostButton(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        height: 44,
                        color: AppColors.danger,
                        onPressed: () => _cancel(context, ref),
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
