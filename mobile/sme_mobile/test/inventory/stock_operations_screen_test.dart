import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/stock_operations_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records a confirmed stock checkout from the separate screen',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _StockOperationsApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: StockOperationsScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('stock-operations-sku')),
      'SKU-00016',
    );
    await tester.pump();
    expect(find.text('Test item'), findsOneWidget);
    expect(find.text('Stock In'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('stock-operations-mode-out')),
    );
    await tester.pump();
    expect(find.text('Quantity to remove'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('stock-operations-quantity')),
      '2',
    );
    await tester.pump();
    expect(find.textContaining('After: 6 units'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stock-operations-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm stock check-out?'), findsOneWidget);
    await tester.tap(find.text('Check out').last);
    await tester.pumpAndSettle();

    expect(
      adapter.requestedPaths,
      contains('/inventory/item-1/issue'),
    );
    expect(adapter.issuedQuantity, 2);
    expect(
      find.byKey(const Key('stock-operations-mode-out')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    dio.close();
  });
}

class _StockOperationsApiAdapter implements HttpClientAdapter {
  final requestedPaths = <String>[];
  double? issuedQuantity;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.uri.path);
    if (options.method == 'GET' && options.uri.path == '/inventory') {
      return _jsonResponse({
        'items': [
          {
            'id': 'item-1',
            'name': 'Test item',
            'sku': 'SKU-00016',
            'quantity': 8,
            'unit': 'units',
            'branch': 'Main branch',
            'branchId': 'branch-1',
          },
        ],
        'totalPages': 1,
      });
    }
    if (options.method == 'POST' &&
        options.uri.path == '/inventory/item-1/issue') {
      issuedQuantity =
          (options.data as Map<String, dynamic>)['quantity'] as double;
      return _jsonResponse({'success': true});
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
