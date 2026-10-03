import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/app_notifications.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/stock_activity_history_screen.dart';

void main() {
  testWidgets('loads paginated activity returned by the inventory API',
      (tester) async {
    final adapter = _MovementAdapter(
      body: '''
{
  "items": [
    {
      "id": "movement-1",
      "occurredAt": "2026-09-29T10:00:00Z",
      "item": "Coke",
      "sku": "COKE-01",
      "movementType": "PurchaseReceived",
      "quantity": 3,
      "reference": "PO-001",
      "supplierName": "Drinks Supplier"
    }
  ],
  "page": 1,
  "pageSize": 100,
  "totalCount": 1,
  "totalPages": 1
}
''',
    );
    final client = AuthenticatedApiClient(
      dio: Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter,
    );

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: StockActivityHistoryScreen(client: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coke'), findsOneWidget);
    expect(find.text('PO received · COKE-01'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('Activity could not be loaded'), findsNothing);
    expect(adapter.methods, ['GET']);

    await tester.tap(find.byTooltip('Refresh activity'));
    await tester.pumpAndSettle();

    expect(find.text('Stock activity refreshed successfully.'), findsOneWidget);
    expect(adapter.methods, ['GET', 'GET']);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('shows activity and filters stock out without writing changes',
      (tester) async {
    final adapter = _MovementAdapter(
      body: '''
[
  {
    "occurredAt": "2026-09-29T10:00:00Z",
    "item": "Coke",
    "sku": "COKE-01",
    "movementType": "PurchaseReceived",
    "quantity": 3,
    "reference": "PO-001",
    "supplierName": "Drinks Supplier"
  },
  {
    "occurredAt": "2026-09-29T11:00:00Z",
    "item": "Tea",
    "sku": "TEA-01",
    "movementType": "Sale",
    "quantity": -1,
    "reference": "SALE-001"
  }
]
''',
    );
    final client = AuthenticatedApiClient(
      dio: Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter,
    );

    await tester.pumpWidget(
      MaterialApp(home: StockActivityHistoryScreen(client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock changes, recorded automatically'), findsOneWidget);
    expect(find.text('Coke'), findsOneWidget);
    expect(find.text('PO received · COKE-01'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);

    await tester.tap(find.text('Stock out'));
    await tester.pumpAndSettle();

    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Coke'), findsNothing);
    expect(adapter.methods, ['GET']);
  });

  testWidgets('opens stock operations from the activity screen',
      (tester) async {
    final adapter = _StockOperationsLaunchAdapter();
    final client = AuthenticatedApiClient(
      dio: Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter,
    );

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: StockActivityHistoryScreen(client: client),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('stock-activity-open-stock-operations')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock In / Out'), findsOneWidget);
    expect(find.byKey(const Key('stock-operations-mode-in')), findsOneWidget);
    expect(
      adapter.requestedPaths,
      contains('/api/inventory'),
    );
    expect(tester.takeException(), isNull);
  });
}

class _MovementAdapter implements HttpClientAdapter {
  _MovementAdapter({required this.body});

  final String body;
  final methods = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    methods.add(options.method);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StockOperationsLaunchAdapter implements HttpClientAdapter {
  final requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.uri.path);
    final body = options.uri.path == '/inventory/movements'
        ? {'items': <Object>[]}
        : {
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
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
