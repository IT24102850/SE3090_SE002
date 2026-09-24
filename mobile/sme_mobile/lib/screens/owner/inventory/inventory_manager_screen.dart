import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/inventory_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Stock on hand — the mobile twin of the web Inventory Manager, with the
/// three writes that actually happen on a shop floor: receiving a delivery,
/// correcting a count, and recording waste.
class InventoryManagerScreen extends ConsumerStatefulWidget {
  const InventoryManagerScreen({super.key});

  @override
  ConsumerState<InventoryManagerScreen> createState() => _InventoryManagerScreenState();
}

class _InventoryManagerScreenState extends ConsumerState<InventoryManagerScreen> {
  String _search = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsProvider);

    return OwnerScaffold(
      title: 'Inventory Manager',
      subtitle: 'What is on the shelf',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New item'),
      ),
      body: itemsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the inventory.',
          onRetry: () => ref.invalidate(inventoryItemsProvider),
        ),
        data: (all) {
          final categories = all.map((i) => i.category).toSet().toList()..sort();
          final rows = all.where((i) {
            if (_category != null && i.category != _category) return false;
            if (_search.isEmpty) return true;
            return '${i.name} ${i.sku}'.toLowerCase().contains(_search.toLowerCase());
          }).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async {
              ref.invalidate(inventoryItemsProvider);
              ref.invalidate(lowStockProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Items', value: '${all.length}', sub: 'on the register'),
                  StatTile(
                    label: 'Low stock',
                    value: '${all.where((i) => i.isLow && !i.isOut).length}',
                    sub: 'at or under reorder',
                    accent: AppColors.warning,
                  ),
                  StatTile(
                    label: 'Out of stock',
                    value: '${all.where((i) => i.isOut).length}',
                    sub: 'nothing left',
                    accent: AppColors.error,
                  ),
                  StatTile(
                    label: 'Stock value',
                    value: formatMoney(all.fold<double>(0, (sum, i) => sum + i.stockValue)),
                    sub: 'quantity × unit cost',
                  ),
                ]),
                const SizedBox(height: 14),
                NeonInputField(
                  hintText: 'Search name or SKU',
                  icon: Icons.search_rounded,
                  clearable: true,
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 10),
                FilterChips<String>(
                  options: [
                    (value: null, label: 'All categories'),
                    for (final c in categories) (value: c, label: c),
                  ],
                  selected: _category,
                  onSelected: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.inventory_2_outlined, message: 'No items match this filter.'),
                  )
                else
                  ...rows.map((item) => InventoryItemCard(item: item)),
              ],
            ),
          );
        },
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, InventoryItem? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ItemForm(existing: existing),
      ),
    );
    if (saved == true) {
      ref.invalidate(inventoryItemsProvider);
      ref.invalidate(lowStockProvider);
    }
  }
}

/// Shared by the manager, the low-stock list and the branch overview, so a
/// row looks and behaves the same wherever stock is shown.
class InventoryItemCard extends ConsumerStatefulWidget {
  final InventoryItem item;
  final bool showBranch;

  const InventoryItemCard({super.key, required this.item, this.showBranch = false});

  @override
  ConsumerState<InventoryItemCard> createState() => _InventoryItemCardState();
}

class _InventoryItemCardState extends ConsumerState<InventoryItemCard> {
  bool _busy = false;

