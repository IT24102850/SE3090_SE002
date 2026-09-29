import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';
import 'notification_ws.dart';

/// Normalized purchase order statuses matching backend workflow.
enum PurchaseOrderStatus {
  draft,
  inReview,
  placed,
  inTransit,
  partiallyReceived,
  received,
  cancelled;

  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Draft';
      case PurchaseOrderStatus.inReview:
        return 'In Review';
      case PurchaseOrderStatus.placed:
        return 'Placed';
      case PurchaseOrderStatus.inTransit:
        return 'In Transit';
      case PurchaseOrderStatus.partiallyReceived:
        return 'Partially Received';
      case PurchaseOrderStatus.received:
        return 'Received';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get apiValue {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Draft';
      case PurchaseOrderStatus.inReview:
        return 'InReview';
      case PurchaseOrderStatus.placed:
        return 'Placed';
      case PurchaseOrderStatus.inTransit:
        return 'InTransit';
      case PurchaseOrderStatus.partiallyReceived:
        return 'PartiallyReceived';
      case PurchaseOrderStatus.received:
        return 'Received';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return AppColors.cyan;
      case PurchaseOrderStatus.inReview:
        return const Color(0xFFFBBF24); // Amber
      case PurchaseOrderStatus.placed:
        return const Color(0xFFA78BFA); // Violet
      case PurchaseOrderStatus.inTransit:
        return const Color(0xFF38BDF8); // Sky blue
      case PurchaseOrderStatus.partiallyReceived:
        return const Color(0xFFFBBF24);
      case PurchaseOrderStatus.received:
        return const Color(0xFF10B981); // Emerald
      case PurchaseOrderStatus.cancelled:
        return const Color(0xFFF43F5E); // Rose
    }
  }

  IconData get icon {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return Icons.edit_note_rounded;
      case PurchaseOrderStatus.inReview:
        return Icons.rate_review_rounded;
      case PurchaseOrderStatus.placed:
        return Icons.verified_rounded;
      case PurchaseOrderStatus.inTransit:
        return Icons.local_shipping_rounded;
      case PurchaseOrderStatus.partiallyReceived:
        return Icons.inventory_rounded;
      case PurchaseOrderStatus.received:
        return Icons.check_circle_rounded;
      case PurchaseOrderStatus.cancelled:
        return Icons.cancel_rounded;
    }
  }

  static PurchaseOrderStatus parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return PurchaseOrderStatus.draft;
    final clean = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    switch (clean) {
      case 'draft':
        return PurchaseOrderStatus.draft;
      case 'inreview':
      case 'review':
      case 'pending':
        return PurchaseOrderStatus.inReview;
      case 'placed':
      case 'approved':
      case 'authorized':
        return PurchaseOrderStatus.placed;
      case 'intransit':
      case 'transit':
      case 'shipped':
      case 'dispatched':
        return PurchaseOrderStatus.inTransit;
      case 'partiallyreceived':
      case 'partial':
        return PurchaseOrderStatus.partiallyReceived;
      case 'received':
      case 'fulfilled':
      case 'completed':
        return PurchaseOrderStatus.received;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return PurchaseOrderStatus.cancelled;
      default:
        return PurchaseOrderStatus.draft;
    }
  }

  bool get isTerminal =>
      this == PurchaseOrderStatus.received ||
      this == PurchaseOrderStatus.cancelled;
  bool get isOpen => !isTerminal;
  bool get needsApproval =>
      this == PurchaseOrderStatus.draft || this == PurchaseOrderStatus.inReview;
  bool get inFulfillment =>
      this == PurchaseOrderStatus.placed ||
      this == PurchaseOrderStatus.inTransit ||
      this == PurchaseOrderStatus.partiallyReceived;

  int get stepIndex {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 0;
      case PurchaseOrderStatus.inReview:
        return 1;
      case PurchaseOrderStatus.placed:
        return 2;
      case PurchaseOrderStatus.inTransit:
        return 3;
      case PurchaseOrderStatus.partiallyReceived:
        return 3;
      case PurchaseOrderStatus.received:
        return 4;
      case PurchaseOrderStatus.cancelled:
        return -1;
    }
  }
}

class PurchaseOrderApprovalScreen extends StatefulWidget {
  const PurchaseOrderApprovalScreen({
    super.key,
    required this.client,
    required this.canApprove,
    bool? canReceive,
  }) : canReceive = canReceive ?? canApprove;

  final AuthenticatedApiClient client;
  final bool canApprove;
  final bool canReceive;

  @override
  State<PurchaseOrderApprovalScreen> createState() =>
      _PurchaseOrderApprovalScreenState();
}

