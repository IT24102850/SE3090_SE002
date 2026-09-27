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

/// Stock by site — the mobile twin of the web Branch Overview. Answers the
/// one question a multi-site operator keeps asking: where is the stock, and
/// which branch is about to run out?
class BranchOverviewScreen extends ConsumerStatefulWidget {
  const BranchOverviewScreen({super.key});

  @override
  ConsumerState<BranchOverviewScreen> createState() => _BranchOverviewScreenState();
}

class _BranchOverviewScreenState extends ConsumerState<BranchOverviewScreen> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsProvider);

    return OwnerScaffold(
      title: 'Branch Overview',
      subtitle: 'Stock by site',
      body: itemsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the branch figures.',
          onRetry: () => ref.invalidate(inventoryItemsProvider),
        ),
        data: (all) {
          final byBranch = <String, List<InventoryItem>>{};
          for (final item in all) {
            byBranch.putIfAbsent(item.branch, () => []).add(item);
          }
          final branches = byBranch.keys.toList()..sort();
          final maxValue = byBranch.values
              .map((items) => items.fold<double>(0, (sum, i) => sum + i.stockValue))
              .fold<double>(0, (a, b) => a > b ? a : b);

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(inventoryItemsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Branches', value: '${branches.length}', sub: 'holding stock'),
                  StatTile(label: 'Items', value: '${all.length}', sub: 'across all sites'),
                  StatTile(
                    label: 'Total value',
                    value: formatMoney(all.fold<double>(0, (sum, i) => sum + i.stockValue)),
                    sub: 'on hand',
                  ),
                  StatTile(
                    label: 'Needs reorder',
                    value: '${all.where((i) => i.isLow).length}',
                    sub: 'at or under level',
                    accent: AppColors.warning,
                  ),
                ]),
                const SizedBox(height: 16),
                const SectionHeader('Stock value by branch'),
                GlassCard(
                  child: Column(
                    children: [
                      for (final branch in branches)
                        RankedBar(
                          label: branch,
                          trailing: formatMoney(byBranch[branch]!.fold<double>(0, (sum, i) => sum + i.stockValue)),
                          value: byBranch[branch]!.fold<double>(0, (sum, i) => sum + i.stockValue),
                          max: maxValue,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader('Branches'),
                for (final branch in branches) _branchCard(branch, byBranch[branch]!),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _branchCard(String branch, List<InventoryItem> items) {
    final low = items.where((i) => i.isLow).toList();
    final isOpen = _expanded == branch;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => setState(() => _expanded = isOpen ? null : branch),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconWell(icon: Icons.store_outlined, color: AppColors.cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(branch, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${items.length} item${items.length == 1 ? '' : 's'} · '
                        '${formatMoney(items.fold<double>(0, (sum, i) => sum + i.stockValue))}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                if (low.isNotEmpty) OwnerStatusChip(status: '${low.length} low'),
                Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.chevron),
              ],
            ),
            if (isOpen) ...[
              const Divider(color: AppColors.hairline, height: 20),
              if (low.isEmpty)
                Text('Nothing needs reordering here.', style: AppTextStyles.caption)
              else
                ...low.map((item) => InventoryItemCard(item: item)),
            ],
          ],
        ),
      ),
    );
  }
}
