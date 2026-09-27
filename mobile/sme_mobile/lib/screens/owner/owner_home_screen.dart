import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/billing_models.dart' show formatMoney;
import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';
import '../../providers/owner_providers.dart';
import '../../shared/date_format.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import '../notifications_screen.dart';
import '../../widgets/route_transitions.dart';
import 'owner_nav.dart';
import 'owner_widgets.dart';

/// The owner's home — the mobile twin of the web dashboard: today at a
/// glance, what needs a decision, and a way into every other part of the
/// workspace without hunting through the drawer.
class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final role = user?.role ?? 'Staff';
    final bookings = ref.watch(ownerBookingsProvider).valueOrNull ?? const [];
    final billing = ref.watch(billingDashboardProvider).valueOrNull;
    final lowStock = ref.watch(lowStockProvider).valueOrNull ?? const [];
    final workflows = ref.watch(agentWorkflowsProvider).valueOrNull ?? const [];
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final today = bookings.where((b) => sameDay(b.startLocal, now)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final pending = bookings.where((b) => b.status == 'Pending').length;
    final waiting = workflows.where((w) => w.awaitingApproval).length;

    return OwnerScaffold(
      title: 'Dashboard',
      subtitle: user?.fullName ?? 'Workspace',
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Notifications',
              onPressed: () => Navigator.of(context).push(slideFadeRoute<void>(const NotificationsScreen())),
            ),
            if (unread > 0)
              Positioned(
                right: 8,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.magenta, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: AppTextStyles.caption.copyWith(color: Colors.white, fontSize: 9),
                  ),
                ),
              ),
          ],
        ),
      ],
      body: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: () async {
          ref.invalidate(ownerBookingsProvider);
          ref.invalidate(billingDashboardProvider);
          ref.invalidate(lowStockProvider);
          ref.invalidate(agentWorkflowsProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            StatGrid(tiles: [
              StatTile(label: 'Today', value: '${today.length}', sub: 'bookings on the day'),
              StatTile(
                label: 'Awaiting approval',
                value: '$pending',
                sub: 'need a decision',
                accent: pending > 0 ? AppColors.warning : AppColors.success,
              ),
              if (billing != null)
                StatTile(
                  label: 'Outstanding',
                  value: formatMoney(billing.totalOutstanding, billing.currency),
                  sub: '${billing.overdueCount} overdue',
                  accent: billing.overdueCount > 0 ? AppColors.error : AppColors.textPrimary,
                )
              else
                const StatTile(label: 'Outstanding', value: '—', sub: 'loading'),
              StatTile(
                label: 'Low stock',
                value: '${lowStock.length}',
                sub: 'items to reorder',
                accent: lowStock.isEmpty ? AppColors.success : AppColors.warning,
              ),
            ]),
            if (waiting > 0) ...[
              const SizedBox(height: 14),
              GlassCard(
                borderColor: AppColors.warning.withValues(alpha: .5),
                child: Row(
                  children: [
                    const Icon(Icons.satellite_alt_outlined, color: AppColors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$waiting agent plan${waiting == 1 ? '' : 's'} waiting for your decision.',
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const SectionHeader('Next up today'),
            if (today.isEmpty)
              GlassCard(child: Text('Nothing booked for today.', style: AppTextStyles.caption))
            else
              for (final booking in today.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 62,
                          child: Text(
                            formatTimeOfDay(booking.startLocal),
                            style: AppTextStyles.caption.copyWith(color: AppColors.cyan),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body,
                              ),
                              Text(booking.resourceName, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        OwnerStatusChip(status: booking.status),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 18),
            const SectionHeader('Everything else'),
            for (final section in ownerSections)
              if (section.forRole(role).where((d) => d.label != 'Dashboard').isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                  child: Text(
                    section.label.toUpperCase(),
                    style: AppTextStyles.label.copyWith(color: AppColors.textMuted, letterSpacing: 1.1),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final destination in section.forRole(role).where((d) => d.label != 'Dashboard'))
                      _DestinationTile(destination: destination),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final OwnerDestination destination;
  const _DestinationTile({required this.destination});

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 32 - 10) / 2;
    return SizedBox(
      width: width.clamp(140, 240),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        // Pushed, not replaced: from the home screen a destination should
        // come back here, which the drawer's own replace behaviour would not.
        onTap: () => openOwnerDestination(context, destination, replace: false),
        child: Row(
          children: [
            Icon(destination.icon, size: 20, color: AppColors.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                destination.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
