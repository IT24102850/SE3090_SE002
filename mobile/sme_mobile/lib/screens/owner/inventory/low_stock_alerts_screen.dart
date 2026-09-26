import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/inventory_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'inventory_manager_screen.dart';

/// What needs reordering — the mobile twin of the web Low Stock Alerts.
/// Out-of-stock first, because an item at zero is already costing sales
/// while one merely below its reorder level is not.
class LowStockAlertsScreen extends ConsumerWidget {
  const LowStockAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Low Stock Alerts',
      subtitle: 'What to reorder',
      body: AsyncList<InventoryItem>(
        provider: lowStockProvider,
        onRefresh: (ref) => ref.invalidate(lowStockProvider),
        emptyMessage: 'Everything is above its reorder level.',
        emptyIcon: Icons.verified_outlined,
        errorMessage: 'Could not load the alerts.',
        builder: (items) {
          final sorted = [...items]..sort((a, b) {
              if (a.isOut != b.isOut) return a.isOut ? -1 : 1;
              return (a.quantity - a.reorderLevel).compareTo(b.quantity - b.reorderLevel);
            });
          final out = sorted.where((i) => i.isOut).length;
          final toBuy = sorted.fold<double>(0, (sum, i) {
            final shortfall = (i.reorderLevel - i.quantity).clamp(0, double.infinity);
            return sum + shortfall * i.unitCost;
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(label: 'Flagged', value: '${sorted.length}', sub: 'at or under reorder', accent: AppColors.warning),
                StatTile(label: 'Out of stock', value: '$out', sub: 'nothing on the shelf', accent: AppColors.error),
                StatTile(label: 'Cost to refill', value: formatMoney(toBuy), sub: 'back to reorder level'),
                StatTile(
                  label: 'Branches hit',
                  value: '${sorted.map((i) => i.branch).toSet().length}',
                  sub: 'sites affected',
                ),
              ]),
              const SizedBox(height: 16),
              if (out > 0) ...[
                const SectionHeader('Out of stock'),
                ...sorted.where((i) => i.isOut).map((i) => InventoryItemCard(item: i, showBranch: true)),
                const SizedBox(height: 10),
              ],
              const SectionHeader('Running low'),
              ...sorted.where((i) => !i.isOut).map((i) => InventoryItemCard(item: i, showBranch: true)),
              if (sorted.every((i) => i.isOut))
                Text('Nothing else is close to its reorder level.', style: AppTextStyles.caption),
            ],
          );
        },
      ),
    );
  }
}
