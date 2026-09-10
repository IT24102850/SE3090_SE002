import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_notifications.dart';
import 'auth/authenticated_api_client.dart';
import 'data/mock_inventory_data.dart';

/// An offline-first physical stock-count workflow. Counts persist on-device
/// immediately, and become server adjustments as soon as a request succeeds.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.client});
  final AuthenticatedApiClient client;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final _scanner = MobileScannerController();
  final _sku = TextEditingController();
  final _quantity = TextEditingController();
  final _store = _CountStore();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectionChanges;
  List<_CatalogItem> _catalog = [];
  List<_PendingCount> _pending = [];
  bool _loading = true, _syncing = false, _torchOn = false;
  String? _scannedCode;

  @override
  void initState() {
    super.initState();
    _connectionChanges = _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _sync(silent: true);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _connectionChanges?.cancel();
    _scanner.dispose();
    _sku.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await _store.load();
    if (!mounted) return;
    setState(() {
      _catalog = saved.catalog;
      _pending = saved.pending;
      _loading = false;
    });
    await _refreshCatalog();
    await _sync(silent: true);
  }

  Future<bool> _refreshCatalog() async {
    try {
      final catalog = <_CatalogItem>[];
      var page = 1, totalPages = 1;
      while (page <= totalPages) {
        final response =
            await widget.client.get('/api/inventory?page=$page&pageSize=100');
        if (response.statusCode != 200) break;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        catalog.addAll(((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_CatalogItem.fromJson));
        page++;
      }
      if (catalog.isNotEmpty) {
        await _store.save(catalog, _pending);
        if (mounted) setState(() => _catalog = catalog);
        return true;
      }
    } catch (_) {}

    // Fallback if catalog is still empty: seed from MockInventoryData so offline counting works immediately
    if (_catalog.isEmpty) {
      final mockItems = await MockInventoryData.getItems();
      final seeded = mockItems
          .map((m) => _CatalogItem(
                id: m.id,
                name: m.name,
                sku: m.sku,
                quantity: m.quantity,
              ))
          .toList();
      await _store.save(seeded, _pending);
      if (mounted) setState(() => _catalog = seeded);
      return true;
    }
    return false;
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing || _pending.isEmpty) return;
    setState(() => _syncing = true);
    try {
      if (!await _refreshCatalog()) return;
      final remaining = <_PendingCount>[];
      for (final count in _pending) {
        final matches = _catalog
            .where((item) => item.sku.toLowerCase() == count.sku.toLowerCase());
        if (matches.isEmpty) {
          remaining.add(count.withError('Item is no longer in the catalog.'));
          continue;
        }
        final item = matches.first;
        final delta = count.quantity - item.quantity;
        if (delta == 0) continue;
        try {
          final response = await widget.client
              .post('/api/inventory/${item.id}/adjust', body: {
            'quantity': delta,
            'reference': 'MOBILE-STOCK-COUNT-${count.id}',
            'notes':
                'Physical count ${count.quantity} recorded at ${count.recordedAt.toIso8601String()}',
          });
          if (response.statusCode < 200 || response.statusCode >= 300) {
            remaining.add(count.withError(_error(response.body) ??
                'The server did not accept this count.'));
          } else {
            // Keep mock inventory in sync
            await MockInventoryData.setCount(count.sku, count.quantity);
          }
        } catch (_) {
          // A failed request is not a successful sync. Keep the entry queued
          // so it can be retried when connectivity returns.
          remaining.add(count.withError('Unable to reach the inventory API.'));
        }
      }
      await _store.save(_catalog, remaining);
      if (mounted) {
        setState(() => _pending = remaining);
      }
      if (!silent && mounted) {
        showAppNotification(
          remaining.isEmpty
              ? 'All stock counts are synced.'
              : '${remaining.length} count(s) are still pending.',
          tone: remaining.isEmpty
              ? AppNotificationTone.success
              : AppNotificationTone.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String? _error(String body) {
    try {
      final value = jsonDecode(body) as Map<String, dynamic>;
      return value['message'] as String? ?? value['title'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty || code == _scannedCode) return;
    setState(() {
      _scannedCode = code;
      _sku.text = code;
    });
    _scanner.stop();
  }

  Future<void> _scanAgain() async {
    setState(() => _scannedCode = null);
    await _scanner.start();
  }

  Future<void> _saveCount() async {
    final code = _sku.text.trim();
    final quantity = double.tryParse(_quantity.text.trim());
    if (code.isEmpty || quantity == null || quantity < 0) {
      showAppNotification('Scan an item and enter a quantity of zero or more.',
          tone: AppNotificationTone.error);
      return;
    }
    final matches =
        _catalog.where((item) => item.sku.toLowerCase() == code.toLowerCase());
    if (matches.isEmpty) {
      showAppNotification(
          'This SKU is not in the saved catalog. Connect once to refresh before counting it.',
          tone: AppNotificationTone.error);
      return;
    }
    final item = matches.first;

    // Keep MockInventoryData in sync so inventory dashboard reflects change
    await MockInventoryData.setCount(item.sku, quantity);

    final entry = _PendingCount(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sku: item.sku,
        name: item.name,
        quantity: quantity,
        recordedAt: DateTime.now());
    final pending = [
      ..._pending
          .where((count) => count.sku.toLowerCase() != item.sku.toLowerCase()),
      entry
    ];
    await _store.save(_catalog, pending);
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _sku.clear();
      _quantity.clear();
      _scannedCode = null;
    });
    showAppNotification('${item.name} saved for sync.',
        tone: AppNotificationTone.success);
    _scanAgain();
    _sync(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final pendingLabel =
        _pending.isEmpty ? 'Synced' : '${_pending.length} pending';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor,
                      const Color(0xFF101A35),
                    ],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF25205A), Color(0xFF123C61)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4025205A),
                              blurRadius: 22,
                              offset: Offset(0, 18),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .14),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _syncing
                                            ? Icons.sync_rounded
                                            : Icons.check_circle_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _syncing ? 'Syncing' : pendingLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Offline-ready stock count',
                              style: TextStyle(
                                color: Color(0xFFBDF5EA),
                                fontSize: 11,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Stock count',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _catalog.isEmpty
                                  ? 'Connect once to cache your catalog'
                                  : '${_catalog.length} items ready to count',
                              style: const TextStyle(
                                color: Color(0xFFD9F3F1),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Catalog',
                              value:
                                  _catalog.isEmpty ? '0' : '${_catalog.length}',
                              accent: const Color(0xFF0E9F8A),
                              icon: Icons.dataset_linked_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              label: 'Pending',
                              value: '${_pending.length}',
                              accent: const Color(0xFFCC8A00),
                              icon: Icons.pending_actions_rounded,
                            ),
                          ),
                        ],
                      ),
                      if (_pending.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0x1FF59E0B),
                            border: Border.all(color: const Color(0x66F59E0B)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0x33F59E0B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.cloud_upload_outlined,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Waiting to sync',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      '${_pending.length} saved count${_pending.length == 1 ? '' : 's'} will upload automatically.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D1E293B),
                              blurRadius: 16,
                              offset: Offset(0, 10),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Scan & count',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const Spacer(),
                                IconButton.filledTonal(
                                  onPressed: () async {
                                    await _scanner.toggleTorch();
                                    if (mounted) {
                                      setState(() => _torchOn = !_torchOn);
                                    }
                                  },
                                  icon: Icon(
                                    _torchOn
                                        ? Icons.flash_on_rounded
                                        : Icons.flash_off_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AspectRatio(
                              aspectRatio: 1.3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    MobileScanner(
                                      controller: _scanner,
                                      onDetect: _onDetect,
                                    ),
                                    const _ScannerOverlay(),
                                    if (_scannedCode != null)
                                      Positioned(
                                        left: 16,
                                        right: 16,
                                        bottom: 16,
                                        child: FilledButton.icon(
                                          onPressed: _scanAgain,
                                          icon:
                                              const Icon(Icons.refresh_rounded),
                                          label: Text('Scanned: $_scannedCode'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Count what is physically on hand',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Counts are saved immediately on this device and synced when the connection returns.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                            const SizedBox(height: 18),
                            if (_catalog.isNotEmpty) ...[
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _catalog.take(6).map((item) {
                                    final isSelected = _sku.text.trim().toLowerCase() ==
                                        item.sku.toLowerCase();
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ActionChip(
                                        avatar: Icon(
                                          isSelected
                                              ? Icons.check_circle_rounded
                                              : Icons.inventory_2_outlined,
                                          size: 15,
                                          color: isSelected
                                              ? const Color(0xFF6366F1)
                                              : null,
                                        ),
                                        label: Text('${item.name} (${item.sku})'),
                                        backgroundColor: isSelected
                                            ? const Color(0xFF6366F1)
                                                .withValues(alpha: 0.15)
                                            : null,
                                        side: isSelected
                                            ? const BorderSide(
                                                color: Color(0xFF6366F1), width: 1.5)
                                            : null,
                                        onPressed: () {
                                          setState(() {
                                            _sku.text = item.sku;
                                            _scannedCode = item.sku;
                                          });
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: _sku,
                              onChanged: (value) => setState(() =>
                                  _scannedCode = value.isEmpty ? null : value),
                              decoration: const InputDecoration(
                                labelText: 'Item barcode / SKU',
                                prefixIcon: Icon(Icons.qr_code_2_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Physical quantity',
                                prefixIcon: Icon(Icons.numbers_rounded),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _saveCount,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save count'),
                            ),
                          ],
                        ),
                      ),
                      if (_pending.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Pending counts',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._pending.reversed.map(
                          (count) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: const Color(0xFFE5EDF7)),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F7F3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: Color(0xFF00C896),
                                ),
                              ),
                              title: Text(
                                count.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${count.sku} · ${count.error ?? 'Saved locally'}',
                                style:
                                    const TextStyle(color: Color(0xFF667085)),
                              ),
                              trailing: Text(
                                _display(count.quantity),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF173B5C),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  String _display(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  final String label;
  final String value;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountStore {
  static const _catalogKey = 'stock_count.catalog.v1',
      _queueKey = 'stock_count.pending.v1';
  Future<({List<_CatalogItem> catalog, List<_PendingCount> pending})>
      load() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> read(String key) {
      try {
        return jsonDecode(prefs.getString(key) ?? '[]') as List<dynamic>;
      } catch (_) {
        return [];
      }
    }

    return (
      catalog: read(_catalogKey)
          .whereType<Map<String, dynamic>>()
          .map(_CatalogItem.fromJson)
          .toList(),
      pending: read(_queueKey)
          .whereType<Map<String, dynamic>>()
          .map(_PendingCount.fromJson)
          .toList()
    );
  }

  Future<void> save(
      List<_CatalogItem> catalog, List<_PendingCount> pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _catalogKey, jsonEncode(catalog.map((item) => item.toJson()).toList()));
    await prefs.setString(
        _queueKey, jsonEncode(pending.map((item) => item.toJson()).toList()));
  }
}

class _CatalogItem {
  const _CatalogItem(
      {required this.id,
      required this.name,
      required this.sku,
      required this.quantity});
  final String id, name, sku;
  final double quantity;
  factory _CatalogItem.fromJson(Map<String, dynamic> json) => _CatalogItem(
      id: '${json['id']}',
      name: '${json['name']}',
      sku: '${json['sku']}',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0);
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'sku': sku, 'quantity': quantity};
}

class _PendingCount {
  const _PendingCount(
      {required this.id,
      required this.sku,
      required this.name,
      required this.quantity,
      required this.recordedAt,
      this.error});
  final String id, sku, name;
  final double quantity;
  final DateTime recordedAt;
  final String? error;
  factory _PendingCount.fromJson(Map<String, dynamic> json) => _PendingCount(
      id: '${json['id']}',
      sku: '${json['sku']}',
      name: '${json['name']}',
      quantity: (json['quantity'] as num).toDouble(),
      recordedAt: DateTime.parse('${json['recordedAt']}'),
      error: json['error'] as String?);
  _PendingCount withError(String error) => _PendingCount(
      id: id,
      sku: sku,
      name: name,
      quantity: quantity,
      recordedAt: recordedAt,
      error: error);
  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'recordedAt': recordedAt.toIso8601String(),
        'error': error
      };
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Center(
          child: Container(
              width: 210,
              height: 180,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 18)
                  ]))));
}