class _PurchaseOrderApprovalScreenState
    extends State<PurchaseOrderApprovalScreen> {
  List<_PurchaseOrder> _allOrders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _notifSub;

  String _selectedFilter =
      'all'; // 'all', 'needs_action', 'fulfillment', 'history'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService().connect();
    try {
      _notifSub = NotificationService().stream.listen((event) {
        try {
          if (event['type'] == 'workflow_update') {
            final action = event['actionType'] as String? ?? '';
            if (action == 'generate_purchase_order' &&
                (event['backend_result'] != null ||
                    event['status'] == 'approved')) {
              if (mounted) {
                showAppNotification(
                  'Agent submitted or updated a purchase order.',
                  tone: AppNotificationTone.info,
                );
                _load();
              }
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSuccess = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orderData = <Map<String, dynamic>>[];
      var page = 1;
      var totalPages = 1;
      do {
        final response = await widget.client
            .get('/api/purchase-orders?page=$page&pageSize=100');
        if (response.statusCode != 200) {
          throw StateError(_apiError(response.body, response.statusCode));
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        orderData.addAll(
          ((data['items'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>(),
        );
        if (page == 1) {
          totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
        }
        page++;
      } while (page <= totalPages);

      final seen = <String>{};
      final orders = orderData
          .map(_PurchaseOrder.fromJson)
          .where((order) => seen.add(order.id))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;
      setState(() {
        _allOrders = orders;
      });
      if (showSuccess) {
        showAppNotification(
          'Purchase orders refreshed (${orders.length} loaded).',
          tone: AppNotificationTone.success,
          title: 'Queue Updated',
        );
      }
    } on StateError catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail(
        'Cannot reach the Purchase Orders API. Please check your network or server connection.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _apiError(String body, int statusCode) {
    if (statusCode == 403) {
      return 'Access denied. Your role or branch permissions do not allow this purchase order action.';
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return 'Purchase orders API returned HTTP $statusCode.';
    }
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      final title = decoded['title'];
      final errors = decoded['errors'];
      final validationMessages = errors is Map
          ? errors.values
              .whereType<List>()
              .expand((messages) => messages)
              .whereType<String>()
              .where((text) => text.trim().isNotEmpty)
              .toList()
          : const <String>[];
      final parts = <String>[
        if (message is String && message.trim().isNotEmpty) message,
        if (validationMessages.isNotEmpty) validationMessages.join(' '),
        if (title is String &&
            title.trim().isNotEmpty &&
            title != message &&
            validationMessages.isEmpty)
          title,
      ];
      if (parts.isNotEmpty) return parts.join(' ');
    }
    return 'Purchase orders API returned HTTP $statusCode.';
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _allOrders = const [];
    });
    showAppNotification(message, tone: AppNotificationTone.error);
  }

  Future<void> _advanceOrderStatus(
    _PurchaseOrder order,
    PurchaseOrderStatus targetStatus, {
    String? confirmTitle,
    String? confirmMessage,
    String? confirmLabel,
    IconData? confirmIcon,
    Color? confirmAccent,
  }) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: confirmTitle ?? 'Update Purchase Order?',
      message: confirmMessage ??
          'Move order ${order.number} to status "${targetStatus.label}"?',
      confirmLabel: confirmLabel ?? 'Confirm',
      icon: confirmIcon ?? targetStatus.icon,
      accent: confirmAccent ?? targetStatus.color,
    );
    if (!confirmed || !mounted || order.approving) return;

    setState(() => order.approving = true);
    try {
      final response = await widget.client.put(
        '/api/purchase-orders/${order.id}/status',
        body: {'status': targetStatus.apiValue},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_apiError(response.body, response.statusCode));
      }
      if (!mounted) return;
      setState(() {
        order.status = targetStatus;
        order.updatedAt = DateTime.now().toUtc().toIso8601String();
        order.approving = false;
        _allOrders = [..._allOrders]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      });
      showAppNotification(
        '${order.number} successfully moved to ${targetStatus.label}.',
        tone: AppNotificationTone.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() => order.approving = false);
        showAppNotification(
          'Status update failed. ${error is StateError ? error.message : 'Please retry.'}',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  Future<void> _cancelOrder(_PurchaseOrder order) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Cancel Purchase Order?',
      message:
          'Are you sure you want to cancel order ${order.number}? This will abort procurement.',
      confirmLabel: 'Cancel Order',
      icon: Icons.cancel_outlined,
      accent: const Color(0xFFF43F5E),
      isDestructive: true,
    );
    if (!confirmed || !mounted || order.approving) return;

    setState(() => order.approving = true);
    try {
      final response = await widget.client.put(
        '/api/purchase-orders/${order.id}/status',
        body: {'status': PurchaseOrderStatus.cancelled.apiValue},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_apiError(response.body, response.statusCode));
      }
      if (!mounted) return;
      setState(() {
        order.status = PurchaseOrderStatus.cancelled;
        order.updatedAt = DateTime.now().toUtc().toIso8601String();
        order.approving = false;
      });
      showAppNotification(
        '${order.number} has been cancelled.',
        tone: AppNotificationTone.warning,
      );
    } catch (error) {
      if (mounted) {
        setState(() => order.approving = false);
        showAppNotification(
          'Could not cancel order. ${error is StateError ? error.message : 'Please retry.'}',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  // Getters for counts & filtered views
  List<_PurchaseOrder> get _openOrders =>
      _allOrders.where((o) => o.status.isOpen).toList();

  int get _needsActionCount =>
      _allOrders.where((o) => o.status.needsApproval).length;

  int get _inFulfillmentCount =>
      _allOrders.where((o) => o.status.inFulfillment).length;

  int get _completedCount =>
      _allOrders.where((o) => o.status.isTerminal).length;

  List<_PurchaseOrder> get _filteredOrders {
    List<_PurchaseOrder> base;
    switch (_selectedFilter) {
      case 'needs_action':
        base = _allOrders.where((o) => o.status.needsApproval).toList();
        break;
      case 'fulfillment':
        base = _allOrders.where((o) => o.status.inFulfillment).toList();
        break;
      case 'history':
        base = _allOrders.where((o) => o.status.isTerminal).toList();
        break;
      default:
        base = _openOrders;
        break;
    }

    if (_searchQuery.trim().isEmpty) return base;

    final q = _searchQuery.trim().toLowerCase();
    return base.where((o) {
      final numberMatch = o.number.toLowerCase().contains(q);
      final supplierMatch = (o.supplier ?? '').toLowerCase().contains(q);
      final branchMatch = (o.branch ?? '').toLowerCase().contains(q);
      final statusMatch = o.status.label.toLowerCase().contains(q);
      final itemMatch = o.items.any((i) => i.name.toLowerCase().contains(q));
      return numberMatch ||
          supplierMatch ||
          branchMatch ||
          statusMatch ||
          itemMatch;
    }).toList();
  }

  void _showCreateOrderModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateOrderBottomSheet(
        client: widget.client,
        onCreated: () => _load(showSuccess: true),
      ),
    );
  }

  Future<void> _receiveOrder(_PurchaseOrder order) async {
    if (!widget.canReceive || order.approving) return;
    var inventoryItems = <Map<String, dynamic>>[];
    if (order.items
        .any((item) => !item.receivingClosed && item.inventoryItemId == null)) {
      try {
        final response =
            await widget.client.get('/api/purchase-orders/options');
        if (response.statusCode != 200) {
          throw StateError(_apiError(response.body, response.statusCode));
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        inventoryItems = ((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (error) {
        if (!mounted) return;
        showAppNotification(
          'Could not load destination-branch inventory items. ${error is StateError ? error.message : 'Please retry.'}',
          tone: AppNotificationTone.error,
        );
        return;
      }
    }
    if (!mounted) return;
    final submission = await showModalBottomSheet<_ReceiptSubmission>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReceivePurchaseOrderSheet(
        order: order,
        inventoryItems: inventoryItems,
      ),
    );
    if (submission == null || submission.items.isEmpty || !mounted) return;

    setState(() => order.approving = true);
    var receiptSaved = false;
    try {
      final response = await widget.client.post(
        '/api/purchase-orders/${order.id}/receive',
        body: {'items': submission.items},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_apiError(response.body, response.statusCode));
      }
      receiptSaved = true;
      if (submission.photos.isNotEmpty) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final receipts = (payload['receipts'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        final receiptId = receipts.isEmpty ? null : '${receipts.first['id']}';
        if (receiptId == null || receiptId.isEmpty) {
          throw StateError(
            'The receipt was saved, but the API did not return its receipt ID. Refresh the order and retry adding photos.',
          );
        }
        for (final photo in submission.photos) {
          final upload = await widget.client.uploadPurchaseReceiptPhoto(
            order.id,
            receiptId,
            await photo.readAsBytes(),
            photo.name,
          );
          if (upload.statusCode < 200 || upload.statusCode >= 300) {
            throw StateError(_apiError(upload.body, upload.statusCode));
          }
        }
      }
      await _load();
      if (!mounted) return;
      showAppNotification(
        '${order.number} receipt saved. Accepted units were added to inventory${submission.photos.isEmpty ? '' : ' and ${submission.photos.length} photos attached'}.',
        tone: AppNotificationTone.success,
      );
    } catch (error) {
      if (mounted) {
        showAppNotification(
          '${receiptSaved ? 'Receipt saved, but photo evidence could not be attached.' : 'Could not record receipt.'} ${error is StateError ? error.message : 'Please retry.'}',
          tone: AppNotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => order.approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: false,
      floatingActionButton: widget.canApprove
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.cyan,
              foregroundColor: const Color(0xFF0A111E),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('New PO',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              onPressed: _showCreateOrderModal,
            )
          : null,
      appBar: GlassAppBar(
        title: 'Purchase Orders',
        actions: [
          IconButton(
            tooltip: 'Refresh Queue',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
            onPressed: () => _load(showSuccess: true),
          ),
        ],
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () => _load(showSuccess: true),
          child: _loading
              ? const AppLoader(message: 'Loading purchase order ledger...')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    // Executive KPI Header Card
                    _buildExecutiveSummary(),
                    const SizedBox(height: 14),

                    // Search & Clear Bar
                    _buildSearchBar(),
                    const SizedBox(height: 12),

                    // Filter Chips
                    _buildFilterChips(),
                    const SizedBox(height: 16),

                    if (_error != null) ...[
                      ErrorState(message: _error!, onRetry: _load),
                      const SizedBox(height: 18),
                    ],

                    // Section Heading
                    SectionHeader(
                      _selectedFilter == 'needs_action'
                          ? 'AWAITING APPROVAL DECISION'
                          : _selectedFilter == 'fulfillment'
                              ? 'ACTIVE ORDERS IN FULFILLMENT'
                              : _selectedFilter == 'history'
                                  ? 'HISTORICAL / COMPLETED ORDERS'
                                  : 'ALL ACTIVE PURCHASE ORDERS',
                      trailing: Text(
                        '${_filteredOrders.length} ${_filteredOrders.length == 1 ? 'Order' : 'Orders'}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_filteredOrders.isEmpty && _error == null)
                      EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: _searchQuery.isNotEmpty
                            ? 'No matching orders'
                            : 'All caught up!',
                        message: _searchQuery.isNotEmpty
                            ? 'No purchase order matches "$_searchQuery". Try a different PO number or supplier.'
                            : _selectedFilter == 'needs_action'
                                ? 'No purchase orders are currently pending review or approval.'
                                : _selectedFilter == 'fulfillment'
                                    ? 'No orders are currently in transit or placed.'
                                    : _selectedFilter == 'history'
                                        ? 'No historical or closed orders found.'
                                        : 'No purchase orders found in the queue.',
                      )
                    else
                      ..._filteredOrders.map(_buildOrderCard),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search PO number, supplier, or branch...',
          hintStyle: TextStyle(
            color: AppColors.textMuted.withValues(alpha: 0.7),
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.cyan,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onChanged: (val) => setState(() => _searchQuery = val),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterChip('all', 'All Open (${_openOrders.length})'),
          const SizedBox(width: 8),
          _buildFilterChip(
            'needs_action',
            'Needs Action ($_needsActionCount)',
            badgeColor: _needsActionCount > 0 ? const Color(0xFFFBBF24) : null,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            'fulfillment',
            'Fulfillment ($_inFulfillmentCount)',
            badgeColor: _inFulfillmentCount > 0 ? AppColors.cyan : null,
          ),
          const SizedBox(width: 8),
          _buildFilterChip('history', 'Completed ($_completedCount)'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, {Color? badgeColor}) {
    final isSelected = _selectedFilter == key;
    final primaryColor = badgeColor ?? AppColors.cyan;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? primaryColor : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveSummary() {
    final totalValue = _allOrders.fold(0.0, (acc, o) => acc + o.amount);
    final receivedCount = _allOrders
        .where((o) => o.status == PurchaseOrderStatus.received)
        .length;
    final cancelledCount = _allOrders
        .where((o) => o.status == PurchaseOrderStatus.cancelled)
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F1C2B), Color(0xFF132030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF263C54)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: badge + role chip
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PROCUREMENT DESK',
                      style: AppTextStyles.label.copyWith(
                        color: const Color(0xFFF59E0B),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.canApprove
                      ? const Color(0xFF10B981).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.canApprove
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : AppColors.glassBorder,
                  ),
                ),
                child: Text(
                  widget.canApprove ? 'APPROVAL PERMITTED' : 'READ ONLY AUDIT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: widget.canApprove
                        ? const Color(0xFF10B981)
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Total value — all orders
          Text('TOTAL PORTFOLIO VALUE',
              style: AppTextStyles.label
                  .copyWith(fontSize: 10, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'LKR ${_formatCurrency(totalValue)}',
              style: AppTextStyles.headline.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Sub-label: breakdown
          const SizedBox(height: 4),
          Text(
            '${_openOrders.length} open · $receivedCount received · $cancelledCount cancelled',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 16),

          // 4 tappable metric tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'OPEN',
                  value: '${_openOrders.length}',
                  color: AppColors.cyan,
                  icon: Icons.inventory_2_rounded,
                  filterKey: 'all',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  label: 'ACTION DUE',
                  value: '$_needsActionCount',
                  color: const Color(0xFFFBBF24),
                  icon: Icons.pending_actions_rounded,
                  filterKey: 'needs_action',
                  highlight: _needsActionCount > 0,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  label: 'IN TRANSIT',
                  value: '$_inFulfillmentCount',
                  color: const Color(0xFF60A5FA),
                  icon: Icons.local_shipping_rounded,
                  filterKey: 'fulfillment',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  label: 'PAST',
                  value: '$_completedCount',
                  color: const Color(0xFF10B981),
                  icon: Icons.check_circle_outline_rounded,
                  filterKey: 'history',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    String? filterKey,
    bool highlight = false,
  }) {
    final isActive = filterKey != null && _selectedFilter == filterKey;
    return GestureDetector(
      onTap: filterKey != null
          ? () => setState(() => _selectedFilter = filterKey)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.18)
              : highlight
                  ? color.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? color.withValues(alpha: 0.7)
                : highlight
                    ? color.withValues(alpha: 0.5)
                    : color.withValues(alpha: 0.22),
            width: isActive || highlight ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: isActive ? color : AppColors.textMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
            if (filterKey != null)
              Text(
                'tap to view',
                style: TextStyle(
                  fontSize: 8,
                  color: color.withValues(alpha: isActive ? 0.9 : 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(_PurchaseOrder order) {
    final status = order.status;
    final statusColor = status.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: InventoryPanel(
        padding: const EdgeInsets.all(16),
        borderColor: statusColor.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: PO Number + Date + Status Badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_rounded, size: 15, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        order.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatDate(order.createdAt.isNotEmpty
                        ? order.createdAt
                        : order.updatedAt),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.label.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Supplier & Branch Details Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.business_rounded,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.supplier ?? 'External Supplier',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.title.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded,
                              size: 13, color: AppColors.cyan),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.branch ?? 'Main Branch',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TOTAL VALUE',
                        style: AppTextStyles.label.copyWith(fontSize: 9)),
                    const SizedBox(height: 2),
                    Text(
                      'LKR ${_formatCurrency(order.amount)}',
                      style: AppTextStyles.title.copyWith(
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Visual Lifecycle Progress Bar
            _buildLifecycleStepper(order.status),
            const SizedBox(height: 14),

            // Line Items Section
            if (order.items.isNotEmpty) ...[
              _buildLineItemsSection(order),
              const SizedBox(height: 14),
            ],
            if (order.receipts.isNotEmpty) ...[
              _buildReceiptHistory(order),
              const SizedBox(height: 14),
            ],

            // Contextual Action Buttons
            _buildActionSection(order),
          ],
        ),
      ),
    );
  }

  Widget _buildLifecycleStepper(PurchaseOrderStatus current) {
    if (current == PurchaseOrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF43F5E).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_rounded, size: 14, color: Color(0xFFF43F5E)),
            SizedBox(width: 6),
            Text('Order Cancelled',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF43F5E))),
          ],
        ),
      );
    }

    final steps = [
      PurchaseOrderStatus.draft,
      PurchaseOrderStatus.inReview,
      PurchaseOrderStatus.placed,
      PurchaseOrderStatus.inTransit,
      PurchaseOrderStatus.received,
    ];
    final activeIndex = current.stepIndex;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = index ~/ 2;
            final isDone = activeIndex > stepBefore;
            return Expanded(
              child: Container(
                height: 2,
                color: isDone
                    ? const Color(0xFF10B981)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final step = steps[stepIndex];
          final isPast = activeIndex > stepIndex;
          final isCurrent = activeIndex == stepIndex;

          final dotColor = isCurrent
              ? step.color
              : isPast
                  ? const Color(0xFF10B981)
                  : AppColors.textMuted.withValues(alpha: 0.4);

          return Tooltip(
            message: step.label,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? dotColor.withValues(alpha: 0.25)
                    : dotColor.withValues(alpha: 0.15),
                border: Border.all(
                  color: dotColor,
                  width: isCurrent ? 2 : 1.2,
                ),
              ),
              child: Center(
                child: isPast
                    ? const Icon(Icons.check_rounded,
                        size: 11, color: Color(0xFF10B981))
                    : isCurrent
                        ? Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                            ),
                          )
                        : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLineItemsSection(_PurchaseOrder order) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ORDER ITEMS (${order.items.length})',
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${order.lineItems} items total',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...order.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} × LKR ${_formatCurrency(item.unitPrice)}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          if (item.receivedQuantity > 0 ||
                              item.damagedQuantity > 0 ||
                              item.shortageQuantity > 0)
                            Text(
                              'Accepted ${item.receivedQuantity} · Damaged ${item.damagedQuantity} · Short ${item.shortageQuantity}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LKR ${_formatCurrency(item.lineTotal)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )),
          if (order.items.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                '+ ${order.items.length - 3} more items',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReceiptHistory(_PurchaseOrder order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECEIPT HISTORY (${order.receipts.length})',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...order.receipts.map((receipt) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${receipt.receivedAt.toLocal()} · ${receipt.receivedBy}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ...receipt.items.map((item) => Text(
                          '${item.name}: ${item.acceptedQuantity} accepted · ${item.damagedQuantity} damaged · ${item.shortageQuantity} short',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        )),
                    if (receipt.photoUrls.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: receipt.photoUrls
                            .map((url) => ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionSection(_PurchaseOrder order) {
    final status = order.status;

    final canReceiveThisOrder = widget.canReceive &&
        (status == PurchaseOrderStatus.inTransit ||
            status == PurchaseOrderStatus.partiallyReceived);
    if (!widget.canApprove && !canReceiveThisOrder) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status == PurchaseOrderStatus.inReview
              ? 'Awaiting Manager or Admin authorization.'
              : 'Read-only: purchase order updates require a Manager or Admin.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    if (status == PurchaseOrderStatus.inTransit ||
        status == PurchaseOrderStatus.partiallyReceived) {
      if (!widget.canReceive) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          child: Text(
            'Waiting for a staff member or Manager to record delivery quantities.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
        );
      }
      return NeonButton(
        label: order.approving ? 'Recording receipt…' : 'Receive items',
        isLoading: order.approving,
        icon: Icons.inventory_rounded,
        height: 44,
        onPressed: order.approving ? null : () => _receiveOrder(order),
      );
    }

    // 1. IN REVIEW: Core Approval Flow
    if (status == PurchaseOrderStatus.inReview) {
      return Row(
        children: [
          Expanded(
            child: GhostButton(
              label: 'Reject',
              icon: Icons.close_rounded,
              color: const Color(0xFFF43F5E),
              height: 44,
              onPressed: order.approving ? null : () => _cancelOrder(order),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: NeonButton(
              label: order.approving ? 'Authorizing...' : 'Approve & Place',
              isLoading: order.approving,
              icon: Icons.check_circle_rounded,
              height: 44,
              onPressed: order.approving
                  ? null
                  : () => _advanceOrderStatus(
                        order,
                        PurchaseOrderStatus.placed,
                        confirmTitle: 'Approve Purchase Order?',
                        confirmMessage:
                            'Authorize order ${order.number} for LKR ${_formatCurrency(order.amount)}? This marks the PO as Placed.',
                        confirmLabel: 'Approve & Place',
                        confirmAccent: const Color(0xFF10B981),
                      ),
            ),
          ),
        ],
      );
    }

    // 2. DRAFT: Advance to In Review or Direct Place
    if (status == PurchaseOrderStatus.draft) {
      return Row(
        children: [
          Expanded(
            child: GhostButton(
              label: 'Cancel',
              icon: Icons.delete_outline_rounded,
              color: const Color(0xFFF43F5E),
              height: 44,
              onPressed: order.approving ? null : () => _cancelOrder(order),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: NeonButton(
              label: order.approving ? 'Advancing...' : 'Submit for Review',
              isLoading: order.approving,
              icon: Icons.send_rounded,
              height: 44,
              onPressed: order.approving
                  ? null
                  : () => _advanceOrderStatus(
                        order,
                        PurchaseOrderStatus.inReview,
                        confirmTitle: 'Submit Order for Review?',
                        confirmMessage:
                            'Submit draft order ${order.number} to the approval desk for authorization?',
                        confirmLabel: 'Submit for Review',
                        confirmAccent: const Color(0xFFFBBF24),
                      ),
            ),
          ),
        ],
      );
    }

    // 3. PLACED: Dispatch / Mark In Transit
    if (status == PurchaseOrderStatus.placed) {
      return Row(
        children: [
          Expanded(
            child: GhostButton(
              label: 'Cancel',
              icon: Icons.close_rounded,
              color: const Color(0xFFF43F5E),
              height: 44,
              onPressed: order.approving ? null : () => _cancelOrder(order),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: NeonButton(
              label: order.approving ? 'Updating...' : 'Mark In Transit',
              isLoading: order.approving,
              icon: Icons.local_shipping_rounded,
              height: 44,
              onPressed: order.approving
                  ? null
                  : () => _advanceOrderStatus(
                        order,
                        PurchaseOrderStatus.inTransit,
                        confirmTitle: 'Mark Order as In Transit?',
                        confirmMessage:
                            'Has supplier ${order.supplier ?? ''} shipped order ${order.number}?',
                        confirmLabel: 'Mark In Transit',
                        confirmAccent: const Color(0xFF38BDF8),
                      ),
            ),
          ),
        ],
      );
    }

    // 5. TERMINAL: Received or Cancelled
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: status == PurchaseOrderStatus.received
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : const Color(0xFFF43F5E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status == PurchaseOrderStatus.received
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFF43F5E).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 6),
          Text(
            status == PurchaseOrderStatus.received
                ? 'Stock received & added to inventory.'
                : 'Order cancelled.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCurrency(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '$integerPart.${parts[1]}';
  }

  static String _formatDate(String isoString) {
    if (isoString.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      const months = [
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
        'Dec'
      ];
      final month = months[dt.month - 1];
      final day = dt.day;
      final year = dt.year;
      return '$month $day, $year';
    } catch (_) {
      return isoString;
    }
  }
}

/// Modal bottom sheet allowing users to create a new purchase order right from mobile.
class _CreateOrderBottomSheet extends StatefulWidget {
  const _CreateOrderBottomSheet({
    required this.client,
    required this.onCreated,
  });

  final AuthenticatedApiClient client;
  final VoidCallback onCreated;

  @override
  State<_CreateOrderBottomSheet> createState() =>
      _CreateOrderBottomSheetState();
}

class _CreateOrderBottomSheetState extends State<_CreateOrderBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _supplierController = TextEditingController();
  final _branchController = TextEditingController();

  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController();

  bool _loading = false;
  bool _loadingOptions = true;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _inventoryItems = [];
  String? _selectedBranchId;
  String? _selectedSupplierId;
  String? _selectedItemId;
  String? _optionsError;

  List<Map<String, dynamic>> get _supplierItems {
    final supplierId = _selectedSupplierId;
    final branchId = _selectedBranchId;
    if (supplierId == null || branchId == null) return const [];
    return _inventoryItems
        .where((item) =>
            '${item['supplierId'] ?? ''}' == supplierId &&
            '${item['branchId'] ?? ''}' == branchId)
        .toList();
  }

  double get _lineTotal {
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final unitPrice = double.tryParse(_unitPriceController.text.trim()) ?? 0;
    return quantity * unitPrice;
  }

  @override
  void initState() {
    super.initState();
    final randomNum = Random().nextInt(9000) + 1000;
    _numberController.text = 'PO-$randomNum';
    _fetchOptions();
  }

  Future<void> _fetchOptions() async {
    try {
      final res = await widget.client.get('/api/purchase-orders/options');
      if (res.statusCode != 200) {
        throw StateError(
          'Could not load suppliers and catalog items (${res.statusCode}).',
        );
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final branches = ((data['branches'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final suppliers = ((data['suppliers'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (mounted) {
        setState(() {
          _branches = branches;
          _suppliers = suppliers;
          _inventoryItems = items;
          _selectedBranchId =
              branches.isNotEmpty ? '${branches.first['id']}' : null;
          _selectedSupplierId =
              suppliers.isNotEmpty ? '${suppliers.first['id']}' : null;
          _optionsError = null;
          _loadingOptions = false;
          _selectSupplierItem(
              _supplierItems.isEmpty ? null : _supplierItems.first);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _selectSupplier(String? supplierId) {
    setState(() {
      _selectedSupplierId = supplierId;
      final items = _supplierItems;
      _selectSupplierItem(items.isEmpty ? null : items.first);
    });
  }

  void _selectSupplierItem(Map<String, dynamic>? item) {
    _selectedItemId = item == null ? null : '${item['id']}';
    _itemNameController.text = item == null
        ? ''
        : '${item['name'] ?? ''}${(item['sku'] as String?)?.trim().isNotEmpty == true ? ' (${item['sku']})' : ''}';
    final unitCost = (item?['unitCost'] as num?)?.toDouble();
    _unitPriceController.text = unitCost == null ? '' : _money(unitCost);
  }

  String _money(double value) => value.toStringAsFixed(2);

  String _formatTotal(double value) => 'LKR ${_money(value)}';

  Map<String, dynamic>? _itemById(String? id) {
    for (final item in _supplierItems) {
      if ('${item['id']}' == id) return item;
    }
    return null;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _supplierController.dispose();
    _branchController.dispose();
    _itemNameController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedSupplierId == null) {
      showAppNotification(
        'Choose a supplier before creating a purchase order.',
        tone: AppNotificationTone.error,
      );
      return;
    }
    if (_selectedItemId == null || _supplierItems.isEmpty) {
      showAppNotification(
        'Choose an inventory item linked to this supplier.',
        tone: AppNotificationTone.error,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final qty = double.tryParse(_quantityController.text) ?? 1;
      final price = double.tryParse(_unitPriceController.text) ?? 0;

      final body = {
        'number': _numberController.text.trim(),
        'branchId': _selectedBranchId,
        'supplierId': _selectedSupplierId,
        'items': [
          {
            'inventoryItemId': _selectedItemId,
            'description': _itemNameController.text.trim(),
            'quantity': qty,
            'unitPrice': price,
          }
        ],
      };

      final response =
          await widget.client.post('/api/purchase-orders', body: body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;
        Navigator.pop(context);
        showAppNotification(
          'Purchase order ${_numberController.text} created successfully.',
          tone: AppNotificationTone.success,
        );
        widget.onCreated();
      } else {
        throw StateError(
            'Failed with code ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(
          'Could not create purchase order. Verify branch and supplier are selected.',
          tone: AppNotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF132032),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Create Purchase Order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // PO Number
              TextFormField(
                controller: _numberController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _inputDec('PO NUMBER'),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              // Supplier Dropdown or Text
              if (_suppliers.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: const Key('po-supplier-dropdown'),
                  initialValue: _selectedSupplierId,
                  dropdownColor: const Color(0xFF17263C),
                  decoration: _inputDec('SUPPLIER'),
                  items: _suppliers
                      .map((s) => DropdownMenuItem(
                            value: '${s['id']}',
                            child: Text(
                              '${s['name']}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged:
                      _loading || _loadingOptions ? null : _selectSupplier,
                ),
              ] else ...[
                TextFormField(
                  controller: _supplierController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _inputDec('SUPPLIER NAME'),
                ),
              ],
              const SizedBox(height: 12),

              // Branch Dropdown or Text
              if (_branches.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedBranchId,
                  dropdownColor: const Color(0xFF17263C),
                  decoration: _inputDec('DELIVERY BRANCH'),
                  items: _branches
                      .map((b) => DropdownMenuItem(
                            value: '${b['id']}',
                            child: Text(
                              '${b['name']}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() {
                    _selectedBranchId = val;
                    final items = _supplierItems;
                    _selectSupplierItem(items.isEmpty ? null : items.first);
                  }),
                ),
              ] else ...[
                TextFormField(
                  controller: _branchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _inputDec('BRANCH NAME'),
                ),
              ],
              const SizedBox(height: 14),

              const Text('INITIAL LINE ITEM',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),

              if (_loadingOptions)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_optionsError != null)
                Text(
                  _optionsError!,
                  key: const Key('po-options-error'),
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                )
              else if (_selectedSupplierId == null)
                const Text(
                  'No supplier is available. Add a supplier before creating a purchase order.',
                  key: Key('po-no-suppliers'),
                  style: TextStyle(color: AppColors.warning, fontSize: 12),
                )
              else if (_supplierItems.isEmpty)
                const Text(
                  'This supplier has no linked inventory items. Assign this supplier to its inventory items in Inventory before creating a purchase order.',
                  key: Key('po-no-supplier-items'),
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    height: 1.4,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('po-item-dropdown-$_selectedSupplierId'),
                  initialValue: _selectedItemId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF17263C),
                  decoration: _inputDec('SUPPLIER ITEM'),
                  items: _supplierItems
                      .map((item) => DropdownMenuItem<String>(
                            value: '${item['id']}',
                            child: Text(
                              '${item['name']} · ${item['sku']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (id) {
                          setState(() => _selectSupplierItem(_itemById(id)));
                        },
                  validator: (id) =>
                      id == null ? 'Choose an item from this supplier' : null,
                ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('po-quantity-field'),
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDec('QTY'),
                      validator: (val) => (double.tryParse(val ?? '') ?? 0) <= 0
                          ? 'Must be > 0'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('po-unit-price-field'),
                      controller: _unitPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      readOnly: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDec('UNIT PRICE (LKR)'),
                      validator: (val) => (double.tryParse(val ?? '') ?? -1) < 0
                          ? 'Invalid'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('po-order-total'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL PRICE',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      _formatTotal(_lineTotal),
                      key: const Key('po-order-total-value'),
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              NeonButton(
                label: _loading ? 'Creating...' : 'Create Purchase Order',
                isLoading: _loading,
                icon: Icons.check_rounded,
                onPressed: _loading || _loadingOptions || _optionsError != null
                    ? null
                    : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cyan),
      ),
    );
  }
}

class _ReceivePurchaseOrderSheet extends StatefulWidget {
  const _ReceivePurchaseOrderSheet({
    required this.order,
    required this.inventoryItems,
  });

  final _PurchaseOrder order;
  final List<Map<String, dynamic>> inventoryItems;

  @override
  State<_ReceivePurchaseOrderSheet> createState() =>
      _ReceivePurchaseOrderSheetState();
}

class _ReceivePurchaseOrderSheetState
    extends State<_ReceivePurchaseOrderSheet> {
  final _accepted = <String, TextEditingController>{};
  final _damaged = <String, TextEditingController>{};
  final _notes = <String, TextEditingController>{};
  final _closedAsShort = <String>{};
  final _linkedInventoryItemIds = <String, String>{};
  final _photos = <XFile>[];

  List<Map<String, dynamic>> get _branchInventoryItems => widget.inventoryItems
      .where((item) => '${item['branchId'] ?? ''}' == widget.order.branchId)
      .toList();

  @override
  void initState() {
    super.initState();
    for (final item in widget.order.items) {
      _accepted[item.id] = TextEditingController(text: '0');
      _damaged[item.id] = TextEditingController(text: '0');
      _notes[item.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      ..._accepted.values,
      ..._damaged.values,
      ..._notes.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final receiptItems = <Map<String, dynamic>>[];
    for (final item in widget.order.items) {
      if (item.receivingClosed) continue;
      final accepted = double.tryParse(_accepted[item.id]!.text.trim());
      final damaged = double.tryParse(_damaged[item.id]!.text.trim());
      final delivered = (accepted ?? 0) + (damaged ?? 0);
      if (accepted == null ||
          damaged == null ||
          accepted < 0 ||
          damaged < 0 ||
          delivered > item.remainingQuantity) {
        showAppNotification(
          'Enter valid quantities. Accepted plus damaged units cannot exceed the ${item.remainingQuantity} units remaining.',
          tone: AppNotificationTone.warning,
        );
        return;
      }

      final closeShort = _closedAsShort.contains(item.id);
      if (delivered == 0 && !closeShort) continue;
      final inventoryItemId =
          item.inventoryItemId ?? _linkedInventoryItemIds[item.id];
      if (accepted > 0 && inventoryItemId == null) {
        showAppNotification(
          'Choose a destination-branch inventory item for ${item.name}.',
          tone: AppNotificationTone.warning,
        );
        return;
      }
      receiptItems.add({
        'purchaseOrderItemId': item.id,
        'acceptedQuantity': accepted,
        'damagedQuantity': damaged,
        'closeRemainingAsShort': closeShort,
        'notes': _notes[item.id]!.text.trim(),
        if (item.inventoryItemId == null && inventoryItemId != null)
          'inventoryItemId': inventoryItemId,
      });
    }

    if (receiptItems.isEmpty) {
      showAppNotification(
        'Enter a delivered quantity or mark an item’s remaining balance as short.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    Navigator.of(context).pop(
      _ReceiptSubmission(items: receiptItems, photos: List.of(_photos)),
    );
  }

  Future<void> _pickPhotos() async {
    if (_photos.length >= 5) {
      showAppNotification(
        'A receipt can have at most five photos.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    final selected = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (!mounted || selected.isEmpty) return;
    final supported = selected.where((file) {
      final extension = file.name.split('.').last.toLowerCase();
      return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension);
    }).toList();
    if (supported.length != selected.length) {
      showAppNotification(
        'Only JPEG, PNG, or WebP photos can be attached.',
        tone: AppNotificationTone.warning,
      );
    }
    if (_photos.length + supported.length > 5) {
      showAppNotification(
        'Select no more than ${5 - _photos.length} additional photos.',
        tone: AppNotificationTone.warning,
      );
      return;
    }
    setState(() => _photos.addAll(supported));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF132032),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Receive ${widget.order.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          const Text(
            'Record what arrived for each item. Only accepted units are added to stock.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.order.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = widget.order.items[index];
                if (item.receivingClosed) {
                  return _receiptLineCard(
                    item,
                    const Text(
                      'Fully accounted for',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }
                final accepted =
                    double.tryParse(_accepted[item.id]!.text.trim()) ?? 0;
                final damaged =
                    double.tryParse(_damaged[item.id]!.text.trim()) ?? 0;
                final delivered = accepted + damaged;
                final remainingAfterDelivery =
                    max(0.0, item.remainingQuantity - delivered);
                return _receiptLineCard(
                  item,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (item.inventoryItemId == null) ...[
                        if (_branchInventoryItems.isEmpty)
                          const Text(
                            'No inventory items are assigned to this destination branch. Accepted units cannot be stocked until an item is available.',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _linkedInventoryItemIds[item.id],
                            isExpanded: true,
                            dropdownColor: const Color(0xFF17263C),
                            decoration: InputDecoration(
                              labelText: 'INVENTORY ITEM FOR ACCEPTED STOCK',
                              labelStyle: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: _branchInventoryItems
                                .map(
                                    (inventoryItem) => DropdownMenuItem<String>(
                                          value: '${inventoryItem['id']}',
                                          child: Text(
                                            '${inventoryItem['name'] ?? 'Inventory item'} · ${inventoryItem['sku'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ))
                                .toList(),
                            onChanged: (id) => setState(() {
                              if (id == null) {
                                _linkedInventoryItemIds.remove(item.id);
                              } else {
                                _linkedInventoryItemIds[item.id] = id;
                              }
                            }),
                          ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 125,
                            child: _receiptQuantityField(
                              label: 'ACCEPTED (GOOD)',
                              controller: _accepted[item.id]!,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          SizedBox(
                            width: 125,
                            child: _receiptQuantityField(
                              label: 'DAMAGED',
                              controller: _damaged[item.id]!,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Accepted to stock: $accepted · Remaining: $remainingAfterDelivery',
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _closedAsShort.contains(item.id),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _closedAsShort.add(item.id);
                          } else {
                            _closedAsShort.remove(item.id);
                          }
                        }),
                        title: Text(
                          'No more delivery expected; close remaining $remainingAfterDelivery as short',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextField(
                        controller: _notes[item.id],
                        maxLength: 1000,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Condition / supplier notes',
                          labelStyle:
                              const TextStyle(color: AppColors.textMuted),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickPhotos,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _photos.isEmpty
                    ? 'Add optional receipt photos'
                    : 'Add receipt photos (${_photos.length}/5)',
              ),
            ),
          ),
          if (_photos.isNotEmpty)
            Wrap(
              spacing: 6,
              children: _photos
                  .map((photo) => InputChip(
                        label: Text(photo.name),
                        onDeleted: () => setState(() => _photos.remove(photo)),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: NeonButton(
              label: 'Record receipt and update stock',
              icon: Icons.inventory_rounded,
              height: 46,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptLineCard(_PurchaseOrderLine item, Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ordered ${item.quantity} · Accepted ${item.receivedQuantity} · Damaged ${item.damagedQuantity} · Short ${item.shortageQuantity} · Remaining ${item.remainingQuantity}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _receiptQuantityField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: onChanged,
      );
}

class _ReceiptSubmission {
  const _ReceiptSubmission({required this.items, required this.photos});

  final List<Map<String, dynamic>> items;
  final List<XFile> photos;
}

class _PurchaseOrderReceipt {
  const _PurchaseOrderReceipt({
    required this.id,
    required this.receivedAt,
    required this.receivedBy,
    required this.items,
    required this.photoUrls,
  });

  final String id;
  final DateTime receivedAt;
  final String receivedBy;
  final List<_PurchaseOrderReceiptLine> items;
  final List<String> photoUrls;

  factory _PurchaseOrderReceipt.fromJson(Map<String, dynamic> json) =>
      _PurchaseOrderReceipt(
        id: '${json['id']}',
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        receivedBy: json['receivedBy'] as String? ?? 'Authorized user',
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_PurchaseOrderReceiptLine.fromJson)
            .toList(),
        photoUrls: ((json['photoUrls'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class _PurchaseOrderReceiptLine {
  const _PurchaseOrderReceiptLine({
    required this.name,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.shortageQuantity,
  });

  final String name;
  final double acceptedQuantity;
  final double damagedQuantity;
  final double shortageQuantity;

  factory _PurchaseOrderReceiptLine.fromJson(Map<String, dynamic> json) =>
      _PurchaseOrderReceiptLine(
        name: '${json['itemName'] ?? 'Item'}',
        acceptedQuantity: (json['acceptedQuantity'] as num?)?.toDouble() ?? 0,
        damagedQuantity: (json['damagedQuantity'] as num?)?.toDouble() ?? 0,
        shortageQuantity: (json['shortageQuantity'] as num?)?.toDouble() ?? 0,
      );
}

class _PurchaseOrder {
  _PurchaseOrder({
    required this.id,
    required this.number,
    this.branchId = '',
    this.supplier,
    this.branch,
    this.amount = 0,
    this.lineItems = 1,
    this.status = PurchaseOrderStatus.draft,
    this.createdAt = '',
    this.updatedAt = '',
    this.items = const [],
    this.receipts = const [],
  });

  final String id, number;
  final String branchId;
  final String? supplier, branch;
  final double amount;
  final int lineItems;
  PurchaseOrderStatus status;
  final String createdAt;
  String updatedAt;
  final List<_PurchaseOrderLine> items;
  final List<_PurchaseOrderReceipt> receipts;
  bool approving = false;

  factory _PurchaseOrder.fromJson(Map<String, dynamic> json) => _PurchaseOrder(
        id: '${json['id']}',
        number: '${json['number']}',
        branchId: '${json['branchId'] ?? ''}',
        supplier:
            json['supplier'] as String? ?? json['supplierName'] as String?,
        branch: json['branch'] as String? ?? json['branchName'] as String?,
        status: PurchaseOrderStatus.parse(json['status'] as String?),
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt:
            json['updatedAt'] as String? ?? json['createdAt'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ??
            (json['totalAmount'] as num?)?.toDouble() ??
            0,
        lineItems: (json['lineItems'] as num?)?.toInt() ??
            (json['items'] as List?)?.length ??
            1,
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_PurchaseOrderLine.fromJson)
            .toList(),
        receipts: ((json['receipts'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_PurchaseOrderReceipt.fromJson)
            .toList(),
      );
}

class _PurchaseOrderLine {
  const _PurchaseOrderLine({
    required this.id,
    this.inventoryItemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.receivedQuantity,
    required this.damagedQuantity,
    required this.shortageQuantity,
    required this.receivingClosed,
  });

  final String id;
  final String? inventoryItemId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final double receivedQuantity;
  final double damagedQuantity;
  final double shortageQuantity;
  final bool receivingClosed;

  double get remainingQuantity =>
      (quantity - receivedQuantity - damagedQuantity - shortageQuantity)
          .clamp(0, double.infinity)
          .toDouble();

  factory _PurchaseOrderLine.fromJson(Map<String, dynamic> json) =>
      _PurchaseOrderLine(
        id: '${json['id']}',
        inventoryItemId: json['inventoryItemId'] as String?,
        name: json['itemName'] as String? ??
            json['description'] as String? ??
            'Purchase item',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
        receivedQuantity: (json['receivedQuantity'] as num?)?.toDouble() ?? 0,
        damagedQuantity: (json['damagedQuantity'] as num?)?.toDouble() ?? 0,
        shortageQuantity: (json['shortageQuantity'] as num?)?.toDouble() ?? 0,
        receivingClosed: json['receivingClosed'] as bool? ?? false,
      );
}
