import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/authenticated_api_client.dart';
import 'auth/app_notifications.dart';
import 'data/mock_inventory_data.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_check_screen.dart';
import 'stock_count_screen.dart';

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({
    super.key,
    required this.client,
    required this.canApprove,
    this.onOpenStockOperations,
  });

  final AuthenticatedApiClient client;
  final bool canApprove;
  final VoidCallback? onOpenStockOperations;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  late final _repository = InventoryDashboardRepository(widget.client);
  DashboardSummary? _summary;
  List<MockInventoryItem> _previewItems = [];
  String? _error;
  bool _loading = true;
  bool _isDemoData = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _repository.loadSummary();
      final liveItems = await _repository.loadPreviewItems();
      if (mounted) {
        setState(() {
          _summary = summary;
          _previewItems = liveItems;
          _isDemoData = false;
        });
      }
    } on http.ClientException catch (_) {
      showAppNotification(
          'Live inventory is unavailable. Showing saved demo data.',
          tone: AppNotificationTone.warning);
      // Keep the dashboard honest when the shared API is unavailable.
      final mockItems = await MockInventoryData.getItems();
      final mockOrders = await MockInventoryData.getOrders();
      final lowStock = mockItems.where((item) => item.isLowStock).length;
      final totalValue =
          mockItems.fold<double>(0, (sum, item) => sum + item.totalValue);
      final pendingCount =
          mockOrders.where((order) => order.status == 'InReview').length;

      if (mounted) {
        setState(() {
          _summary = DashboardSummary(
            totalItems: mockItems.length,
            totalValue: totalValue,
            lowStock: lowStock,
            pendingOrders: pendingCount,
          );
          _previewItems = mockItems;
          _isDemoData = true;
          _error = null;
        });
      }
    } on TimeoutException catch (_) {
      showAppNotification(
          'The inventory request timed out. Showing saved demo data.',
          tone: AppNotificationTone.warning);
      final mockItems = await MockInventoryData.getItems();
      final mockOrders = await MockInventoryData.getOrders();
      if (mounted) {
        setState(() {
          _summary = DashboardSummary(
            totalItems: mockItems.length,
            totalValue:
                mockItems.fold<double>(0, (sum, item) => sum + item.totalValue),
            lowStock: mockItems.where((item) => item.isLowStock).length,
            pendingOrders:
                mockOrders.where((order) => order.status == 'InReview').length,
          );
          _previewItems = mockItems;
          _isDemoData = true;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to load live inventory: $error');
        showAppNotification('Unable to load live inventory.',
            tone: AppNotificationTone.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('INVENTORY OVERVIEW',
                                    style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1)),
                                const SizedBox(height: 4),
                                Text('Inventory at a glance',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w900)),
                              ])),
                          if (widget.onOpenStockOperations != null)
                            IconButton.filledTonal(
                              onPressed: widget.onOpenStockOperations,
                              tooltip: 'Open stock operations',
                              icon: const Icon(Icons.inventory_2_rounded),
                            ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                              onPressed: _load,
                              tooltip: 'Refresh dashboard',
                              icon: const Icon(Icons.refresh_rounded)),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Live stock, procurement, and branch signals for your SME Inventory workspace.',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (_isDemoData) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 16, color: Color(0xFFF59E0B)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Live inventory is unavailable. Pull to retry when the API is connected.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (_error != null)
                          _DashboardError(message: _error!, onRetry: _load),
                        if (_summary != null) _MetricGrid(summary: _summary!),
                        const SizedBox(height: 24),
                        Text('Quick Operations',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.qr_code_scanner_rounded,
                                label: 'Scan & Log',
                                color: const Color(0xFF6366F1),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StockCheckScreen(client: widget.client),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.format_list_numbered_rounded,
                                label: 'Stock Count',
                                color: const Color(0xFF06B6D4),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StockCountScreen(client: widget.client),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                icon: Icons.assignment_turned_in_rounded,
                                label: 'PO Queue',
                                color: const Color(0xFF10B981),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PurchaseOrderApprovalScreen(
                                      client: widget.client,
                                      canApprove: widget.canApprove,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        // Stock Health list
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Stock Health & Levels',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              '${(_previewItems as List<MockInventoryItem>?)?.length ?? 0} items',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...((_previewItems as List<MockInventoryItem>?) ??
                                const [])
                            .map((item) => Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14.5,
                                                ),
                                              ),
                                            ),
                                            _StockBadge(
                                              quantity: item.quantity,
                                              reorderLevel: item.reorderLevel,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '${item.sku} • ${item.category} • ${item.branch}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        // Stock Level Bar
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: LinearProgressIndicator(
                                                  value: (item.quantity /
                                                          (item.reorderLevel *
                                                              2))
                                                      .clamp(0.02, 1.0),
                                                  minHeight: 8,
                                                  backgroundColor:
                                                      theme.colorScheme.outline,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    item.quantity <= 0
                                                        ? const Color(
                                                            0xFFEF4444)
                                                        : item.isLowStock
                                                            ? const Color(
                                                                0xFFF59E0B)
                                                            : const Color(
                                                                0xFF10B981),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Text(
                                              '${item.quantity.toInt()} / ${item.reorderLevel.toInt()} ${item.unit}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class InventoryDashboardRepository {
  InventoryDashboardRepository(this._client);
  final AuthenticatedApiClient _client;

  Future<DashboardSummary> loadSummary() async {
    final results = await Future.wait([_loadInventory(), _loadPendingOrders()]);
    final items = results[0] as List<_DashboardItem>;
    final pendingOrders = results[1] as int;
    final lowStock = items
        .where(
            (item) => item.quantity <= 0 || item.quantity < item.reorderLevel)
        .length;
    final value = items.fold<double>(
        0, (total, item) => total + (item.quantity * item.unitCost));
    return DashboardSummary(
        totalItems: items.length,
        totalValue: value,
        lowStock: lowStock,
        pendingOrders: pendingOrders);
  }

  Future<List<_DashboardItem>> _loadInventory() async {
    final items = <_DashboardItem>[];
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages) {
      final response =
          await _client.get('/api/inventory?page=$page&pageSize=100');
      if (response.statusCode != 200) {
        throw Exception('Inventory request failed');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      items.addAll(((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_DashboardItem.fromJson));
      page++;
    }
    return items;
  }

  Future<int> _loadPendingOrders() async {
    final response =
        await _client.get('/api/purchase-orders?status=InReview&pageSize=1');
    if (response.statusCode != 200) {
      throw Exception('Purchase order request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['totalCount'] as num?)?.toInt() ?? 0;
  }

  Future<List<MockInventoryItem>> loadPreviewItems() async {
    final response = await _client.get('/api/inventory?page=1&pageSize=100');
    if (response.statusCode != 200) {
      throw Exception('Inventory preview request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MockInventoryItem.fromJson)
        .toList();
  }
}

class _DashboardItem {
  const _DashboardItem(
      {required this.quantity,
      required this.reorderLevel,
      required this.unitCost});
  final double quantity, reorderLevel, unitCost;
  factory _DashboardItem.fromJson(Map<String, dynamic> json) => _DashboardItem(
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      reorderLevel: (json['reorderLevel'] as num?)?.toDouble() ?? 0,
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0);
}

class DashboardSummary {
  const DashboardSummary(
      {required this.totalItems,
      required this.totalValue,
      required this.lowStock,
      required this.pendingOrders});
  final int totalItems, lowStock, pendingOrders;
  final double totalValue;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        final columns = constraints.maxWidth < 560
            ? 2
            : constraints.maxWidth > 920
                ? 4
                : 2;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 2 ? 1.6 : 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _DashboardMetric(
              label: 'Total stock value',
              value: _currency(summary.totalValue),
              note: '${summary.totalItems} catalog item(s)',
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF6366F1),
            ),
            _DashboardMetric(
              label: 'Low-stock alerts',
              value: '${summary.lowStock}',
              note: summary.lowStock == 0
                  ? 'All items healthy'
                  : 'Requires reordering',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
            ),
            _DashboardMetric(
              label: 'Pending POs',
              value: '${summary.pendingOrders}',
              note: summary.pendingOrders == 0
                  ? 'Queue clear'
                  : 'Needs manager review',
              icon: Icons.assignment_turned_in_outlined,
              color: const Color(0xFF10B981),
            ),
            _DashboardMetric(
              label: 'Catalog Items',
              value: '${summary.totalItems}',
              note: 'Tracked inventory',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF06B6D4),
            ),
          ],
        );
      });

  String _currency(double value) {
    final digits = value.toStringAsFixed(0);
    final whole =
        digits.replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'LKR $whole';
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric(
      {required this.label,
      required this.value,
      required this.note,
      required this.icon,
      required this.color});
  final String label, value, note;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, color: color, size: 18)),
                ],
              ),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
              Text(note,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
      ));
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.reorderLevel});

  final double quantity, reorderLevel;

  @override
  Widget build(BuildContext context) {
    final isOut = quantity <= 0;
    final isLow = quantity < reorderLevel;
    final color = isOut
        ? const Color(0xFFEF4444)
        : isLow
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);
    final text = isOut
        ? 'Out of stock'
        : isLow
            ? 'Low stock'
            : 'In stock';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Icon(Icons.cloud_off_outlined, size: 34),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again'))
          ])));
}
