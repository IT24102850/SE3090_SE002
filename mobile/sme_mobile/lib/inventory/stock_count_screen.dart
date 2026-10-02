import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'inventory_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';
import 'inventory_loading_state.dart';

/// Offline-first physical stock audit screen.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.client});
  final AuthenticatedApiClient client;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen>
    with TickerProviderStateMixin {
  final _scanner = MobileScannerController();
  final _sku = TextEditingController();
  final _quantity = TextEditingController();
  final _reasonNotes = TextEditingController();
  final _picker = ImagePicker();
  final _store = _CountStore();
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectionChanges;
  List<_CatalogItem> _catalog = [];
  Map<String, _BranchLocation> _branchLocations = {};
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
  bool _scanSucceeded = false;
  List<XFile> _selectedPhotos = [];
  String? _selectedCatalogItemId;
  double? _latitude;
  double? _longitude;
  String? _locationBranchId;
  bool _capturingLocation = false;
  static const _branchVerificationRadiusMeters = 150.0;

  ({double distanceMeters})? get _locationVerification {
    final item = _selectedCatalogItem;
    final branchId = item?.branchId;
    if (branchId == null ||
        branchId != _locationBranchId ||
        _latitude == null ||
        _longitude == null) {
      return null;
    }
    final branch = _branchLocations[branchId];
    if (branch?.latitude == null || branch?.longitude == null) return null;
    return (
      distanceMeters: Geolocator.distanceBetween(
        _latitude!,
        _longitude!,
        branch!.latitude!,
        branch.longitude!,
      ),
    );
  }

  late final AnimationController _scanLineController;
  late final AnimationController _scanSuccessController;
  late final AnimationController _pageIntroController;

  Future<void> _captureLocation() async {
    if (_capturingLocation) return;
    setState(() => _capturingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
            'Turn on device location to attach an audit location.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError(
            'Location permission was denied. You can continue without it.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
            'Location permission is disabled for Unify. Enable it in device settings or continue without location.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationBranchId = _selectedCatalogItem?.branchId;
      });
      final verification = _locationVerification;
      showAppNotification(
        verification == null
            ? 'GPS coordinates attached. This branch has no configured location, so proximity cannot be verified.'
            : verification.distanceMeters <= _branchVerificationRadiusMeters
                ? 'Branch verified · ${verification.distanceMeters.round()} m from ${_selectedCatalogItem?.branch ?? 'the branch'}.'
                : 'You are ${verification.distanceMeters.round()} m from the configured branch. Move within ${_branchVerificationRadiusMeters.round()} m or remove GPS to record an unverified manual count.',
        tone: verification == null
            ? AppNotificationTone.warning
            : verification.distanceMeters <= _branchVerificationRadiusMeters
                ? AppNotificationTone.success
                : AppNotificationTone.error,
      );
    } on StateError catch (error) {
      if (mounted) {
        showAppNotification(error.message, tone: AppNotificationTone.warning);
      }
    } catch (error) {
      if (mounted) {
        showAppNotification(
          'Could not capture the device location: $error',
          tone: AppNotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _scanSuccessController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: 0.94,
      upperBound: 1,
    );
    _pageIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    try {
      _connectionChanges =
          _connectivity.onConnectivityChanged.listen((results) {
        final online =
            results.any((result) => result != ConnectivityResult.none);
        if (!mounted) return;
        final connectionRestored = online && !_isOnline;
        final connectionLost = !online && _isOnline;
        setState(() => _isOnline = online);
        if (connectionRestored) {
          showAppNotification(
            'Connection restored. Syncing saved physical counts.',
            tone: AppNotificationTone.info,
          );
          _sync(announceEmpty: false);
        } else if (connectionLost) {
          showAppNotification(
            'You are offline. New physical counts will stay safely queued on this device.',
            tone: AppNotificationTone.warning,
          );
        }
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
    _scanSuccessController.dispose();
    _pageIntroController.dispose();
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
    final savedBranches = await _store.loadBranchLocations();
    if (mounted) setState(() => _branchLocations = savedBranches);
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
      if (!await _store.save(catalog, _pending)) return false;
      if (mounted) setState(() => _catalog = catalog);
      await _refreshBranchLocations();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshBranchLocations() async {
    try {
      final response = await widget.client.get('/api/inventory/branches');
      if (response.statusCode != 200) return;
      final payload = jsonDecode(response.body);
      if (payload is! List) return;
      final locations = <String, _BranchLocation>{};
      for (final row in payload.whereType<Map<String, dynamic>>()) {
        final location = _BranchLocation.fromJson(row);
        locations[location.id] = location;
      }
      await _store.saveBranchLocations(locations);
      if (mounted) setState(() => _branchLocations = locations);
    } catch (_) {
      // Keep the last known branch locations for offline verification.
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
        if (!mounted) return;
        showAppNotification(
          response.statusCode == 403
              ? 'You cannot review this count. It must be reviewed by a different Admin or Manager with access to this branch.'
              : _error(response.body) ??
                  'The stock count could not be reviewed (server ${response.statusCode}).',
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

  Future<void> _sync({bool silent = false, bool announceEmpty = true}) async {
    if (!mounted || _syncing) return;
    final queued = _pending.where((count) => !count.requiresReview).toList();
    if (queued.isEmpty) {
      if (!silent && (announceEmpty || _pending.isNotEmpty)) {
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
        final matches = _catalog.where((item) {
          if (count.inventoryItemId != null) {
            return item.id == count.inventoryItemId;
          }
          if (item.sku.toLowerCase() != count.sku.toLowerCase()) return false;
          return count.branchId == null || item.branchId == count.branchId;
        }).toList();
        if (matches.isEmpty) {
          remaining.add(count.withError(
            'Item is no longer in catalog. Verify it and take a new count.',
            requiresReview: true,
          ));
          continue;
        }
        if (matches.length > 1) {
          remaining.add(count.withError(
            'This saved count matches the same SKU in multiple branches. Review it and take a new branch-specific count.',
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
            'latitude': count.latitude,
            'longitude': count.longitude,
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
      final persisted = await _store.save(_catalog, pendingAfterSync);
      if (mounted) setState(() => _pending = pendingAfterSync);
      if (!persisted && mounted) {
        showAppNotification(
          'Counts synced, but the offline queue could not be updated on this device. Keep this screen open and try again before closing the app.',
          tone: AppNotificationTone.error,
        );
      }
      await _loadApprovalQueue();

      if (!silent && mounted && persisted) {
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

  void _clearItemDraft() {
    _quantity.clear();
    _reason = null;
    _reasonNotes.clear();
    _selectedPhotos = [];
    _latitude = null;
    _longitude = null;
    _locationBranchId = null;
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (code == null || code.isEmpty || code == _scannedCode) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _clearItemDraft();
      _scannedCode = code;
      _scanSucceeded = true;
      _sku.text = code;
      _selectedCatalogItemId = null;
    });
    _scanSuccessController.repeat(reverse: true);
    showAppNotification(
      'Code captured. Check the matching item and enter its physical quantity.',
      tone: AppNotificationTone.success,
    );
    _scanner.stop();
  }

  Future<void> _scanAgain() async {
    try {
      setState(() {
        _scannedCode = null;
        _scanSucceeded = false;
      });
      _scanSuccessController.stop();
      _scanSuccessController.value = 0;
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
    if (code.isEmpty ||
        quantity == null ||
        !quantity.isFinite ||
        quantity < 0) {
      showAppNotification(
          'Scan or enter SKU and specify a quantity of zero or more.',
          tone: AppNotificationTone.warning);
      return;
    }
    final matches = _catalog
        .where((item) => item.sku.toLowerCase() == code.toLowerCase())
        .toList();
    if (matches.isEmpty) {
      showAppNotification(
          'SKU "$code" is not in the cached catalog. Pull to refresh while online.',
          tone: AppNotificationTone.error);
      return;
    }
    final item = _selectedCatalogItem;
    if (item == null) {
      showAppNotification(
        'Choose the correct branch for SKU "$code" before saving this count.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
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

    final branchLocation =
        item.branchId == null ? null : _branchLocations[item.branchId!];
    final verification = _locationVerification;
    if (branchLocation?.isConfigured == true &&
        verification != null &&
        verification.distanceMeters > _branchVerificationRadiusMeters) {
      showAppNotification(
        'Branch verification failed. You are ${verification.distanceMeters.round()} m away; move within ${_branchVerificationRadiusMeters.round()} m or remove GPS to record this as an unverified manual count.',
        tone: AppNotificationTone.error,
      );
      return;
    }
    if (branchLocation?.isConfigured == true &&
        _latitude != null &&
        verification == null) {
      showAppNotification(
        'GPS belongs to another item or branch. Remove it and capture location again.',
        tone: AppNotificationTone.error,
      );
      return;
    }
    if (branchLocation?.isConfigured == true && _latitude == null) {
      final proceedUnverified = await showAppConfirmation(
        context: context,
        title: 'Continue without GPS verification?',
        message:
            'This branch has a configured location, but this count has no GPS proof. Continue as an explicitly unverified manual count?',
        confirmLabel: 'Continue unverified',
        icon: Icons.location_searching_rounded,
        accent: AppColors.warning,
      );
      if (!proceedUnverified || !mounted) return;
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
        inventoryItemId: item.id,
        sku: item.sku,
        name: item.name,
        branchId: item.branchId,
        branch: item.branch,
        quantity: quantity,
        systemQuantityAtCount: item.quantity,
        recordedAt: DateTime.now().toUtc(),
        reason: reason,
        reasonNotes: variance == 0 || _reasonNotes.text.trim().isEmpty
            ? null
            : _reasonNotes.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        evidence: await _readSelectedEvidence(),
      );
      final pending = [
        ..._pending.where((count) {
          if (count.inventoryItemId != null) {
            return count.inventoryItemId != item.id;
          }
          if (count.sku.toLowerCase() != item.sku.toLowerCase()) return true;
          if (count.branchId != null) return count.branchId != item.branchId;
          return matches.length > 1;
        }),
        entry,
      ];
      if (!await _store.save(_catalog, pending)) {
        throw StateError(
          'The count could not be saved on this device. Free some storage and try again.',
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _pending = pending;
        _sku.clear();
        _selectedCatalogItemId = null;
        _quantity.clear();
        _scannedCode = null;
        _reason = null;
        _reasonNotes.clear();
        _selectedPhotos = [];
        _latitude = null;
        _longitude = null;
        _locationBranchId = null;
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

  List<_CatalogItem> get _matchingCatalogItems {
    final code = _sku.text.trim().toLowerCase();
    if (code.isEmpty) return const [];
    return _catalog.where((item) => item.sku.toLowerCase() == code).toList();
  }

  _CatalogItem? get _selectedCatalogItem {
    final matches = _matchingCatalogItems;
    if (_selectedCatalogItemId != null) {
      return matches
          .where((item) => item.id == _selectedCatalogItemId)
          .firstOrNull;
    }
    return matches.length == 1 ? matches.single : null;
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
    return InventoryScaffold(
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: _loading
              ? const InventoryLoadingState(
                  key: ValueKey('stock-count-loading'),
                  message: 'Preparing stock count',
                  detail: 'Loading your inventory for an offline audit',
                )
              : RefreshIndicator(
                  key: const ValueKey('stock-count-content'),
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
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Column(
                      children: [
                        _entrance(0, _buildAuditHero()),
                        const SizedBox(height: 14),

                        // Offline / Online Status Header
                        _entrance(1, _buildStatusBanner()),
                        const SizedBox(height: 18),

                        // Metrics Strip
                        _entrance(
                            2,
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
                            )),
                        const SizedBox(height: 20),

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
                          const SizedBox(height: 18),
                        ],

                        // Scanner Viewport
                        _entrance(3, _buildScannerBox()),
                        const SizedBox(height: 18),

                        // Quick Catalog Chips
                        _entrance(
                            4,
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
                                                  .copyWith(
                                                      color: AppColors.cyan)),
                                        ),
                                        _buildCatalogChipCarousel(),
                                        const SizedBox(height: 18),
                                      ],
                                    ),
                            )),

                        // Physical Count Form
                        _entrance(5, _buildCountInputCard()),
                        const SizedBox(height: 22),

                        // Pending Queue List
                        AnimatedSize(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, .04),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: _pending.isEmpty
                                ? const SizedBox.shrink(
                                    key: ValueKey('stock-count-queue-empty'),
                                  )
                                : Column(
                                    key: ValueKey(_pending
                                        .map((count) => count.id)
                                        .join('|')),
                                    children: [
                                      SectionHeader(
                                        'SAVED AUDIT QUEUE',
                                        trailing: Text(
                                            '${_pending.length} unsynced',
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                    color: const Color(
                                                        0xFFF59E0B))),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._pending.map(_buildPendingCard),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _entrance(int index, Widget child) {
    final start = (index * .08).clamp(0.0, .55);
    final animation = CurvedAnimation(
      parent: _pageIntroController,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, .08 + (index * .008)),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildAuditHero() {
    final completedSteps = <bool>[
      _selectedCatalogItem != null,
      double.tryParse(_quantity.text.trim()) != null,
      _pending.isNotEmpty || _selectedPhotos.isNotEmpty,
    ].where((complete) => complete).length;
    final progress = completedSteps / 3;

    return AnimatedBuilder(
      animation: _scanLineController,
      builder: (context, child) {
        final glow = .12 + (_scanLineController.value * .08);
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF102B43), Color(0xFF111B31)],
            ),
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: .32),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: glow),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF4F7CFF)],
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: .3),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PHYSICAL INVENTORY',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Count with confidence',
                      style: AppTextStyles.title.copyWith(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan, verify and reconcile stock—even when offline.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_isOnline ? AppColors.success : AppColors.warning)
                      .withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isOnline ? 'LIVE' : 'OFFLINE',
                  style: AppTextStyles.label.copyWith(
                    color: _isOnline ? AppColors.success : AppColors.warning,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  completedSteps == 0
                      ? 'Start by scanning or selecting an item'
                      : '$completedSteps of 3 audit steps ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(progress * 100).round()}%',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
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
                            ? _syncing
                                ? AppColors.cyan
                                : const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _isOnline
                              ? _syncing
                                  ? 'SYNCING SAVED COUNTS'
                                  : 'ONLINE & SYNC READY'
                              : 'OFFLINE MODE ACTIVE',
                          key: ValueKey(_isOnline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label.copyWith(
                            color: _isOnline
                                ? _syncing
                                    ? AppColors.cyan
                                    : const Color(0xFF10B981)
                                : const Color(0xFFFBBF24),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _pending.isEmpty
                      ? 'All counts uploaded to server.'
                      : '${_pending.length} counts queued · auto-sync while this screen is open; review any marked RECOUNT REQUIRED.',
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
                child: AnimatedContainer(
                  key: const Key('stock-count-scan-frame'),
                  duration: const Duration(milliseconds: 260),
                  width: 180,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: !_scanSucceeded
                          ? AppColors.cyan.withValues(alpha: 0.6)
                          : AppColors.success,
                      width: _scanSucceeded ? 2.5 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (!_scanSucceeded
                                ? AppColors.cyan
                                : AppColors.success)
                            .withValues(alpha: _scanSucceeded ? 0.5 : 0.2),
                        blurRadius: _scanSucceeded ? 28 : 16,
                        spreadRadius: _scanSucceeded ? 2 : 0,
                      ),
                    ],
                  ),
                  child: !_scanSucceeded
                      ? null
                      : const Center(
                          child: Icon(
                            Icons.check_circle_rounded,
                            key: Key('stock-count-scan-success-icon'),
                            color: AppColors.success,
                            size: 52,
                          ),
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
              bottom: _scanSucceeded ? 12 : -58,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .35),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: !_scanSucceeded
                    ? const SizedBox(
                        key: ValueKey('scan-ready'),
                        height: 36,
                        child: Center(
                          child: Text(
                            'Align a QR code or barcode inside the frame',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      )
                    : AnimatedBuilder(
                        key: ValueKey('scan-success-$_scannedCode'),
                        animation: _scanSuccessController,
                        builder: (context, child) => Transform.scale(
                          scale: _scanSuccessController.value,
                          child: child,
                        ),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          decoration: BoxDecoration(
                            color: const Color(0xF011292C),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.85),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.success.withValues(alpha: 0.28),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                key:
                                    Key('stock-count-scan-success-banner-icon'),
                                color: AppColors.success,
                                size: 25,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'CODE CAPTURED',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      _scannedCode!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                key: const Key('stock-count-scan-again'),
                                onPressed: _scanAgain,
                                icon: const Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 17,
                                ),
                                label: const Text('Scan again'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
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
          final isSelected = _selectedCatalogItem?.id == item.id;

          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _clearItemDraft();
                _sku.text = item.sku;
                _scannedCode = item.sku;
                _scanSucceeded = false;
                _selectedCatalogItemId = item.id;
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
                    '${item.name} (${item.sku}) · ${item.branch}',
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
            key: const Key('stock-count-sku-field'),
            controller: _sku,
            style: AppTextStyles.body
                .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            onChanged: (val) {
              setState(() {
                _clearItemDraft();
                _scannedCode = val.isEmpty ? null : val;
                _scanSucceeded = false;
                _selectedCatalogItemId = null;
              });
            },
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
          if (_matchingCatalogItems.length > 1) ...[
            DropdownButtonFormField<String>(
              key: const Key('stock-count-branch-selector'),
              isExpanded: true,
              initialValue: _matchingCatalogItems
                      .any((item) => item.id == _selectedCatalogItemId)
                  ? _selectedCatalogItemId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Choose branch for this SKU *',
                filled: true,
              ),
              items: _matchingCatalogItems
                  .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.branch} · ${_formatAuditQuantity(item.quantity)} ${item.unit}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              selectedItemBuilder: (context) => _matchingCatalogItems
                  .map((item) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${item.branch} · ${_formatAuditQuantity(item.quantity)} ${item.unit}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == _selectedCatalogItemId) return;
                setState(() {
                  _clearItemDraft();
                  _selectedCatalogItemId = value;
                });
              },
            ),
            const SizedBox(height: 14),
          ],

          // Quantity input
          TextField(
            key: const Key('stock-count-quantity-field'),
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
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .035),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: matchedItem != null
                  ? Column(
                      key: ValueKey('count-preview-${matchedItem.sku}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                      style: AppTextStyles.subtitle
                                          .copyWith(fontSize: 13),
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
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('count-preview-empty'),
                    ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: matchedItem != null && hasVariance && variance != 0
                  ? Column(
                      key: ValueKey('count-reason-${matchedItem.sku}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _reason,
                          decoration: const InputDecoration(
                            labelText: 'Reason for discrepancy *',
                            filled: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'DamagedStock',
                                child: Text('Damaged stock')),
                            DropdownMenuItem(
                                value: 'LostOrMissing',
                                child: Text('Lost / missing')),
                            DropdownMenuItem(
                                value: 'CountingError',
                                child: Text('Counting error')),
                            DropdownMenuItem(
                                value: 'SupplierShortage',
                                child: Text('Supplier shortage')),
                            DropdownMenuItem(
                                value: 'Other', child: Text('Other')),
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
                            children:
                                List.generate(_selectedPhotos.length, (index) {
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
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.warning),
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('count-no-discrepancy'),
                    ),
            ),
          ),

          if (matchedItem != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('stock-count-capture-location'),
              onPressed: _capturingLocation ? null : _captureLocation,
              icon: _capturingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cyan,
                      ),
                    )
                  : Icon(
                      _latitude == null
                          ? Icons.my_location_rounded
                          : Icons.location_on_rounded,
                    ),
              label: Text(
                _capturingLocation
                    ? 'Getting location…'
                    : _latitude == null
                        ? matchedItem.branchId != null &&
                                _branchLocations[matchedItem.branchId!]
                                        ?.isConfigured ==
                                    true
                            ? 'Verify branch location with GPS'
                            : 'Add GPS location to this count (optional)'
                        : 'Location attached · ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cyan,
                alignment: Alignment.centerLeft,
              ),
            ),
            Container(
              key: const Key('stock-count-location-explanation'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.cyan,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationExplanation(matchedItem),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_latitude != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('stock-count-clear-location'),
                  onPressed: () => setState(() {
                    _latitude = null;
                    _longitude = null;
                    _locationBranchId = null;
                  }),
                  child: const Text('Remove location'),
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

  String _locationExplanation(_CatalogItem item) {
    final branch =
        item.branchId == null ? null : _branchLocations[item.branchId!];
    if (branch?.isConfigured != true) {
      return 'Branch GPS is not configured, so proximity verification is unavailable. GPS tagging remains optional and never tracks you continuously.';
    }
    if (_latitude == null) {
      return 'Capture GPS to verify within ${_branchVerificationRadiusMeters.round()} m of ${item.branch}. You can still submit without GPS, but must confirm it as unverified.';
    }
    final verification = _locationVerification;
    if (verification == null) {
      return 'GPS coordinates are attached, but branch proximity could not be verified. This branch location may have changed; refresh the catalog.';
    }
    if (verification.distanceMeters <= _branchVerificationRadiusMeters) {
      return 'Branch verified · ${verification.distanceMeters.round()} m from ${item.branch}. Coordinates are attached to the audit; no continuous tracking.';
    }
    return 'Outside the ${_branchVerificationRadiusMeters.round()} m verification area · ${verification.distanceMeters.round()} m from ${item.branch}. Remove GPS to continue as an unverified manual count.';
  }

  Widget _buildApprovalCard(Map<String, dynamic> count) {
    final variance = (count['variance'] as num?)?.toDouble() ?? 0;
    final canReview = _canApproveCounts && count['canReview'] == true;
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
            if (count['latitude'] is num && count['longitude'] is num)
              Text(
                'Location · ${(count['latitude'] as num).toStringAsFixed(5)}, ${(count['longitude'] as num).toStringAsFixed(5)}',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted),
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
            if (canReview)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: Key('stock-count-approval-reject-${count['id']}'),
                      onPressed: () => _reviewCount(count, 'Reject'),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: Key('stock-count-approval-approve-${count['id']}'),
                      onPressed: () => _reviewCount(count, 'Approve'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Approve'),
                    ),
                  ),
                ],
              )
            else
              Text(
                _canApproveCounts
                    ? 'This count must be reviewed by a different Admin or Manager with access to this branch.'
                    : 'Waiting for an Admin or Manager to review this adjustment.',
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
                  if (entry.latitude != null && entry.longitude != null)
                    Text(
                      'Location · ${entry.latitude!.toStringAsFixed(5)}, ${entry.longitude!.toStringAsFixed(5)}',
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
                final saved = await _store.save(_catalog, pending);
                if (!saved) {
                  if (mounted) {
                    showAppNotification(
                      'The saved count could not be removed from device storage.',
                      tone: AppNotificationTone.error,
                    );
                  }
                  return;
                }
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
  static const _branchesKey = 'stock_count_branch_locations_v1';

  Future<({List<_CatalogItem> catalog, List<_PendingCount> pending})>
      load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final catRaw = prefs.getString(_catalogKey);
      final penRaw = prefs.getString(_pendingKey);

      final catalog = <_CatalogItem>[];
      final catalogRows = catRaw == null ? null : jsonDecode(catRaw);
      if (catalogRows is List) {
        for (final row in catalogRows.whereType<Map<String, dynamic>>()) {
          try {
            catalog.add(_CatalogItem.fromJson(row));
          } catch (_) {
            // Preserve every valid cached row when one entry is malformed.
          }
        }
      }

      final pending = <_PendingCount>[];
      final pendingRows = penRaw == null ? null : jsonDecode(penRaw);
      if (pendingRows is List) {
        for (final row in pendingRows.whereType<Map<String, dynamic>>()) {
          try {
            pending.add(_PendingCount.fromJson(row));
          } catch (_) {
            // Preserve every recoverable offline count.
          }
        }
      }

      return (catalog: catalog, pending: pending);
    } catch (_) {
      return (catalog: <_CatalogItem>[], pending: <_PendingCount>[]);
    }
  }

  Future<bool> save(
      List<_CatalogItem> catalog, List<_PendingCount> pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingSaved = await prefs.setString(
          _pendingKey, jsonEncode(pending.map((p) => p.toJson()).toList()));
      final catalogSaved = await prefs.setString(
          _catalogKey, jsonEncode(catalog.map((i) => i.toJson()).toList()));
      return catalogSaved && pendingSaved;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, _BranchLocation>> loadBranchLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_branchesKey);
      if (raw == null) return {};
      final rows = jsonDecode(raw);
      if (rows is! List) return {};
      final locations = <String, _BranchLocation>{};
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final branch = _BranchLocation.fromJson(row);
        locations[branch.id] = branch;
      }
      return locations;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBranchLocations(
    Map<String, _BranchLocation> locations,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _branchesKey,
        jsonEncode(locations.values.map((branch) => branch.toJson()).toList()),
      );
    } catch (_) {}
  }
}

class _BranchLocation {
  const _BranchLocation({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });

  final String id, name;
  final double? latitude, longitude;

  bool get isConfigured => latitude != null && longitude != null;

  factory _BranchLocation.fromJson(Map<String, dynamic> json) =>
      _BranchLocation(
        id: '${json['id']}',
        name: '${json['name'] ?? 'Branch'}',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
      };
}

class _CatalogItem {
  const _CatalogItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.quantity,
    this.branchId,
    this.branch = 'Main branch',
    this.unit = 'units',
  });

  final String id, sku, name, unit;
  final double quantity;
  final String? branchId;
  final String branch;

  factory _CatalogItem.fromJson(Map<String, dynamic> json) => _CatalogItem(
        id: '${json['id']}',
        sku: '${json['sku'] ?? ''}',
        name: '${json['name'] ?? ''}',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        branchId: json['branchId'] as String?,
        branch: json['branch'] as String? ?? 'Main branch',
        unit: '${json['unit'] ?? json['unitName'] ?? 'units'}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'quantity': quantity,
        'branchId': branchId,
        'branch': branch,
        'unit': unit,
      };
}

class _PendingCount {
  const _PendingCount({
    required this.id,
    this.inventoryItemId,
    required this.sku,
    required this.name,
    this.branchId,
    this.branch,
    required this.quantity,
    required this.systemQuantityAtCount,
    required this.recordedAt,
    required this.reason,
    required this.evidence,
    this.latitude,
    this.longitude,
    this.lastError,
    this.requiresReview = false,
    this.reasonNotes,
    this.changedActivity = const [],
  });

  final String id, sku, name;
  final String? inventoryItemId, branchId, branch;
  final double quantity;
  final double? systemQuantityAtCount;
  final DateTime recordedAt;
  final String reason;
  final String? reasonNotes;
  final double? latitude, longitude;
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
        inventoryItemId: inventoryItemId,
        sku: sku,
        name: name,
        branchId: branchId,
        branch: branch,
        quantity: quantity,
        systemQuantityAtCount: systemQuantityAtCount,
        recordedAt: recordedAt,
        reason: reason,
        reasonNotes: reasonNotes,
        latitude: latitude,
        longitude: longitude,
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
      inventoryItemId: json['inventoryItemId'] as String?,
      sku: '${json['sku']}',
      name: '${json['name']}',
      branchId: json['branchId'] as String?,
      branch: json['branch'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      systemQuantityAtCount: systemQuantity,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      reason: json['reason'] as String? ?? 'Other',
      reasonNotes: json['reasonNotes'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
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
        'inventoryItemId': inventoryItemId,
        'sku': sku,
        'name': name,
        'branchId': branchId,
        'branch': branch,
        'quantity': quantity,
        'systemQuantityAtCount': systemQuantityAtCount,
        'recordedAt': recordedAt.toIso8601String(),
        'reason': reason,
        'reasonNotes': reasonNotes,
        'latitude': latitude,
        'longitude': longitude,
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
