import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth/authenticated_api_client.dart';

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({
    super.key,
    required this.client,
    this.onOpenStockOperations,
  });

  final AuthenticatedApiClient client;
  final VoidCallback? onOpenStockOperations;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  late final _repository = InventoryDashboardRepository(widget.client);
  DashboardSummary? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final summary = await _repository.loadSummary();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load inventory metrics. Check your connection and try again.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(
    child: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('INVENTORY OVERVIEW', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text('Inventory at a glance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ])),
                if (widget.onOpenStockOperations != null)
                  IconButton.filledTonal(
                    onPressed: widget.onOpenStockOperations,
                    tooltip: 'Open stock operations',
                    icon: const Icon(Icons.inventory_2_rounded),
                  ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh dashboard', icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 8),
              const Text('Live stock and purchasing signals for today.', style: TextStyle(color: Color(0xFF667085))),
              const SizedBox(height: 24),
              if (_error != null) _DashboardError(message: _error!, onRetry: _load),
              if (_summary != null) _MetricGrid(summary: _summary!),
              const SizedBox(height: 28),
              Text('How to use this', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const _DashboardHint(icon: Icons.fact_check_outlined, text: 'Record physical quantities from the Stock count tab.'),
              const _DashboardHint(icon: Icons.approval_outlined, text: 'Review pending orders in the Approvals tab.'),
            ]),
              ),
            ),
    ),
  ));
}

class InventoryDashboardRepository {
  InventoryDashboardRepository(this._client);
  final AuthenticatedApiClient _client;

  Future<DashboardSummary> loadSummary() async {
    final results = await Future.wait([_loadInventory(), _loadPendingOrders()]);
    final items = results[0] as List<_DashboardItem>;
    final pendingOrders = results[1] as int;
    final lowStock = items.where((item) => item.quantity <= 0 || item.quantity < item.reorderLevel).length;
    final value = items.fold<double>(0, (total, item) => total + (item.quantity * item.unitCost));
    return DashboardSummary(totalItems: items.length, totalValue: value, lowStock: lowStock, pendingOrders: pendingOrders);
  }

  Future<List<_DashboardItem>> _loadInventory() async {
    final items = <_DashboardItem>[];
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages) {
      final response = await _client.get('/api/inventory?page=$page&pageSize=100');
      if (response.statusCode != 200) throw Exception('Inventory request failed');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      items.addAll(((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>().map(_DashboardItem.fromJson));
      page++;
    }
    return items;
  }

  Future<int> _loadPendingOrders() async {
    final response = await _client.get('/api/purchase-orders?status=InReview&pageSize=1');
    if (response.statusCode != 200) throw Exception('Purchase order request failed');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['totalCount'] as num?)?.toInt() ?? 0;
  }
}

class _DashboardItem {
  const _DashboardItem({required this.quantity, required this.reorderLevel, required this.unitCost});
  final double quantity, reorderLevel, unitCost;
  factory _DashboardItem.fromJson(Map<String, dynamic> json) => _DashboardItem(quantity: (json['quantity'] as num?)?.toDouble() ?? 0, reorderLevel: (json['reorderLevel'] as num?)?.toDouble() ?? 0, unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0);
}

class DashboardSummary {
  const DashboardSummary({required this.totalItems, required this.totalValue, required this.lowStock, required this.pendingOrders});
  final int totalItems, lowStock, pendingOrders; final double totalValue;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.summary});
  final DashboardSummary summary;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, constraints) {
    final columns = constraints.maxWidth < 560 ? 1 : constraints.maxWidth > 920 ? 3 : 2;
    return GridView.count(
      crossAxisCount: columns,
      childAspectRatio: columns == 1 ? 3.2 : 2.15,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _DashboardMetric(label: 'Total stock value', value: _currency(summary.totalValue), note: '${summary.totalItems} catalog item(s)', icon: Icons.account_balance_wallet_outlined, color: const Color(0xFF0E6972)),
        _DashboardMetric(label: 'Low-stock items', value: '${summary.lowStock}', note: summary.lowStock == 0 ? 'All items are healthy' : 'Needs attention', icon: Icons.warning_amber_rounded, color: const Color(0xFFD97706)),
        _DashboardMetric(label: 'Pending POs', value: '${summary.pendingOrders}', note: summary.pendingOrders == 0 ? 'No approvals waiting' : 'Awaiting manager approval', icon: Icons.approval_outlined, color: const Color(0xFF7C3AED)),
      ],
    );
  });

  String _currency(double value) {
    final digits = value.toStringAsFixed(2).split('.');
    final whole = digits.first.replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'LKR $whole.${digits.last}';
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.label, required this.value, required this.note, required this.icon, required this.color});
  final String label, value, note; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)),
    const Spacer(), Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(fontWeight: FontWeight.w700)), Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
  ])));
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [const Icon(Icons.cloud_off_outlined, size: 34), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('Try again'))])));
}

class _DashboardHint extends StatelessWidget {
  const _DashboardHint({required this.icon, required this.text});
  final IconData icon; final String text;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text));
}
