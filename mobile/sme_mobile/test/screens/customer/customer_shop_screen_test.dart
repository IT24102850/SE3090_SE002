import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/models/public_tenant_model.dart';
import 'package:sme_mobile/providers/public_tenant_provider.dart';
import 'package:sme_mobile/screens/customer/customer_shop_screen.dart';
import 'package:sme_mobile/services/push_notification_service.dart';
import 'package:sme_mobile/widgets/ui/glass_card.dart';

void main() {
  const branchId = 'branch-main';
  const itemId = 'item-tea';

  testWidgets('customer can build a basket and place a pickup order',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _CustomerShopApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: PushNotificationService.navigatorKey,
          home: CustomerShopScreen(
            client: AuthenticatedApiClient(dio: dio),
            initialBranchId: branchId,
            tenantId: 'tenant-main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fresh tea leaves'), findsOneWidget,
        reason: 'Observed API requests: ${adapter.requests}');
    expect(adapter.requests, contains('GET /branches?tenantId=tenant-main'));
    expect(find.byTooltip('Cart, 0 items'), findsOneWidget);
    await tester.tap(find.byTooltip('Cart, 0 items'));
    await tester.pumpAndSettle();
    expect(find.text('Your basket is waiting'), findsOneWidget);
    await tester.tap(find.text('Continue shopping'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add Fresh tea leaves to basket'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cart, 1 item'), findsOneWidget);
    await tester.tap(find.textContaining('Basket · 1'));
    await tester.pumpAndSettle();

    expect(find.text('Your basket'), findsOneWidget);
    await tester.ensureVisible(find.text('Place order'));
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect(adapter.createdOrder, isNotNull);
    expect(adapter.createdOrder!['branchId'], branchId);
    expect(adapter.createdOrder!['fulfillmentMethod'], 'Pickup');
    final items = adapter.createdOrder!['items'] as List<dynamic>;
    expect((items.single as Map)['inventoryItemId'], itemId);
    expect(find.text('My orders'), findsOneWidget);
    expect(find.text('Awaiting store confirmation · Step 1 of 5'),
        findsOneWidget);
    expect(find.text('All · 1'), findsOneWidget);
    await tester.ensureVisible(find.text('Completed · 0'));
    await tester.tap(find.text('Completed · 0'));
    await tester.pumpAndSettle();
    expect(find.text('No completed orders in your history.'), findsOneWidget);
    await tester.ensureVisible(find.text('In progress · 1'));
    await tester.tap(find.text('In progress · 1'));
    await tester.pumpAndSettle();
    expect(find.text('ORD-261002-ABCD1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('empty locations offer a way to find and join a business',
      (tester) async {
    const business = PublicTenant(
      id: 'business-1',
      businessName: 'Town Pantry',
      businessType: 'Retail',
    );
    final adapter = _CustomerShopApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    String? joinedTenantId;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicTenantsProvider.overrideWith((ref) async => [business]),
        ],
        child: MaterialApp(
          navigatorKey: PushNotificationService.navigatorKey,
          home: CustomerShopScreen(
            client: AuthenticatedApiClient(dio: dio),
            tenantId: 'customer-pool',
            onJoinBusiness: (tenantId) async {
              joinedTenantId = tenantId;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Your account is not connected to a store yet'),
        findsOneWidget);
    await tester.tap(find.text('Find a business'));
    await tester.pumpAndSettle();
    expect(find.text('Find a Business'), findsOneWidget);
    await tester.tap(
      find.ancestor(
        of: find.text('Town Pantry'),
        matching: find.byType(GlassCard),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop this business'));
    await tester.pumpAndSettle();

    expect(joinedTenantId, business.id);
    expect(adapter.requests, contains('GET /branches?tenantId=business-1'));
    expect(find.text('Fresh tea leaves'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('shopper can switch businesses after locations have loaded',
      (tester) async {
    const business = PublicTenant(
      id: 'business-2',
      businessName: 'Town Pantry',
      businessType: 'Retail',
    );
    final adapter = _CustomerShopApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    String? joinedTenantId;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicTenantsProvider.overrideWith((ref) async => [business]),
        ],
        child: MaterialApp(
          navigatorKey: PushNotificationService.navigatorKey,
          home: CustomerShopScreen(
            client: AuthenticatedApiClient(dio: dio),
            initialBranchId: branchId,
            tenantId: 'tenant-main',
            onJoinBusiness: (tenantId) async {
              joinedTenantId = tenantId;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh tea leaves'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch business'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Town Pantry'),
        matching: find.byType(GlassCard),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop this business'));
    await tester.pumpAndSettle();

    expect(joinedTenantId, business.id);
    expect(adapter.requests, contains('GET /branches?tenantId=business-2'));
    expect(find.text('Fresh tea leaves'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('delivery checkout shows a map and allows placing a GPS pin',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _CustomerShopApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    final geocodingDio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: PushNotificationService.navigatorKey,
          home: CustomerShopScreen(
            client: AuthenticatedApiClient(dio: dio),
            geocodingClient: geocodingDio,
            initialBranchId: branchId,
            tenantId: 'tenant-main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Fresh tea leaves to basket'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Basket · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deliver to me'));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Search a place or landmark'), findsOneWidget);
    await tester.enterText(
      find.ancestor(
        of: find.text('Search a place or landmark'),
        matching: find.byType(TextField),
      ),
      'Colombo',
    );
    expect(find.text('Colombo'), findsOneWidget);
    await tester.tap(find.byTooltip('Search places'));
    await tester.pumpAndSettle();
    expect(find.text('Colombo, Sri Lanka'), findsOneWidget,
        reason: 'Requests: ${adapter.requests}');
    await tester.tap(find.byTooltip('Clear place search'));
    await tester.pumpAndSettle();
    expect(find.text('Colombo, Sri Lanka'), findsNothing);
    await tester.enterText(
      find.ancestor(
        of: find.text('Search a place or landmark'),
        matching: find.byType(TextField),
      ),
      'Colombo',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Colombo, Sri Lanka'), findsOneWidget);
    await tester.tap(find.text('Colombo, Sri Lanka'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pin selected.'), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsOneWidget);
    await tester.enterText(
      find.ancestor(
        of: find.text('Delivery address'),
        matching: find.byType(TextField),
      ),
      '12 Main Road',
    );

    await tester.ensureVisible(find.text('Place order'));
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect(adapter.createdOrder?['deliveryLatitude'], isA<double>(),
        reason: 'Order body: ${adapter.createdOrder}');
    expect(adapter.createdOrder?['deliveryLongitude'], isA<double>());
    expect(tester.takeException(), isNull);
    dio.close();
    geocodingDio.close();
  });
}

class _CustomerShopApiAdapter implements HttpClientAdapter {
  Map<String, dynamic>? createdOrder;
  List<Map<String, dynamic>> orders = [];
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path.split('?').first;
    requests.add('${options.method} ${options.path}');
    Object response;
    var statusCode = 200;
    if (options.uri.host == 'nominatim.openstreetmap.org') {
      response = [
        {
          'place_id': 42,
          'lat': '6.9271',
          'lon': '79.8612',
          'display_name': 'Colombo, Sri Lanka',
        }
      ];
      return ResponseBody.fromString(
        jsonEncode(response),
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path.endsWith('/customer-orders/branches')) {
      statusCode = 404;
      response = {'message': 'Not found'};
    } else if (path.endsWith('/branches')) {
      response = options.path.contains('tenantId=customer-pool')
          ? []
          : [
              {'id': 'branch-main', 'name': 'Main store', 'address': 'Town'}
            ];
    } else if (path.endsWith('/tenant/public')) {
      response = [];
    } else if (path.endsWith('/customer-orders/products')) {
      response = [
        {
          'id': 'item-tea',
          'name': 'Fresh tea leaves',
          'description': 'A bright, fragrant blend.',
          'sku': 'TEA-01',
          'category': 'Pantry',
          'unit': 'pack',
          'quantityAvailable': 5,
          'price': 75,
        }
      ];
    } else if (path.endsWith('/customer-orders') && options.method == 'POST') {
      createdOrder = Map<String, dynamic>.from(options.data as Map);
      response = {
        'id': 'order-1',
        'number': 'ORD-261002-ABCD1234',
        'status': 'Pending',
        'paymentStatus': 'DueOnFulfillment',
        'fulfillmentMethod': 'Pickup',
        'deliveryAddress': null,
        'notes': null,
        'total': 75,
        'createdAt': '2026-10-02T08:00:00Z',
        'items': [
          {
            'inventoryItemId': 'item-tea',
            'itemName': 'Fresh tea leaves',
            'sku': 'TEA-01',
            'unit': 'pack',
            'quantity': 1,
            'unitPrice': 75,
            'lineTotal': 75,
          }
        ],
      };
      orders = [Map<String, dynamic>.from(response as Map)];
      statusCode = 201;
    } else if (path.endsWith('/customer-orders')) {
      response = orders;
    } else {
      response = {};
    }

    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
