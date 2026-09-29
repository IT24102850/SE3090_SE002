import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/inventory_models.dart';
import 'package:sme_mobile/inventory/sales_screen.dart';

void main() {
  testWidgets('records a sale against branch-assigned stock', (tester) async {
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();

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
            .getRect(
              find.byType(DropdownButtonFormField<InventoryItem>),
            )
            .top));
    expect(
      tester.getRect(header).bottom,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    await tester.tap(find.byType(DropdownButtonFormField<InventoryItem>));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned stock'), findsNothing);
    await tester.tap(find.text('Coffee Beans').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sale-unit-price-display')), findsOneWidget);
    expect(find.byKey(const Key('sale-unit-price-field')), findsNothing);
    expect(find.text('LKR 80.00'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.tap(find.text('Record sale'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm sale'), findsWidgets);
    expect(find.byKey(const Key('sale-confirmation-dialog')), findsOneWidget);
    expect(find.text('LKR 160.00'), findsNWidgets(2));
    expect(find.text('Remaining stock'), findsOneWidget);
    expect(adapter.recordedSale, isNull);
    await tester.tap(find.text('Confirm sale').last);
    await tester.pumpAndSettle();

    expect(adapter.recordedSale, {'quantity': 2.0, 'unitPrice': 80.0});
    expect(
      adapter.requestedPaths,
      contains('/api/inventory/${_SalesApiAdapter.itemId}/sell'),
    );
    expect(adapter.remainingQuantity, 3);
    expect(find.textContaining('Sale recorded successfully'), findsOneWidget);

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
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<InventoryItem>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee Beans').last);
    await tester.pumpAndSettle();
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

  testWidgets('shows sale and refresh errors from the backend', (tester) async {
    final adapter = _SalesApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: SalesScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<InventoryItem>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee Beans').last);
    await tester.pumpAndSettle();

    adapter.failSale = true;
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
    adapter.failRevenue = true;
    await tester.tap(find.byTooltip('Refresh sales'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh failed: report unavailable'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });

  testWidgets('explains a missing sales endpoint instead of only HTTP 404', (
    tester,
  ) async {
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
    await tester.tap(find.byType(DropdownButtonFormField<InventoryItem>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee Beans').last);
    await tester.pumpAndSettle();
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

  final requestedPaths = <String>[];
  double remainingQuantity = 5;
  Map<String, dynamic>? recordedSale;
  bool failSale = false;
  bool failRevenue = false;
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

    if (uri.path == '/api/inventory') {
      return _jsonResponse({
        'items': [
          {
            'id': itemId,
            'name': 'Coffee Beans',
            'sku': 'COF-01',
            'category': 'Coffee',
            'quantity': remainingQuantity,
            'unit': 'kg',
            'reorderLevel': 2,
            'unitCost': 80,
            'branch': 'Main branch',
            'branchId': 'bcf51a09-74f3-4697-bfd6-f508c7770302',
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
            'branch': 'Main branch',
          },
        ],
        'totalPages': 1,
      });
    }

    if (uri.path == '/api/reports/revenue') {
      if (failRevenue) {
        return _jsonResponse({'message': 'report unavailable'}, 503);
      }
      return _jsonResponse({
        'totalRevenue': 0,
        'buckets': [
          {'date': '2026-09-29T00:00:00Z', 'revenue': 0},
        ],
      });
    }

    if (uri.path.endsWith('/sell')) {
      recordedSale = Map<String, dynamic>.from(options.data as Map);
      if (failSale) {
        return _jsonResponse(saleFailureBody, saleFailureStatus);
      }
      remainingQuantity -= (recordedSale!['quantity'] as num).toDouble();
      return _jsonResponse({'remainingQuantity': remainingQuantity});
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
