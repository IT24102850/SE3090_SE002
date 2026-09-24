import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';

/// Offline-first physical stock audit screen.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.client});
  final AuthenticatedApiClient client;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen>
    with SingleTickerProviderStateMixin {
  final _scanner = MobileScannerController();
  final _sku = TextEditingController();
  final _quantity = TextEditingController();
  final _store = _CountStore();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectionChanges;
  List<_CatalogItem> _catalog = [];
  List<_PendingCount> _pending = [];
  bool _loading = true,
      _syncing = false,
      _savingCount = false,
      _torchOn = false;
  String? _scannedCode;
  bool _isOnline = true;
  late final AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    try {
      _connectionChanges =
          _connectivity.onConnectivityChanged.listen((results) {
        final online =
            results.any((result) => result != ConnectivityResult.none);
        if (mounted) setState(() => _isOnline = online);
        if (online) _sync(silent: true);
      }, onError: (_) {
        // Ignore if native channel is unavailable before app restart
      });
    } catch (_) {
      // Graceful fallback if plugin not yet bound
    }
    _load();
  }

  @override
  void dispose() {
    _connectionChanges?.cancel();
    _scanner.dispose();
    _scanLineController.dispose();
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
        if (response.statusCode != 200) return false;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        catalog.addAll(((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_CatalogItem.fromJson));
        page++;
      }
      await _store.save(catalog, _pending);
      if (mounted) setState(() => _catalog = catalog);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirmSync() async {
    if (_pending.isEmpty || _syncing) {
      await _sync();
      return;
    }
    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Sync physical counts?',
      message:
          'Apply ${_pending.length} saved physical count${_pending.length == 1 ? '' : 's'} to the inventory ledger now?',
      confirmLabel: 'Sync Counts',
      icon: Icons.sync_rounded,
      accent: AppColors.cyan,
    );
    if (confirmed && mounted) await _sync();
  }

  Future<void> _sync({bool silent = false}) async {
    if (!mounted || _syncing) return;
    if (_pending.isEmpty) {
      if (!silent) {
        showAppNotification(
          'There are no physical counts waiting to sync.',
          tone: AppNotificationTone.info,
        );
      }

      return;
    }
    final queued = List<_PendingCount>.of(_pending);
    final queuedIds = queued.map((count) => count.id).toSet();
    setState(() => _syncing = true);
    try {
      if (!await _refreshCatalog()) {
        if (!silent && mounted) {
          showAppNotification(
            'Could not refresh inventory before syncing. Counts remain queued.',
            tone: AppNotificationTone.error,
          );
        }
        return;
      }
      final remaining = <_PendingCount>[];
      for (final count in queued) {
        final matches = _catalog
            .where((item) => item.sku.toLowerCase() == count.sku.toLowerCase());
        if (matches.isEmpty) {
          remaining.add(count.withError('Item is no longer in catalog.'));
          continue;
        }
        final item = matches.first;
        final delta = count.quantity - item.quantity;
        if (delta == 0) continue;
        try {
          final response = await widget.client
              .post('/api/inventory/${item.id}/adjust', body: {
            'quantity': delta,
            'reference': 'MOBILE-AUDIT-${count.id}',
            'notes':
                'Physical audit count ${count.quantity} recorded at ${count.recordedAt.toIso8601String()}',
          });
          if (response.statusCode < 200 || response.statusCode >= 300) {
            remaining.add(count.withError(
                _error(response.body) ?? 'Server rejected audit adjustment.'));
          }
        } catch (_) {
          remaining.add(count.withError('Unable to reach inventory service.'));
        }
      }
      final newCounts =
          _pending.where((count) => !queuedIds.contains(count.id)).toList();
      final pendingAfterSync = [...newCounts, ...remaining];
      await _store.save(_catalog, pendingAfterSync);
      if (mounted) setState(() => _pending = pendingAfterSync);

      if (!silent && mounted) {
        showAppNotification(
          pendingAfterSync.isEmpty
              ? 'All physical counts synced to inventory ledger.'
              : '${pendingAfterSync.length} count(s) pending sync retry.',
          tone: pendingAfterSync.isEmpty
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
    HapticFeedback.mediumImpact();
    setState(() {
      _scannedCode = code;
      _sku.text = code;
    });
    showAppNotification(
      'Barcode scanned. Enter the physical quantity to continue.',
      tone: AppNotificationTone.success,
    );
    _scanner.stop();
  }

  Future<void> _scanAgain() async {
    try {
      setState(() => _scannedCode = null);
      await _scanner.start();
      if (mounted) {
        showAppNotification(
          'Scanner ready. Align the next barcode inside the frame.',
          tone: AppNotificationTone.info,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppNotification(
          'The scanner could not be started. Enter the SKU manually.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  Future<void> _saveCount() async {
    if (_savingCount) return;
    final code = _sku.text.trim();
    final quantity = double.tryParse(_quantity.text.trim());
    if (code.isEmpty || quantity == null || quantity < 0) {
      showAppNotification(
          'Scan or enter SKU and specify a quantity of zero or more.',
          tone: AppNotificationTone.warning);
      return;
    }
    final matches =
        _catalog.where((item) => item.sku.toLowerCase() == code.toLowerCase());
    if (matches.isEmpty) {
      showAppNotification(
          'SKU "$code" is not in the cached catalog. Pull to refresh while online.',
          tone: AppNotificationTone.error);
      return;
    }
    final item = matches.first;

    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Save physical count?',
      message:
          'Record ${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} unit${quantity == 1 ? '' : 's'} for ${item.name} (${item.sku})?',
      confirmLabel: 'Save Count',
      icon: Icons.fact_check_rounded,
      accent: AppColors.cyan,
    );
    if (!confirmed || !mounted) return;

    setState(() => _savingCount = true);
    try {
      final entry = _PendingCount(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sku: item.sku,
        name: item.name,
        quantity: quantity,
        recordedAt: DateTime.now(),
      );
      final pending = [
        ..._pending.where((c) => c.sku.toLowerCase() != item.sku.toLowerCase()),
        entry,
      ];
      await _store.save(_catalog, pending);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _sku.clear();
        _quantity.clear();
        _scannedCode = null;
      });
      showAppNotification('${item.name} physical count recorded for sync.',
          tone: AppNotificationTone.success);
      _scanAgain();
      _sync(silent: true);
    } finally {
      if (mounted) setState(() => _savingCount = false);
    }
  }

  _CatalogItem? get _selectedCatalogItem {
    final code = _sku.text.trim().toLowerCase();
    if (code.isEmpty) return null;
    return _catalog.where((i) => i.sku.toLowerCase() == code).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Stock Audit',
        actions: [
          IconButton(
            onPressed: _syncing ? null : _confirmSync,
            tooltip: 'Sync Counts Now',
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) =>
                  RotationTransition(turns: animation, child: child),
              child: _syncing
                  ? const SizedBox(
                      key: ValueKey('sync-loader'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.cyan),
                    )
                  : const Icon(
                      key: ValueKey('sync-icon'),
                      Icons.sync_rounded,
                      color: AppColors.cyan,
                    ),
            ),
          ),
        ],
      ),
      child: SafeArea(
        child: _loading
            ? const AppLoader(message: 'Initializing local inventory cache...')
            : RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.overlaySurface,
                onRefresh: () async {
                  final refreshed = await _refreshCatalog();
                  if (!refreshed) {
                    if (mounted) {
                      showAppNotification(
                        'Inventory could not be refreshed. Showing the last saved catalog.',
                        tone: AppNotificationTone.error,
                      );
                    }
                    return;
                  }
                  await _sync();
                  if (mounted && !_syncing) {
                    showAppNotification(
                      _pending.isEmpty
                          ? 'Inventory catalog refreshed and counts synchronized.'
                          : 'Inventory catalog refreshed. Pending counts remain queued.',
                      tone: _pending.isEmpty
                          ? AppNotificationTone.success
                          : AppNotificationTone.warning,
                    );
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // Offline / Online Status Header
                    _buildStatusBanner(),
                    const SizedBox(height: 18),

                    // Metrics Strip
                    Row(
                      children: [
                        Expanded(
                          child: _AuditStatCard(
                            label: 'CACHED SKUS',
                            value: '${_catalog.length}',
                            icon: Icons.dataset_rounded,
                            accentColor: AppColors.cyan,
                            subLabel: 'Available offline',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AuditStatCard(
                            label: 'PENDING QUEUE',
                            value: '${_pending.length}',
                            icon: Icons.cloud_upload_rounded,
                            accentColor: _pending.isNotEmpty
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981),
                            subLabel: _pending.isNotEmpty
                                ? 'Pending server sync'
                                : 'Fully synchronized',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Scanner Viewport
                    _buildScannerBox(),
                    const SizedBox(height: 18),

                    // Quick Catalog Chips
                    AnimatedSize(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: _catalog.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              children: [
                                SectionHeader(
                                  'CACHED ITEMS',
                                  trailing: Text('Tap to select',
                                      style: AppTextStyles.caption
                                          .copyWith(color: AppColors.cyan)),
                                ),
                                _buildCatalogChipCarousel(),
                                const SizedBox(height: 18),
                              ],
                            ),
                    ),

                    // Physical Count Form
                    _buildCountInputCard(),
                    const SizedBox(height: 22),

                    // Pending Queue List
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      child: _pending.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              children: [
                                SectionHeader(
                                  'SAVED AUDIT QUEUE',
                                  trailing: Text('${_pending.length} unsynced',
                                      style: AppTextStyles.caption.copyWith(
                                          color: const Color(0xFFF59E0B))),
                                ),
                                const SizedBox(height: 8),
                                ..._pending.map(_buildPendingCard),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF142235),
        border: Border.all(
          color: (_isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
              .withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_isOnline
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color:
                  _isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _isOnline
                            ? 'ONLINE & SYNC READY'
                            : 'OFFLINE MODE ACTIVE',
                        key: ValueKey(_isOnline),
                        style: AppTextStyles.label.copyWith(
                          color: _isOnline
                              ? const Color(0xFF10B981)
                              : const Color(0xFFFBBF24),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _pending.isEmpty
                      ? 'All counts uploaded to server.'
                      : '${_pending.length} counts queued for automatic sync.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_pending.isNotEmpty && _isOnline)
            GhostButton(
              label: 'Sync',
              icon: Icons.sync_rounded,
              height: 36,
              expand: false,
              onPressed: _syncing ? null : () => _sync(),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerBox() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.4), width: 1.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
            ),
            AnimatedBuilder(
              animation: _scanLineController,
              builder: (context, child) => Positioned(
                top: 26 + (_scanLineController.value * 112),
                left: 28,
                right: 28,
                child: child!,
              ),
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.85),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.7),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 180,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.6),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xCC050A1A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  tooltip: _torchOn ? 'Turn Flash Off' : 'Turn Flash On',
                  onPressed: () async {
                    try {
                      await _scanner.toggleTorch();
                      if (mounted) {
                        setState(() => _torchOn = !_torchOn);
                        showAppNotification(
                          _torchOn
                              ? 'Scanner flash turned on.'
                              : 'Scanner flash turned off.',
                          tone: AppNotificationTone.info,
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        showAppNotification(
                          'The scanner flash is unavailable on this device.',
                          tone: AppNotificationTone.warning,
                        );
                      }
                    }
                  },
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      key: ValueKey(_torchOn),
                      color: _torchOn ? AppColors.cyan : Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: 14,
              right: 14,
              bottom: _scannedCode == null ? -54 : 14,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _scannedCode == null ? 0 : 1,
                child: GhostButton(
                  label: _scannedCode == null
                      ? 'Scan a barcode'
                      : 'Scanned: $_scannedCode (Tap to rescan)',
                  icon: Icons.refresh_rounded,
                  height: 38,
                  onPressed: _scannedCode == null ? null : _scanAgain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogChipCarousel() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _catalog.take(15).length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final item = _catalog[idx];
          final isSelected =
              _sku.text.trim().toLowerCase() == item.sku.toLowerCase();

          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _sku.text = item.sku;
                _scannedCode = item.sku;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.cyan.withValues(alpha: 0.2)
                    : AppColors.glassFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.cyan : AppColors.glassBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.inventory_2_outlined,
                    size: 14,
                    color:
                        isSelected ? AppColors.cyan : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${item.name} (${item.sku})',
                    style: AppTextStyles.caption.copyWith(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountInputCard() {
    final matchedItem = _selectedCatalogItem;
    final physicalQty = double.tryParse(_quantity.text.trim());
    final hasVariance = matchedItem != null && physicalQty != null;
    final variance = hasVariance ? physicalQty - matchedItem.quantity : 0.0;

    return InventoryPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PHYSICAL AUDIT LOGGING', style: AppTextStyles.label),
          const SizedBox(height: 12),

          // SKU input
          TextField(
            controller: _sku,
            style: AppTextStyles.body
                .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            onChanged: (val) =>
                setState(() => _scannedCode = val.isEmpty ? null : val),
            decoration: InputDecoration(
              labelText: 'Item SKU / Barcode',
              labelStyle:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              prefixIcon:
                  const Icon(Icons.qr_code_2_rounded, color: AppColors.cyan),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.glassBorder),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Quantity input
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style:
                AppTextStyles.title.copyWith(fontSize: 18, color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Counted Quantity on Hand',
              labelStyle:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              prefixIcon:
                  const Icon(Icons.numbers_rounded, color: AppColors.cyan),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.glassBorder),
              ),
            ),
          ),

          // Real-time Variance Preview Banner
          if (matchedItem != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matchedItem.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.subtitle.copyWith(fontSize: 13),
                        ),
                        Text(
                          'System Record: ${matchedItem.quantity.toInt()} ${matchedItem.unit}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (hasVariance)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (variance == 0
                                ? const Color(0xFF10B981)
                                : variance > 0
                                    ? AppColors.cyan
                                    : const Color(0xFFF43F5E))
                            .withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        variance == 0
                            ? 'MATCHED (0)'
                            : variance > 0
                                ? '+${variance.toInt()} SURPLUS'
                                : '${variance.toInt()} DEFICIT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: variance == 0
                              ? const Color(0xFF10B981)
                              : variance > 0
                                  ? AppColors.cyan
                                  : const Color(0xFFF43F5E),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          NeonButton(
            label: _savingCount ? 'Saving...' : 'Record Physical Count',
            isLoading: _savingCount,
            icon: Icons.save_rounded,
            onPressed: _saveCount,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(_PendingCount entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InventoryPanel(
        padding: const EdgeInsets.all(14),
        borderColor: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_outlined,
                  color: Color(0xFFF59E0B), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle
                        .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'SKU: ${entry.sku} • Counted: ${entry.quantity.toInt()} units',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (entry.lastError != null)
                    Text(
                      entry.lastError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFFF43F5E), fontSize: 11),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFF43F5E), size: 20),
              onPressed: () async {
                final confirmed = await showAppConfirmation(
                  context: context,
                  title: 'Remove saved count?',
                  message:
                      'Remove the unsynced count for ${entry.name}? This cannot be undone.',
                  confirmLabel: 'Remove Count',
                  icon: Icons.delete_outline_rounded,
                  accent: const Color(0xFFF43F5E),
                  isDestructive: true,
                );
                if (!confirmed || !mounted) return;
                final pending =
                    _pending.where((c) => c.id != entry.id).toList();
                await _store.save(_catalog, pending);
                if (mounted) {
                  setState(() => _pending = pending);
                  showAppNotification(
                    'Saved count removed from the sync queue.',
                    tone: AppNotificationTone.success,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditStatCard extends StatelessWidget {
  const _AuditStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.subLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return InventoryPanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFF29394D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Icon(icon, size: 17, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              style: AppTextStyles.headlineSmall.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption
                .copyWith(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CountStore {
  static const _catalogKey = 'stock_count_catalog_v2';
  static const _pendingKey = 'stock_count_pending_v2';

  Future<({List<_CatalogItem> catalog, List<_PendingCount> pending})>
      load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final catRaw = prefs.getString(_catalogKey);
      final penRaw = prefs.getString(_pendingKey);

      final catalog = catRaw == null
          ? <_CatalogItem>[]
          : (jsonDecode(catRaw) as List)
              .whereType<Map<String, dynamic>>()
              .map(_CatalogItem.fromJson)
              .toList();

      final pending = penRaw == null
          ? <_PendingCount>[]
          : (jsonDecode(penRaw) as List)
              .whereType<Map<String, dynamic>>()
              .map(_PendingCount.fromJson)
              .toList();

      return (catalog: catalog, pending: pending);
    } catch (_) {
      return (catalog: <_CatalogItem>[], pending: <_PendingCount>[]);
    }
  }

  Future<void> save(
      List<_CatalogItem> catalog, List<_PendingCount> pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _catalogKey, jsonEncode(catalog.map((i) => i.toJson()).toList()));
      await prefs.setString(
          _pendingKey, jsonEncode(pending.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }
}

class _CatalogItem {
  const _CatalogItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.quantity,
    this.unit = 'units',
  });

  final String id, sku, name, unit;
  final double quantity;

  factory _CatalogItem.fromJson(Map<String, dynamic> json) => _CatalogItem(
        id: '${json['id']}',
        sku: '${json['sku'] ?? ''}',
        name: '${json['name'] ?? ''}',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: '${json['unit'] ?? json['unitName'] ?? 'units'}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'unit': unit,
      };
}

class _PendingCount {
  const _PendingCount({
    required this.id,
    required this.sku,
    required this.name,
    required this.quantity,
    required this.recordedAt,
    this.lastError,
  });

  final String id, sku, name;
  final double quantity;
  final DateTime recordedAt;
  final String? lastError;

  _PendingCount withError(String error) => _PendingCount(
        id: id,
        sku: sku,
        name: name,
        quantity: quantity,
        recordedAt: recordedAt,
        lastError: error,
      );

  factory _PendingCount.fromJson(Map<String, dynamic> json) => _PendingCount(
        id: '${json['id']}',
        sku: '${json['sku']}',
        name: '${json['name']}',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        lastError: json['lastError'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'recordedAt': recordedAt.toIso8601String(),
        'lastError': lastError,
      };
}
