import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/booking_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The operational report pack — the mobile twin of the web Reports page:
/// revenue, reliability (no-shows and utilisation), what sells and which
/// resources carry the load.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenue = ref.watch(ownerRevenueProvider);
    final noShows = ref.watch(ownerNoShowStatsProvider);
    final bookings = ref.watch(ownerBookingsProvider).valueOrNull ?? const <Booking>[];
    final billing = ref.watch(billingDashboardProvider).valueOrNull;

    final now = DateTime.now();
    final last30 = bookings.where((b) => b.startLocal.isAfter(now.subtract(const Duration(days: 30)))).toList();

    final byType = <String, int>{};
    final byResource = <String, int>{};
    for (final booking in last30) {
      byType.update(booking.bookingTypeName, (v) => v + 1, ifAbsent: () => 1);
      byResource.update(booking.resourceName, (v) => v + 1, ifAbsent: () => 1);
    }
    final topTypes = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topResources = byResource.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return OwnerScaffold(
      title: 'Reports',
      subtitle: 'The last 30 days',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(ownerRevenueProvider);
            ref.invalidate(ownerNoShowStatsProvider);
            ref.invalidate(ownerBookingsProvider);
          },
        ),
      ],
      body: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: () async {
          ref.invalidate(ownerRevenueProvider);
          ref.invalidate(ownerNoShowStatsProvider);
          ref.invalidate(ownerBookingsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            noShows.when(
              loading: () => const AppLoader(size: 20),
              error: (error, _) => Text('Reliability figures are unavailable.', style: AppTextStyles.caption),
              data: (stats) => StatGrid(tiles: [
                StatTile(label: 'Bookings', value: '${stats.total}', sub: 'in the period'),
                StatTile(
                  label: 'Completed',
                  value: '${stats.completed}',
                  sub: 'turned up and done',
                  accent: AppColors.success,
                ),
                StatTile(
                  label: 'No-show rate',
                  value: '${stats.noShowRate.toStringAsFixed(1)}%',
                  sub: '${stats.noShows} missed',
                  accent: stats.noShowRate > 10 ? AppColors.error : AppColors.success,
                ),
                StatTile(
                  label: 'Utilisation',
                  value: '${stats.utilizationRate.toStringAsFixed(1)}%',
                  sub: 'of capacity used',
                  accent: stats.utilizationRate < 50 ? AppColors.warning : AppColors.success,
                ),
              ]),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Revenue'),
            revenue.when(
              loading: () => const GlassCard(child: AppLoader(size: 20)),
              error: (error, _) => GlassCard(
                child: Text('Revenue figures are unavailable.', style: AppTextStyles.caption),
              ),
              data: (report) => GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatMoney(report.totalRevenue), style: AppTextStyles.stat),
                    Text('taken in the period', style: AppTextStyles.caption),
                    const SizedBox(height: 12),
                    MiniSeriesChart(
                      primaryLabel: 'Revenue',
                      secondaryLabel: 'Collected',
                      points: [
                        for (final bucket in report.buckets)
                          (
                            label: bucket.label.length >= 10 ? bucket.label.substring(5) : bucket.label,
                            primary: bucket.value,
                            secondary: 0.0,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (billing != null) ...[
              const SizedBox(height: 18),
              const SectionHeader('Billing at a glance'),
              GlassCard(
                child: Column(
                  children: [
                    DetailRow(label: 'Invoiced', value: formatMoney(billing.totalInvoiced, billing.currency)),
                    DetailRow(
                      label: 'Collected',
                      value: formatMoney(billing.totalCollected, billing.currency),
                      valueColor: AppColors.success,
                    ),
                    DetailRow(
                      label: 'Outstanding',
                      value: formatMoney(billing.totalOutstanding, billing.currency),
                      valueColor: AppColors.warning,
                    ),
                    DetailRow(label: 'Collection rate', value: '${billing.collectionRate.toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const SectionHeader('What sells'),
            GlassCard(
              child: topTypes.isEmpty
                  ? Text('No bookings in the period.', style: AppTextStyles.caption)
                  : Column(
                      children: [
                        for (final entry in topTypes.take(8))
                          RankedBar(
                            label: entry.key,
                            trailing: '${entry.value}',
                            value: entry.value.toDouble(),
                            max: topTypes.first.value.toDouble(),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Busiest resources'),
            GlassCard(
              child: topResources.isEmpty
                  ? Text('No bookings in the period.', style: AppTextStyles.caption)
                  : Column(
                      children: [
                        for (final entry in topResources.take(8))
                          RankedBar(
                            label: entry.key,
                            trailing: '${entry.value}',
                            value: entry.value.toDouble(),
                            max: topResources.first.value.toDouble(),
                            color: AppColors.violet,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Where bookings end up'),
            GlassCard(
              child: Column(
                children: [
                  for (final status in const ['Completed', 'Confirmed', 'Pending', 'Cancelled', 'NoShow'])
                    DetailRow(
                      label: status,
                      value: '${last30.where((b) => b.status == status).length}',
                      valueColor: OwnerStatusChip.colorOf(status),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
