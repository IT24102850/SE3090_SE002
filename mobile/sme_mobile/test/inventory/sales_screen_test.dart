import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/sales_screen.dart';

void _setMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectSalesBranch(WidgetTester tester, String branch) async {
  await tester.ensureVisible(find.byKey(const Key('sales-branch-dropdown')));
  await tester.tap(find.byKey(const Key('sales-branch-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(branch).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('records a sale against branch-assigned stock', (tester) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select a branch'), findsOneWidget);
    expect(find.text('All branches'), findsNothing);
    expect(find.byKey(const Key('sales-select-branch-prompt')), findsOneWidget);
    await _selectSalesBranch(tester, 'Main branch');

    expect(find.text('Branch sales'), findsOneWidget);
    expect(find.text('Sales performance'), findsNothing);
    expect(find.text('SALES REVENUE'), findsNothing);
    expect(find.text('Inventory analytics'), findsNothing);
    expect(find.text('LKR 540.00'), findsOneWidget);
    expect(find.byKey(const Key('sales-branch-dropdown')), findsOneWidget);
    final header = find.byKey(const Key('sales-form-header'));
    expect(find.text('Record a sale'), findsOneWidget);
    final safeTop = tester.view.padding.top / tester.view.devicePixelRatio;
    expect(
      tester.getTopLeft(header).dy,
      greaterThanOrEqualTo(safeTop + kToolbarHeight),
    );
    expect(
        tester.getRect(header).bottom,
        lessThan(tester
            .getRect(find.byKey(const Key('sale-item-search-field')))
            .top));
    expect(
      tester.getRect(header).bottom,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    await tester.ensureVisible(find.byKey(const Key('sale-item-search-field')));
    await tester.tap(find.byKey(const Key('sale-item-search-field')));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned stock'), findsNothing);
    await tester.tap(find.byKey(const Key(
      'sale-item-option-${_SalesApiAdapter.itemId}',
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sale-unit-price-display')), findsOneWidget);
    expect(find.byKey(const Key('sale-unit-price-field')), findsNothing);
    expect(find.text('LKR 120.00'), findsNWidgets(2));

    await tester.ensureVisible(find.byKey(const Key('sale-quantity-field')));
    await tester.enterText(find.byKey(const Key('sale-quantity-field')), '2');
    await tester.ensureVisible(find.text('Record sale'));
    await tester.tap(find.text('Record sale'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm sale'), findsWidgets);
    expect(find.byKey(const Key('sale-confirmation-dialog')), findsOneWidget);
    expect(find.text('LKR 240.00'), findsNWidgets(2));
    expect(find.text('Remaining stock'), findsOneWidget);
    expect(adapter.recordedSale, isNull);
    await tester.tap(find.text('Confirm sale').last);
    await tester.pumpAndSettle();

    expect(adapter.recordedSale, {
      'quantity': 2.0,
      'expectedSellingPrice': 120.0,
      'expectedUnitCost': 80.0,
      'reference': startsWith('SALE-MOB-'),
    });
    expect(
      adapter.requestedPaths,
      contains('/api/inventory/${_SalesApiAdapter.itemId}/sell'),
    );
    expect(adapter.remainingQuantity, 3);
    expect(find.textContaining('Sale recorded successfully'), findsOneWidget);
    expect(find.byKey(const Key('sale-receipt-dialog')), findsOneWidget);
    expect(find.text('SALE-20260929-000001'), findsOneWidget);
    expect(find.text('UNIFY · SALES RECEIPT'), findsOneWidget);
    expect(find.text('Sale recorded'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(
      find.textContaining('Payment collection is not recorded'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sale-receipt-low-stock')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byTooltip('Refresh sales'));
    await tester.pumpAndSettle();
    expect(find.text('Sales and inventory refreshed successfully.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });

  testWidgets('cancelling a sale displays feedback without posting', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await _selectSalesBranch(tester, 'Main branch');
    await tester.ensureVisible(find.byKey(const Key('sale-item-search-field')));
    await tester.tap(find.byKey(const Key('sale-item-search-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key(
      'sale-item-option-${_SalesApiAdapter.itemId}',
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Record sale'));
    await tester.tap(find.text('Record sale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(adapter.recordedSale, isNull);
    expect(adapter.remainingQuantity, 5);
    expect(
        find.text('Sale cancelled. No inventory was changed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });

  testWidgets('searches inventory by SKU and shows accurate item details', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await _selectSalesBranch(tester, 'Colombo Branch');

    final searchField = find.byKey(const Key('sale-item-search-field'));
    await tester.ensureVisible(searchField);
    await tester.tap(searchField);
    await tester.enterText(searchField, 'wTr-05');
    await tester.pumpAndSettle();

    expect(find.text('Bottled Water'), findsOneWidget);
    expect(find.text('WTR-05 · Drinks · Colombo Branch'), findsOneWidget);
    expect(find.text('12 bottle available · LKR 20.00'), findsOneWidget);
    expect(find.text('Coffee Beans'), findsNothing);

    await tester.tap(find.byKey(
      const Key('sale-item-option-59a715eb-6a6c-421b-b717-f141dc48c454'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Colombo Branch'), findsNWidgets(2));
    expect(find.text('LKR 20.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('branch selection filters stock and recent sale activity', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select a branch'), findsOneWidget);
    expect(find.text('All branches'), findsNothing);
    expect(
      adapter.requestedUris.where(
        (uri) =>
            uri.path == '/api/inventory' ||
            uri.path == '/api/reports/sales-activity',
      ),
      isEmpty,
    );
    await tester.ensureVisible(find.byKey(const Key('sales-branch-dropdown')));
    await tester.tap(find.byKey(const Key('sales-branch-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colombo Branch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sale-item-search-field')));
    await tester.pumpAndSettle();

    expect(find.text('Bottled Water'), findsOneWidget);
    expect(find.text('Coffee Beans'), findsNothing);
    expect(
      adapter.requestedUris.any(
        (uri) =>
            uri.path == '/api/inventory' &&
            uri.queryParameters['branchId'] == _SalesApiAdapter.colomboBranchId,
      ),
      isTrue,
    );
    expect(
      adapter.requestedUris.any(
        (uri) =>
            uri.path == '/api/reports/sales-activity' &&
            uri.queryParameters['branchId'] == _SalesApiAdapter.colomboBranchId,
      ),
      isTrue,
    );
    expect(
      adapter.requestedUris.any(
        (uri) => uri.path == '/api/reports/revenue',
      ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('operational sales screen shows activity errors and retries',
      (tester) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter()..activityGate = Completer<void>();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('sales-branch-dropdown')));
    await tester.tap(find.byKey(const Key('sales-branch-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main branch').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Sales performance'), findsNothing);
    expect(find.byKey(const Key('branch-fetch-loading-panel')), findsOneWidget);
    expect(
      adapter.requestedUris.any((uri) => uri.path == '/api/reports/revenue'),
      isFalse,
    );
    adapter.failActivity = true;
    adapter.activityGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sales-load-error')), findsOneWidget);
    expect(find.text('Could not load branch sales data'), findsWidgets);
    expect(find.text('sales activity unavailable'), findsOneWidget);
    expect(find.byKey(const Key('sale-item-search-field')), findsOneWidget);

    adapter.failActivity = false;
    await tester.tap(find.byKey(const Key('sales-retry-load')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sales-load-error')), findsNothing);
    expect(
      find.byKey(const Key('recent-sale-SALE-HISTORY-001')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });

  testWidgets('shows real recent sales and opens their receipt',
      (tester) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await _selectSalesBranch(tester, 'Main branch');

    await tester.ensureVisible(find.text('Recent sales & receipts'));
    expect(find.text('Recent sales & receipts'), findsOneWidget);
    expect(
        find.byKey(const Key('recent-sale-SALE-HISTORY-001')), findsOneWidget);
    expect(find.text('Roasted Coffee'), findsOneWidget);
    expect(find.text('LKR 540.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recent-sale-SALE-HISTORY-001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sale-receipt-dialog')), findsOneWidget);
    expect(find.text('SALE-HISTORY-001'), findsOneWidget);
    expect(find.text('Branch details unavailable'), findsOneWidget);
    expect(find.textContaining('Quantity total: 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    dio.close();
  });

  testWidgets('shows sale and refresh errors from the backend', (tester) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await _selectSalesBranch(tester, 'Main branch');
    await tester.ensureVisible(find.byKey(const Key('sale-item-search-field')));
    await tester.tap(find.byKey(const Key('sale-item-search-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key(
      'sale-item-option-${_SalesApiAdapter.itemId}',
    )));
    await tester.pumpAndSettle();

    adapter.failSale = true;
    await tester.ensureVisible(find.text('Record sale'));
    await tester.tap(find.text('Record sale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm sale').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Sale failed: Quantity exceeds available stock.'),
      findsOneWidget,
    );
    expect(adapter.remainingQuantity, 5);

    await tester.pump(const Duration(seconds: 6));
    adapter.failActivity = true;
    await tester.tap(find.byTooltip('Refresh sales'));
    await tester.pumpAndSettle();
    expect(
      find.text('Refresh failed: sales activity unavailable'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });

  testWidgets('explains a missing sales endpoint instead of only HTTP 404', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final adapter = _SalesApiAdapter()
      ..failSale = true
      ..saleFailureStatus = 404
      ..saleFailureBody = '<html>Not Found</html>';
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await _selectSalesBranch(tester, 'Main branch');
    await tester.ensureVisible(find.byKey(const Key('sale-item-search-field')));
    await tester.tap(find.byKey(const Key('sale-item-search-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key(
      'sale-item-option-${_SalesApiAdapter.itemId}',
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Record sale'));
    await tester.tap(find.text('Record sale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm sale').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Sale failed: The sales API endpoint was not found (HTTP 404). '
        'Check the deployed backend route.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });
}

class _SalesApiAdapter implements HttpClientAdapter {
  static const itemId = '0bd2b33c-9903-4e19-9ae5-4c9024e96f83';
  static const mainBranchId = 'bcf51a09-74f3-4697-bfd6-f508c7770302';
  static const colomboBranchId = '0e984137-2d68-40bb-8020-43fe0b81c740';

  final requestedPaths = <String>[];
  final requestedUris = <Uri>[];
  double remainingQuantity = 5;
  Map<String, dynamic>? recordedSale;
  bool failSale = false;
  bool failActivity = false;
  Completer<void>? activityGate;
  int saleFailureStatus = 409;
  Object saleFailureBody = const {
    'title': 'One or more validation errors occurred.',
    'errors': {
      'quantity': ['Quantity exceeds available stock.'],
    },
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    requestedPaths.add(uri.path);
    requestedUris.add(uri);

    if (uri.path == '/api/inventory/branches') {
      return _jsonResponse([
        {'id': mainBranchId, 'name': 'Main branch'},
        {'id': colomboBranchId, 'name': 'Colombo Branch'},
      ]);
    }
    if (uri.path == '/api/inventory') {
      final items = [
        {
          'id': itemId,
          'name': 'Coffee Beans',
          'sku': 'COF-01',
          'category': 'Coffee',
          'quantity': remainingQuantity,
          'unit': 'kg',
          'reorderLevel': 3,
          'unitCost': 80,
          'sellingPrice': 120,
          'branch': 'Main branch',
          'branchId': mainBranchId,
        },
        {
          'id': '59a715eb-6a6c-421b-b717-f141dc48c454',
          'name': 'Bottled Water',
          'sku': 'WTR-05',
          'category': 'Drinks',
          'quantity': 12,
          'unit': 'bottle',
          'reorderLevel': 3,
          'unitCost': 10,
          'sellingPrice': 20,
          'branch': 'Colombo Branch',
          'branchId': colomboBranchId,
        },
        {
          'id': '6aa6b7bd-32d6-44be-9382-fb2e790375f2',
          'name': 'Unassigned stock',
          'sku': 'COF-02',
          'category': 'Coffee',
          'quantity': 4,
          'unit': 'kg',
          'reorderLevel': 2,
          'unitCost': 80,
          'sellingPrice': 120,
          'branch': 'Main branch',
        },
      ];
      final branchId = uri.queryParameters['branchId'];
      return _jsonResponse({
        'items': branchId == null
            ? items
            : items.where((item) => item['branchId'] == branchId).toList(),
        'totalPages': 1,
      });
    }

    if (uri.path == '/api/reports/sales-activity') {
      await activityGate?.future;
      if (failActivity) {
        return _jsonResponse({'message': 'sales activity unavailable'}, 503);
      }
      return _jsonResponse({
        'grossProfit': 200,
        'salesCount': 3,
        'averageSale': 180,
        'recentSales': [
          {
            'reference': 'SALE-HISTORY-001',
            'occurredAt': '2026-09-29T08:00:00Z',
            'amount': 540,
            'quantity': 3,
            'items': ['Roasted Coffee'],
            'grossProfit': 180,
          },
        ],
      });
    }

    if (uri.path.endsWith('/sell')) {
      recordedSale = Map<String, dynamic>.from(options.data as Map);
      if (failSale) {
        return _jsonResponse(saleFailureBody, saleFailureStatus);
      }
      remainingQuantity -= (recordedSale!['quantity'] as num).toDouble();
      return _jsonResponse({
        'reference': 'SALE-20260929-000001',
        'remainingQuantity': remainingQuantity,
        'itemName': 'Coffee Beans',
        'quantity': recordedSale!['quantity'],
        'unitPrice': 120,
        'amount': 240,
        'grossProfit': 80,
        'occurredAt': '2026-09-29T08:00:00Z',
      });
    }

    return _jsonResponse({'message': 'Unexpected endpoint: ${uri.path}'}, 404);
  }

  ResponseBody _jsonResponse(Object body, [int statusCode = 200]) =>
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
