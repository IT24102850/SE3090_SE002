import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.geocodingClient,
  }) : client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient client;
  final String? initialBranchId;
  final String? tenantId;
  final Future<bool> Function(String tenantId)? onJoinBusiness;
  final Dio? geocodingClient;

  @override
  State<CustomerShopScreen> createState() => _CustomerShopScreenState();
}

class _CustomerShopScreenState extends State<CustomerShopScreen> {
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationSearchController = TextEditingController();
  final _deliveryMapController = MapController();
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
  bool _capturingDeliveryLocation = false;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _deliveryLocationMessage;
  List<Map<String, dynamic>> _deliveryPlaceResults = [];
  String? _deliverySearchError;
  bool _searchingDeliveryPlace = false;
  bool _deliveryMapReady = false;
  int _deliverySearchRequestId = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _refreshingOrders = false;
  String? _orderRefreshError;
  Timer? _trackingTimer;
  Timer? _deliverySearchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _showOrders) unawaited(_refreshOrders());
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _deliverySearchDebounce?.cancel();
    _addressController.dispose();
    _notesController.dispose();
    _locationSearchController.dispose();
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
        _orderRefreshError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOrders() async {
    if (_refreshingOrders || _loading) return;
    _refreshingOrders = true;
    try {
      final response = await widget.client.get('/customer-orders');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _responseError(
            response.body, 'Could not refresh your order tracking.');
      }
      final orders = _decodeList(response.body);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _orderRefreshError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _orderRefreshError =
            error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _refreshingOrders = false;
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
    if (_cart.isNotEmpty) {
      final shouldSwitch = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Switch business?'),
          content: const Text(
              'Your current basket will be cleared. Your memberships and order history stay saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep shopping'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Switch business'),
            ),
          ],
        ),
      );
      if (shouldSwitch != true || !mounted) return;
    }
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

  void _setDeliveryPin(
      double latitude, double longitude, StateSetter setSheetState) {
    setSheetState(() {
      _deliveryLatitude = latitude;
      _deliveryLongitude = longitude;
      _deliveryLocationMessage =
          'Pin selected. It will be shared with this business for this order only.';
      _deliveryPlaceResults = [];
      _deliverySearchError = null;
    });
    if (_deliveryMapReady) {
      _deliveryMapController.move(LatLng(latitude, longitude), 15);
    }
  }

  Future<void> _searchDeliveryPlaces(
      BuildContext sheetContext, StateSetter setSheetState) async {
    _deliverySearchDebounce?.cancel();
    final query = _locationSearchController.text.trim();
    if (query.length < 3) {
      setSheetState(() =>
          _deliverySearchError = 'Enter at least 3 characters to search.');
      return;
    }
    final requestId = ++_deliverySearchRequestId;
    setSheetState(() {
      _searchingDeliveryPlace = true;
      _deliverySearchError = null;
      _deliveryPlaceResults = [];
    });
    try {
      final response = await (widget.geocodingClient ?? Dio()).get<dynamic>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {'format': 'jsonv2', 'limit': 5, 'q': query},
        options: Options(
          headers: {'User-Agent': 'UnifySME/1.0 (customer delivery map)'},
          responseType: ResponseType.json,
        ),
      );
      if (response.data is! List) {
        throw const FormatException(
            'The place search returned an invalid response.');
      }
      final places = (response.data as List).whereType<Map>().map((place) {
        final latitude = double.tryParse(place['lat']?.toString() ?? '');
        final longitude = double.tryParse(place['lon']?.toString() ?? '');
        final label = place['display_name']?.toString();
        if (latitude == null ||
            longitude == null ||
            label == null ||
            label.isEmpty) {
          throw const FormatException(
              'The place search returned an invalid location.');
        }
        return <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'label': label,
        };
      }).toList();
      if (requestId != _deliverySearchRequestId ||
          !mounted ||
          !sheetContext.mounted) {
        return;
      }
      setSheetState(() {
        _deliveryPlaceResults = places;
        if (places.isEmpty) {
          _deliverySearchError =
              'No places found. Try a nearby town or landmark.';
        }
      });
    } on DioException {
      if (requestId == _deliverySearchRequestId &&
          mounted &&
          sheetContext.mounted) {
        setSheetState(() => _deliverySearchError =
            'Place search is unavailable right now. You can still tap the map to place a pin.');
      }
    } on FormatException catch (error) {
      if (requestId == _deliverySearchRequestId &&
          mounted &&
          sheetContext.mounted) {
        setSheetState(() => _deliverySearchError = error.message);
      }
    } finally {
      if (requestId == _deliverySearchRequestId &&
          mounted &&
          sheetContext.mounted) {
        setSheetState(() => _searchingDeliveryPlace = false);
      }
    }
  }

  Future<void> _captureDeliveryPin(
      BuildContext sheetContext, StateSetter setSheetState) async {
    if (_capturingDeliveryLocation) return;
    setSheetState(() {
      _capturingDeliveryLocation = true;
      _deliveryLocationMessage = null;
      _cartError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
            'Turn on location services or enter your address manually.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
            'Location permission was not granted. You can still enter your address manually.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted || !sheetContext.mounted) return;
      _setDeliveryPin(position.latitude, position.longitude, setSheetState);
    } catch (error) {
      if (!mounted || !sheetContext.mounted) return;
      setSheetState(() {
        _deliveryLocationMessage = error is StateError
            ? error.message.toString()
            : 'Could not get your location. Enter your address and try again.';
      });
    } finally {
      if (mounted && sheetContext.mounted) {
        setSheetState(() => _capturingDeliveryLocation = false);
      }
    }
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
                      Text(
                        'Optional: search or tap the map to place a delivery pin. It is shared with the business for this order only.',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _locationSearchController,
                              maxLength: 180,
                              decoration: InputDecoration(
                                counterText: '',
                                prefixIcon: const Icon(Icons.search_rounded),
                                labelText: 'Search a place or landmark',
                                hintText: 'Town, street or nearby place',
                                suffixIcon: _locationSearchController
                                        .text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear place search',
                                        onPressed: () {
                                          _deliverySearchDebounce?.cancel();
                                          _deliverySearchRequestId++;
                                          _locationSearchController.clear();
                                          setSheetState(() {
                                            _deliveryPlaceResults = [];
                                            _deliverySearchError = null;
                                            _searchingDeliveryPlace = false;
                                          });
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                              onChanged: (query) {
                                _deliverySearchDebounce?.cancel();
                                _deliverySearchRequestId++;
                                setSheetState(() {
                                  _deliveryPlaceResults = [];
                                  _deliverySearchError = null;
                                  _searchingDeliveryPlace = false;
                                });
                                if (query.trim().length >= 3) {
                                  _deliverySearchDebounce = Timer(
                                    const Duration(seconds: 1),
                                    () {
                                      if (context.mounted) {
                                        unawaited(_searchDeliveryPlaces(
                                            context, setSheetState));
                                      }
                                    },
                                  );
                                }
                              },
                              onSubmitted: (_) =>
                                  _searchDeliveryPlaces(context, setSheetState),
                            ),
                          ),
                          const SizedBox(width: 7),
                          IconButton.filledTonal(
                            tooltip: 'Search places',
                            onPressed: _searchingDeliveryPlace
                                ? null
                                : () => _searchDeliveryPlaces(
                                    context, setSheetState),
                            icon: _searchingDeliveryPlace
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.search_rounded),
                          ),
                        ],
                      ),
                      if (_deliverySearchError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _deliverySearchError!,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.error),
                        ),
                      ],
                      if (_searchingDeliveryPlace)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.violet.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 17,
                                height: 17,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 9),
                              Text('Finding places near you…',
                                  style: AppTextStyles.caption),
                              const Spacer(),
                              const SizedBox(
                                width: 40,
                                child: LinearProgressIndicator(),
                              ),
                            ],
                          ),
                        ),
                      if (_deliveryPlaceResults.isNotEmpty)
                        ..._deliveryPlaceResults.map((place) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.place_outlined,
                                  color: AppColors.cyan),
                              title: Text(
                                place['label'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption,
                              ),
                              onTap: () => _setDeliveryPin(
                                place['latitude'] as double,
                                place['longitude'] as double,
                                setSheetState,
                              ),
                            )),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 210,
                          child: FlutterMap(
                            mapController: _deliveryMapController,
                            options: MapOptions(
                              initialCenter: LatLng(
                                _deliveryLatitude ?? 6.9271,
                                _deliveryLongitude ?? 79.8612,
                              ),
                              initialZoom: _deliveryLatitude == null ? 13 : 15,
                              onMapReady: () => _deliveryMapReady = true,
                              onTap: (_, point) => _setDeliveryPin(
                                point.latitude,
                                point.longitude,
                                setSheetState,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.sme_mobile',
                              ),
                              if (_deliveryLatitude != null &&
                                  _deliveryLongitude != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: LatLng(
                                        _deliveryLatitude!,
                                        _deliveryLongitude!,
                                      ),
                                      width: 44,
                                      height: 52,
                                      child: const Icon(
                                        Icons.location_pin,
                                        size: 44,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                              RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution(
                                    'OpenStreetMap contributors',
                                    onTap: () => unawaited(launchUrl(
                                      Uri.parse(
                                          'https://www.openstreetmap.org/copyright'),
                                      mode: LaunchMode.externalApplication,
                                    )),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      OutlinedButton.icon(
                        onPressed: _capturingDeliveryLocation
                            ? null
                            : () => _captureDeliveryPin(context, setSheetState),
                        icon: _capturingDeliveryLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_deliveryLatitude == null
                                ? Icons.my_location_rounded
                                : Icons.location_on_rounded),
                        label: Text(_deliveryLatitude == null
                            ? '◎ Use my current location'
                            : 'Move map to my current location'),
                      ),
                      if (_deliveryLocationMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _deliveryLocationMessage!,
                          style: AppTextStyles.caption,
                        ),
                      ],
                      if (_deliveryLatitude != null)
                        Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: [
                            TextButton.icon(
                              onPressed: () => unawaited(launchUrl(
                                Uri.https('www.google.com', '/maps/search/', {
                                  'api': '1',
                                  'query':
                                      '$_deliveryLatitude,$_deliveryLongitude',
                                }),
                                mode: LaunchMode.externalApplication,
                              )),
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: const Text('Open in Google Maps'),
                            ),
                            TextButton(
                              onPressed: () => setSheetState(() {
                                _deliveryLatitude = null;
                                _deliveryLongitude = null;
                                _deliveryLocationMessage =
                                    'Delivery pin removed.';
                                _deliveryPlaceResults = [];
                              }),
                              child: const Text('Remove delivery pin'),
                            ),
                          ],
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
          'deliveryLatitude': _delivery ? _deliveryLatitude : null,
          'deliveryLongitude': _delivery ? _deliveryLongitude : null,
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
        _deliveryLatitude = null;
        _deliveryLongitude = null;
        _deliveryLocationMessage = null;
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
    final updates = (order['statusUpdates'] as List? ?? const [])
        .whereType<Map>()
        .map((update) => Map<String, dynamic>.from(update))
        .toList();
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
          if (updates.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Order journey', style: AppTextStyles.subtitle),
            const SizedBox(height: 8),
            ...updates.asMap().entries.map((entry) {
              final update = entry.value;
              final time =
                  DateTime.tryParse(update['createdAt'] as String? ?? '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry.key == updates.length - 1
                          ? Icons.radio_button_checked
                          : Icons.check_circle,
                      size: 18,
                      color: entry.key == updates.length - 1
                          ? AppColors.cyan
                          : AppColors.success,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(update['status'] as String? ?? 'Update',
                              style: AppTextStyles.body),
                          Text(update['message'] as String? ?? '',
                              style: AppTextStyles.caption),
                          if (time != null)
                            Text(
                              '${time.day}/${time.month}/${time.year} · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              style: AppTextStyles.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
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
          if (isDelivery &&
              order['deliveryLatitude'] is num &&
              order['deliveryLongitude'] is num)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final latitude =
                      (order['deliveryLatitude'] as num).toDouble();
                  final longitude =
                      (order['deliveryLongitude'] as num).toDouble();
                  final uri = Uri.https('www.google.com', '/maps/search/', {
                    'api': '1',
                    'query': '$latitude,$longitude',
                  });
                  if (!await launchUrl(uri,
                          mode: LaunchMode.externalApplication) &&
                      mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not open the map app.')),
                    );
                  }
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('View delivery pin'),
              ),
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
          IconButton(
            tooltip: 'Switch business',
            onPressed: _findBusiness,
            icon: const Icon(Icons.storefront_outlined),
          ),
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
                if (_orderRefreshError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Order updates paused: $_orderRefreshError. Pull down to retry.',
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
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

class _ShopHero extends StatefulWidget {
  const _ShopHero({required this.orderCount});

  final int orderCount;

  @override
  State<_ShopHero> createState() => _ShopHeroState();
}

class _ShopHeroState extends State<_ShopHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..forward();

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _glowController.isAnimating) _glowController.stop();
    final heroContent = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF38246F),
            AppColors.shopIndigo,
            AppColors.shopViolet,
            AppColors.shopRose
          ],
          stops: [0, .3, .68, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 11),
          ),
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -48,
            top: -80,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) => Transform.translate(
                offset: reduceMotion
                    ? Offset.zero
                    : Offset(
                        5 * _glowController.value,
                        8 * _glowController.value,
                      ),
                child: child,
              ),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1.2,
                  ),
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.025),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 34,
            bottom: -116,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A LITTLE SOMETHING FOR YOU',
                        style: AppTextStyles.label.copyWith(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.75),
                          letterSpacing: 1.2,
                        )),
                    const SizedBox(height: 8),
                    Text('Find your next favorite',
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontSize: 22,
                          color: Colors.white,
                        )),
                    const SizedBox(height: 5),
                    Text(
                      'Browse the collection, then pick up or get it delivered.',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 13),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        child: Text(
                          '${widget.orderCount} ${widget.orderCount == 1 ? 'order' : 'orders'} with us',
                          style: AppTextStyles.caption.copyWith(
                            color: const Color(0xFF8DF4F0),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) => Transform.translate(
                  offset: reduceMotion
                      ? Offset.zero
                      : Offset(0, -3 * _glowController.value),
                  child: child,
                ),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white.withValues(alpha: 0.18),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.38)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    size: 34,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (reduceMotion) return heroContent;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: heroContent,
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
