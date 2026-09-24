import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/inventory_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Procurement — the mobile twin of the web Purchase Order Manager: raise
/// an order against a supplier, watch it through to receipt, and let the
/// receipt put the stock back on the shelf.
class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  String _status = '';

  static const _statuses = ['Draft', 'Submitted', 'Approved', 'Received', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(purchaseOrdersProvider);

    return OwnerScaffold(
      title: 'Purchase Orders',
      subtitle: 'What is on order',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: _newOrder,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('New order'),
      ),
      body: ordersAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the purchase orders.',
          onRetry: () => ref.invalidate(purchaseOrdersProvider),
        ),
        data: (all) {
          final rows = _status.isEmpty ? all : all.where((o) => o.status == _status).toList();
          final open = all.where((o) => o.status != 'Received' && o.status != 'Cancelled').toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(purchaseOrdersProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Orders', value: '${all.length}', sub: 'raised'),
                  StatTile(label: 'Open', value: '${open.length}', sub: 'not yet received', accent: AppColors.warning),
                  StatTile(
                    label: 'On order',
                    value: formatMoney(open.fold<double>(0, (sum, o) => sum + o.totalCost)),
                    sub: 'committed spend',
                  ),
                  StatTile(
                    label: 'Received',
                    value: '${all.where((o) => o.status == 'Received').length}',
                    sub: 'landed',
                    accent: AppColors.success,
                  ),
                ]),
                const SizedBox(height: 14),
                FilterChips<String>(
                  options: [
                    (value: '', label: 'All'),
                    for (final s in _statuses) (value: s, label: s),
                  ],
                  selected: _status,
                  onSelected: (v) => setState(() => _status = v ?? ''),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.local_shipping_outlined, message: 'No orders match this filter.'),
                  )
                else
                  ...rows.map((order) => _OrderCard(order: order, statuses: _statuses)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _newOrder() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _OrderForm(),
      ),
    );
    if (saved == true) ref.invalidate(purchaseOrdersProvider);
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final PurchaseOrder order;
  final List<String> statuses;
  const _OrderCard({required this.order, required this.statuses});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).setPurchaseOrderStatus(widget.order.id, status);
      ref.invalidate(purchaseOrdersProvider);
      // Receiving an order puts stock on the shelf, so the stock screens
      // have to be told as well.
      if (status == 'Received') {
        ref.invalidate(inventoryItemsProvider);
        ref.invalidate(stockMovementsProvider);
        ref.invalidate(lowStockProvider);
      }
      if (mounted) AppSnackBar.success(context, 'Order marked $status.');
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not change this order.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
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
                      Text(o.orderNumber.isEmpty ? 'Order' : o.orderNumber,
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text('${o.supplier} · ${o.branch}', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                OwnerStatusChip(status: o.status),
              ],
            ),
            const SizedBox(height: 10),
            DetailRow(label: 'Total', value: formatMoney(o.totalCost)),
            DetailRow(label: 'Lines', value: '${o.lineItemCount > 0 ? o.lineItemCount : o.lines.length}'),
            if (o.orderedAt != null) DetailRow(label: 'Raised', value: formatFullDate(o.orderedAt!)),
            if (o.receivedAt != null) DetailRow(label: 'Received', value: formatFullDate(o.receivedAt!)),
            if (o.lines.isNotEmpty) ...[
              const Divider(color: AppColors.hairline, height: 20),
              for (final line in o.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('${line.quantity.toStringAsFixed(0)} × ${line.itemName}', style: AppTextStyles.caption)),
                      Text(formatMoney(line.lineTotal), style: AppTextStyles.caption),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 10),
            if (_busy)
              const AppLoader(size: 18)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in widget.statuses.where((s) => s != o.status))
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: OwnerStatusChip.colorOf(status).withValues(alpha: .5)),
                      ),
                      onPressed: () => _setStatus(status),
                      child: Text(status, style: AppTextStyles.caption.copyWith(color: OwnerStatusChip.colorOf(status))),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderForm extends ConsumerStatefulWidget {
  const _OrderForm();

  @override
  ConsumerState<_OrderForm> createState() => _OrderFormState();
}

