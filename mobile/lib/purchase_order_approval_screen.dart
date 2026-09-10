import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth/app_notifications.dart';
import 'auth/authenticated_api_client.dart';
import 'auth/notification_ws.dart';
import 'data/mock_inventory_data.dart';

class PurchaseOrderApprovalScreen extends StatefulWidget {
  const PurchaseOrderApprovalScreen(
      {super.key, required this.client, required this.canApprove});
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
  bool _isDemoData = false;
  String? _error;

  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService().connect();
    // subscribe to notification websocket events
    try {
      _notifSub = NotificationService().stream.listen((event) {
        try {
          if (event['type'] == 'workflow_update') {
            final action = event['actionType'] as String? ?? '';
            // if a backend PO was created or workflow approved, refresh the PO list
            if (action == 'generate_purchase_order' &&
                (event['backend_result'] != null ||
                    event['status'] == 'approved')) {
              // refresh list on main isolate
              if (mounted) {
                showAppNotification('Agent placed or updated a purchase order.',
                    tone: AppNotificationTone.info);
                _load();
              }
            }
          }
        } catch (e) {
          // ignore
        }
      });
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
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
        _isDemoData = false;
      });
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _isDemoData = false;
        });
        showAppNotification('Purchase orders could not be loaded.',
            tone: AppNotificationTone.error);
      }
    } catch (_) {
      // Fallback to MockInventoryData orders
      final mockOrders = await MockInventoryData.getOrders();
      final pending = mockOrders
          .where((po) => po.status == 'InReview')
          .map((po) => _PurchaseOrder(
                id: po.id,
                number: po.number,
                supplier: po.supplier,
                branch: po.branch,
                amount: po.amount,
                lineItems: po.lineItems,
              ))
          .toList();
      if (mounted) {
        setState(() {
          _orders = pending;
          _isDemoData = true;
          _error = null;
        });
        showAppNotification(
            'Live purchase orders are unavailable. Showing saved demo orders.',
            tone: AppNotificationTone.warning);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(_PurchaseOrder order) async {
    setState(() => order.approving = true);
    try {
      final response = await widget.client.put(
          '/api/purchase-orders/${order.id}/status',
          body: {'status': 'Placed'});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception();
      }
      await MockInventoryData.approveOrder(order.id);
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item.id == order.id));
      showAppNotification('${order.number} approved and marked as placed.',
          tone: AppNotificationTone.success);
    } catch (_) {
      // Never replace a live queue with local demo data after a live API
      // failure. Local approvals are only allowed for an already demo-backed
      // queue.
      if (!_isDemoData) {
        if (mounted) {
          setState(() => order.approving = false);
          showAppNotification(
              'Approval could not be completed while the API is unavailable.',
              tone: AppNotificationTone.error);
        }
        return;
      }
      final approved = await MockInventoryData.approveOrder(order.id);
      if (approved && mounted) {
        setState(() => _orders.removeWhere((item) => item.id == order.id));
        showAppNotification(
            '${order.number} approved and marked as placed (Demo sync).',
            tone: AppNotificationTone.success);
      } else if (mounted) {
        setState(() => order.approving = false);
        showAppNotification(
            'Approval could not be completed. Please try again.',
            tone: AppNotificationTone.error);
      }
    }
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PURCHASE ORDERS',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Approval queue',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.canApprove
                          ? 'Review and approve pending supplier orders.'
                          : 'Viewing as read-only. Sign in as Manager to approve.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_isDemoData)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0x1FF59E0B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x40F59E0B)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: Color(0xFFF59E0B)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Showing demo approval queue. Approvals sync with inventory operations.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_error != null)
                      _MessageCard(
                          message: _error!, icon: Icons.cloud_off_outlined),
                    if (_error == null && _orders.isEmpty)
                      const _MessageCard(
                        message:
                            'No purchase orders are waiting for approval.\nAll caught up!',
                        icon: Icons.task_alt_rounded,
                      ),
                    ..._orders.map((order) => Card(
                          margin: const EdgeInsets.only(bottom: 14),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.receipt_long_rounded,
                                        size: 20,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        order.number,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const _StatusChip(),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Icon(Icons.business_rounded,
                                        size: 16, color: Color(0xFF667085)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        order.supplier ??
                                            'Supplier not specified',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.storefront_rounded,
                                        size: 16, color: Color(0xFF667085)),
                                    const SizedBox(width: 6),
                                    Text(
                                      order.branch ?? 'Main branch',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${order.lineItems} line item${order.lineItems == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (order.amount > 0)
                                        Text(
                                          'LKR ${order.amount.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed:
                                      widget.canApprove && !order.approving
                                          ? () => _approve(order)
                                          : null,
                                  icon: order.approving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded),
                                  label: Text(
                                    order.approving
                                        ? 'Approving...'
                                        : widget.canApprove
                                            ? 'Approve and place order'
                                            : 'Approval restricted to Managers',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Awaiting approval',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 36, color: const Color(0xFF667085)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
}
