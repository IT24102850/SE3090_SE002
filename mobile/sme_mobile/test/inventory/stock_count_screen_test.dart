import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/stock_count_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('requires branch selection for duplicate SKUs and syncs by item',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _StockCountApiAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      home: StockCountScreen(client: AuthenticatedApiClient(dio: dio)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (var attempt = 0;
        attempt < 10 &&
            find.byKey(const Key('stock-count-content')).evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));

    final skuField = find.byKey(const Key('stock-count-sku-field'));
    await tester.enterText(skuField, 'DUP-01');
    await tester.pump();
    expect(adapter.requestedPaths, contains('/inventory'));
    expect(
        find.byKey(const Key('stock-count-branch-selector')), findsOneWidget);
    expect(find.byKey(const Key('count-preview-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stock-count-branch-selector')));
    await tester.pump();
    await tester.tap(find.text('North branch · 7 units').last);
    await tester.pump();
    expect(find.byKey(const Key('count-preview-DUP-01')), findsOneWidget);
    expect(find.text('North item'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('stock-count-quantity-field')),
      '7',
    );
    await tester.ensureVisible(find.text('Record Physical Count'));
    await tester.tap(find.text('Record Physical Count'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Save Count'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      adapter.requestedPaths,
      contains(
          '/inventory/${_StockCountApiAdapter.northItemId}/physical-count'),
    );
    expect(
      adapter.requestedPaths,
      isNot(contains(
        '/inventory/${_StockCountApiAdapter.southItemId}/physical-count',
      )),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
    dio.close();
  });
}

class _StockCountApiAdapter implements HttpClientAdapter {
  static const northItemId = 'f62d0c79-62b9-43e1-8bf3-f00c73b23901';
  static const southItemId = 'ca6e6eab-9a1a-4abe-b59e-514dad539a02';

  final requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.uri.path);
    if (options.uri.path == '/inventory') {
      return _jsonResponse({
        'items': [
          {
            'id': northItemId,
            'name': 'North item',
            'sku': 'DUP-01',
            'quantity': 7,
            'unit': 'units',
            'branch': 'North branch',
            'branchId': 'north-branch',
          },
          {
            'id': southItemId,
            'name': 'South item',
            'sku': 'DUP-01',
            'quantity': 12,
            'unit': 'units',
            'branch': 'South branch',
            'branchId': 'south-branch',
          },
        ],
        'totalPages': 1,
      });
    }
    if (options.uri.path == '/inventory/physical-count-approvals') {
      return _jsonResponse({'items': [], 'canApprove': false});
    }
    if (options.uri.path.endsWith('/physical-count')) {
      return _jsonResponse({'id': 'audit-1', 'status': 'Matched'});
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