class _OrderLineDraft {
  NamedOption? item;
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController unitCost = TextEditingController();

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }
}

class _OrderFormState extends ConsumerState<_OrderForm> {
  final _number = TextEditingController();
  final List<_OrderLineDraft> _lines = [_OrderLineDraft()];
  String? _branchId;
  String? _supplierId;
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold<double>(0, (sum, l) {
        final qty = double.tryParse(l.quantity.text) ?? 0;
        final cost = double.tryParse(l.unitCost.text) ?? 0;
        return sum + qty * cost;
      });

  Future<void> _save() async {
    if (_branchId == null || _supplierId == null) {
      AppSnackBar.error(context, 'Pick a branch and a supplier.');
      return;
    }
    final lines = _lines
        .where((l) => l.item != null)
        .map((l) => PurchaseOrderLine(
              inventoryItemId: l.item!.id,
              itemName: l.item!.name,
              quantity: double.tryParse(l.quantity.text) ?? 1,
              unitCost: double.tryParse(l.unitCost.text) ?? l.item!.unitCost,
            ))
        .toList();
    if (lines.isEmpty) {
      AppSnackBar.error(context, 'Add at least one item.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepositoryProvider).createPurchaseOrder(
            branchId: _branchId!,
            supplierId: _supplierId!,
            number: _number.text.trim().isEmpty ? null : _number.text.trim(),
            lines: lines,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not raise this order.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final optionsAsync = ref.watch(purchaseOrderOptionsProvider);

    return SafeArea(
      child: optionsAsync.when(
        loading: () => const SizedBox(height: 220, child: AppLoader()),
        error: (error, _) => SizedBox(
          height: 220,
          child: ErrorState(
            message: 'Could not load suppliers and items.',
            onRetry: () => ref.invalidate(purchaseOrderOptionsProvider),
          ),
        ),
        data: (options) {
          // Items are scoped to the branch the order is for, so a line
          // cannot be raised against stock that lives somewhere else.
          final items = _branchId == null
              ? options.items
              : options.items.where((i) => i.branchId == null || i.branchId == _branchId).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New purchase order', style: AppTextStyles.title),
                const SizedBox(height: 12),
                Text('Branch', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<String>(
                  options: [for (final b in options.branches) (value: b.id, label: b.name)],
                  selected: _branchId,
                  onSelected: (v) => setState(() => _branchId = v),
                ),
                const SizedBox(height: 12),
                Text('Supplier', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<String>(
                  options: [for (final s in options.suppliers) (value: s.id, label: s.name)],
                  selected: _supplierId,
                  onSelected: (v) => setState(() => _supplierId = v),
                ),
                const SizedBox(height: 12),
                NeonInputField(label: 'Order number', controller: _number, helperText: 'blank = generated'),
                const SizedBox(height: 14),
                Text('Lines', style: AppTextStyles.label),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++) _lineEditor(i, items),
                GhostButton(
                  label: 'Add a line',
                  icon: Icons.add_rounded,
                  height: 42,
                  onPressed: () => setState(() => _lines.add(_OrderLineDraft())),
                ),
                const SizedBox(height: 14),
                GlassCard(child: DetailRow(label: 'Order total', value: formatMoney(_total))),
                const SizedBox(height: 14),
                NeonButton(label: 'Raise order', isLoading: _saving, onPressed: _saving ? null : _save),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lineEditor(int index, List<NamedOption> items) {
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(line.item?.name ?? 'Pick an item', style: AppTextStyles.body)),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  onPressed: _lines.length == 1 ? null : () => setState(() => _lines.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FilterChips<String>(
              options: [for (final item in items) (value: item.id, label: item.sku ?? item.name)],
              selected: line.item?.id,
              onSelected: (id) => setState(() {
                line.item = items.where((i) => i.id == id).cast<NamedOption?>().firstWhere((_) => true, orElse: () => null);
                if (line.item != null && line.unitCost.text.isEmpty) {
                  line.unitCost.text = line.item!.unitCost.toStringAsFixed(2);
                }
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: NeonInputField(
                  label: 'Qty',
                  controller: line.quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: NeonInputField(
                  label: 'Unit cost',
                  controller: line.unitCost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
