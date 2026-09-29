import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'authenticated_api_client.dart';
import 'inventory_models.dart';
import 'inventory_panel.dart';
import 'sale_receipt.dart';

enum _SalesFeedbackTone { info, success, error }

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.client});

  final AuthenticatedApiClient client;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _quantityController = TextEditingController(text: '1');
  List<InventoryItem> _items = const [];
  List<_RevenueDay> _days = const [];
  List<_RecentSale> _recentSales = const [];
  InventoryItem? _selectedItem;
  bool _loading = true;
  bool _saving = false;
  bool _inventoryLoaded = false;
  bool _hasLoadedOnce = false;
  int _inventoryRevision = 0;
  double _totalRevenue = 0;
  double? _grossProfit;
  int _periodDays = 7;

  List<InventoryItem> get _availableItems => _items
      .where((item) => item.quantity > 0 && item.branchId != null)
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, _SalesFeedbackTone tone) {
    if (!mounted) return;
    switch (tone) {
      case _SalesFeedbackTone.info:
        AppSnackBar.info(context, message);
      case _SalesFeedbackTone.success:
        AppSnackBar.success(context, message);
      case _SalesFeedbackTone.error:
        AppSnackBar.error(context, message);
    }
  }

  Future<void> _load({bool showRefreshFeedback = false}) async {
    setState(() {
      _loading = true;
      _inventoryLoaded = false;
      _days = const [];
      _totalRevenue = 0;
      _grossProfit = null;
    });
    try {
      final items = <InventoryItem>[];
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages) {
        final response =
            await widget.client.get('/api/inventory?page=$page&pageSize=100');
        if (response.statusCode != 200) {
          throw _apiError(response.body, response.statusCode);
        }
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        totalPages = (payload['totalPages'] as num?)?.toInt() ?? 1;
        items.addAll(((payload['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InventoryItem.fromJson));
        page++;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _inventoryRevision++;
        _inventoryLoaded = true;
        _selectedItem = _selectedItem == null
            ? null
            : items
                .where((item) =>
                    item.id == _selectedItem!.id &&
                    item.quantity > 0 &&
                    item.branchId != null)
                .firstOrNull;
      });

      final now = DateTime.now().toUtc();
      final to = DateTime.utc(now.year, now.month, now.day);
      final from = to.subtract(Duration(days: _periodDays - 1));
      final query = '?from=${Uri.encodeQueryComponent(from.toIso8601String())}'
          '&to=${Uri.encodeQueryComponent(to.toIso8601String())}';
      final report = await widget.client.get('/api/reports/revenue$query');
      if (report.statusCode != 200) {
        throw _apiError(report.body, report.statusCode);
      }
      final data = jsonDecode(report.body) as Map<String, dynamic>;
      final rawBuckets = data['buckets'];
      if (rawBuckets is! List) {
        throw const FormatException('Sales report has no daily totals.');
      }
      final days = rawBuckets.whereType<Map<String, dynamic>>().map((bucket) {
        final rawDate = bucket['date'] as String? ?? '';
        return _RevenueDay(
          rawDate.length >= 10 ? rawDate.substring(5) : '',
          (bucket['revenue'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      final activity =
          await widget.client.get('/api/reports/sales-activity$query');
      if (activity.statusCode != 200) {
        throw _apiError(activity.body, activity.statusCode);
      }
      final activityData = jsonDecode(activity.body) as Map<String, dynamic>;
      final recentSales = ((activityData['recentSales'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_RecentSale.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _days = days;
        _recentSales = recentSales;
        _totalRevenue = (data['totalRevenue'] as num?)?.toDouble() ??
            days.fold<double>(0, (sum, day) => sum + day.amount);
        _grossProfit = (activityData['grossProfit'] as num?)?.toDouble();
        _loading = false;
        _hasLoadedOnce = true;
      });
      if (showRefreshFeedback) {
        _showFeedback('Sales and inventory refreshed successfully.',
            _SalesFeedbackTone.success);
      }
    } catch (error) {
      if (!mounted) return;
      final message = _messageFromError(error);
      setState(() => _loading = false);
      _showFeedback(
        showRefreshFeedback
            ? 'Refresh failed: $message'
            : 'Could not load sales: $message',
        _SalesFeedbackTone.error,
      );
    }
  }

  String _apiError(String body, int status) {
    final data = _tryDecodeJson(body);
    if (data is Map) {
      final detail = _findApiMessage(data);
      if (detail != null) return detail;
    }

    final plainText = body.trim();
    if (plainText.isNotEmpty &&
        !plainText.startsWith('<') &&
        plainText.length <= 300) {
      return plainText;
    }

    return switch (status) {
      400 =>
        'The sale request was invalid (HTTP 400). Check the quantity and price.',
      401 => 'Your session has expired. Sign in again and retry the sale.',
      403 => 'You do not have permission to record this sale (HTTP 403).',
      404 =>
        'The sales API endpoint was not found (HTTP 404). Check the deployed backend route.',
      409 =>
        'The sale conflicts with the latest inventory state (HTTP 409). Refresh stock and retry.',
      422 =>
        'The backend could not process this sale (HTTP 422). Check the entered values.',
      429 => 'Too many requests. Wait a moment, then try again.',
      500 ||
      502 ||
      503 ||
      504 =>
        'The backend is temporarily unavailable (HTTP $status). Try again shortly.',
      _ => 'The request failed (HTTP $status). Please try again.',
    };
  }

  Object? _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {}
    return null;
  }

  String _messageFromError(Object error) {
    if (error is DioException) {
      if (error.response != null) {
        final responseData = error.response?.data;
        return _apiError(
          responseData is String
              ? responseData
              : jsonEncode(responseData ?? {}),
          error.response?.statusCode ?? 0,
        );
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The request timed out. Check your connection and try again.',
        DioExceptionType.connectionError =>
          'Could not connect to the deployed backend. Check your internet connection and try again.',
        DioExceptionType.badCertificate =>
          'A secure connection to the backend could not be established.',
        DioExceptionType.cancel => 'The request was cancelled.',
        _ => 'The backend request could not be completed. Please try again.',
      };
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String? _findApiMessage(Map data) {
    for (final key in const ['detail', 'message', 'error']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }

    final errors = data['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is List) {
          for (final message in value) {
            if (message is String && message.trim().isNotEmpty) {
              return message.trim();
            }
          }
        }
      }
    } else if (errors is List) {
      for (final message in errors) {
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    }
    final title = data['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();
    return null;
  }

  Future<void> _recordSale() async {
    final item = _selectedItem;
    final quantity = double.tryParse(_quantityController.text.trim());
    final price = item?.sellingPrice;
    final cost = item?.unitCost;
    if (item != null && price == null) {
      _showFeedback(
        'Set a selling price for ${item.name} in web inventory before recording a sale.',
        _SalesFeedbackTone.error,
      );
      return;
    }
    if (item != null && cost == null) {
      _showFeedback(
        'Set the unit cost for ${item.name} in web inventory to calculate profit.',
        _SalesFeedbackTone.error,
      );
      return;
    }
    if (item != null && price != null && cost != null && price <= cost) {
      _showFeedback(
        'Selling price must be greater than unit cost. Update prices in web inventory.',
        _SalesFeedbackTone.error,
      );
      return;
    }
    if (item == null ||
        item.quantity <= 0 ||
        item.branchId == null ||
        quantity == null ||
        quantity <= 0 ||
        price == null ||
        cost == null) {
      _showFeedback('Choose an item and enter a valid quantity.',
          _SalesFeedbackTone.error);
      return;
    }
    if (quantity > item.quantity) {
      _showFeedback(
        'Only ${_quantity(item.quantity)} ${item.unit} are in stock.',
        _SalesFeedbackTone.error,
      );
      return;
    }

    final confirmed = await _confirmSale(item, quantity, price, cost);
    if (!mounted) return;
    if (!confirmed) {
      _showFeedback(
          'Sale cancelled. No inventory was changed.', _SalesFeedbackTone.info);
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      final saleReference =
          'SALE-MOB-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final response = await widget.client.post(
        '/api/inventory/${item.id}/sell',
        body: {
          'quantity': quantity,
          'expectedSellingPrice': price,
          'expectedUnitCost': cost,
          'reference': saleReference,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response.body, response.statusCode);
      }
      if (!mounted) return;
      final saleResult = _tryDecodeJson(response.body);
      final saleData = saleResult is Map<String, dynamic>
          ? saleResult
          : const <String, dynamic>{};
      final saleAmount =
          (saleData['amount'] as num?)?.toDouble() ?? quantity * price;
      final grossProfit = (saleData['grossProfit'] as num?)?.toDouble() ??
          quantity * (price - cost);
      final occurredAt = DateTime.tryParse(
            saleData['occurredAt'] as String? ?? '',
          ) ??
          DateTime.now();
      final receipt = SaleReceipt(
        reference: saleData['reference'] as String? ?? saleReference,
        itemName: saleData['itemName'] as String? ?? item.name,
        sku: item.sku,
        branch: item.branch,
        quantity: (saleData['quantity'] as num?)?.toDouble() ?? quantity,
        unit: item.unit,
        unitPrice: (saleData['unitPrice'] as num?)?.toDouble() ?? price,
        total: saleAmount,
        occurredAt: occurredAt,
        remainingQuantity:
            (saleData['remainingQuantity'] as num?)?.toDouble() ??
                item.quantity - quantity,
        reorderLevel: item.reorderLevel,
      );
      _quantityController.text = '1';
      _showFeedback(
        'Sale recorded successfully: ${_quantity(quantity)} ${item.unit} '
        '${item.name} for LKR ${_money(price)} each '
        '(total LKR ${_money(saleAmount)}, gross profit '
        'LKR ${_money(grossProfit)}). Inventory stock was updated.',
        _SalesFeedbackTone.success,
      );
      await _load();
      if (mounted) {
        setState(() => _saving = false);
        await showDialog<void>(
          context: context,
          builder: (_) => SaleReceiptDialog(receipt: receipt),
        );
      }
    } catch (error) {
      if (mounted) {
        _showFeedback(
          'Sale failed: ${_messageFromError(error)}',
          _SalesFeedbackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmSale(
    InventoryItem item,
    double quantity,
    double unitPrice,
    double unitCost,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: const Key('sale-confirmation-dialog'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.bgMid, AppColors.overlaySurface],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withValues(alpha: .15),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: AppColors.cyan,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm sale',
                      style: AppTextStyles.subtitle.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Record ${_quantity(quantity)} ${item.unit} of ${item.name} '
                'at LKR ${_money(unitPrice)} each?',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.glassFill,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Column(
                  children: [
                    _confirmationDetail(
                      'Sale total',
                      'LKR ${_money(quantity * unitPrice)}',
                      valueColor: AppColors.cyan,
                    ),
                    const SizedBox(height: 9),
                    _confirmationDetail(
                      'Estimated gross profit',
                      'LKR ${_money(quantity * (unitPrice - unitCost))}',
                      valueColor: AppColors.success,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 11),
                      child: Divider(height: 1, color: AppColors.hairline),
                    ),
                    _confirmationDetail(
                      'Remaining stock',
                      '${_quantity(item.quantity - quantity)} ${item.unit}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Cancel',
                      expand: false,
                      height: 48,
                      onPressed: () => Navigator.pop(dialogContext, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeonButton(
                      label: 'Confirm sale',
                      expand: false,
                      height: 48,
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.pop(dialogContext, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return confirmed ?? false;
  }

  Widget _confirmationDetail(
    String label,
    String value, {
    Color valueColor = AppColors.textPrimary,
  }) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextStyles.body.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );

  String _quantity(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  String _money(double value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final maxRevenue = _days.fold<double>(
      0,
      (max, day) => max > day.amount ? max : day.amount,
    );
    return AppBackgroundScaffold(
      showParticles: false,
      appBar: GlassAppBar(
        title: 'Sales',
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(showRefreshFeedback: true),
            tooltip: 'Refresh sales',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: () => _load(showRefreshFeedback: true),
        color: AppColors.cyan,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
            16,
            32,
          ),
          children: [
            _buildSaleForm(),
            const SizedBox(height: 24),
            _sectionHeading(
              Icons.receipt_long_rounded,
              'Recent sales & receipts',
              'Your latest saved sales. Tap one to view or share its receipt.',
            ),
            const SizedBox(height: 10),
            _buildRecentSales(),
            const SizedBox(height: 24),
            _sectionHeading(Icons.show_chart_rounded, 'Sales performance',
                'Sales revenue and gross profit from the last $_periodDays days.'),
            const SizedBox(height: 10),
            _buildRevenueChart(maxRevenue),
            const SizedBox(height: 14),
            Row(
              children: [
                _periodButton(7),
                const SizedBox(width: 8),
                _periodButton(30),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(IconData icon, String title, String subtitle) => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.violet, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: AppTextStyles.subtitle
                      .copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted, fontSize: 10)),
            ]),
          ),
        ],
      );

  Widget _buildSaleForm() => InventoryPanel(
        padding: const EdgeInsets.all(15),
        borderColor: AppColors.violet.withValues(alpha: .28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: const Key('sales-form-header'),
              child: _sectionHeading(
                Icons.add_shopping_cart_rounded,
                'Record a sale',
                'Choose an item; stock updates when saved.',
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: const ValueKey('sale-saving-status'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: .24),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cyan,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recording sale — please wait…',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<InventoryItem>(
              key: ValueKey(_inventoryRevision),
              initialValue: _selectedItem,
              isExpanded: true,
              dropdownColor: AppColors.bgMid,
              selectedItemBuilder: (context) => _availableItems
                  .map((item) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${item.name} · ${item.sku}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.textPrimary),
                        ),
                      ))
                  .toList(),
              decoration: _inputDecoration(
                  'Inventory item', Icons.inventory_2_outlined),
              items: _availableItems
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.name,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.textPrimary)),
                            Text(
                              '${item.sku} · ${_quantity(item.quantity)} ${item.unit} available · ${item.branch}',
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textMuted, fontSize: 9),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: _saving ||
                      _loading ||
                      !_inventoryLoaded ||
                      _availableItems.isEmpty
                  ? null
                  : (item) {
                      setState(() {
                        _selectedItem = item;
                      });
                    },
            ),
            if (_inventoryLoaded && _availableItems.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _items.any((item) => item.quantity > 0)
                    ? 'Stock exists, but each item must be assigned to a branch before it can be sold.'
                    : 'No stock is currently available to sell. Receive or adjust inventory, then refresh.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.warning, fontSize: 10),
              ),
            ],
            if (_selectedItem != null) ...[
              const SizedBox(height: 7),
              Text(
                'Available: ${_quantity(_selectedItem!.quantity)} ${_selectedItem!.unit} · ${_selectedItem!.branch}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        return RegExp(r'^\d*\.?\d{0,3}$')
                                .hasMatch(newValue.text)
                            ? newValue
                            : oldValue;
                      }),
                    ],
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                    decoration:
                        _inputDecoration('Quantity', Icons.numbers_rounded),
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildUnitPriceDisplay()),
              ],
            ),
            if (_selectedItem != null) ...[
              const SizedBox(height: 10),
              _buildSalePreview(),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ||
                        _loading ||
                        !_inventoryLoaded ||
                        _availableItems.isEmpty
                    ? null
                    : _recordSale,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.point_of_sale_rounded, size: 18),
                label: Text(_saving ? 'Saving sale…' : 'Record sale'),
              ),
            ),
          ],
        ),
      );

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        prefixIcon: Icon(icon, size: 18, color: AppColors.cyan),
        filled: true,
        fillColor: const Color(0xFF0D1728),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
      );

  Widget _buildUnitPriceDisplay() {
    final item = _selectedItem;
    return Container(
      key: const Key('sale-unit-price-display'),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1728),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            size: 18,
            color: AppColors.cyan,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELLING PRICE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 8,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item == null
                      ? 'Select item'
                      : item.sellingPrice == null
                          ? 'Set price on web'
                          : 'LKR ${_money(item.sellingPrice!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: item == null
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalePreview() {
    final quantity = double.tryParse(_quantityController.text) ?? 0;
    final price = _selectedItem?.sellingPrice ?? 0;
    final cost = _selectedItem?.unitCost;
    final total = quantity * price;
    final profit = cost == null ? null : quantity * (price - cost);
    final remaining = (_selectedItem?.quantity ?? 0) - quantity;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.violet.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SALE TOTAL',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 8,
                      letterSpacing: .6,
                    )),
                const SizedBox(height: 3),
                Text('LKR ${_money(total)}',
                    style: AppTextStyles.subtitle.copyWith(
                      color: AppColors.violet,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Profit: ${profit == null ? 'Set cost on web' : 'LKR ${_money(profit)}'}',
                style: AppTextStyles.caption.copyWith(
                  color: profit == null ? AppColors.warning : AppColors.success,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'After sale: ${_quantity(remaining < 0 ? 0 : remaining)} ${_selectedItem!.unit}',
                style: AppTextStyles.caption.copyWith(
                  color: remaining < 0
                      ? AppColors.danger
                      : AppColors.textSecondary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(double maxRevenue) {
    if (_loading) {
      return _buildSalesLoadingPanel();
    }
    final chartDays = _days;
    final labelIndices = _periodDays <= 7
        ? List<int>.generate(chartDays.length, (index) => index)
        : <int>[
            for (var index = 0; index < chartDays.length; index += 5) index,
            if (chartDays.isNotEmpty && (chartDays.length - 1) % 5 != 0)
              chartDays.length - 1,
          ];
    return InventoryPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LKR ${_money(_totalRevenue)}',
              style: AppTextStyles.headlineSmall.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              )),
          Text('Total revenue · $_periodDays days',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              )),
          Text(
            _grossProfit == null
                ? 'Gross profit unavailable until all sold items have unit costs.'
                : 'Gross profit · LKR ${_money(_grossProfit!)}',
            style: AppTextStyles.caption.copyWith(
              color:
                  _grossProfit == null ? AppColors.warning : AppColors.success,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _chartStat(
                  'ACTIVE DAYS',
                  '${_days.where((day) => day.amount > 0).length}',
                  Icons.event_available_outlined,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _chartStat(
                  'BEST DAY',
                  _days.isEmpty
                      ? '—'
                      : 'LKR ${_money(_days.fold<double>(0, (best, day) => best > day.amount ? best : day.amount))}',
                  Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (_days.isEmpty || maxRevenue <= 0)
            SizedBox(
              height: 95,
              child: Center(
                child: Text('No sales recorded in this period yet.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted)),
              ),
            )
          else
            SizedBox(
              height: 130,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      key: const Key('sales-chart-bars'),
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: chartDays.map((day) {
                        final factor =
                            (day.amount / maxRevenue).clamp(.04, 1.0);
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _periodDays > 7 ? .75 : 2,
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: day.amount <= 0 ? .025 : factor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.violet.withValues(
                                      alpha: day.amount > 0 ? .9 : .14,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    key: const Key('sales-chart-date-labels'),
                    height: 14,
                    child: Row(
                      children: labelIndices.map((index) {
                        return Expanded(
                          child: Align(
                            alignment: index == 0
                                ? Alignment.centerLeft
                                : index == labelIndices.last
                                    ? Alignment.centerRight
                                    : Alignment.center,
                            child: Text(
                              chartDays[index].label,
                              key: Key('sales-chart-date-$index'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSalesLoadingPanel() => InventoryPanel(
        key: const Key('sales-loading-panel'),
        padding: const EdgeInsets.all(22),
        child: SizedBox(
          height: 236,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Column(
                key: ValueKey(
                    _hasLoadedOnce ? 'updating-sales' : 'loading-sales'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      backgroundColor: AppColors.violet.withValues(alpha: .16),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _hasLoadedOnce ? 'Updating sales…' : 'Loading sales…',
                    key: const Key('sales-loading-message'),
                    style: AppTextStyles.subtitle.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please wait while we refresh your inventory and sales data.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildRecentSales() {
    if (_loading) {
      return InventoryPanel(
        key: const Key('recent-sales-loading'),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.cyan,
              ),
            ),
            const SizedBox(width: 11),
            Text(
              'Loading recent sales…',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    if (_recentSales.isEmpty) {
      return InventoryPanel(
        key: const Key('recent-sales-empty'),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No sales recorded in the last $_periodDays days.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return InventoryPanel(
      key: const Key('recent-sales-list'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < _recentSales.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: AppColors.hairline),
            _recentSaleTile(_recentSales[index]),
          ],
        ],
      ),
    );
  }

  Widget _recentSaleTile(_RecentSale sale) {
    final itemSummary =
        sale.items.isEmpty ? 'Inventory sale' : sale.items.join(', ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('recent-sale-${sale.reference}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showHistoricalReceipt(sale),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_outlined,
                  color: AppColors.cyan,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sale.reference} · ${_dateTime(sale.occurredAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                    if (sale.grossProfit != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Gross profit · LKR ${_money(sale.grossProfit!)}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.success,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LKR ${_money(sale.amount)}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistoricalReceipt(_RecentSale sale) async {
    final receipt = SaleReceipt(
      reference: sale.reference,
      itemName: sale.items.isEmpty ? 'Inventory sale' : sale.items.join(', '),
      branch: 'Not included in the sales report',
      quantity: sale.quantity,
      unit: '',
      total: sale.amount,
      occurredAt: sale.occurredAt,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => SaleReceiptDialog(receipt: receipt),
    );
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  Widget _periodButton(int days) {
    final selected = _periodDays == days;
    return OutlinedButton(
      onPressed: _loading || selected
          ? null
          : () {
              setState(() => _periodDays = days);
              _load();
            },
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? AppColors.cyan : AppColors.textSecondary,
        side: BorderSide(
            color: selected ? AppColors.cyan : AppColors.glassBorder),
      ),
      child: Text('$days days'),
    );
  }

  Widget _chartStat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.violet.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.violet.withValues(alpha: .16)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.violet),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.textMuted, fontSize: 7)),
                  const SizedBox(height: 2),
                  Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RevenueDay {
  const _RevenueDay(this.label, this.amount);
  final String label;
  final double amount;
}

class _RecentSale {
  const _RecentSale({
    required this.reference,
    required this.occurredAt,
    required this.amount,
    required this.quantity,
    required this.items,
    required this.grossProfit,
  });

  final String reference;
  final DateTime occurredAt;
  final double amount;
  final double quantity;
  final List<String> items;
  final double? grossProfit;

  factory _RecentSale.fromJson(Map<String, dynamic> json) => _RecentSale(
        reference: json['reference'] as String? ?? 'SALE',
        occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        items: (json['items'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        grossProfit: (json['grossProfit'] as num?)?.toDouble(),
      );
}
