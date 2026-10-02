import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/screens/customer/customer_shop_screen.dart';
import 'package:sme_mobile/services/push_notification_service.dart';

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
      MaterialApp(
        navigatorKey: PushNotificationService.navigatorKey,
        home: CustomerShopScreen(
          client: AuthenticatedApiClient(dio: dio),
          initialBranchId: branchId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fresh tea leaves'), findsOneWidget,
        reason: 'Observed API requests: ${adapter.requests}');
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
    expect(find.text('ORD-261002-ABCD1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
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
    if (path.endsWith('/customer-orders/branches')) {
      response = [
        {'id': 'branch-main', 'name': 'Main store', 'address': 'Town'}
      ];
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
