import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/inventory_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stock health metric filters the ledger to low stock',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _DashboardApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: InventoryDashboard(
        client: AuthenticatedApiClient(dio: dio),
        role: 'Admin',
        canApprove: true,
        canReceive: true,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('dashboard-metric-low-stock')), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('MANAGER'), findsNothing);
    expect(
      find.byKey(const Key('dashboard-action-stock-activity')),
      findsOneWidget,
    );
    expect(find.text('Stock In / Out'), findsNothing);
    expect(find.text('StockSense AI'), findsNothing);
    expect(find.text('Explore AI stock insights'), findsNothing);
    await tester.tap(find.byKey(const Key('dashboard-metric-low-stock')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Low stock item'), findsOneWidget);
    expect(find.text('Healthy item'), findsNothing);
    expect(find.text('Empty item'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('North'), findsOneWidget);
    expect(find.text('2 units'), findsOneWidget);
    expect(find.text('7 units'), findsOneWidget);
    expect(
      find.byKey(const Key('dashboard-filter-low-stock')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    dio.close();
  });
}

class _DashboardApiAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.uri.path == '/inventory') {
      return _jsonResponse({
        'items': [
          {
            'id': 'low-1',
            'name': 'Low stock item',
            'sku': 'LOW-001',
            'quantity': 2,
            'unit': 'units',
            'reorderLevel': 5,
            'unitCost': 10,
            'branch': 'Main',
          },
          {
            'id': 'low-2',
            'name': 'Low stock item',
            'sku': 'LOW-001',
            'quantity': 7,
            'unit': 'units',
            'reorderLevel': 5,
            'unitCost': 10,
            'branch': 'North',
          },
          {
            'id': 'healthy-1',
            'name': 'Healthy item',
            'sku': 'GOOD-001',
            'quantity': 20,
            'unit': 'units',
            'reorderLevel': 5,
            'unitCost': 10,
            'branch': 'Main',
          },
          {
            'id': 'empty-1',
            'name': 'Empty item',
            'sku': 'EMPTY-001',
            'quantity': 0,
            'unit': 'units',
            'reorderLevel': 5,
            'unitCost': 10,
            'branch': 'Main',
          },
        ],
        'totalPages': 1,
      });
    }
    if (options.method == 'GET' && options.uri.path == '/purchase-orders') {
      return _jsonResponse({'items': [], 'totalPages': 1});
    }
    return _jsonResponse({'message': 'Unexpected endpoint'}, statusCode: 404);
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
