import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/api_service.dart';
import 'package:sme_mobile/services/secure_storage_service.dart';

/// API integration at the HTTP boundary: the real [ApiService] Dio client
/// and its interceptor, with the transport replaced by a fake adapter that
/// records each request and answers with a chosen status. What is checked is
/// exactly what would reach ASP.NET Core.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, [this.body = const {}]);

  final int status;
  final Object body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpClientAdapter originalAdapter;

  setUpAll(() => originalAdapter = ApiService.dio.httpClientAdapter);
  tearDownAll(() => ApiService.dio.httpClientAdapter = originalAdapter);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.onUnauthorized = null;
  });

  _FakeAdapter answer(int status, [Object body = const {}]) {
    final adapter = _FakeAdapter(status, body);
    ApiService.dio.httpClientAdapter = adapter;
    return adapter;
  }

  test('attaches the stored JWT as a bearer token and sends JSON', () async {
    await SecureStorageService.saveToken('jwt-abc');
    final adapter = answer(200, [
      {'id': 'b1'}
    ]);

    final response = await ApiService.dio.get('/bookings/my-bookings');

    expect(response.data, [
      {'id': 'b1'}
    ]);
    expect(adapter.lastRequest!.headers['Authorization'], 'Bearer jwt-abc');
    expect(adapter.lastRequest!.headers['Content-Type'], 'application/json');
    expect(adapter.lastRequest!.uri.path, endsWith('/api/bookings/my-bookings'));
  });

  test('sends no Authorization header when signed out', () async {
    final adapter = answer(200);

    await ApiService.dio.get('/tenants/public');

    expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
  });

  test('a 401 clears the stored session and notifies the app once', () async {
    await SecureStorageService.saveToken('expired');
    var notified = 0;
    ApiService.onUnauthorized = () => notified++;
    answer(401, {'message': 'Token expired'});

    await expectLater(
      ApiService.dio.get('/auth/me'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
    );

    expect(await SecureStorageService.getToken(), isNull);
    expect(notified, 1);
  });

  test('a 403 is passed to the caller and keeps the session', () async {
    await SecureStorageService.saveToken('still-valid');
    answer(403, {'title': 'Forbidden'});

    await expectLater(
      ApiService.dio.post('/agent/workflow/x/approve'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 403)),
    );

    expect(await SecureStorageService.getToken(), 'still-valid');
  });

  test('a configured base URL is normalised to end in /api', () {
    final previous = ApiService.baseUrl;
    addTearDown(() => ApiService.baseUrl = previous);

    ApiService.baseUrl = 'https://sme-backend-lxsp.onrender.com/';

    expect(ApiService.baseUrl, 'https://sme-backend-lxsp.onrender.com/api');
    expect(ApiService.origin, 'https://sme-backend-lxsp.onrender.com');
  });
}
