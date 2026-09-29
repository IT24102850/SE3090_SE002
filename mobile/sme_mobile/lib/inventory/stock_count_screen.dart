import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  final _reasonNotes = TextEditingController();
  final _picker = ImagePicker();
  final _store = _CountStore();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectionChanges;
  List<_CatalogItem> _catalog = [];
  List<_PendingCount> _pending = [];
  List<Map<String, dynamic>> _approvalQueue = [];
  bool _loading = true,
      _syncing = false,
      _savingCount = false,
      _torchOn = false,
      _approvalLoading = false;
  String? _scannedCode;
  String? _reason;
  bool _isOnline = true;
  bool _canApproveCounts = false;
  List<XFile> _selectedPhotos = [];
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
    _reasonNotes.dispose();
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
    await _loadApprovalQueue();
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

  Future<void> _loadApprovalQueue() async {
    if (_approvalLoading) return;
    setState(() => _approvalLoading = true);
    try {
      final response =
          await widget.client.get('/api/inventory/physical-count-approvals');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 403) {
          if (mounted) setState(() => _approvalQueue = []);
          return;
        }
        throw StateError(
            'Could not load count approvals (server ${response.statusCode}).');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = ((payload['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (mounted) {
        setState(() {
          _approvalQueue = items;
          _canApproveCounts = payload['canApprove'] == true;
        });
      }
    } catch (error) {
      if (mounted) {
        showAppNotification(
          error is StateError
              ? error.message
              : 'Could not load manager approval queue.',
          tone: AppNotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _approvalLoading = false);
    }
  }

  Future<void> _reviewCount(Map<String, dynamic> count, String decision) async {
    final countId = count['id']?.toString();
    if (countId == null) return;
    final notesController = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text(
          decision == 'Approve'
              ? 'Approve stock adjustment?'
              : 'Reject stock count?',
          style: AppTextStyles.subtitle.copyWith(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${count['itemName']}: ${_formatAuditQuantity((count['variance'] as num?)?.toDouble() ?? 0)} units',
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLength: 1000,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: decision == 'Reject'
                    ? 'Reason for rejection (required)'
                    : 'Review note (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final note = notesController.text.trim();
              if (decision == 'Reject' && note.isEmpty) return;
              Navigator.pop(dialogContext, note);
            },
            child: Text(decision),
          ),
        ],
      ),
    );
    notesController.dispose();
    if (notes == null || !mounted) return;
    try {
      final response = await widget.client.post(
        '/api/inventory/physical-count-approvals/$countId/review',
        body: {'decision': decision, 'notes': notes},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        showAppNotification(
          _error(response.body) ?? 'The stock count could not be reviewed.',
          tone: AppNotificationTone.error,
        );
        await _loadApprovalQueue();
        return;
      }
      showAppNotification(
        decision == 'Approve'
            ? 'Stock adjustment approved and applied.'
            : 'Stock count rejected.',
        tone: AppNotificationTone.success,
      );
      await _loadApprovalQueue();
      await _refreshCatalog();
    } catch (_) {
      if (mounted) {
        showAppNotification(
          'Could not reach the approval service.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  Future<void> _sync({bool silent = false}) async {
    if (!mounted || _syncing) return;
    final queued = _pending.where((count) => !count.requiresReview).toList();
    if (queued.isEmpty) {
      if (!silent) {
        showAppNotification(
          _pending.isEmpty
              ? 'There are no physical counts waiting to sync.'
              : 'Remove counts marked for recount, refresh inventory, and count those items again.',
          tone: _pending.isEmpty
              ? AppNotificationTone.info
              : AppNotificationTone.warning,
        );
      }

      return;
    }
    final queuedIds = queued.map((count) => count.id).toSet();
    setState(() => _syncing = true);
    try {
      var appliedCount = 0;
      var matchedCount = 0;
      var approvalCount = 0;
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
          remaining.add(count.withError(
            'Item is no longer in catalog. Verify it and take a new count.',
            requiresReview: true,
          ));
          continue;
        }
        final item = matches.first;
        if (count.systemQuantityAtCount == null) {
          remaining.add(count.withError(
            'This saved count has no system-quantity snapshot. Remove it and recount.',
            requiresReview: true,
          ));
          continue;
        }
        try {
          final response = await widget.client
              .post('/api/inventory/${item.id}/physical-count', body: {
            'countedQuantity': count.quantity,
            'systemQuantityAtCount': count.systemQuantityAtCount,
            'countedAt': count.recordedAt.toUtc().toIso8601String(),
            'reference': 'MOBILE-AUDIT-${count.id}',
            'reason': count.reason,
            'reasonNotes': count.reasonNotes,
          });
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final conflict = _decodeJsonMap(response.body);
            remaining.add(count.withError(
              _error(response.body) ?? 'Server rejected physical count.',
              requiresReview:
                  response.statusCode == 409 || response.statusCode == 404,
              changedActivity: _formatChangedActivity(
                conflict?['changedMovements'],
              ),
            ));
            continue;
          }
          final audit = _decodeJsonMap(response.body);
          final auditId = audit?['id']?.toString();
          if (auditId == null) {
            remaining.add(count.withError(
              'Count was recorded, but the audit response did not include its ID. Sync again to safely verify it.',
            ));
            continue;
          }
          switch (audit?['status']) {
            case 'Applied':
              appliedCount++;
            case 'Matched':
              matchedCount++;
            case 'PendingApproval':
              approvalCount++;
            default:
              remaining.add(count.withError(
                'The server returned an unknown count status. Sync again to verify it.',
              ));
              continue;
          }
          try {
            for (var index = 0; index < count.evidence.length; index++) {
              final evidence = count.evidence[index];
              final upload = await widget.client.uploadPhysicalCountPhoto(
                auditId,
                base64Decode(evidence.bytesBase64),
                evidence.fileName,
                '${count.id}-$index',
              );
              if (upload.statusCode < 200 || upload.statusCode >= 300) {
                throw StateError(
                    _error(upload.body) ?? 'Evidence photo upload failed.');
              }
            }
          } catch (error) {
            remaining.add(count.withError(
              error is StateError
                  ? error.message
                  : 'Count saved, but its evidence could not be uploaded. Sync again to retry.',
            ));
          }
        } catch (_) {
          remaining.add(count.withError('Unable to reach inventory service.'));
        }
      }
      final newCounts =
          _pending.where((count) => !queuedIds.contains(count.id)).toList();
      final pendingAfterSync = [...newCounts, ...remaining];
      await _refreshCatalog();
      await _store.save(_catalog, pendingAfterSync);
      if (mounted) setState(() => _pending = pendingAfterSync);
      await _loadApprovalQueue();

      if (!silent && mounted) {
        final recountCount =
            pendingAfterSync.where((count) => count.requiresReview).length;
        final syncedSummary = [
          if (appliedCount > 0) '$appliedCount adjustment(s) applied',
          if (matchedCount > 0) '$matchedCount count(s) matched',
          if (approvalCount > 0)
            '$approvalCount large adjustment(s) awaiting manager approval',
        ].join('; ');
        showAppNotification(
          pendingAfterSync.isEmpty
              ? (syncedSummary.isEmpty
                  ? 'All physical counts synced to inventory ledger.'
                  : syncedSummary)
              : recountCount > 0
                  ? '$recountCount count(s) changed since counting and need a fresh count.'
                  : '${pendingAfterSync.length} count(s) pending sync retry.${syncedSummary.isEmpty ? '' : ' $syncedSummary.'}',
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
    final value = _decodeJsonMap(body);
    return value?['message'] as String? ?? value?['title'] as String?;
  }

  Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _formatChangedActivity(Object? payload) {
    if (payload is! List) return const [];
    return payload.whereType<Map<String, dynamic>>().map((movement) {
      final quantity = (movement['quantity'] as num?)?.toDouble() ?? 0;
      final sign = quantity > 0 ? '+' : '';
      final type = movement['movementType']?.toString() ?? 'Stock change';
      final reference = movement['reference']?.toString();
      final actor = movement['performedBy']?.toString();
      final occurredAt = DateTime.tryParse(
        movement['occurredAt']?.toString() ?? '',
      );
      final details = [
        if (reference != null && reference.isNotEmpty) reference,
        if (actor != null && actor.isNotEmpty) 'by $actor',
        if (occurredAt != null) occurredAt.toLocal().toString(),
      ];
      return '$type: $sign${_formatAuditQuantity(quantity)}'
          '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
    }).toList();
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
    final variance = quantity - item.quantity;
    final reason = variance == 0 ? 'NoDiscrepancy' : _reason;
    if (reason == null) {
      showAppNotification(
        'Choose a reason for the stock difference before saving.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    if (variance != 0 &&
        _reason == 'Other' &&
        _reasonNotes.text.trim().isEmpty) {
      showAppNotification(
        'Add a short note when the reason is Other.',
        tone: AppNotificationTone.warning,
      );
      return;
    }

    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Save physical count?',
      message:
          'System quantity: ${_formatAuditQuantity(item.quantity)}\nCounted quantity: ${_formatAuditQuantity(quantity)}\nAdjustment: ${variance > 0 ? '+' : ''}${_formatAuditQuantity(variance)}\n\n${_isLargeVariance(variance, item.quantity) ? 'This large adjustment will wait for a manager approval.' : 'The adjustment will be applied when the count syncs.'}\nIf stock changes before sync, you will be asked to recount.',
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
        systemQuantityAtCount: item.quantity,
        recordedAt: DateTime.now().toUtc(),
        reason: reason,
        reasonNotes: variance == 0 || _reasonNotes.text.trim().isEmpty
            ? null
            : _reasonNotes.text.trim(),
        evidence: await _readSelectedEvidence(),
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
        _reason = null;
        _reasonNotes.clear();
        _selectedPhotos = [];
      });
      showAppNotification(
          _isLargeVariance(variance, item.quantity)
              ? '${item.name} count saved; the adjustment will wait for manager approval after sync.'
              : '${item.name} physical count saved for sync.',
          tone: AppNotificationTone.success);
      _scanAgain();
      _sync(silent: true);
    } catch (error) {
      if (mounted) {
        showAppNotification(
          error is StateError ? error.message : 'Could not save the count.',
          tone: AppNotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingCount = false);
    }
  }

  _CatalogItem? get _selectedCatalogItem {
    final code = _sku.text.trim().toLowerCase();
    if (code.isEmpty) return null;
    return _catalog.where((i) => i.sku.toLowerCase() == code).firstOrNull;
  }

  bool _isLargeVariance(double variance, double systemQuantity) {
    final absoluteVariance = variance.abs();
    return absoluteVariance > 5 ||
        (systemQuantity == 0
            ? absoluteVariance > 0
            : absoluteVariance / systemQuantity > 0.10);
  }

  Future<void> _pickEvidence(ImageSource source) async {
    try {
      final List<XFile> photos;
      if (source == ImageSource.gallery) {
        photos = await _picker.pickMultiImage(
          imageQuality: 55,
          maxWidth: 1200,
        );
      } else {
        final photo = await _picker.pickImage(
          source: source,
          imageQuality: 55,
          maxWidth: 1200,
        );
        photos = photo == null ? [] : [photo];
      }
      if (!mounted || photos.isEmpty) return;
      final totalPhotos = _selectedPhotos.length + photos.length;
      setState(() {
        _selectedPhotos = [..._selectedPhotos, ...photos].take(3).toList();
      });
      if (totalPhotos > 3) {
        showAppNotification(
          'A maximum of 3 evidence photos can be attached.',
          tone: AppNotificationTone.warning,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppNotification(
          'Could not select evidence photos.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  Future<List<_PendingEvidence>> _readSelectedEvidence() async {
    final evidence = <_PendingEvidence>[];
    for (final photo in _selectedPhotos.take(3)) {
      final bytes = await photo.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('${photo.name} exceeds the 5 MB photo limit.');
      }
      evidence.add(_PendingEvidence(
        fileName: photo.name,
        bytesBase64: base64Encode(bytes),
      ));
    }
    return evidence;
  }

  Future<void> _showEvidenceSourcePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.cyan),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_outlined, color: AppColors.cyan),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickEvidence(source);
  }

  Widget _quantitySummary(
    double systemQuantity,
    double countedQuantity,
    double adjustment,
    String unit,
  ) {
    final adjustmentColor = adjustment == 0
        ? AppColors.success
        : adjustment > 0
            ? AppColors.cyan
            : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          _quantitySummaryRow(
              'System quantity', systemQuantity, unit, AppColors.textPrimary),
          const SizedBox(height: 7),
          _quantitySummaryRow(
              'Counted quantity', countedQuantity, unit, AppColors.textPrimary),
          const Divider(height: 14, color: AppColors.hairline),
          _quantitySummaryRow(
            'Adjustment',
            adjustment,
            unit,
            adjustmentColor,
            signed: true,
          ),
        ],
      ),
    );
  }

  Widget _quantitySummaryRow(
      String label, double quantity, String unit, Color color,
      {bool signed = false}) {
    final sign = signed && quantity > 0 ? '+' : '';
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
        ),
        Text(
          '$sign${_formatAuditQuantity(quantity)} $unit',
          style: AppTextStyles.body
              .copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
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
                  await _loadApprovalQueue();
                  if (mounted && !_syncing) {
                    showAppNotification(
                      _pending.isEmpty
                          ? 'Inventory catalog refreshed and counts synchronized.'
                          : 'Inventory catalog refreshed. Review queued counts for recount warnings.',
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

                    if (_approvalLoading || _approvalQueue.isNotEmpty) ...[
                      SectionHeader(
                        'LARGE DISCREPANCIES',
                        trailing: Text(
                            '${_approvalQueue.length} awaiting review',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.warning)),
                      ),
                      if (_approvalLoading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.cyan),
                          ),
                        )
                      else
                        ..._approvalQueue.map(_buildApprovalCard),
                      const SizedBox(height: 14),
                    ],

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
                      : '${_pending.length} counts queued; review any marked RECOUNT REQUIRED.',
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
                          'System Record: ${_formatAuditQuantity(matchedItem.quantity)} ${matchedItem.unit}',
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
                                ? '+${_formatAuditQuantity(variance)} SURPLUS'
                                : '${_formatAuditQuantity(variance)} DEFICIT',
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
            if (hasVariance) ...[
              const SizedBox(height: 10),
              _quantitySummary(
                matchedItem.quantity,
                physicalQty,
                variance,
                matchedItem.unit,
              ),
            ],
          ],

          if (matchedItem != null && hasVariance && variance != 0) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason for discrepancy *',
                filled: true,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'DamagedStock', child: Text('Damaged stock')),
                DropdownMenuItem(
                    value: 'LostOrMissing', child: Text('Lost / missing')),
                DropdownMenuItem(
                    value: 'CountingError', child: Text('Counting error')),
                DropdownMenuItem(
                    value: 'SupplierShortage',
                    child: Text('Supplier shortage')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _reason = value),
            ),
            if (_reason == 'Other') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _reasonNotes,
                maxLength: 1000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Explain the discrepancy *',
                  filled: true,
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _selectedPhotos.length >= 3
                  ? null
                  : () => _showEvidenceSourcePicker(),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _selectedPhotos.isEmpty
                    ? 'Add evidence photos (optional)'
                    : 'Evidence photos (${_selectedPhotos.length}/3)',
              ),
            ),
            if (_selectedPhotos.isNotEmpty)
              Wrap(
                spacing: 8,
                children: List.generate(_selectedPhotos.length, (index) {
                  return InputChip(
                    label: Text(_selectedPhotos[index].name),
                    onDeleted: () => setState(
                      () => _selectedPhotos.removeAt(index),
                    ),
                  );
                }),
              ),
            if (_isLargeVariance(variance, matchedItem.quantity))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Manager approval required: adjustment is over 5 units or over 10% of system stock.',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.warning),
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

  Widget _buildApprovalCard(Map<String, dynamic> count) {
    final variance = (count['variance'] as num?)?.toDouble() ?? 0;
    final photos =
        (count['photoUrls'] as List?)?.whereType<String>().toList() ??
            const <String>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InventoryPanel(
        padding: const EdgeInsets.all(14),
        borderColor: AppColors.warning.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${count['itemName'] ?? 'Unknown item'} (${count['sku'] ?? 'Unknown SKU'})',
              style: AppTextStyles.subtitle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              'System ${count['systemQuantityAtCount']} → counted ${count['countedQuantity']} · adjustment ${variance > 0 ? '+' : ''}${_formatAuditQuantity(variance)}',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            Text(
              'Reason: ${count['reason']}${count['reasonNotes'] == null ? '' : ' · ${count['reasonNotes']}'}',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            Text(
              'Counted by ${count['countedBy'] ?? 'Unknown'} · ${count['countedAt'] ?? ''}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photos[index],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 72,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_canApproveCounts)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reviewCount(count, 'Reject'),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _reviewCount(count, 'Approve'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Waiting for an Admin or Manager to review this adjustment.',
                style: AppTextStyles.caption.copyWith(color: AppColors.warning),
              ),
          ],
        ),
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
                    'SKU: ${entry.sku} • Counted: ${entry.quantity} • System at count: ${entry.systemQuantityAtCount ?? 'unknown'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (entry.lastError != null)
                    Text(
                      entry.requiresReview
                          ? 'RECOUNT REQUIRED · ${entry.lastError}'
                          : entry.lastError!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: entry.requiresReview
                            ? AppColors.error
                            : AppColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  for (final activity in entry.changedActivity)
                    Text(
                      '• $activity',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  if (entry.evidence.isNotEmpty)
                    Text(
                      '${entry.evidence.length} evidence photo(s) queued',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
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

String _formatAuditQuantity(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
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
    required this.systemQuantityAtCount,
    required this.recordedAt,
    required this.reason,
    required this.evidence,
    this.lastError,
    this.requiresReview = false,
    this.reasonNotes,
    this.changedActivity = const [],
  });

  final String id, sku, name;
  final double quantity;
  final double? systemQuantityAtCount;
  final DateTime recordedAt;
  final String reason;
  final String? reasonNotes;
  final List<_PendingEvidence> evidence;
  final String? lastError;
  final bool requiresReview;
  final List<String> changedActivity;

  _PendingCount withError(
    String error, {
    bool requiresReview = false,
    List<String> changedActivity = const [],
  }) =>
      _PendingCount(
        id: id,
        sku: sku,
        name: name,
        quantity: quantity,
        systemQuantityAtCount: systemQuantityAtCount,
        recordedAt: recordedAt,
        reason: reason,
        reasonNotes: reasonNotes,
        evidence: evidence,
        lastError: error,
        requiresReview: requiresReview,
        changedActivity:
            changedActivity.isEmpty ? this.changedActivity : changedActivity,
      );

  factory _PendingCount.fromJson(Map<String, dynamic> json) {
    final systemQuantity = (json['systemQuantityAtCount'] as num?)?.toDouble();
    final lastError = json['lastError'] as String?;
    return _PendingCount(
      id: '${json['id']}',
      sku: '${json['sku']}',
      name: '${json['name']}',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      systemQuantityAtCount: systemQuantity,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      reason: json['reason'] as String? ?? 'Other',
      reasonNotes: json['reasonNotes'] as String?,
      evidence: ((json['evidence'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_PendingEvidence.fromJson)
          .toList(),
      lastError: lastError ??
          (systemQuantity == null
              ? 'Saved before count validation was added. Remove and recount.'
              : null),
      requiresReview: json['requiresReview'] == true || systemQuantity == null,
      changedActivity: ((json['changedActivity'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'systemQuantityAtCount': systemQuantityAtCount,
        'recordedAt': recordedAt.toIso8601String(),
        'reason': reason,
        'reasonNotes': reasonNotes,
        'evidence': evidence.map((photo) => photo.toJson()).toList(),
        'lastError': lastError,
        'requiresReview': requiresReview,
        'changedActivity': changedActivity,
      };
}

class _PendingEvidence {
  const _PendingEvidence({required this.fileName, required this.bytesBase64});

  final String fileName;
  final String bytesBase64;

  factory _PendingEvidence.fromJson(Map<String, dynamic> json) =>
      _PendingEvidence(
        fileName: json['fileName'] as String? ?? 'evidence.jpg',
        bytesBase64: json['bytesBase64'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'bytesBase64': bytesBase64,
      };
}
