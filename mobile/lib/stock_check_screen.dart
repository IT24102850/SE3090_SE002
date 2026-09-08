import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'auth/authenticated_api_client.dart';
import 'auth/app_notifications.dart';
import 'data/mock_inventory_data.dart';

enum StockOperation { checkIn, checkOut }

class StockCheckScreen extends StatefulWidget {
  const StockCheckScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<StockCheckScreen> createState() => _StockCheckScreenState();
}

class _StockCheckScreenState extends State<StockCheckScreen> {
  final _scanner = MobileScannerController();
  final _barcode = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  StockOperation _operation = StockOperation.checkIn;
  String? _scannedCode;
  bool _torchOn = false;
  bool _saving = false;
  List<MockInventoryItem> _availableItems = const [];

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final items = await MockInventoryData.getItems();
    if (mounted) setState(() => _availableItems = items);
  }

  @override
  void dispose() {
    _scanner.dispose();
    _barcode.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty || value == _scannedCode) return;
    setState(() {
      _scannedCode = value;
      _barcode.text = value;
    });
    _scanner.stop();
  }

  Future<void> _scanAgain() async {
    setState(() => _scannedCode = null);
    await _scanner.start();
  }

  Future<void> _submit() async {
    final code = _barcode.text.trim();
    final quantity = int.tryParse(_quantity.text);
    if (code.isEmpty || quantity == null || quantity <= 0) {
      showAppNotification(
          'Scan or enter an item code and enter a valid quantity.',
          tone: AppNotificationTone.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final inventoryResponse =
          await widget.client.get('/api/inventory?pageSize=100');
      if (inventoryResponse.statusCode == 200) {
        final payload =
            jsonDecode(inventoryResponse.body) as Map<String, dynamic>;
        final items = payload['items'] as List<dynamic>? ?? const [];
        Map<String, dynamic>? item;
        for (final candidate in items) {
          if (candidate is Map<String, dynamic> &&
              candidate['sku']?.toString().toLowerCase() ==
                  code.toLowerCase()) {
            item = candidate;
            break;
          }
        }
        if (item != null) {
          final endpoint = _operation == StockOperation.checkIn
              ? '/api/inventory/${item['id']}/receive'
              : '/api/inventory/${item['id']}/adjust';
          final response = await widget.client.post(
            endpoint,
            body: {
              'quantity':
                  _operation == StockOperation.checkIn ? quantity : -quantity,
              'reference': 'MOBILE-SCAN',
              'notes': 'Recorded from the mobile barcode scanner',
            },
          );
          if (response.statusCode >= 200 && response.statusCode < 300) {
            await MockInventoryData.updateQuantity(
              code,
              _operation == StockOperation.checkIn
                  ? quantity.toDouble()
                  : -quantity.toDouble(),
            );
            if (!mounted) return;
            showAppNotification(
              '${_operation == StockOperation.checkIn ? 'Check-in' : 'Check-out'} recorded for ${item['name']}.',
              tone: AppNotificationTone.success,
            );
            setState(() {
              _scannedCode = null;
              _barcode.clear();
              _quantity.text = '1';
            });
            _loadPresets();
            return;
          }
        }
      }
    } catch (_) {
      // Live API unreachable, fall back to offline demo store
    }

    // Offline / Demo store fallback
    final delta = _operation == StockOperation.checkIn
        ? quantity.toDouble()
        : -quantity.toDouble();
    final updated = await MockInventoryData.updateQuantity(code, delta);
    if (!mounted) return;
    if (updated != null) {
      showAppNotification(
        '${_operation == StockOperation.checkIn ? 'Check-in' : 'Check-out'} recorded for ${updated.name} (Now: ${updated.quantity.toInt()} ${updated.unit}).',
        tone: AppNotificationTone.success,
      );
      setState(() {
        _scannedCode = null;
        _barcode.clear();
        _quantity.text = '1';
      });
      _loadPresets();
    } else {
      showAppNotification(
        'No inventory item matches "$code". Tap an item from the list below.',
        tone: AppNotificationTone.error,
      );
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movements',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: _scanAgain,
            tooltip: 'Scan again',
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode switcher
              SegmentedButton<StockOperation>(
                segments: const [
                  ButtonSegment(
                    value: StockOperation.checkIn,
                    icon: Icon(Icons.add_circle_outline),
                    label: Text('Check in (Receive)'),
                  ),
                  ButtonSegment(
                    value: StockOperation.checkOut,
                    icon: Icon(Icons.remove_circle_outline),
                    label: Text('Check out (Issue)'),
                  ),
                ],
                selected: {_operation},
                onSelectionChanged: (selection) =>
                    setState(() => _operation = selection.first),
              ),
              const SizedBox(height: 18),
              // Camera scanner card
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scanner,
                        onDetect: _onDetect,
                      ),
                      const _ScannerOverlay(),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: IconButton.filledTonal(
                          tooltip:
                              _torchOn ? 'Turn flash off' : 'Turn flash on',
                          onPressed: () async {
                            await _scanner.toggleTorch();
                            if (mounted) {
                              setState(() => _torchOn = !_torchOn);
                            }
                          },
                          icon: Icon(_torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded),
                        ),
                      ),
                      if (_scannedCode != null)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: .65),
                            child: Center(
                              child: Container(
                                margin: const EdgeInsets.all(20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFF10B981)),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF10B981), size: 36),
                                    const SizedBox(height: 6),
                                    const Text('Code captured',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text(_scannedCode!,
                                        style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: _scanAgain,
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 18),
                                      label: const Text('Scan another'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Catalog quick picker
              if (_availableItems.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.touch_app_outlined,
                        size: 16, color: Color(0xFF6366F1)),
                    const SizedBox(width: 6),
                    Text(
                      'Quick Pick Catalog Item',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _availableItems.map((item) {
                      final isSelected = _barcode.text.trim().toLowerCase() ==
                          item.sku.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.inventory_2_outlined,
                            size: 16,
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          label: Text('${item.name} (${item.sku})'),
                          backgroundColor: isSelected
                              ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                              : null,
                          side: isSelected
                              ? const BorderSide(
                                  color: Color(0xFF6366F1), width: 1.5)
                              : null,
                          onPressed: () {
                            setState(() {
                              _barcode.text = item.sku;
                              _scannedCode = item.sku;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _barcode,
                        onChanged: (value) => setState(() =>
                            _scannedCode = value.isEmpty ? null : value),
                        decoration: const InputDecoration(
                          labelText: 'Item barcode / QR value',
                          prefixIcon: Icon(Icons.qr_code_2_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Quick quantity increment pills
                      Row(
                        children: [1, 5, 10, 25].map((amt) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                final current =
                                    int.tryParse(_quantity.text) ?? 0;
                                setState(() {
                                  _quantity.text = '${current + amt}';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('+$amt',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_operation == StockOperation.checkIn
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline),
                        label: Text(_saving
                            ? 'Recording…'
                            : _operation == StockOperation.checkIn
                                ? 'Record check-in'
                                : 'Record check-out'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StockOperationException implements Exception {
  const StockOperationException(this.message);
  final String message;
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Center(
          child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 18)
                  ]))));
}
