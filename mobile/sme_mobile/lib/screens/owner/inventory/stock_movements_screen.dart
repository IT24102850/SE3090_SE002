import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Every movement of stock, newest first — the mobile twin of the web Stock
/// Movement Log. This is the audit trail behind the quantities on the
/// manager screen, which is why quantities are never edited directly.
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  ConsumerState<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  String? _type;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final movementsAsync = ref.watch(stockMovementsProvider);

    return OwnerScaffold(
      title: 'Stock Movements',
      subtitle: 'Everything in and out',
      body: movementsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the movement log.',
          onRetry: () => ref.invalidate(stockMovementsProvider),
        ),
        data: (all) {
          final types = all.map((m) => m.movementType).toSet().toList()..sort();
          final rows = all.where((m) {
            if (_type != null && m.movementType != _type) return false;
            if (_search.isEmpty) return true;
            return '${m.item} ${m.sku} ${m.reference ?? ''}'.toLowerCase().contains(_search.toLowerCase());
          }).toList();

          final inbound = all.where((m) => m.isInbound).fold<double>(0, (sum, m) => sum + m.quantity);
          final outbound = all.where((m) => !m.isInbound).fold<double>(0, (sum, m) => sum + m.quantity.abs());

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(stockMovementsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Movements', value: '${all.length}', sub: 'on the log'),
                  StatTile(label: 'In', value: _trim(inbound), sub: 'units received', accent: AppColors.success),
                  StatTile(label: 'Out', value: _trim(outbound), sub: 'units issued', accent: AppColors.warning),
                  StatTile(label: 'Net', value: _trim(inbound - outbound), sub: 'change on hand'),
                ]),
                const SizedBox(height: 14),
                NeonInputField(
                  hintText: 'Search item, SKU or reference',
                  icon: Icons.search_rounded,
                  clearable: true,
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 10),
                FilterChips<String>(
                  options: [
                    (value: null, label: 'All kinds'),
                    for (final t in types) (value: t, label: t),
                  ],
                  selected: _type,
                  onSelected: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.swap_vert_outlined, message: 'No movements match this filter.'),
                  )
                else
                  for (final movement in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              movement.isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                              size: 18,
                              color: movement.isInbound ? AppColors.success : AppColors.warning,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(movement.item,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                                  Text(
                                    [
                                      movement.movementType,
                                      if (movement.occurredAt != null) formatDayMonth(movement.occurredAt!),
                                      if (movement.reference?.isNotEmpty == true) movement.reference!,
                                    ].join(' · '),
                                    style: AppTextStyles.caption,
                                  ),
                                  if (movement.notes?.isNotEmpty == true)
                                    Text(movement.notes!, style: AppTextStyles.caption),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${movement.isInbound ? '+' : ''}${_trim(movement.quantity)}',
                              style: AppTextStyles.body.copyWith(
                                color: movement.isInbound ? AppColors.success : AppColors.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
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
