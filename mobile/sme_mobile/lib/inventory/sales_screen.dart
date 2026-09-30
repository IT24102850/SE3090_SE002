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
  final _itemSearchController = TextEditingController();
  List<InventoryItem> _items = const [];
  List<_SalesBranch> _branches = const [];
  List<_RecentSale> _recentSales = const [];
  InventoryItem? _selectedItem;
  String _selectedBranchId = '';
  bool _loading = true;
  bool _saving = false;
  bool _inventoryLoaded = false;
  bool _itemPickerExpanded = false;
  String? _loadError;
  int _loadGeneration = 0;

  List<InventoryItem> get _availableItems => _items
      .where((item) =>
          item.quantity > 0 &&
          item.branchId != null &&
          _selectedBranchId.isNotEmpty &&
          item.branchId == _selectedBranchId)
      .toList();

  List<InventoryItem> get _matchingAvailableItems {
    final query = _itemSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _availableItems;

    final terms = query.split(RegExp(r'\s+'));
    final matches = <({InventoryItem item, int score})>[];
    for (final item in _availableItems) {
      final name = item.name.toLowerCase();
      final sku = item.sku.toLowerCase();
      final searchable =
          '${item.name} ${item.sku} ${item.category} ${item.branch} ${item.unit}'
              .toLowerCase();
      if (!terms.every(searchable.contains)) continue;

      final score = sku == query
          ? 0
          : name == query
              ? 1
              : sku.startsWith(query)
                  ? 2
                  : name.startsWith(query)
                      ? 3
                      : 4;
      matches.add((item: item, score: score));
    }
    matches.sort((a, b) => a.score.compareTo(b.score));
    return matches.map((match) => match.item).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  void _selectItem(InventoryItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedItem = item;
      _itemPickerExpanded = false;
      _itemSearchController.text = '${item.name} · ${item.sku}';
    });
    FocusScope.of(context).unfocus();
  }

  Widget _buildItemPicker() {
    final canSearch =
        !_saving && !_loading && _inventoryLoaded && _availableItems.isNotEmpty;
    final matches = _matchingAvailableItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('sale-item-search-field'),
          controller: _itemSearchController,
          enabled: canSearch,
          textInputAction: TextInputAction.search,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          decoration: _inputDecoration(
            'Search item, SKU, category or branch',
            Icons.search_rounded,
          ).copyWith(
            suffixIcon: IconButton(
              tooltip: _itemPickerExpanded ? 'Close item list' : 'Browse items',
              onPressed: canSearch
                  ? () {
                      setState(() {
                        _itemPickerExpanded = !_itemPickerExpanded;
                        if (_itemPickerExpanded) {
                          _itemSearchController.clear();
                        } else if (_selectedItem != null) {
                          _itemSearchController.text =
                              '${_selectedItem!.name} · ${_selectedItem!.sku}';
                        }
                      });
                    }
                  : null,
              icon: Icon(
                _itemPickerExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.textMuted,
              ),
            ),
          ),
          onTap: canSearch
              ? () => setState(() => _itemPickerExpanded = true)
              : null,
          onChanged: canSearch
              ? (_) => setState(() => _itemPickerExpanded = true)
              : null,
        ),
        if (canSearch)
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _itemPickerExpanded
                ? Padding(
                    key: const ValueKey('sale-picker-open'),
                    padding: const EdgeInsets.only(top: 7),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Container(
                        key: ValueKey(
                            'sale-item-search-${matches.isEmpty ? 'empty' : 'results'}'),
                        constraints: const BoxConstraints(maxHeight: 270),
                        decoration: BoxDecoration(
                          color: AppColors.bgMid,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: matches.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  'No matching in-stock items. Try another name, SKU, category or branch.',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textMuted,
                                    height: 1.4,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: matches.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                  color: AppColors.hairline,
                                ),
                                itemBuilder: (context, index) {
                                  final item = matches[index];
                                  return InkWell(
                                    key: Key('sale-item-option-${item.id}'),
                                    onTap: () => _selectItem(item),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: AppColors.cyan
                                                  .withValues(alpha: .1),
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                            child: const Icon(
                                              Icons.inventory_2_outlined,
                                              color: AppColors.cyan,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTextStyles.body
                                                      .copyWith(
                                                    color:
                                                        AppColors.textPrimary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${item.sku} · ${item.category} · ${item.branch}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                    color: AppColors.textMuted,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${_quantity(item.quantity)} ${item.unit} available'
                                                  '${item.sellingPrice == null ? ' · Price not set' : ' · LKR ${_money(item.sellingPrice!)}'}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                    color: item.sellingPrice ==
                                                            null
                                                        ? AppColors.warning
                                                        : AppColors
                                                            .textSecondary,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.textMuted,
                                            size: 19,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('sale-picker-closed'),
                  ),
          ),
      ],
    );
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
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _inventoryLoaded = false;
      _loadError = null;
    });
    try {
      final branchesResponse =
          await widget.client.get('/api/inventory/branches');
      if (branchesResponse.statusCode != 200) {
        throw _apiError(branchesResponse.body, branchesResponse.statusCode);
      }
      final branchData = jsonDecode(branchesResponse.body);
      if (branchData is! List) {
        throw const FormatException('Branch response has no branch list.');
      }
      final branches = branchData
          .whereType<Map<String, dynamic>>()
          .map(_SalesBranch.fromJson)
          .toList();
      if (!mounted || generation != _loadGeneration) return;
      final selectedBranchId = branches.any(
        (branch) => branch.id == _selectedBranchId,
      )
          ? _selectedBranchId
          : branches.length == 1
              ? branches.single.id
              : '';
      setState(() {
        _branches = branches;
        _selectedBranchId = selectedBranchId;
      });

      if (selectedBranchId.isEmpty) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _items = const [];
          _recentSales = const [];
          _selectedItem = null;
          _inventoryLoaded = false;
          _loading = false;
        });
        return;
      }

      final items = <InventoryItem>[];
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages) {
        final inventoryQuery = <String, String>{
          'page': '$page',
          'pageSize': '100',
          'branchId': selectedBranchId,
        };
        final response = await widget.client.get(
            '/api/inventory?${Uri(queryParameters: inventoryQuery).query}');
        if (response.statusCode != 200) {
          throw _apiError(response.body, response.statusCode);
        }
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        totalPages = (payload['totalPages'] as num?)?.toInt() ?? 1;
        items.addAll(((payload['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InventoryItem.fromJson));
        page++;
        if (generation != _loadGeneration) return;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = items;
        _inventoryLoaded = true;
        _selectedItem = _selectedItem == null
            ? null
            : items
                .where((item) =>
                    item.id == _selectedItem!.id &&
                    item.quantity > 0 &&
                    item.branchId != null)
                .firstOrNull;
        _itemSearchController.text = _selectedItem == null
            ? ''
            : '${_selectedItem!.name} · ${_selectedItem!.sku}';
        _itemPickerExpanded = false;
      });

      final now = DateTime.now().toUtc();
      final to = DateTime.utc(now.year, now.month, now.day);
      final from = to.subtract(const Duration(days: 29));
      final activityQuery = <String, String>{
        'branchId': selectedBranchId,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'page': '1',
        'pageSize': '10',
      };
      final query = Uri(queryParameters: activityQuery).query;
      final activity =
          await widget.client.get('/api/reports/sales-activity?$query');
      if (activity.statusCode != 200) {
        throw _apiError(activity.body, activity.statusCode);
      }
      final activityData = jsonDecode(activity.body) as Map<String, dynamic>;
      final recentSales = ((activityData['recentSales'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_RecentSale.fromJson)
          .toList();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _recentSales = recentSales;
        _loading = false;
      });
      if (showRefreshFeedback) {
        _showFeedback('Sales and inventory refreshed successfully.',
            _SalesFeedbackTone.success);
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      final message = _messageFromError(error);
      setState(() {
        _loading = false;
        _loadError = message;
      });
      if (showRefreshFeedback) {
        _showFeedback(
          'Refresh failed: $message',
          _SalesFeedbackTone.error,
        );
      }
    }
  }

  void _changeBranch(String? branchId) {
    if (branchId == null || branchId == _selectedBranchId) return;
    setState(() {
      _selectedBranchId = branchId;
      _selectedItem = null;
      _itemSearchController.clear();
      _quantityController.text = '1';
      _itemPickerExpanded = false;
    });
    _load();
  }

  String get _selectedBranchName =>
      _branches
          .where((branch) => branch.id == _selectedBranchId)
          .map((branch) => branch.name)
          .firstOrNull ??
      'selected branch';

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
            _sectionHeading(
              Icons.point_of_sale_rounded,
              'Branch sales',
              'Record a sale and review recent receipts for the selected branch.',
            ),
            const SizedBox(height: 14),
            if (_loadError != null) ...[
              const SizedBox(height: 2),
              _buildBranchErrorPanel(),
            ],
            _buildSaleForm(),
            const SizedBox(height: 24),
            _sectionHeading(
              Icons.receipt_long_rounded,
              'Recent sales & receipts',
              'Your latest saved sales. Tap one to view or share its receipt.',
            ),
            const SizedBox(height: 10),
            _buildRecentSales(),
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

  Widget _buildBranchErrorPanel() => InventoryPanel(
        key: const Key('sales-load-error'),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.danger,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Could not load branch sales data',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _loadError ?? 'Please try again.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('sales-retry-load'),
                    onPressed: _loading
                        ? null
                        : () => _load(showRefreshFeedback: true),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Retry'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cyan,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildBranchPicker() => DropdownButtonFormField<String>(
        key: const Key('sales-branch-dropdown'),
        initialValue: _selectedBranchId,
        isExpanded: true,
        decoration: _inputDecoration('Sale branch', Icons.storefront_outlined),
        dropdownColor: AppColors.bgMid,
        style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
        items: [
          if (_branches.length != 1)
            const DropdownMenuItem(
              value: '',
              child: Text('Select a branch'),
            ),
          ..._branches.map(
            (branch) => DropdownMenuItem(
              value: branch.id,
              child: Text(branch.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged:
            _loading || _saving || _branches.length <= 1 ? null : _changeBranch,
      );

  Widget _buildBranchLoadingPanel({Key? key}) => InventoryPanel(
        key: key,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const _BranchFetchAnimation(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _branches.isEmpty && _selectedBranchId.isEmpty
                            ? 'Loading available branches…'
                            : 'Fetching $_selectedBranchName data…',
                        key: const Key('branch-fetch-loading-title'),
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Please wait while branch stock and sales are refreshed.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: AppColors.glassBorder,
                color: AppColors.cyan,
              ),
            ),
          ],
        ),
      );

  Widget _buildSelectBranchPrompt({Key? key}) => InventoryPanel(
        key: key,
        padding: const EdgeInsets.all(14),
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
                Icons.storefront_outlined,
                color: AppColors.cyan,
                size: 19,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                _branches.isEmpty
                    ? 'No branches are available for sales.'
                    : 'Select a branch to fetch its stock and sales data.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSaleForm() => InventoryPanel(
        padding: const EdgeInsets.all(15),
        borderColor: AppColors.violet.withValues(alpha: .28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedBranchId.isEmpty && !_loading) ...[
              _buildSelectBranchPrompt(
                key: const Key('sales-select-branch-prompt'),
              ),
              const SizedBox(height: 12),
            ],
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
            _buildBranchPicker(),
            const SizedBox(height: 12),
            if (_loading)
              _buildBranchLoadingPanel(
                key: const Key('branch-fetch-loading-panel'),
              )
            else if (_loadError != null && !_inventoryLoaded)
              const SizedBox.shrink()
            else if (_selectedBranchId.isEmpty)
              const SizedBox.shrink()
            else ...[
              _buildItemPicker(),
              if (_inventoryLoaded && _availableItems.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _items.any((item) => item.quantity > 0)
                      ? 'No sellable stock is assigned to this branch.'
                      : 'No stock is currently available at this branch. Receive or adjust inventory, then refresh.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.warning, fontSize: 10),
                ),
              ],
              if (_selectedItem != null) ...[
                const SizedBox(height: 7),
                Text(
                  'Available: ${_quantity(_selectedItem!.quantity)} ${_selectedItem!.unit} · ${_selectedItem!.branch}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('sale-quantity-field'),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .15),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    'LKR ${_money(total)}',
                    key: ValueKey(total),
                    style: AppTextStyles.subtitle.copyWith(
                      color: AppColors.violet,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  'Profit: ${profit == null ? 'Set cost on web' : 'LKR ${_money(profit)}'}',
                  key: ValueKey(profit),
                  style: AppTextStyles.caption.copyWith(
                    color:
                        profit == null ? AppColors.warning : AppColors.success,
                    fontSize: 9,
                  ),
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

  Widget _buildRecentSales() {
    if (_loading) {
      return _buildBranchLoadingPanel(
        key: const Key('recent-sales-loading'),
      );
    }
    if (_loadError != null) {
      return const SizedBox.shrink();
    }
    if (_selectedBranchId.isEmpty) {
      return _buildSelectBranchPrompt(
        key: const Key('recent-sales-select-branch-prompt'),
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
                'No recent sales were found for this branch.',
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
      branch: 'Branch details unavailable',
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

}

class _SalesBranch {
  const _SalesBranch({required this.id, required this.name});

  final String id;
  final String name;

  factory _SalesBranch.fromJson(Map<String, dynamic> json) => _SalesBranch(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class _BranchFetchAnimation extends StatefulWidget {
  const _BranchFetchAnimation({required this.size});

  final double size;

  @override
  State<_BranchFetchAnimation> createState() => _BranchFetchAnimationState();
}

class _BranchFetchAnimationState extends State<_BranchFetchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pulse = .88 + (_controller.value * .12);
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: widget.size * .78,
                    height: widget.size * .78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cyan.withValues(
                        alpha: .08 + (_controller.value * .06),
                      ),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: .24),
                      ),
                    ),
                  ),
                ),
                RotationTransition(
                  turns: Tween<double>(begin: -.012, end: .012).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: widget.size * .42,
                    color: AppColors.cyan,
                  ),
                ),
                Positioned(
                  right: widget.size * .08,
                  bottom: widget.size * .13,
                  child: _fetchDot(.0, .55),
                ),
                Positioned(
                  right: widget.size * .22,
                  bottom: widget.size * .035,
                  child: _fetchDot(.22, .77),
                ),
                Positioned(
                  right: widget.size * .4,
                  bottom: widget.size * .025,
                  child: _fetchDot(.44, .99),
                ),
              ],
            );
          },
        ),
      );

  Widget _fetchDot(double begin, double end) => Opacity(
        opacity: CurvedAnimation(
          parent: _controller,
          curve: Interval(begin, end, curve: Curves.easeInOut),
        ).value,
        child: Container(
          width: widget.size * .09,
          height: widget.size * .09,
          decoration: const BoxDecoration(
            color: AppColors.violet,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _RecentSale {
  const _RecentSale({
    required this.reference,
    required this.occurredAt,
    required this.amount,
    required this.quantity,
    required this.items,
  });

  final String reference;
  final DateTime occurredAt;
  final double amount;
  final double quantity;
  final List<String> items;

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
      );
}
