import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/authenticated_api_client.dart';
import 'auth/app_notifications.dart';
import 'data/inventory_models.dart';
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
  List<InventoryItem> _previewItems = const [];
  String? _error;
  bool _loading = true;

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
        });
      }
    } on http.ClientException catch (_) {
      // An unreachable API is shown as exactly that. This used to swap in a
      // saved demo catalogue, which meant the totals on screen could be for
      // a business that does not exist while looking identical to live ones.
      _fail('The inventory API cannot be reached. Check the connection and pull to retry.');
    } on TimeoutException catch (_) {
      _fail('The inventory request timed out. Pull to retry.');
    } catch (error) {
      _fail('Unable to load inventory: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    // Whatever was on screen from the last successful load is cleared too:
    // stale totals under an error banner still read as current totals.
    setState(() {
      _error = message;
      _summary = null;
      _previewItems = const [];
    });
    showAppNotification(message, tone: AppNotificationTone.error);
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
                        Container(
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [BoxShadow(color: Color(0x553B82F6), blurRadius: 24, offset: Offset(0, 12))],
                          ),
                          child: Stack(children: [
                            Positioned(right: -44, top: -52, child: _HeroOrb(size: 142, color: Colors.white.withValues(alpha: .12))),
                            Positioned(right: 64, bottom: -58, child: _HeroOrb(size: 110, color: const Color(0xFFFDE68A).withValues(alpha: .18))),
                            Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(builder: (context, constraints) {
                                final title = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('BUSINESS OVERVIEW',
                                          style: TextStyle(
                                              color: Colors.white.withValues(alpha: .78),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.1)),
                                      const SizedBox(height: 4),
                                      Text('Your business at a glance',
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900)),
                                    ]);
                                final actions = Wrap(spacing: 8, runSpacing: 8, children: [
                                  if (widget.onOpenStockOperations != null)
                                    IconButton.filledTonal(
                                      onPressed: widget.onOpenStockOperations,
                                      tooltip: 'Open stock operations',
                                      icon: const Icon(Icons.inventory_2_rounded),
                                    ),
                                  IconButton.filledTonal(
                                      onPressed: _load,
                                      tooltip: 'Refresh dashboard',
                                      icon: const Icon(Icons.refresh_rounded)),
                                ]);
                                // Too narrow for title + action buttons side by
                                // side (a briefly tiny browser window, a docked
                                // inspector): stack them instead of overflowing.
                                if (constraints.maxWidth < 240) {
                                  return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [title, const SizedBox(height: 10), actions]);
                                }
                                return Row(children: [
                                  Expanded(child: title),
                                  const SizedBox(width: 8),
                                  actions,
                                ]);
                              }),
                              const SizedBox(height: 15),
                              const Wrap(spacing: 9, runSpacing: 8, children: [
                                _HeroStatus(icon: Icons.bolt_rounded, label: 'Live workspace'),
                                _HeroStatus(icon: Icons.auto_awesome_rounded, label: 'Ready for today'),
                              ]),
                            ],
                          )]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Live operations, resources, and team signals for your business workspace.',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          _DashboardError(message: _error!, onRetry: _load),
                        if (_summary != null) _MetricGrid(summary: _summary!),
                        const SizedBox(height: 24),
                        Text('Quick actions',
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
                            Text('Operational health',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              '${_previewItems.length} items',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_previewItems.isEmpty && _error == null)
                          const _EmptyHealthState()
                        else
                          ..._previewItems.map((item) => Card(
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

  Future<List<InventoryItem>> loadPreviewItems() async {
    final response = await _client.get('/api/inventory?page=1&pageSize=100');
    if (response.statusCode != 200) {
      throw Exception('Inventory preview request failed');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InventoryItem.fromJson)
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

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      );
}

class _EmptyHealthState extends StatelessWidget {
  const _EmptyHealthState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF10B981)),
        ),
        const SizedBox(height: 12),
        Text('Your inventory will appear here',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Add a catalog item or pull to refresh your live operations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12.5)),
      ]),
    );
  }
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
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: color)),
            Positioned(right: -21, bottom: -29, child: Container(width: 92, height: 92, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .09)))),
            Padding(
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
      )]));
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: .28)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
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

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: .23)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
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
