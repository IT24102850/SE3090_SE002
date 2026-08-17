import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_notifications.dart';
import 'auth/authenticated_api_client.dart';

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
      if (results.any((result) => result != ConnectivityResult.none)) _sync(silent: true);
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
    setState(() { _catalog = saved.catalog; _pending = saved.pending; _loading = false; });
    await _refreshCatalog();
    await _sync(silent: true);
  }

  Future<bool> _refreshCatalog() async {
    try {
      final catalog = <_CatalogItem>[];
      var page = 1, totalPages = 1;
      while (page <= totalPages) {
        final response = await widget.client.get('/api/inventory?page=$page&pageSize=100');
        if (response.statusCode != 200) return false;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        catalog.addAll(((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>().map(_CatalogItem.fromJson));
        page++;
      }
      await _store.save(catalog, _pending);
      if (mounted) setState(() => _catalog = catalog);
      return true;
    } catch (_) { return false; }
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing || _pending.isEmpty) return;
    setState(() => _syncing = true);
    try {
      if (!await _refreshCatalog()) return;
      final remaining = <_PendingCount>[];
      for (final count in _pending) {
        final matches = _catalog.where((item) => item.sku.toLowerCase() == count.sku.toLowerCase());
        if (matches.isEmpty) { remaining.add(count.withError('Item is no longer in the catalog.')); continue; }
        final item = matches.first;
        final delta = count.quantity - item.quantity;
        if (delta == 0) continue;
        try {
          final response = await widget.client.post('/api/inventory/${item.id}/adjust', body: {
            'quantity': delta,
            'reference': 'MOBILE-STOCK-COUNT-${count.id}',
            'notes': 'Physical count ${count.quantity} recorded at ${count.recordedAt.toIso8601String()}',
          });
          if (response.statusCode < 200 || response.statusCode >= 300) {
            remaining.add(count.withError(_error(response.body) ?? 'The server did not accept this count.'));
          }
        } catch (_) { remaining.add(count.withError('Waiting for an internet connection.')); }
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
              : AppNotificationTone.info,
        );
      }
    } finally { if (mounted) setState(() => _syncing = false); }
  }

  String? _error(String body) {
    try { final value = jsonDecode(body) as Map<String, dynamic>; return value['message'] as String? ?? value['title'] as String?; } catch (_) { return null; }
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty || code == _scannedCode) return;
    setState(() { _scannedCode = code; _sku.text = code; });
    _scanner.stop();
  }

  Future<void> _scanAgain() async { setState(() => _scannedCode = null); await _scanner.start(); }

  Future<void> _saveCount() async {
    final code = _sku.text.trim();
    final quantity = double.tryParse(_quantity.text.trim());
    if (code.isEmpty || quantity == null || quantity < 0) {
      showAppNotification('Scan an item and enter a quantity of zero or more.', tone: AppNotificationTone.error); return;
    }
    final matches = _catalog.where((item) => item.sku.toLowerCase() == code.toLowerCase());
    if (matches.isEmpty) {
      showAppNotification('This SKU is not in the saved catalog. Connect once to refresh before counting it.', tone: AppNotificationTone.error); return;
    }
    final item = matches.first;
    final entry = _PendingCount(id: DateTime.now().microsecondsSinceEpoch.toString(), sku: item.sku, name: item.name, quantity: quantity, recordedAt: DateTime.now());
    final pending = [..._pending.where((count) => count.sku.toLowerCase() != item.sku.toLowerCase()), entry];
    await _store.save(_catalog, pending);
    if (!mounted) return;
    setState(() { _pending = pending; _sku.clear(); _quantity.clear(); _scannedCode = null; });
    showAppNotification('${item.name} saved for sync.', tone: AppNotificationTone.success);
    _scanAgain();
    _sync(silent: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('OFFLINE-READY', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                                const SizedBox(height: 4),
                                Text('Stock count', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text(_catalog.isEmpty ? 'No saved catalog yet' : '${_catalog.length} items available offline', style: const TextStyle(color: Color(0xFF667085))),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(onPressed: _syncing ? null : _sync, tooltip: 'Sync now', icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded)),
                        ],
                      ),
                    ),
                    if (_pending.isNotEmpty)
                      Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(20, 0, 20, 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.cloud_upload_outlined, color: Color(0xFFB54708)), const SizedBox(width: 9), Text('${_pending.length} count(s) waiting to sync', style: const TextStyle(fontWeight: FontWeight.w700))])),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(aspectRatio: 1.25, child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Stack(fit: StackFit.expand, children: [MobileScanner(controller: _scanner, onDetect: _onDetect), const _ScannerOverlay(), Positioned(top: 12, right: 12, child: IconButton.filledTonal(onPressed: () async { await _scanner.toggleTorch(); if (mounted) setState(() => _torchOn = !_torchOn); }, icon: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded))), if (_scannedCode != null) Positioned(left: 16, right: 16, bottom: 16, child: FilledButton.icon(onPressed: _scanAgain, icon: const Icon(Icons.refresh_rounded), label: Text('Scanned: $_scannedCode')))]))),
                            const SizedBox(height: 18),
                            Text('Count what is physically on hand', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text('Counts are saved immediately on this device and synced when the connection returns.', style: TextStyle(color: Color(0xFF667085))),
                            const SizedBox(height: 18),
                            TextField(controller: _sku, onChanged: (value) => setState(() => _scannedCode = value.isEmpty ? null : value), decoration: const InputDecoration(labelText: 'Item barcode / SKU', prefixIcon: Icon(Icons.qr_code_2_rounded))),
                            const SizedBox(height: 14),
                            TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Physical quantity', prefixIcon: Icon(Icons.numbers_rounded))),
                            const SizedBox(height: 20),
                            FilledButton.icon(onPressed: _saveCount, icon: const Icon(Icons.save_outlined), label: const Text('Save count')),
                            if (_pending.isNotEmpty) ...[
                              const SizedBox(height: 28),
                              Text('Pending counts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              ..._pending.reversed.map(
                                (count) => Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.inventory_2_outlined),
                                    title: Text(count.name),
                                    subtitle: Text('${count.sku} · ${count.error ?? 'Saved locally'}'),
                                    trailing: Text(_display(count.quantity), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );

  String _display(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

class _CountStore {
  static const _catalogKey = 'stock_count.catalog.v1', _queueKey = 'stock_count.pending.v1';
  Future<({List<_CatalogItem> catalog, List<_PendingCount> pending})> load() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> read(String key) { try { return jsonDecode(prefs.getString(key) ?? '[]') as List<dynamic>; } catch (_) { return []; } }
    return (catalog: read(_catalogKey).whereType<Map<String, dynamic>>().map(_CatalogItem.fromJson).toList(), pending: read(_queueKey).whereType<Map<String, dynamic>>().map(_PendingCount.fromJson).toList());
  }
  Future<void> save(List<_CatalogItem> catalog, List<_PendingCount> pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catalogKey, jsonEncode(catalog.map((item) => item.toJson()).toList()));
    await prefs.setString(_queueKey, jsonEncode(pending.map((item) => item.toJson()).toList()));
  }
}

class _CatalogItem {
  const _CatalogItem({required this.id, required this.name, required this.sku, required this.quantity});
  final String id, name, sku; final double quantity;
  factory _CatalogItem.fromJson(Map<String, dynamic> json) => _CatalogItem(id: '${json['id']}', name: '${json['name']}', sku: '${json['sku']}', quantity: (json['quantity'] as num?)?.toDouble() ?? 0);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'sku': sku, 'quantity': quantity};
}

class _PendingCount {
  const _PendingCount({required this.id, required this.sku, required this.name, required this.quantity, required this.recordedAt, this.error});
  final String id, sku, name; final double quantity; final DateTime recordedAt; final String? error;
  factory _PendingCount.fromJson(Map<String, dynamic> json) => _PendingCount(id: '${json['id']}', sku: '${json['sku']}', name: '${json['name']}', quantity: (json['quantity'] as num).toDouble(), recordedAt: DateTime.parse('${json['recordedAt']}'), error: json['error'] as String?);
  _PendingCount withError(String error) => _PendingCount(id: id, sku: sku, name: name, quantity: quantity, recordedAt: recordedAt, error: error);
  Map<String, dynamic> toJson() => {'id': id, 'sku': sku, 'name': name, 'quantity': quantity, 'recordedAt': recordedAt.toIso8601String(), 'error': error};
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Center(child: Container(width: 210, height: 180, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)]))));
}
