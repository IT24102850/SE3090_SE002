import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth/app_notifications.dart';
import 'auth/authenticated_api_client.dart';
import 'auth/notification_ws.dart';

class PurchaseOrderApprovalScreen extends StatefulWidget {
  const PurchaseOrderApprovalScreen({super.key, required this.client, required this.canApprove});
  final AuthenticatedApiClient client;
  final bool canApprove;

  @override
  State<PurchaseOrderApprovalScreen> createState() => _PurchaseOrderApprovalScreenState();
}

class _PurchaseOrderApprovalScreenState extends State<PurchaseOrderApprovalScreen> {
  List<_PurchaseOrder> _orders = [];
  bool _loading = true;
  String? _error;

  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    _load();
    // subscribe to notification websocket events
    try {
      _notifSub = NotificationService().stream.listen((event) {
        try {
          if (event['type'] == 'workflow_update') {
            final action = event['actionType'] as String? ?? '';
            // if a backend PO was created or workflow approved, refresh the PO list
            if (action == 'generate_purchase_order' && (event['backend_result'] != null || event['status'] == 'approved')) {
              // refresh list on main isolate
              if (mounted) {
                showAppNotification('Agent placed or updated a purchase order.', tone: AppNotificationTone.info);
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
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.client.get('/api/purchase-orders?status=InReview&pageSize=100');
      if (response.statusCode != 200) throw Exception();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _orders = ((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>().map(_PurchaseOrder.fromJson).toList());
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load purchase orders. Pull down or tap refresh to try again.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _approve(_PurchaseOrder order) async {
    setState(() => order.approving = true);
    try {
      final response = await widget.client.put('/api/purchase-orders/${order.id}/status', body: {'status': 'Placed'});
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception();
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item.id == order.id));
      showAppNotification('${order.number} approved and marked as placed.', tone: AppNotificationTone.success);
    } catch (_) {
      if (mounted) {
        setState(() => order.approving = false);
        showAppNotification('Approval could not be completed. Please try again.', tone: AppNotificationTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PURCHASE ORDERS', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text('Approval queue', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ])),
                IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
              ]),
              const SizedBox(height: 8),
              Text(widget.canApprove ? 'One tap sends an approved order to purchasing.' : 'Only managers can approve purchase orders.', style: const TextStyle(color: Color(0xFF667085))),
              const SizedBox(height: 24),
              if (_error != null) _MessageCard(message: _error!, icon: Icons.cloud_off_outlined),
              if (_error == null && _orders.isEmpty) const _MessageCard(message: 'No purchase orders are waiting for approval.', icon: Icons.task_alt_rounded),
              ..._orders.map((order) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(order.number, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), const _StatusChip()]),
                  const SizedBox(height: 8),
                  Text(order.supplier ?? 'Supplier not specified'),
                  Text(order.branch ?? 'Branch not specified', style: const TextStyle(color: Color(0xFF667085))),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: widget.canApprove && !order.approving ? () => _approve(order) : null, icon: order.approving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline_rounded), label: Text(order.approving ? 'Approving...' : 'Approve order')),
                ])),
              )),
            ]),
    )),
  );
}

class _PurchaseOrder {
  _PurchaseOrder({required this.id, required this.number, this.supplier, this.branch});
  final String id, number; final String? supplier, branch; bool approving = false;
  factory _PurchaseOrder.fromJson(Map<String, dynamic> json) => _PurchaseOrder(id: '${json['id']}', number: '${json['number']}', supplier: json['supplier'] as String?, branch: json['branch'] as String?);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(20)), child: const Text('Awaiting approval', style: TextStyle(color: Color(0xFF8A5A00), fontSize: 12, fontWeight: FontWeight.w700)));
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.icon});
  final String message; final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(icon, size: 36, color: const Color(0xFF667085)), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center)])));
}
