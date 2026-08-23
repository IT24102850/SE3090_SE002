import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sme_inventory_app/auth/app_notifications.dart';
import 'package:sme_inventory_app/auth/auth_controller.dart';
import 'package:sme_inventory_app/auth/auth_repository.dart';
import 'package:sme_inventory_app/auth/authenticated_api_client.dart';
import 'package:sme_inventory_app/main.dart';
import 'package:sme_inventory_app/stock_count_screen.dart';

class _FakeInventoryClient implements http.Client {
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _respond(url, 'GET');

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers,
          Object? body,
          Encoding? encoding}) =>
      _respond(url, 'POST');

  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers,
          Object? body,
          Encoding? encoding}) =>
      _respond(url, 'PUT');

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers,
          Object? body,
          Encoding? encoding}) =>
      _respond(url, 'PATCH');

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers,
          Object? body,
          Encoding? encoding}) =>
      _respond(url, 'DELETE');

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      _respond(url, 'HEAD');

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await _respond(url, 'GET');
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await _respond(url, 'GET');
    return response.bodyBytes;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _respond(request.url, request.method);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {}

  Future<http.Response> _respond(Uri url, String method) async {
    final responseBody = switch (method) {
      'GET' when url.path == '/api/inventory' =>
        '{"items":[{"id":1,"sku":"SKU-100","name":"Widget Pack","quantity":10}],"totalPages":1}',
      'POST' when url.path == '/api/inventory/1/adjust' => '{"ok":true}',
      _ => 'not found',
    };

    final statusCode = switch (method) {
      'GET' when url.path == '/api/inventory' => 200,
      'POST' when url.path == '/api/inventory/1/adjust' => 200,
      _ => 404,
    };

    return http.Response(responseBody, statusCode,
        headers: {'content-type': 'application/json'});
  }
}

late http.Client mockInventoryClient;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner'),
      (call) async {
        switch (call.method) {
          case 'state':
            return 'ready';
          case 'request':
            return true;
          case 'start':
          case 'stop':
          case 'pause':
          case 'resume':
          case 'toggleTorch':
          case 'analyzeImage':
          case 'updateScanWindow':
          case 'resetScanWindow':
            return null;
          case 'availableCameras':
            return 1;
          default:
            return null;
        }
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        switch (call.method) {
          case 'checkConnectivity':
            return 'wifi';
          default:
            return null;
        }
      },
    );

    mockInventoryClient = _FakeInventoryClient();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  testWidgets('shows the sign-in form when no session exists', (tester) async {
    final auth = AuthController(
      AuthRepository(apiBaseUrl: 'http://localhost:5107'),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(auth: auth)),
    );

    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('renders the stock count scanner and form', (tester) async {
    final client = AuthenticatedApiClient(
      apiBaseUrl: 'http://localhost:5107',
      accessToken: 'token',
      client: mockInventoryClient,
    );

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: StockCountScreen(client: client),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Stock count'), findsOneWidget);
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(find.text('Item barcode / SKU'), findsOneWidget);
    expect(find.text('Physical quantity'), findsOneWidget);
  });

  testWidgets('accepts a valid stock count and shows a success notification',
      (tester) async {
    final client = AuthenticatedApiClient(
      apiBaseUrl: 'http://localhost:5107',
      accessToken: 'token',
      client: mockInventoryClient,
    );

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: StockCountScreen(client: client),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'SKU-100');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tester.tap(find.text('Save count'));
    await tester.pump();

    expect(find.text('Widget Pack saved for sync.'), findsOneWidget);
  });

  testWidgets('shows a success snackbar with the expected tone',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    showAppNotification('Count saved successfully.',
        tone: AppNotificationTone.success);
    await tester.pump();

    expect(find.text('Count saved successfully.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
  });
}