  Future<void> _move(String kind) async {
    final quantity = TextEditingController();
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text(
          switch (kind) { 'receive' => 'Receive stock', 'waste' => 'Record waste', _ => 'Correct the count' },
          style: AppTextStyles.title,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeonInputField(
              label: 'Quantity',
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              helperText: kind == 'adjust' ? 'Negative takes stock off' : null,
            ),
            const SizedBox(height: 10),
            NeonInputField(label: kind == 'waste' ? 'Reason' : 'Note', controller: note),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return;

    final value = double.tryParse(quantity.text) ?? 0;
    if (value == 0) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      switch (kind) {
        case 'receive':
          await repo.receive(widget.item.id, value, notes: note.text.trim());
        case 'waste':
          await repo.waste(widget.item.id, value, reason: note.text.trim());
        default:
          await repo.adjust(widget.item.id, value, notes: note.text.trim());
      }
      ref.invalidate(inventoryItemsProvider);
      ref.invalidate(lowStockProvider);
      ref.invalidate(stockMovementsProvider);
      ref.invalidate(inventoryUsageProvider);
      if (mounted) AppSnackBar.success(context, 'Stock updated.');
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not update this item.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accent = item.isOut ? AppColors.error : (item.isLow ? AppColors.warning : AppColors.success);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${item.sku} · ${item.category}${widget.showBranch ? ' · ${item.branch}' : ''}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_trim(item.quantity)} ${item.unit}',
                      style: AppTextStyles.body.copyWith(color: accent, fontWeight: FontWeight.w700),
                    ),
                    Text('reorder at ${_trim(item.reorderLevel)}', style: AppTextStyles.caption),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(formatMoney(item.unitCost), style: AppTextStyles.caption),
                Text(' per ${item.unit}', style: AppTextStyles.caption),
                const Spacer(),
                Text('worth ${formatMoney(item.stockValue)}', style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 10),
            if (_busy)
              const AppLoader(size: 18)
            else
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Receive',
                      icon: Icons.add_box_outlined,
                      height: 38,
                      color: AppColors.success,
                      onPressed: () => _move('receive'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(
                      label: 'Adjust',
                      icon: Icons.tune_rounded,
                      height: 38,
                      onPressed: () => _move('adjust'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(
                      label: 'Waste',
                      icon: Icons.delete_sweep_outlined,
                      height: 38,
                      color: AppColors.warning,
                      onPressed: () => _move('waste'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 14.000 reads badly on a shelf label; 14 does.
  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

class _ItemForm extends ConsumerStatefulWidget {
  final InventoryItem? existing;
  const _ItemForm({this.existing});

  @override
  ConsumerState<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<_ItemForm> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _reorder;
  late final TextEditingController _unitCost;
  String? _branchId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _sku = TextEditingController(text: e?.sku ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _quantity = TextEditingController(text: e?.quantity.toString() ?? '0');
    _reorder = TextEditingController(text: e?.reorderLevel.toString() ?? '0');
    _unitCost = TextEditingController(text: e?.unitCost.toString() ?? '0');
    _branchId = e?.branchId;
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _description, _quantity, _reorder, _unitCost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _sku.text.trim().isEmpty) {
      AppSnackBar.error(context, 'A name and an SKU, please.');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      if (widget.existing == null) {
        await repo.createItem(
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          branchId: _branchId,
          quantity: double.tryParse(_quantity.text) ?? 0,
          reorderLevel: double.tryParse(_reorder.text) ?? 0,
          unitCost: double.tryParse(_unitCost.text),
        );
      } else {
        await repo.updateItem(
          widget.existing!.id,
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          categoryId: widget.existing!.categoryId,
          unitId: widget.existing!.unitId,
          branchId: _branchId,
          reorderLevel: double.tryParse(_reorder.text) ?? 0,
          unitCost: double.tryParse(_unitCost.text),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(context, serverMessage(error, 'Could not save this item — the SKU may already exist.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(ownerBranchesProvider).valueOrNull ?? const [];
    final isNew = widget.existing == null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isNew ? 'New item' : 'Edit item', style: AppTextStyles.title),
            const SizedBox(height: 12),
            NeonInputField(label: 'Name', controller: _name),
            const SizedBox(height: 10),
            NeonInputField(label: 'SKU', controller: _sku),
            const SizedBox(height: 10),
            NeonInputField(label: 'Description', controller: _description, maxLines: 2),
            const SizedBox(height: 10),
            Row(children: [
              if (isNew) ...[
                Expanded(
                  child: NeonInputField(
                    label: 'Opening qty',
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: NeonInputField(
                  label: 'Reorder level',
                  controller: _reorder,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonInputField(
                  label: 'Unit cost',
                  controller: _unitCost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ]),
            if (!isNew)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Quantity is changed by receiving, adjusting or wasting — not by editing, so every movement is on the log.',
                  style: AppTextStyles.caption,
                ),
              ),
            if (branches.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Branch', style: AppTextStyles.label),
              const SizedBox(height: 8),
              FilterChips<String>(
                options: [
                  (value: null, label: 'Unassigned'),
                  for (final b in branches) (value: b.id, label: b.name),
                ],
                selected: _branchId,
                onSelected: (v) => setState(() => _branchId = v),
              ),
            ],
            const SizedBox(height: 14),
            NeonButton(label: 'Save item', isLoading: _saving, onPressed: _saving ? null : _save),
            if (!isNew) ...[
              const SizedBox(height: 8),
              GhostButton(
                label: 'Delete item',
                icon: Icons.delete_outline_rounded,
                color: AppColors.error,
                onPressed: () async {
                  try {
                    await ref.read(inventoryRepositoryProvider).deleteItem(widget.existing!.id);
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (error) {
                    // The API refuses to delete an item that still has stock,
                    // and says so; that is the useful message, not ours.
                    if (context.mounted) {
                      AppSnackBar.error(context, serverMessage(error, 'Could not delete this item.'));
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
