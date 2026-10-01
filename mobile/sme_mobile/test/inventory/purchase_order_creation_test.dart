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
  const mainBranchId = '3b4dbe2a-a430-40b1-afdb-fb2171cefb88';
  const northBranchId = 'd91f3b79-e72e-4bc5-9aa0-f59b362a1003';

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

    expect(
      find.textContaining('Coffee from Supplier One · COF-01'),
      findsOneWidget,
    );
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

    expect(
      find.textContaining('Tea from Supplier Two · TEA-02 · Main Branch'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Coffee from Supplier One · COF-01'),
      findsNothing,
    );
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

    await tester.enterText(
      find.byKey(const Key('po-quantity-field-$mainBranchId')),
      '3',
    );
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

  testWidgets(
      'staff can create an assigned-branch request without approval rights',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _PurchaseOrderApiAdapter(assignedBranchOnly: true);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: PushNotificationService.navigatorKey,
        scaffoldMessengerKey: appMessengerKey,
        home: PurchaseOrderApprovalScreen(
          client: AuthenticatedApiClient(dio: dio),
          canApprove: false,
          canCreate: true,
          canReceive: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New PO'), findsOneWidget);
    await tester.tap(find.text('New PO'));
    await tester.pumpAndSettle();
    expect(find.text('North Branch'), findsNothing);
    await tester.ensureVisible(find.text('Create Purchase Order').last);
    await tester.tap(find.text('Create Purchase Order').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(adapter.createdOrder?['branchId'], mainBranchId);
    expect(adapter.createdBatch, isNull);
    expect(adapter.createdOrder?['supplierId'],
        _PurchaseOrderApiAdapter.supplierOneId);
    expect(adapter.createdOrder?['items'], hasLength(1));
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('creates branch-specific orders in one batch request',
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
          canCreateMultiBranch: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New PO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('po-supplier-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplier Two').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey(
          'po-item-dropdown-${_PurchaseOrderApiAdapter.supplierTwoId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('North Branch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('po-select-all-branches')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('po-branch-checkbox-$northBranchId')),
          )
          .value,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('po-quantity-field-$northBranchId')),
      '4',
    );
    await tester.pump();
    expect(find.text('LKR 375.00'), findsOneWidget);

    await tester.ensureVisible(find.text('Create Purchase Order').last);
    await tester.tap(find.text('Create Purchase Order').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(adapter.createdBatch, isNotNull);
    expect(adapter.createdBatch!['supplierId'],
        _PurchaseOrderApiAdapter.supplierTwoId);
    final branchOrders = adapter.createdBatch!['branchOrders'] as List;
    expect(branchOrders, hasLength(2));
    expect(branchOrders[0]['branchId'], mainBranchId);
    expect(branchOrders[1]['branchId'], northBranchId);
    expect(
      (branchOrders[0]['items'] as List).single['quantity'],
      1.0,
    );
    expect(
      (branchOrders[1]['items'] as List).single['quantity'],
      4.0,
    );
    expect(
      (branchOrders[0]['items'] as List).single['inventoryItemId'],
      _PurchaseOrderApiAdapter.northTeaItemId,
    );
    expect(
      (branchOrders[1]['items'] as List).single['inventoryItemId'],
      _PurchaseOrderApiAdapter.northTeaItemId,
    );
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('receipt form clearly separates stock, damage, and shortages',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _PurchaseOrderApiAdapter()
      ..purchaseOrders = [
        {
          'id': 'po-receive',
          'number': 'PO-3264-02',
          'branchId': mainBranchId,
          'branch': 'Main Branch',
          'supplier': 'Supplier Two',
          'status': 'InTransit',
          'totalAmount': 75,
          'lineItems': 1,
          'createdAt': '2026-09-30T10:00:00Z',
          'updatedAt': '2026-09-30T10:00:00Z',
          'items': [
            {
              'id': 'line-1',
              'inventoryItemId': _PurchaseOrderApiAdapter.teaItemId,
              'itemName': 'Tea bags',
              'quantity': 5,
              'unitPrice': 15,
              'lineTotal': 75,
              'receivedQuantity': 1,
              'damagedQuantity': 1,
              'shortageQuantity': 0,
              'receivingClosed': false,
            }
          ],
        }
      ];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: PushNotificationService.navigatorKey,
        scaffoldMessengerKey: appMessengerKey,
        home: PurchaseOrderApprovalScreen(
          client: AuthenticatedApiClient(dio: dio),
          canApprove: true,
          canReceive: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive items'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Enter the quantities delivered in this shipment.'),
      findsOneWidget,
    );
    expect(find.text('Order progress'), findsOneWidget);
    expect(find.textContaining('Ordered  5'), findsOneWidget);
    expect(find.textContaining('Accepted  1'), findsOneWidget);
    expect(find.byKey(const Key('receipt-accepted-line-1')), findsOneWidget);
    expect(find.byKey(const Key('receipt-damaged-line-1')), findsOneWidget);
    expect(find.text('Added to stock'), findsOneWidget);
    expect(find.text('Still expected'), findsOneWidget);
    expect(
      find.textContaining('units stay open for a later delivery.'),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Receipt evidence'), findsOneWidget);
    expect(find.text('Optional photos of the delivery or damaged items.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });
}

class _PurchaseOrderApiAdapter implements HttpClientAdapter {
  static const supplierOneId = 'd4cbe84b-0888-4725-b387-97d21a44caad';
  static const supplierTwoId = 'd4cbe84b-0888-4725-b387-97d21a44caae';
  static const teaItemId = 'a78856d1-1b82-4d06-a4fa-e21f3fa52a02';
  static const northTeaItemId = 'a78856d1-1b82-4d06-a4fa-e21f3fa52a03';

  _PurchaseOrderApiAdapter({this.assignedBranchOnly = false});

  final bool assignedBranchOnly;

  Map<String, dynamic>? createdOrder;
  Map<String, dynamic>? createdBatch;
  List<Map<String, dynamic>> purchaseOrders = const [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/api/purchase-orders/options') {
      const branches = [
        {'id': '3b4dbe2a-a430-40b1-afdb-fb2171cefb88', 'name': 'Main Branch'},
        {'id': 'd91f3b79-e72e-4bc5-9aa0-f59b362a1003', 'name': 'North Branch'},
      ];
      const items = [
        {
          'id': 'cd28fddd-f09a-435c-9772-12831bc65001',
          'name': 'Coffee from Supplier One',
          'sku': 'COF-01',
          'unitCost': 120,
          'supplierId': supplierOneId,
          'branchId': '3b4dbe2a-a430-40b1-afdb-fb2171cefb88',
        },
        {
          'id': teaItemId,
          'name': 'Tea from Supplier Two',
          'sku': 'TEA-02',
          'unitCost': 75,
          'supplierId': supplierTwoId,
          'branchId': '3b4dbe2a-a430-40b1-afdb-fb2171cefb88',
          'branchName': 'Main Branch',
        },
        {
          'id': northTeaItemId,
          'name': 'Tea from Supplier Two',
          'sku': 'TEA-02',
          'unitCost': 75,
          'supplierId': supplierTwoId,
          'branchId': 'd91f3b79-e72e-4bc5-9aa0-f59b362a1003',
          'branchName': 'North Branch',
        },
      ];
      return _jsonResponse({
        'branches': assignedBranchOnly ? [branches.first] : branches,
        'suppliers': [
          {'id': supplierOneId, 'name': 'Supplier One'},
          {'id': supplierTwoId, 'name': 'Supplier Two'},
        ],
        'items': assignedBranchOnly
            ? items
                .where((item) =>
                    item['branchId'] == '3b4dbe2a-a430-40b1-afdb-fb2171cefb88')
                .toList()
            : items,
      });
    }
    if (options.uri.path == '/api/purchase-orders' && options.method == 'GET') {
      return _jsonResponse({'items': purchaseOrders, 'totalPages': 1});
    }
    if (options.uri.path == '/api/purchase-orders' &&
        options.method == 'POST') {
      createdOrder = Map<String, dynamic>.from(options.data as Map);
      return _jsonResponse({'id': 'po-1', 'number': createdOrder!['number']},
          statusCode: 201);
    }
    if (options.uri.path == '/api/purchase-orders/batch' &&
        options.method == 'POST') {
      createdBatch = Map<String, dynamic>.from(options.data as Map);
      return _jsonResponse(
        [
          {'id': 'po-1', 'number': '${createdBatch!['number']}-01'},
          {'id': 'po-2', 'number': '${createdBatch!['number']}-02'},
        ],
        statusCode: 201,
      );
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
