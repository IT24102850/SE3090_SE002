import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/purchase_order_approval_screen.dart';
import 'package:sme_mobile/services/push_notification_service.dart';

void main() {
  testWidgets('supplier selection filters items and calculates order total',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _PurchaseOrderApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: PushNotificationService.navigatorKey,
        scaffoldMessengerKey: appMessengerKey,
        home: PurchaseOrderApprovalScreen(
          client: AuthenticatedApiClient(dio: dio),
          canApprove: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New PO'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee from Supplier One · COF-01'), findsOneWidget);
    expect(find.text('TOTAL PRICE'), findsOneWidget);
    expect(find.text('LKR 120.00'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('po-unit-price-field')),
          )
          .controller
          ?.text,
      '120.00',
    );

    await tester.tap(find.byKey(const Key('po-supplier-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplier Two').last);
    await tester.pumpAndSettle();

    expect(find.text('Tea from Supplier Two · TEA-02'), findsOneWidget);
    expect(find.text('Coffee from Supplier One · COF-01'), findsNothing);
    expect(find.text('LKR 75.00'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('po-unit-price-field')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );

    await tester.enterText(find.byKey(const Key('po-quantity-field')), '3');
    await tester.pump();
    expect(find.text('LKR 225.00'), findsOneWidget);

    await tester.ensureVisible(find.text('Create Purchase Order').last);
    await tester.tap(find.text('Create Purchase Order').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(adapter.createdOrder, isNotNull);
    expect(adapter.createdOrder!['supplierId'],
        _PurchaseOrderApiAdapter.supplierTwoId);
    final orderItem =
        (adapter.createdOrder!['items'] as List).single as Map<String, dynamic>;
    expect(orderItem['inventoryItemId'], _PurchaseOrderApiAdapter.teaItemId);
    expect(orderItem['unitPrice'], 75.0);
    expect(orderItem['quantity'], 3.0);
    expect(tester.takeException(), isNull);
    dio.close();
  });
}

class _PurchaseOrderApiAdapter implements HttpClientAdapter {
  static const supplierOneId = 'd4cbe84b-0888-4725-b387-97d21a44caad';
  static const supplierTwoId = 'd4cbe84b-0888-4725-b387-97d21a44caae';
  static const teaItemId = 'a78856d1-1b82-4d06-a4fa-e21f3fa52a02';

  Map<String, dynamic>? createdOrder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/api/purchase-orders/options') {
      return _jsonResponse({
        'branches': [
          {'id': '3b4dbe2a-a430-40b1-afdb-fb2171cefb88', 'name': 'Main Branch'},
        ],
        'suppliers': [
          {'id': supplierOneId, 'name': 'Supplier One'},
          {'id': supplierTwoId, 'name': 'Supplier Two'},
        ],
        'items': [
          {
            'id': 'cd28fddd-f09a-435c-9772-12831bc65001',
            'name': 'Coffee from Supplier One',
            'sku': 'COF-01',
            'unitCost': 120,
            'supplierId': supplierOneId,
          },
          {
            'id': teaItemId,
            'name': 'Tea from Supplier Two',
            'sku': 'TEA-02',
            'unitCost': 75,
            'supplierId': supplierTwoId,
          },
        ],
      });
    }
    if (options.uri.path == '/api/purchase-orders' && options.method == 'GET') {
      return _jsonResponse({'items': [], 'totalPages': 1});
    }
    if (options.uri.path == '/api/purchase-orders' &&
        options.method == 'POST') {
      createdOrder = Map<String, dynamic>.from(options.data as Map);
      return _jsonResponse({'id': 'po-1', 'number': createdOrder!['number']},
          statusCode: 201);
    }
    return _jsonResponse({'message': 'Unexpected request'}, statusCode: 404);
  }

  ResponseBody _jsonResponse(Object body, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );

  @override
  void close({bool force = false}) {}
}
