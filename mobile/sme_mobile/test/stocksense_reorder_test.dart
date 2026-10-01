import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/authenticated_api_client.dart';
import 'package:sme_mobile/inventory/stocksense_reorder.dart';

/// StockSense reorders on the phone, through the real inventory client with
/// a scripted HTTP adapter: what the request sheet sends, the gate decision it
/// shows, and the "My reorder requests" states.
class _Api implements HttpClientAdapter {
  _Api(this.answer);
  final (int, Object) Function(RequestOptions) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _workflow(String status, {String? po, String? outcome}) => {
      'id': 'r1',
      'status': status,
      'supplierName': 'MediSupply',
      'totalValue': 160000,
      'totalUnits': 200,
      'lines': [
        {'inventoryItemId': 'i1', 'name': 'Latex gloves', 'quantity': 200, 'unitCost': 800}
      ],
      'checks': [
        {'rule': 'value_within_auto_limit', 'passed': false, 'detail': 'Over the limit.'}
      ],
      'finalOutcome': outcome,
      'purchaseOrderNumber': po,
      'createdAt': '2026-10-01T08:00:00Z',
    };

StockSenseReorderRepository _repo(_Api api) =>
    StockSenseReorderRepository(AuthenticatedApiClient(dio: Dio(BaseOptions(baseUrl: 'http://test/api'))..httpClientAdapter = api));

final _recommendations = <Map<String, dynamic>>[
  {'inventory_item_id': 'i1', 'item_name': 'Latex gloves', 'branch_id': 'b1', 'recommended_quantity': 99.2},
  {'inventory_item_id': 'i2', 'item_name': 'Face masks', 'branch_id': 'b1', 'recommended_quantity': 40},
];

Future<void> _pumpSheet(WidgetTester tester, _Api api) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StockSenseReorderSheet(repository: _repo(api), recommendations: _recommendations, analysisWorkflowId: 'a1'),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('a recommendation without a branch cannot become an order line', () {
    expect(ReorderLineDraft.fromRecommendation({'inventory_item_id': 'x', 'item_name': 'X'}), isNull);
    expect(ReorderLineDraft.fromRecommendation(_recommendations.first)!.quantity, 100); // rounded up
  });

  testWidgets('needs a supplier before sending', (tester) async {
    final api = _Api((r) => (200, {'suppliers': [{'id': 's1', 'name': 'MediSupply'}]}));
    await _pumpSheet(tester, api);

    await tester.tap(find.text('Request reorder'));
    await tester.pump();

    expect(find.text('Choose a supplier.'), findsOneWidget);
    expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('sends the selected lines and shows that the order awaits approval', (tester) async {
    final api = _Api((r) => r.method == 'POST'
        ? (201, _workflow('AwaitingApproval', outcome: 'Paused for approval: over the limit.'))
        : (200, {'suppliers': [{'id': 's1', 'name': 'MediSupply'}]}));
    await _pumpSheet(tester, api);

    await tester.tap(find.byKey(const Key('reorder-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MediSupply').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reorder-select-i2'))); // leave masks out
    await tester.enterText(find.byKey(const Key('reorder-qty-i1')), '120');
    await tester.tap(find.text('Request reorder'));
    await tester.pumpAndSettle();

    final post = api.requests.singleWhere((r) => r.method == 'POST');
    expect(post.path, endsWith('/inventory/agent/reorders'));
    expect(post.data, {
      'branchId': 'b1',
      'supplierId': 's1',
      'analysisWorkflowId': 'a1',
      'lines': [
        {'inventoryItemId': 'i1', 'quantity': 120}
      ],
    });
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.textContaining("notification when a manager decides"), findsOneWidget);
  });

  testWidgets('shows the server validation message when the request is refused', (tester) async {
    final api = _Api((r) => r.method == 'POST'
        ? (400, {'errors': {'lines': ['Each item may appear only once.']}})
        : (200, {'suppliers': [{'id': 's1', 'name': 'MediSupply'}]}));
    await _pumpSheet(tester, api);

    await tester.tap(find.byKey(const Key('reorder-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MediSupply').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request reorder'));
    await tester.pumpAndSettle();

    expect(find.text('Each item may appear only once.'), findsOneWidget);
  });

  testWidgets('My reorder requests lists each request with its status and order', (tester) async {
    final api = _Api((_) => (200, [_workflow('Completed', po: 'SS-20261001-1234', outcome: 'Approved - purchase order placed.')]));
    await tester.pumpWidget(MaterialApp(home: MyReordersScreen(repository: _repo(api))));
    await tester.pumpAndSettle();

    expect(find.text('Ordered'), findsOneWidget);
    expect(find.text('Purchase order SS-20261001-1234'), findsOneWidget);
    expect(api.requests.single.uri.query, 'mine=true');
  });

  testWidgets('My reorder requests shows an empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MyReordersScreen(repository: _repo(_Api((_) => (200, []))))));
    await tester.pumpAndSettle();

    expect(find.textContaining('No reorder requests yet'), findsOneWidget);
  });

  testWidgets('My reorder requests shows an error state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MyReordersScreen(repository: _repo(_Api((_) => (403, {}))))));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be loaded (403)'), findsOneWidget);
  });
}
