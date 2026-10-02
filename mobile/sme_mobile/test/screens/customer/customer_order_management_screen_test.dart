import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/services/push_notification_service.dart';
import 'package:sme_mobile/screens/customer/customer_order_management_screen.dart';

void main() {
  testWidgets('admin can progress an order and refreshes status counts',
      (tester) async {
    final adapter = _ManagedOrdersAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      home: CustomerOrderManagementScreen(
        client: AuthenticatedApiClient(dio: dio),
      ),
    ));
    await tester.pumpAndSettle();

    expect(adapter.requests, contains('GET /customer-orders/manage'));
    expect(find.text('ORD-1001'), findsOneWidget);
    expect(find.text('1 total · 1 open · 0 completed'), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);
    expect(find.text('Central branch'), findsOneWidget);

    await tester.tap(find.text('Confirmed'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(adapter.updatedStatus, 'Confirmed');
    expect(
      adapter.requests,
      contains('PUT /customer-orders/manage/order-1/status'),
    );
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('1 total · 1 open · 0 completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('cancelling explains stock restoration and asks for confirmation',
      (tester) async {
    final adapter = _ManagedOrdersAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      home: CustomerOrderManagementScreen(
        client: AuthenticatedApiClient(dio: dio),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('reserved stock will be returned'), findsOneWidget);
    expect(adapter.lastUpdatedStatus, isNull);

    await tester.tap(find.text('Keep order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(adapter.lastUpdatedStatus, 'Cancelled');
    expect(adapter.updatedStatus, 'Cancelled');
    expect(tester.takeException(), isNull);
    dio.close();
  });
}

class _ManagedOrdersAdapter implements HttpClientAdapter {
  final List<String> requests = [];
  String updatedStatus = 'Pending';
  String? lastUpdatedStatus;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    requests.add('${options.method} $path');
    Object response;
    var statusCode = 200;
    if (path == '/customer-orders/manage' && options.method == 'GET') {
      response = [_managedOrder()];
    } else if (path == '/customer-orders/manage/order-1/status' &&
        options.method == 'PUT') {
      final requestBody = options.data is String
          ? jsonDecode(options.data as String) as Map
          : options.data as Map;
      lastUpdatedStatus = requestBody['status']?.toString();
      updatedStatus = lastUpdatedStatus ?? updatedStatus;
      response = {
        'orderId': 'order-1',
        'number': 'ORD-1001',
        'status': updatedStatus,
        'message': 'Updated',
      };
    } else {
      statusCode = 404;
      response = {'message': 'Not found'};
    }

    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  Map<String, dynamic> _managedOrder() => {
        'customerName': 'Alice Customer',
        'branchName': 'Central branch',
        'order': {
          'id': 'order-1',
          'branchId': 'branch-1',
          'number': 'ORD-1001',
          'status': updatedStatus,
          'paymentStatus': 'DueOnFulfillment',
          'fulfillmentMethod': 'Pickup',
          'deliveryAddress': null,
          'deliveryLatitude': null,
          'deliveryLongitude': null,
          'notes': null,
          'total': 125.0,
          'createdAt': '2026-10-02T08:00:00Z',
          'items': [
            {
              'inventoryItemId': 'item-1',
              'itemName': 'Tea',
              'sku': 'TEA-1',
              'unit': 'pack',
              'quantity': 1,
              'unitPrice': 125,
              'lineTotal': 125,
            }
          ],
          'statusUpdates': [],
        },
      };

  @override
  void close({bool force = false}) {}
}
