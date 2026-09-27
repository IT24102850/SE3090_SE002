import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Where the stock actually goes — the mobile twin of the web Inventory
/// Analytics: what came in against what went out over the period, ranked by
/// item, plus the value sitting on the shelf doing nothing.
class InventoryAnalyticsScreen extends ConsumerWidget {
  const InventoryAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(inventoryUsageProvider);
    final items = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];

    return OwnerScaffold(
      title: 'Inventory Analytics',
      subtitle: 'The last 30 days',
      body: usageAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the usage figures.',
          onRetry: () => ref.invalidate(inventoryUsageProvider),
        ),
        data: (usage) {
          final byIssued = [...usage.items]..sort((a, b) => b.issued.compareTo(a.issued));
          final maxIssued = byIssued.isEmpty ? 0.0 : byIssued.first.issued;

          // Stock nothing has moved in the period: capital tied up for no
          // return, which is the figure this screen exists to surface.
          final movedSkus = usage.items.map((i) => i.sku).toSet();
          final idle = items.where((i) => !movedSkus.contains(i.sku) && i.quantity > 0).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async {
              ref.invalidate(inventoryUsageProvider);
              ref.invalidate(inventoryItemsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Received', value: _trim(usage.totalReceived), sub: 'units in', accent: AppColors.success),
                  StatTile(label: 'Issued', value: _trim(usage.totalIssued), sub: 'units out', accent: AppColors.warning),
                  StatTile(label: 'Net', value: _trim(usage.net), sub: 'change on hand'),
                  StatTile(label: 'Items moved', value: '${usage.items.length}', sub: 'had any movement'),
                ]),
                const SizedBox(height: 16),
                const SectionHeader('In against out'),
                GlassCard(
                  child: MiniSeriesChart(
                    primaryLabel: 'Received',
                    secondaryLabel: 'Issued',
                    primaryColor: AppColors.success,
                    secondaryColor: AppColors.warning,
                    points: [
                      for (final row in usage.items.take(14))
                        (label: row.sku, primary: row.received, secondary: row.issued),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader('Most used'),
                GlassCard(
                  child: byIssued.isEmpty
                      ? Text('Nothing moved in this period.', style: AppTextStyles.caption)
                      : Column(
                          children: [
                            for (final row in byIssued.take(10))
                              RankedBar(
                                label: row.itemName,
                                trailing: '${_trim(row.issued)} out',
                                value: row.issued,
                                max: maxIssued,
                                color: AppColors.warning,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  'Sitting idle',
                  trailing: Text('${idle.length} item${idle.length == 1 ? '' : 's'}', style: AppTextStyles.caption),
                ),
                GlassCard(
                  child: idle.isEmpty
                      ? Text('Everything on the shelf has moved at least once.', style: AppTextStyles.caption)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatMoney(idle.fold<double>(0, (sum, i) => sum + i.stockValue))} of stock has not moved.',
                              style: AppTextStyles.body.copyWith(color: AppColors.warning),
                            ),
                            const SizedBox(height: 8),
                            for (final item in idle.take(12))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text('${item.name} · ${item.branch}',
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                                    ),
                                    Text(formatMoney(item.stockValue), style: AppTextStyles.caption),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}
