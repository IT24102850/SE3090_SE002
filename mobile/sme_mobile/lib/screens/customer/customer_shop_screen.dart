import 'dart:convert';

import 'package:flutter/material.dart';

import '../../inventory/authenticated_api_client.dart';
import '../../models/public_tenant_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import 'book_business_list_screen.dart';

class CustomerShopScreen extends StatefulWidget {
  CustomerShopScreen({
    super.key,
    AuthenticatedApiClient? client,
    this.initialBranchId,
    this.tenantId,
    this.onJoinBusiness,
  }) : client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient client;
  final String? initialBranchId;
  final String? tenantId;
  final Future<bool> Function(String tenantId)? onJoinBusiness;

  @override
  State<CustomerShopScreen> createState() => _CustomerShopScreenState();
}

class _CustomerShopScreenState extends State<CustomerShopScreen> {
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  final Map<String, double> _cart = {};
  String? _branchId;
  String? _activeTenantId;
  String? _error;
  String? _cartError;
  String _category = 'All items';
  String _search = '';
  bool _showOrders = false;
  bool _delivery = false;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('The store returned an invalid list.');
    }
    return decoded.map((value) {
      if (value is! Map) {
        throw const FormatException('The store returned an invalid item.');
      }
      return Map<String, dynamic>.from(value);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var branchesResponse =
          await widget.client.get('/customer-orders/branches');
      final currentTenantId = _activeTenantId ?? widget.tenantId;
      if (branchesResponse.statusCode == 404 &&
          currentTenantId != null &&
          currentTenantId.isNotEmpty) {
        branchesResponse = await widget.client.get(
            '/branches?tenantId=${Uri.encodeQueryComponent(currentTenantId)}');
      }
      final ordersResponse = await widget.client.get('/customer-orders');
      if (branchesResponse.statusCode < 200 ||
          branchesResponse.statusCode >= 300) {
        throw _responseError(
            branchesResponse.body, 'Could not load store locations.');
      }
      if (ordersResponse.statusCode < 200 || ordersResponse.statusCode >= 300) {
        throw _responseError(
            ordersResponse.body, 'Could not load your orders.');
      }
      final branches = _decodeList(branchesResponse.body);
      final orders = _decodeList(ordersResponse.body);
      final branchStillAvailable =
          branches.any((branch) => branch['id'] == _branchId);
      final preferredBranch =
          branches.any((branch) => branch['id'] == widget.initialBranchId)
              ? widget.initialBranchId
              : null;
      final branchId = branchStillAvailable
          ? _branchId
          : preferredBranch ??
              (branches.isEmpty ? null : branches.first['id'] as String?);
      final products = branchId == null
          ? <Map<String, dynamic>>[]
          : await _fetchProducts(branchId);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _orders = orders;
        _branchId = branchId;
        _products = products;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchProducts(String branchId) async {
    final response =
        await widget.client.get('/customer-orders/products?branchId=$branchId');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _responseError(
          response.body, 'Could not load the product catalog.');
    }
    return _decodeList(response.body);
  }

  Exception _responseError(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return Exception(decoded['message'] as String);
      }
    } on FormatException {
      return Exception(fallback);
    }
    return Exception(fallback);
  }

  Future<void> _selectBranch(String? branchId) async {
    if (branchId == null || branchId == _branchId) return;
    setState(() {
      _branchId = branchId;
      _products = [];
      _cart.clear();
      _category = 'All items';
      _loading = true;
      _error = null;
    });
    try {
      final products = await _fetchProducts(branchId);
      if (mounted) setState(() => _products = products);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findBusiness() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BookBusinessListScreen(
          onBusinessSelected: _connectToBusiness,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<bool> _connectToBusiness(PublicTenant tenant) async {
    final joinBusiness = widget.onJoinBusiness;
    if (joinBusiness == null || !await joinBusiness(tenant.id) || !mounted) {
      return false;
    }
    setState(() {
      _activeTenantId = tenant.id;
      _branchId = null;
      _branches = [];
      _products = [];
      _cart.clear();
    });
    Navigator.of(context).pop();
    return true;
  }

  List<String> get _categories => [
        'All items',
        ..._products
            .map((product) =>
                product['category'] as String? ?? 'Everyday essentials')
            .toSet(),
      ];

  List<Map<String, dynamic>> get _visibleProducts {
    final query = _search.trim().toLowerCase();
    return _products.where((product) {
      final productCategory =
          product['category'] as String? ?? 'Everyday essentials';
      final searchable =
          '${product['name']} ${product['description'] ?? ''} ${product['sku']} $productCategory'
              .toLowerCase();
      return (_category == 'All items' || productCategory == _category) &&
          (query.isEmpty || searchable.contains(query));
    }).toList();
  }

  double get _cartTotal {
    var total = 0.0;
    for (final entry in _cart.entries) {
      final product =
          _firstOrNull(_products.where((item) => item['id'] == entry.key));
      if (product != null) {
        total += (product['price'] as num).toDouble() * entry.value;
      }
    }
    return total;
  }

  String _price(num amount) => 'LKR ${amount.toStringAsFixed(2)}';

  void _changeQuantity(Map<String, dynamic> product, double change) {
    final id = product['id'] as String;
    final available = (product['quantityAvailable'] as num).toDouble();
    final quantity = (_cart[id] ?? 0) + change;
    setState(() {
      if (quantity <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = quantity.clamp(0, available).toDouble();
      }
    });
  }

  Future<void> _openCart() async {
    setState(() => _cartError = null);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              22,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Your basket', style: AppTextStyles.headlineSmall),
                  const SizedBox(height: 4),
                  Text('A quick look at your lovely finds',
                      style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 14),
                  if (_cart.isEmpty) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Column(
                          children: [
                            const Icon(Icons.shopping_bag_outlined,
                                size: 42, color: AppColors.cyan),
                            const SizedBox(height: 10),
                            Text('Your basket is waiting',
                                style: AppTextStyles.subtitle),
                            const SizedBox(height: 4),
                            Text('Add something lovely from the shop.',
                                style: AppTextStyles.caption),
                            TextButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Continue shopping'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ..._cart.entries.map((entry) {
                      final product = _products
                          .firstWhere((item) => item['id'] == entry.key);
                      final price = (product['price'] as num).toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(product['name'] as String,
                                      style: AppTextStyles.subtitle),
                                  Text('${entry.value} × ${_price(price)}',
                                      style: AppTextStyles.caption),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove one ${product['name']}',
                              onPressed: () {
                                _changeQuantity(product, -1);
                                setSheetState(() {});
                              },
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: AppColors.textMuted),
                            ),
                            Text(entry.value.toString(),
                                style: AppTextStyles.subtitle),
                            IconButton(
                              tooltip: 'Add one ${product['name']}',
                              onPressed: entry.value >=
                                      (product['quantityAvailable'] as num)
                                          .toDouble()
                                  ? null
                                  : () {
                                      _changeQuantity(product, 1);
                                      setSheetState(() {});
                                    },
                              icon: const Icon(Icons.add_circle_outline,
                                  color: AppColors.cyan),
                            ),
                            Text(_price(price * entry.value),
                                style: AppTextStyles.subtitle),
                          ],
                        ),
                      );
                    }),
                    const Divider(color: AppColors.hairline, height: 22),
                    Text('Fulfilment', style: AppTextStyles.subtitle),
                    const SizedBox(height: 5),
                    RadioGroup<bool>(
                      groupValue: _delivery,
                      onChanged: (value) =>
                          setSheetState(() => _delivery = value ?? false),
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            value: false,
                            title: Text(
                                'Pick up at ${_firstOrNull(_branches.where((branch) => branch['id'] == _branchId))?['name'] ?? 'the store'}',
                                style: AppTextStyles.body),
                            activeColor: AppColors.cyan,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                          RadioListTile<bool>(
                            value: true,
                            title: Text('Deliver to me',
                                style: AppTextStyles.body),
                            activeColor: AppColors.cyan,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                    if (_delivery) ...[
                      TextField(
                        controller: _addressController,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Delivery address',
                          hintText: 'Street, town, and a helpful landmark',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _notesController,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'A note for the team (optional)',
                        hintText: 'Anything we should know?',
                      ),
                    ),
                    const SizedBox(height: 7),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_outlined,
                                color: AppColors.success, size: 19),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'No payment needed now. Pay at pickup or when your order is delivered.',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textBody),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_cartError != null) ...[
                      const SizedBox(height: 10),
                      Text(_cartError!,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.error)),
                    ],
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estimated total',
                                  style: AppTextStyles.caption),
                              Text(_price(_cartTotal),
                                  style: AppTextStyles.title
                                      .copyWith(color: AppColors.cyan)),
                            ],
                          ),
                        ),
                        NeonButton(
                          label: _submitting ? 'Placing…' : 'Place order',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: _submitting
                              ? null
                              : () => _placeOrder(sheetContext, setSheetState),
                          isLoading: _submitting,
                          expand: false,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder(
    BuildContext sheetContext,
    StateSetter setSheetState,
  ) async {
    if (_delivery && _addressController.text.trim().isEmpty) {
      setSheetState(() => _cartError = 'Please add a delivery address.');
      return;
    }
    if (_branchId == null) {
      setSheetState(
          () => _cartError = 'Choose a store location before ordering.');
      return;
    }
    setState(() {
      _submitting = true;
      _cartError = null;
    });
    setSheetState(() {});
    try {
      final response = await widget.client.post(
        '/customer-orders',
        body: {
          'branchId': _branchId,
          'fulfillmentMethod': _delivery ? 'Delivery' : 'Pickup',
          'deliveryAddress': _delivery ? _addressController.text.trim() : null,
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'items': _cart.entries
              .map((entry) => {
                    'inventoryItemId': entry.key,
                    'quantity': entry.value,
                  })
              .toList(),
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _responseError(response.body, 'Could not place your order.');
      }
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      setState(() {
        _cart.clear();
        _addressController.clear();
        _notesController.clear();
        _showOrders = true;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Your order is in! The business has been notified. Pay at pickup or delivery.')),
        );
      }
    } catch (error) {
      if (mounted && sheetContext.mounted) {
        setSheetState(() =>
            _cartError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        if (sheetContext.mounted) setSheetState(() {});
      }
    }
  }

  Widget _productCard(Map<String, dynamic> product, int index) {
    final id = product['id'] as String;
    final quantity = _cart[id] ?? 0;
    final available = (product['quantityAvailable'] as num).toDouble();
    final price = (product['price'] as num).toDouble();
    final name = product['name'] as String? ?? 'Item';
    final category = product['category'] as String? ?? 'Everyday essentials';
    return TweenAnimationBuilder<double>(
      key: ValueKey(id),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 280 + (index % 5) * 45),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: AppColors.glassFill,
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 82,
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x443F8CFF),
                    Color(0x447A4DFF),
                    Color(0x22FF2D95)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 5,
                    top: -11,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 68,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.overlaySurface.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        child: Text(category,
                            style:
                                AppTextStyles.caption.copyWith(fontSize: 10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle),
                  const SizedBox(height: 4),
                  Text(
                    product['description'] as String? ??
                        'A lovely $category pick, ready for you.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_price(price),
                                style: AppTextStyles.subtitle
                                    .copyWith(color: AppColors.cyan)),
                            Text(
                                '${product['unit'] == null ? '' : '/ ${product['unit']} · '}$available available',
                                style: AppTextStyles.caption
                                    .copyWith(fontSize: 10)),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: quantity > 0
                            ? _QuantityControl(
                                key: ValueKey('quantity-$id'),
                                quantity: quantity,
                                canAdd: quantity < available,
                                onRemove: () => _changeQuantity(product, -1),
                                onAdd: () => _changeQuantity(product, 1),
                              )
                            : IconButton.filledTonal(
                                key: ValueKey('add-$id'),
                                tooltip: 'Add $name to basket',
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      AppColors.cyan.withValues(alpha: 0.15),
                                  foregroundColor: AppColors.cyan,
                                ),
                                onPressed: () => _changeQuantity(
                                    product, available < 1 ? available : 1),
                                icon: const Icon(Icons.add_rounded),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final items = (order['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final created = DateTime.tryParse(order['createdAt'] as String? ?? '');
    final dateLabel = created == null
        ? ''
        : '${created.day}/${created.month}/${created.year} · ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final isDelivery = order['fulfillmentMethod'] == 'Delivery';
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order['number'] as String? ?? 'Your order',
                        style: AppTextStyles.subtitle),
                    Text(dateLabel, style: AppTextStyles.caption),
                  ],
                ),
              ),
              _OrderStatusChip(status: order['status'] as String? ?? 'Pending'),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('${item['quantity']} × ${item['itemName']}',
                            style: AppTextStyles.bodyMuted)),
                    Text(_price((item['lineTotal'] as num).toDouble()),
                        style: AppTextStyles.caption),
                  ],
                ),
              )),
          const Divider(color: AppColors.hairline, height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  isDelivery
                      ? 'Delivery · ${order['deliveryAddress'] ?? ''}'
                      : 'Pickup · pay when you collect',
                  style: AppTextStyles.caption,
                ),
              ),
              Text(_price((order['total'] as num).toDouble()),
                  style:
                      AppTextStyles.subtitle.copyWith(color: AppColors.cyan)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final cartCount =
        _cart.values.fold<double>(0, (total, quantity) => total + quantity);
    return AppBackgroundScaffold(
      appBar: GlassAppBar(
        title: 'Shop & orders',
        actions: [
          _CartAppBarAction(count: cartCount, onPressed: _openCart),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty || _showOrders
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: NeonButton(
                  label:
                      'Basket · ${cartCount.toStringAsFixed(cartCount % 1 == 0 ? 0 : 2)}  ·  ${_price(_cartTotal)}',
                  icon: Icons.shopping_bag_outlined,
                  onPressed: _openCart,
                ),
              ),
            ),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _ShopHero(orderCount: _orders.length),
              const SizedBox(height: 16),
              _ShopTabs(
                showOrders: _showOrders,
                orderCount: _orders.length,
                onChanged: (value) => setState(() => _showOrders = value),
              ),
              if (_showOrders) ...[
                const SizedBox(height: 16),
                if (_loading)
                  const AppLoader()
                else if (_error != null)
                  ErrorState(message: _error!, onRetry: _load)
                else if (_orders.isEmpty)
                  const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message:
                          'Your first order is waiting. Explore the shop to find something you love.')
                else
                  ..._orders.map(_orderCard),
              ] else ...[
                const SizedBox(height: 14),
                if (_error != null)
                  ErrorState(message: _error!, onRetry: _load)
                else if (_loading)
                  const AppLoader()
                else if (_branches.isEmpty)
                  Column(
                    children: [
                      const EmptyState(
                        icon: Icons.storefront_outlined,
                        message:
                            'Your account is not connected to a store yet, or this business has not added a shopping location.',
                      ),
                      const SizedBox(height: 14),
                      NeonButton(
                        label: 'Find a business',
                        icon: Icons.search_rounded,
                        onPressed: _findBusiness,
                      ),
                    ],
                  )
                else ...[
                  _StoreSelector(
                    branches: _branches,
                    branchId: _branchId,
                    onChanged: _selectBranch,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search the collection',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 7),
                      itemBuilder: (context, index) {
                        final value = categories[index];
                        return ChoiceChip(
                          label: Text(value),
                          selected: value == _category,
                          onSelected: (_) => setState(() => _category = value),
                          selectedColor: AppColors.cyan.withValues(alpha: 0.18),
                          backgroundColor: AppColors.glassFill,
                          labelStyle: AppTextStyles.caption.copyWith(
                            color: value == _category
                                ? AppColors.cyan
                                : AppColors.textMuted,
                          ),
                          side: BorderSide(
                              color: value == _category
                                  ? AppColors.cyan.withValues(alpha: 0.35)
                                  : AppColors.glassBorder),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_visibleProducts.isEmpty)
                    const EmptyState(
                        icon: Icons.search_off_rounded,
                        message:
                            'No items match that search. Try another word or category.')
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 700 ? 3 : 2;
                        return GridView.builder(
                          itemCount: _visibleProducts.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 320,
                          ),
                          itemBuilder: (context, index) =>
                              _productCard(_visibleProducts[index], index),
                        );
                      },
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CartAppBarAction extends StatelessWidget {
  const _CartAppBarAction({
    required this.count,
    required this.onPressed,
  });

  final double count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final countLabel = count.toStringAsFixed(count % 1 == 0 ? 0 : 2);
    return TweenAnimationBuilder<double>(
      key: ValueKey(countLabel),
      tween: Tween(begin: 0.82, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: IconButton(
        tooltip: 'Cart, $countLabel ${count == 1 ? 'item' : 'items'}',
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.shopping_bag_outlined),
            Positioned(
              right: -9,
              top: -8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.overlaySurface,
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(
                      countLabel,
                      key: ValueKey(countLabel),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.onPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _ShopHero extends StatelessWidget {
  const _ShopHero({required this.orderCount});

  final int orderCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            AppColors.shopIndigo,
            AppColors.shopViolet,
            AppColors.shopRose
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
              color: AppColors.violet.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 9)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A LITTLE SOMETHING FOR YOU',
                    style: AppTextStyles.label.copyWith(fontSize: 9)),
                const SizedBox(height: 7),
                Text('Find your next favorite',
                    style: AppTextStyles.headlineSmall.copyWith(fontSize: 21)),
                const SizedBox(height: 5),
                Text('Browse the collection, then pick up or get it delivered.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textBody)),
                const SizedBox(height: 12),
                Text(
                    '$orderCount ${orderCount == 1 ? 'order' : 'orders'} with us',
                    style:
                        AppTextStyles.caption.copyWith(color: AppColors.cyan)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.shopping_bag_rounded,
              size: 54, color: Color(0xB3FFFFFF)),
        ],
      ),
    );
  }
}

class _ShopTabs extends StatelessWidget {
  const _ShopTabs(
      {required this.showOrders,
      required this.orderCount,
      required this.onChanged});

  final bool showOrders;
  final int orderCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          _ShopTab(
              label: 'Browse items',
              selected: !showOrders,
              onTap: () => onChanged(false)),
          _ShopTab(
              label: 'My orders ($orderCount)',
              selected: showOrders,
              onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _ShopTab extends StatelessWidget {
  const _ShopTab(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.cyan.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: TextButton(
          onPressed: onTap,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: selected ? AppColors.cyan : AppColors.textMuted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreSelector extends StatelessWidget {
  const _StoreSelector(
      {required this.branches,
      required this.branchId,
      required this.onChanged});

  final List<Map<String, dynamic>> branches;
  final String? branchId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 20, color: AppColors.cyan),
        const SizedBox(width: 8),
        Expanded(child: Text('Shopping at', style: AppTextStyles.caption)),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButtonFormField<String>(
            initialValue: branchId,
            isExpanded: true,
            decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
            items: branches
                .map((branch) => DropdownMenuItem<String>(
                      value: branch['id'] as String,
                      child: Text(branch['name'] as String? ?? 'Store',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    super.key,
    required this.quantity,
    required this.canAdd,
    required this.onRemove,
    required this.onAdd,
  });

  final double quantity;
  final bool canAdd;
  final VoidCallback onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove one',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline,
              color: AppColors.textMuted, size: 20),
        ),
        Text(quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2),
            style: AppTextStyles.caption),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Add one',
          onPressed: canAdd ? onAdd : null,
          icon: const Icon(Icons.add_circle_outline,
              color: AppColors.cyan, size: 20),
        ),
      ],
    );
  }
}

class _OrderStatusChip extends StatelessWidget {
  const _OrderStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final pending = status.toLowerCase() == 'pending';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (pending ? AppColors.warning : AppColors.success)
            .withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (pending ? AppColors.warning : AppColors.success)
                .withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          status,
          style: AppTextStyles.caption.copyWith(
            fontSize: 10,
            color: pending ? AppColors.warning : AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}
