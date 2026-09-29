import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'authenticated_api_client.dart';

enum _MovementFilter { all, stockIn, stockOut }

class _StockMovement {
  const _StockMovement({
    required this.occurredAt,
    required this.item,
    required this.sku,
    required this.type,
    required this.quantity,
    this.reference,
    this.notes,
    this.supplier,
    this.performedBy,
  });

  final DateTime occurredAt;
  final String item;
  final String sku;
  final String type;
  final double quantity;
  final String? reference;
  final String? notes;
  final String? supplier;
  final String? performedBy;

  factory _StockMovement.fromJson(Map<String, dynamic> json) {
    return _StockMovement(
      occurredAt: DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      item: json['item']?.toString() ?? 'Unknown item',
      sku: json['sku']?.toString() ?? 'Unknown SKU',
      type: json['movementType']?.toString() ?? 'Stock activity',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      reference: _nonEmpty(json['reference']),
      notes: _nonEmpty(json['notes']),
      supplier: _nonEmpty(json['supplierName']),
      performedBy: _nonEmpty(json['performedBy']),
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class StockActivityHistoryScreen extends StatefulWidget {
  const StockActivityHistoryScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<StockActivityHistoryScreen> createState() =>
      _StockActivityHistoryScreenState();
}

class _StockActivityHistoryScreenState
    extends State<StockActivityHistoryScreen> {
  List<_StockMovement> _movements = const [];
  bool _loading = true;
  String? _loadError;
  String _query = '';
  _MovementFilter _filter = _MovementFilter.all;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response =
          await widget.client.get('/api/inventory/movements?pageSize=100');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'Could not load stock activity (server ${response.statusCode}).');
      }
      final payload = jsonDecode(response.body);
      if (payload is! List) {
        throw const FormatException('Unexpected stock activity response.');
      }
      final movements = payload
          .whereType<Map<String, dynamic>>()
          .map(_StockMovement.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _movements = movements;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is StateError || error is FormatException
            ? error.toString().replaceFirst('Bad state: ', '')
            : 'Unable to connect to stock activity. Check your connection and retry.';
      });
    }
  }

  List<_StockMovement> get _visibleMovements {
    final query = _query.trim().toLowerCase();
    return _movements.where((movement) {
      final matchesFilter = switch (_filter) {
        _MovementFilter.all => true,
        _MovementFilter.stockIn => movement.quantity > 0,
        _MovementFilter.stockOut => movement.quantity < 0,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return [
        movement.item,
        movement.sku,
        movement.type,
        movement.reference ?? '',
        movement.notes ?? '',
        movement.supplier ?? '',
        movement.performedBy ?? '',
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMovements;
    return AppBackgroundScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Stock Activity',
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadMovements,
            tooltip: 'Refresh activity',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
          ),
        ],
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMovements,
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _buildIntro(),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                style: AppTextStyles.body.copyWith(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search item, SKU, reference, or person',
                  hintStyle: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: AppColors.cyan),
                  filled: true,
                  fillColor: AppColors.glassFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _filterChip('All', _MovementFilter.all),
                  _filterChip('Stock in', _MovementFilter.stockIn),
                  _filterChip('Stock out', _MovementFilter.stockOut),
                ],
              ),
              const SizedBox(height: 14),
              if (_loading && _movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  ),
                )
              else if (_loadError != null && _movements.isEmpty)
                _buildMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Activity could not be loaded',
                  message: _loadError!,
                  action: TextButton.icon(
                    onPressed: _loadMovements,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                )
              else if (visible.isEmpty)
                _buildMessage(
                  icon: Icons.receipt_long_outlined,
                  title: _movements.isEmpty
                      ? 'No stock activity yet'
                      : 'No matching activity',
                  message: _movements.isEmpty
                      ? 'Purchase receipts, sales, and other stock changes will appear here automatically.'
                      : 'Try another search or select a different filter.',
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'LATEST ACTIVITY',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Text(
                      '${visible.length} record${visible.length == 1 ? '' : 's'}',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...visible.map(_buildMovementCard),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Refresh failed. Showing previously loaded activity.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Showing up to the 100 most recent stock changes.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded, color: AppColors.cyan, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stock changes, recorded automatically',
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Text(
                  'Review activity from PO receiving, sales, issues, and adjustments. This screen does not change stock.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _MovementFilter filter) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: AppColors.cyan.withValues(alpha: 0.22),
      backgroundColor: AppColors.glassFill,
      labelStyle: AppTextStyles.caption.copyWith(
        color: _filter == filter ? AppColors.cyan : AppColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: _filter == filter ? AppColors.cyan : AppColors.glassBorder,
      ),
      showCheckmark: false,
    );
  }

  Widget _buildMovementCard(_StockMovement movement) {
    final color = movement.quantity > 0
        ? AppColors.success
        : movement.quantity < 0
            ? AppColors.warning
            : AppColors.textSecondary;
    final icon = movement.quantity > 0
        ? Icons.south_west_rounded
        : movement.quantity < 0
            ? Icons.north_east_rounded
            : Icons.sync_alt_rounded;
    final quantityPrefix = movement.quantity > 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.item,
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_movementLabel(movement.type)} · ${movement.sku}',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$quantityPrefix${_formatQuantity(movement.quantity)}',
                style: AppTextStyles.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _detail(Icons.schedule_rounded, _formatDate(movement.occurredAt)),
              if (movement.reference != null)
                _detail(Icons.tag_rounded, movement.reference!),
              if (movement.supplier != null)
                _detail(Icons.local_shipping_outlined, movement.supplier!),
              if (movement.performedBy != null)
                _detail(Icons.person_outline_rounded, movement.performedBy!),
            ],
          ),
          if (movement.notes != null) ...[
            const SizedBox(height: 8),
            Text(
              movement.notes!,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.caption
              .copyWith(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.iconGhost),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary, height: 1.4),
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action,
          ],
        ],
      ),
    );
  }

  String _movementLabel(String value) {
    return switch (value) {
      'PurchaseReceived' => 'PO received',
      'Receive' => 'Stock received',
      'Issue' => 'Stock issued',
      'Sale' => 'Sale',
      'Waste' => 'Waste',
      'Adjustment' => 'Adjustment',
      'RecipeConsumption' => 'Recipe use',
      'TransferIn' || 'TransferReceived' => 'Transfer received',
      'TransferOut' || 'TransferSent' => 'Transfer sent',
      _ => value
          .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'),
            (match) => '${match[1]} ${match[2]}',
          )
          .replaceFirstMapped(
            RegExp(r'^[a-z]'),
            (match) => match[0]!.toUpperCase(),
          ),
    };
  }

  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][local.month - 1];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$month ${local.day}, ${local.year} · $hour:$minute $period';
  }
}
