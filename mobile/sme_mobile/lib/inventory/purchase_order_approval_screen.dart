import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'app_notifications.dart';
import 'authenticated_api_client.dart';
import 'inventory_panel.dart';
import 'notification_ws.dart';

class PurchaseOrderApprovalScreen extends StatefulWidget {
  const PurchaseOrderApprovalScreen({
    super.key,
    required this.client,
    required this.canApprove,
  });

  final AuthenticatedApiClient client;
  final bool canApprove;

  @override
  State<PurchaseOrderApprovalScreen> createState() =>
      _PurchaseOrderApprovalScreenState();
}

class _PurchaseOrderApprovalScreenState
    extends State<PurchaseOrderApprovalScreen> {
  List<_PurchaseOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _notifSub;

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
                showAppNotification('Agent placed or updated a purchase order.',
                    tone: AppNotificationTone.info);
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
    super.dispose();
  }

  Future<void> _load({bool showSuccess = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client
          .get('/api/purchase-orders?status=InReview&pageSize=100');
      if (response.statusCode != 200) {
        throw StateError(
            'Purchase orders API returned ${response.statusCode}.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _orders = ((data['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_PurchaseOrder.fromJson)
            .toList();
      });
      if (showSuccess) {
        showAppNotification(
          'Purchase approval queue refreshed successfully.',
          tone: AppNotificationTone.success,
          title: 'Queue updated',
        );
      }
    } on StateError catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail(
          'The purchase orders API cannot be reached. Verify network connectivity.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _orders = const [];
    });
    showAppNotification(message, tone: AppNotificationTone.error);
  }

  Future<void> _approve(_PurchaseOrder order) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Approve Purchase Order?',
      message:
          'Authorize order ${order.number} for LKR ${order.amount.toStringAsFixed(2)}? This marks the PO as Placed.',
      confirmLabel: 'Approve & Place',
      icon: Icons.verified_rounded,
      accent: const Color(0xFF10B981),
    );
    if (!confirmed || !mounted || order.approving) return;

    setState(() => order.approving = true);
    try {
      final response = await widget.client.put(
        '/api/purchase-orders/${order.id}/status',
        body: {'status': 'Placed'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception();
      }
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item.id == order.id));
      showAppNotification(
        '${order.number} successfully authorized and marked as Placed.',
        tone: AppNotificationTone.success,
      );
    } catch (_) {
      if (mounted) {
        setState(() => order.approving = false);
        showAppNotification(
          'Approval could not be completed. Please retry.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  Future<void> _reject(_PurchaseOrder order) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Reject Purchase Order?',
      message:
          'Are you sure you want to reject ${order.number}? This will cancel the order.',
      confirmLabel: 'Reject Order',
      icon: Icons.cancel_outlined,
      accent: const Color(0xFFF43F5E),
      isDestructive: true,
    );
    if (!confirmed || !mounted || order.approving) return;

    setState(() => order.approving = true);
    try {
      final response = await widget.client.put(
        '/api/purchase-orders/${order.id}/status',
        body: {'status': 'Cancelled'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception();
      }
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item.id == order.id));
      showAppNotification(
        '${order.number} has been rejected and cancelled.',
        tone: AppNotificationTone.warning,
      );
    } catch (_) {
      if (mounted) {
        setState(() => order.approving = false);
        showAppNotification(
          'Could not reject order. Please retry.',
          tone: AppNotificationTone.error,
        );
      }
    }
  }

  double get _totalQueueAmount =>
      _orders.fold(0.0, (acc, item) => acc + item.amount);

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Purchase Approvals',
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
              ? const AppLoader(message: 'Loading pending approvals...')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    // Executive Header Card
                    _buildExecutiveSummary(),
                    const SizedBox(height: 18),

                    if (_error != null) ...[
                      ErrorState(message: _error!, onRetry: _load),
                      const SizedBox(height: 18),
                    ],

                    SectionHeader(
                      'AWAITING EXECUTIVE DECISION',
                      trailing: Text('${_orders.length} Orders',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.cyan)),
                    ),
                    const SizedBox(height: 12),

                    if (_orders.isEmpty && _error == null)
                      const EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'All caught up!',
                        message:
                            'No purchase orders are currently pending review or approval.',
                      )
                    else
                      ..._orders.map((order) => _buildOrderCard(order)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildExecutiveSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF142235),
        border: Border.all(color: const Color(0xFF2A4058)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
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
                      'APPROVAL DESK',
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
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL QUEUE COMMITMENT', style: AppTextStyles.label),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'LKR ${_totalQueueAmount.toStringAsFixed(2)}',
                        style: AppTextStyles.headline.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_orders.length} Orders Pending',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(_PurchaseOrder order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: InventoryPanel(
        padding: const EdgeInsets.all(18),
        borderColor: const Color(0xFFF59E0B).withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    size: 22,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.title.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Created for ${order.supplier ?? 'External Supplier'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
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
                      const Text(
                        'IN REVIEW',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
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
            const SizedBox(height: 16),

            // Order stats row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final location = Row(
                    children: [
                      const Icon(Icons.storefront_rounded,
                          size: 16, color: AppColors.cyan),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.branch ?? 'Main branch',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${order.lineItems} item${order.lineItems == 1 ? '' : 's'}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  );
                  final amount = Text(
                    'LKR ${order.amount.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title.copyWith(
                      color: const Color(0xFF10B981),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  );

                  if (constraints.maxWidth < 380) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        location,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: amount),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: location),
                      const SizedBox(width: 12),
                      Flexible(child: amount),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            if (widget.canApprove) ...[
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      color: const Color(0xFFF43F5E),
                      height: 46,
                      onPressed: order.approving ? null : () => _reject(order),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: NeonButton(
                      label: order.approving
                          ? 'Authorizing...'
                          : 'Approve & Place',
                      isLoading: order.approving,
                      icon: Icons.check_circle_rounded,
                      height: 46,
                      onPressed: order.approving ? null : () => _approve(order),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Approvals are restricted to Managers & Administrators.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PurchaseOrder {
  _PurchaseOrder({
    required this.id,
    required this.number,
    this.supplier,
    this.branch,
    this.amount = 0,
    this.lineItems = 1,
  });

  final String id, number;
  final String? supplier, branch;
  final double amount;
  final int lineItems;
  bool approving = false;

  factory _PurchaseOrder.fromJson(Map<String, dynamic> json) => _PurchaseOrder(
        id: '${json['id']}',
        number: '${json['number']}',
        supplier: json['supplier'] as String?,
        branch: json['branch'] as String?,
        amount: (json['amount'] as num?)?.toDouble() ??
            (json['totalAmount'] as num?)?.toDouble() ??
            0,
        lineItems: (json['lineItems'] as num?)?.toInt() ??
            (json['items'] as List?)?.length ??
            1,
      );
}
