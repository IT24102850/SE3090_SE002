import 'dart:convert';

import 'package:flutter/material.dart';

import '../../inventory/authenticated_api_client.dart';
import '../../inventory/inventory_panel.dart';
import '../../inventory/inventory_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/ui/workflow_loading_state.dart';

enum _OrderView { active, all, completed }

class CustomerOrderManagementScreen extends StatefulWidget {
  CustomerOrderManagementScreen({
    super.key,
    AuthenticatedApiClient? client,
  }) : client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient client;

  @override
  State<CustomerOrderManagementScreen> createState() =>
      _CustomerOrderManagementScreenState();
}

class _CustomerOrderManagementScreenState
    extends State<CustomerOrderManagementScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = false;
  String? _error;
  String? _updatingOrderId;
  _OrderView _view = _OrderView.active;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.get('/customer-orders/manage');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _responseMessage(
            response.body, 'Could not load customer orders.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException(
            'The order service returned an invalid list.');
      }
      final orders = decoded.map((entry) {
        if (entry is! Map) {
          throw const FormatException(
              'The order service returned an invalid order.');
        }
        return Map<String, dynamic>.from(entry);
      }).toList();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleOrders {
    return _orders.where((managed) {
      final status = _order(managed)['status']?.toString().toLowerCase();
      return switch (_view) {
        _OrderView.active => status != 'completed' && status != 'cancelled',
        _OrderView.all => true,
        _OrderView.completed => status == 'completed',
      };
    }).toList();
  }

  Future<void> _refreshOrders() async {
    if (_updatingOrderId != null) return;
    await _loadOrders();
  }

  int _countFor(_OrderView view) {
    return _orders.where((managed) {
      final status = _order(managed)['status']?.toString().toLowerCase();
      return switch (view) {
        _OrderView.active => status != 'completed' && status != 'cancelled',
        _OrderView.all => true,
        _OrderView.completed => status == 'completed',
      };
    }).length;
  }

  Future<void> _updateStatus(
      Map<String, dynamic> managed, String nextStatus) async {
    if (!mounted || _loading || _updatingOrderId != null) return;
    final order = _order(managed);
    final orderNumber = order['number']?.toString() ?? 'this order';
    if (nextStatus == 'Cancelled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel customer order?'),
          content: Text(
            'Cancel $orderNumber? Its reserved stock will be returned to inventory and the customer will be notified.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep order'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel order'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final orderId = order['id']?.toString();
    if (orderId == null || orderId.isEmpty) {
      AppSnackBar.error(
          context, 'This order is missing its ID. Refresh and try again.');
      return;
    }

    setState(() {
      _updatingOrderId = orderId;
      _error = null;
    });
    try {
      final response = await widget.client.put(
        '/customer-orders/manage/$orderId/status',
        body: {'status': nextStatus},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _responseMessage(response.body, 'Could not update this order.');
      }
      if (!mounted) return;
      // The write succeeded. Keep its confirmed status even if reloading fails.
      setState(() {
        _orders = _orders.map((entry) {
          final current = _order(entry);
          if (current['id']?.toString() != orderId) return entry;
          final updated = {...current, 'status': nextStatus};
          return entry['order'] is Map ? {...entry, 'order': updated} : updated;
        }).toList();
      });
      await _loadOrders();
      if (mounted) {
        AppSnackBar.success(
            context, '$orderNumber marked ${_statusLabel(nextStatus)}.');
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _countFor(_OrderView.active);
    final completedCount = _countFor(_OrderView.completed);
    return InventoryScaffold(
      appBar: GlassAppBar(
        title: 'Customer orders',
        actions: [
          IconButton(
            tooltip: 'Refresh customer orders',
            onPressed:
                _loading || _updatingOrderId != null ? null : _refreshOrders,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          onRefresh: _refreshOrders,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _OrdersSummary(
                total: _orders.length,
                active: activeCount,
                completed: completedCount,
              ),
              const SizedBox(height: 16),
              _OrderViewFilters(
                selected: _view,
                countFor: _countFor,
                onChanged: (view) => setState(() => _view = view),
              ),
              const SizedBox(height: 14),
              if (_loading && _orders.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: WorkflowLoadingState(
                      message: 'Refreshing orders', compact: true),
                ),
              if (_loading && _orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: WorkflowLoadingState(
                    message: 'Gathering your orders',
                    detail:
                        'Preparing customer details and the latest order updates',
                  ),
                )
              else if (_error != null && _orders.isEmpty)
                ErrorState(message: _error!, onRetry: _loadOrders)
              else if (_error != null)
                InlineErrorBanner(
                    message: _error!,
                    onDismiss: () {
                      setState(() => _error = null);
                    }),
              if (!_loading &&
                  !(_error != null && _orders.isEmpty) &&
                  _visibleOrders.isEmpty)
                EmptyState(
                  icon: _view == _OrderView.completed
                      ? Icons.task_alt_rounded
                      : Icons.receipt_long_outlined,
                  title: _view == _OrderView.active
                      ? 'No open customer orders'
                      : _view == _OrderView.completed
                          ? 'No completed orders yet'
                          : 'No customer orders yet',
                  message: _view == _OrderView.active
                      ? 'New orders will appear here when customers check out.'
                      : 'Orders placed by customers will appear here.',
                )
              else if (_orders.isNotEmpty)
                ..._visibleOrders.map(_buildOrderCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> managed) {
    final order = _order(managed);
    final status = order['status']?.toString() ?? 'Pending';
    final actions = _nextStatuses(order);
    final items = (order['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final orderId = order['id']?.toString();
    final busy = orderId != null && _updatingOrderId == orderId;
    final createdAt = DateTime.tryParse(order['createdAt']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InventoryPanel(
        borderColor: AppColors.cyan.withValues(alpha: .2),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order['number']?.toString() ?? 'Customer order',
                        style: AppTextStyles.subtitle),
                    if (createdAt != null)
                      Text(_formatDate(createdAt),
                          style: AppTextStyles.caption),
                  ],
                ),
                const SizedBox(height: 8),
                _OrderStatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 13),
            _OrderDetailRow(
              icon: Icons.person_outline_rounded,
              label: managed['customerName']?.toString() ?? 'Customer',
            ),
            const SizedBox(height: 7),
            _OrderDetailRow(
              icon: Icons.store_outlined,
              label: managed['branchName']?.toString() ?? 'Store',
            ),
            const SizedBox(height: 7),
            _OrderDetailRow(
              icon: order['fulfillmentMethod'] == 'Delivery'
                  ? Icons.local_shipping_outlined
                  : Icons.storefront_outlined,
              label: order['fulfillmentMethod'] == 'Delivery'
                  ? 'Delivery · ${order['deliveryAddress'] ?? 'Address not provided'}'
                  : 'Pickup',
            ),
            if (items.isNotEmpty) ...[
              const Divider(color: AppColors.hairline, height: 22),
              ...items.map((item) {
                final quantity = item['quantity'];
                final quantityLabel = quantity is num
                    ? quantity.toString()
                    : quantity?.toString() ?? '0';
                final lineTotal = _money(item['lineTotal']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$quantityLabel × ${item['itemName'] ?? 'Item'}',
                          style: AppTextStyles.bodyMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(lineTotal, style: AppTextStyles.caption),
                    ],
                  ),
                );
              }),
            ],
            const Divider(color: AppColors.hairline, height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment: ${_paymentLabel(order['paymentStatus'])}',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 6),
                Text(
                  _money(order['total']),
                  style: AppTextStyles.subtitle.copyWith(color: AppColors.cyan),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions.map((nextStatus) {
                  final cancel = nextStatus == 'Cancelled';
                  return OutlinedButton.icon(
                    onPressed: _updatingOrderId != null || _loading
                        ? null
                        : () => _updateStatus(managed, nextStatus),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            cancel
                                ? Icons.close_rounded
                                : _actionIcon(nextStatus),
                            size: 17,
                          ),
                    label: Text(busy ? 'Saving…' : _statusLabel(nextStatus)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      backgroundColor:
                          (cancel ? AppColors.error : AppColors.cyan)
                              .withValues(alpha: .08),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      foregroundColor:
                          cancel ? AppColors.error : AppColors.cyan,
                      side: BorderSide(
                        color: (cancel ? AppColors.error : AppColors.cyan)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _order(Map<String, dynamic> managed) {
  final order = managed['order'];
  return order is Map ? Map<String, dynamic>.from(order) : managed;
}

List<String> _nextStatuses(Map<String, dynamic> order) {
  final status = order['status']?.toString();
  switch (status) {
    case 'Pending':
      return ['Confirmed', 'Cancelled'];
    case 'Confirmed':
      return ['Preparing', 'Cancelled'];
    case 'Preparing':
      return [
        order['fulfillmentMethod'] == 'Delivery'
            ? 'OutForDelivery'
            : 'ReadyForPickup',
        'Cancelled',
      ];
    case 'ReadyForPickup':
    case 'OutForDelivery':
      return ['Completed'];
    default:
      return [];
  }
}

IconData _actionIcon(String status) {
  return switch (status) {
    'Confirmed' => Icons.check_rounded,
    'Preparing' => Icons.inventory_2_outlined,
    'ReadyForPickup' => Icons.shopping_bag_outlined,
    'OutForDelivery' => Icons.local_shipping_outlined,
    'Completed' => Icons.task_alt_rounded,
    _ => Icons.arrow_forward_rounded,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'ReadyForPickup' => 'Ready for pickup',
    'OutForDelivery' => 'Out for delivery',
    _ => status,
  };
}

String _money(Object? value) {
  final amount =
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return 'LKR ${amount.toStringAsFixed(2)}';
}

String _paymentLabel(Object? value) => switch (value?.toString()) {
      'DueOnFulfillment' => 'Due on fulfillment',
      'Paid' => 'Paid',
      'Pending' => 'Pending',
      'Refunded' => 'Refunded',
      null => 'Due on fulfillment',
      final String label => label,
    };

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day}/${local.month}/${local.year} · '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _responseMessage(String body, String fallback) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final message = decoded['message'] ?? decoded['title'];
      if (message is String && message.isNotEmpty) return message;
    }
  } on FormatException {
    return fallback;
  }
  return fallback;
}

class _OrdersSummary extends StatelessWidget {
  const _OrdersSummary({
    required this.total,
    required this.active,
    required this.completed,
  });

  final int total;
  final int active;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return InventoryPanel(
      padding: const EdgeInsets.all(22),
      fill: const Color(0xFF1B4C49),
      borderColor: const Color(0xFF74DCC0).withValues(alpha: .4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF9EF2D5).withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Color(0xFF9EF2D5), size: 28),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order desk',
                    style: AppTextStyles.title
                        .copyWith(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('$total total · $active open · $completed completed',
                    style: AppTextStyles.caption),
                const SizedBox(height: 8),
                Text('From checkout to a happy customer.',
                    style: AppTextStyles.caption
                        .copyWith(color: const Color(0xFFAFE1D3))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderViewFilters extends StatelessWidget {
  const _OrderViewFilters({
    required this.selected,
    required this.countFor,
    required this.onChanged,
  });

  final _OrderView selected;
  final int Function(_OrderView) countFor;
  final ValueChanged<_OrderView> onChanged;

  static const _options = [
    (_OrderView.active, 'Open'),
    (_OrderView.all, 'All'),
    (_OrderView.completed, 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (view, label) in _options) ...[
          ChoiceChip(
            label: Text('$label · ${countFor(view)}'),
            selected: selected == view,
            onSelected: (_) => onChanged(view),
            selectedColor: AppColors.cyan.withValues(alpha: 0.15),
            backgroundColor: AppColors.glassFill,
            side: BorderSide(
              color: selected == view
                  ? AppColors.cyan.withValues(alpha: 0.5)
                  : AppColors.glassBorder,
            ),
            labelStyle: AppTextStyles.caption.copyWith(
              color: selected == view ? AppColors.cyan : AppColors.textBody,
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderDetailRow extends StatelessWidget {
  const _OrderDetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.iconSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppTextStyles.caption)),
      ],
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Pending' => AppColors.warning,
      'Completed' => AppColors.success,
      'Cancelled' => AppColors.error,
      _ => AppColors.cyan,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
