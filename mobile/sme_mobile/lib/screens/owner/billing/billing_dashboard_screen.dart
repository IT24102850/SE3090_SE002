import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The money screen — the mobile twin of the web Billing Dashboard: what
/// was billed, what came in, what is still owed and how old it is, plus the
/// recurring book and anything waiting on a human.
class BillingDashboardScreen extends ConsumerWidget {
  const BillingDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(billingDashboardProvider);
    final outstanding = ref.watch(outstandingReportProvider).valueOrNull;

    return OwnerScaffold(
      title: 'Billing Dashboard',
      subtitle: 'The last 30 days',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(billingDashboardProvider);
            ref.invalidate(outstandingReportProvider);
          },
        ),
      ],
      body: dashboardAsync.when(
        loading: () => const AppLoader(message: 'Adding it up…'),
        error: (error, _) => ErrorState(
          message: 'Could not load the billing figures.',
          onRetry: () => ref.invalidate(billingDashboardProvider),
        ),
        data: (d) => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async {
            ref.invalidate(billingDashboardProvider);
            ref.invalidate(outstandingReportProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(label: 'Invoiced', value: formatMoney(d.totalInvoiced, d.currency), sub: 'billed in period'),
                StatTile(
                  label: 'Collected',
                  value: formatMoney(d.totalCollected, d.currency),
                  sub: '${d.collectionRate.toStringAsFixed(0)}% of what was billed',
                  accent: AppColors.success,
                ),
                StatTile(
                  label: 'Outstanding',
                  value: formatMoney(d.totalOutstanding, d.currency),
                  sub: 'still owed',
                  accent: d.totalOutstanding > 0 ? AppColors.warning : AppColors.textPrimary,
                ),
                StatTile(
                  label: 'Overdue',
                  value: formatMoney(d.overdueAmount, d.currency),
                  sub: '${d.overdueCount} invoice${d.overdueCount == 1 ? '' : 's'} past terms',
                  accent: d.overdueCount > 0 ? AppColors.error : AppColors.success,
                ),
              ]),
              const SizedBox(height: 14),
              StatGrid(tiles: [
                StatTile(label: 'MRR', value: formatMoney(d.monthlyRecurringRevenue, d.currency), sub: 'recurring each month'),
                StatTile(label: 'Active plans', value: '${d.activeSubscriptions}', sub: 'subscriptions running'),
                StatTile(
                  label: 'Claims pending',
                  value: '${d.pendingClaims}',
                  sub: formatMoney(d.pendingClaimsAmount, d.currency),
                  accent: d.pendingClaims > 0 ? AppColors.warning : AppColors.textPrimary,
                ),
                StatTile(
                  label: 'Approvals',
                  value: '${d.pendingApprovals}',
                  sub: 'waiting on a human',
                  accent: d.pendingApprovals > 0 ? AppColors.warning : AppColors.success,
                ),
              ]),
              const SizedBox(height: 18),
              const SectionHeader('Invoiced against collected'),
              GlassCard(
                child: MiniSeriesChart(
                  primaryLabel: 'Invoiced',
                  secondaryLabel: 'Collected',
                  points: [
                    for (final p in d.revenueSeries)
                      (label: p.date.length >= 10 ? p.date.substring(5) : p.date, primary: p.invoiced, secondary: p.collected),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeader('How old the debt is'),
              GlassCard(
                child: outstanding == null
                    ? const AppLoader(size: 20)
                    : outstanding.count == 0
                        ? Text('Nothing outstanding — every invoice is settled.', style: AppTextStyles.caption)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${formatMoney(outstanding.totalOutstanding, d.currency)} across ${outstanding.count} invoice${outstanding.count == 1 ? '' : 's'}',
                                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              for (final bucket in outstanding.buckets)
                                RankedBar(
                                  label: '${bucket.label}  ·  ${bucket.count}',
                                  trailing: formatMoney(bucket.amount, d.currency),
                                  value: bucket.amount,
                                  max: outstanding.buckets
                                      .map((b) => b.amount)
                                      .fold<double>(0, (a, b) => a > b ? a : b),
                                  color: bucket.label.contains('90') ? AppColors.error : AppColors.warning,
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
