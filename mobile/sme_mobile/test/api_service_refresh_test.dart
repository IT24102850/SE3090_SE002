import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/api_service.dart';
import 'package:sme_mobile/services/secure_storage_service.dart';

/// Refresh-token handling in the shared Dio client: an expired access token
/// is traded for a new pair once and the failed request is replayed; a
/// refused refresh signs the user out. The adapter answers per path.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.answer);

  final (int, Object) Function(RequestOptions) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpClientAdapter original;
  setUpAll(() => original = ApiService.dio.httpClientAdapter);
  tearDownAll(() => ApiService.dio.httpClientAdapter = original);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.onUnauthorized = null;
  });

  test('an expired access token is refreshed once and the request replayed', () async {
    await SecureStorageService.saveToken('expired-access');
    await SecureStorageService.saveRefreshToken('refresh-1');
    final adapter = _ScriptedAdapter((r) {
      if (r.path.endsWith('/auth/refresh')) {
        return (200, {'accessToken': 'new-access', 'refreshToken': 'refresh-2'});
      }
      return r.headers['Authorization'] == 'Bearer new-access' ? (200, {'ok': true}) : (401, {});
    });
    ApiService.dio.httpClientAdapter = adapter;

    final response = await ApiService.dio.get('/bookings/my-bookings');

    expect(response.data, {'ok': true});
    expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), hasLength(1));
    final refreshCall = adapter.requests.firstWhere((r) => r.path.endsWith('/auth/refresh'));
    expect(refreshCall.data, {'refreshToken': 'refresh-1'});
    expect(await SecureStorageService.getToken(), 'new-access');
    expect(await SecureStorageService.getRefreshToken(), 'refresh-2');
  });

  test('concurrent 401s share a single refresh', () async {
    await SecureStorageService.saveToken('expired-access');
    await SecureStorageService.saveRefreshToken('refresh-1');
    final adapter = _ScriptedAdapter((r) {
      if (r.path.endsWith('/auth/refresh')) {
        return (200, {'accessToken': 'new-access', 'refreshToken': 'refresh-2'});
      }
      return r.headers['Authorization'] == 'Bearer new-access' ? (200, {}) : (401, {});
    });
    ApiService.dio.httpClientAdapter = adapter;

    await Future.wait([
      ApiService.dio.get('/a'),
      ApiService.dio.get('/b'),
      ApiService.dio.get('/c'),
    ]);

    expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), hasLength(1));
  });

  test('a refused refresh signs the user out once', () async {
    await SecureStorageService.saveToken('expired-access');
    await SecureStorageService.saveRefreshToken('revoked');
    var notified = 0;
    ApiService.onUnauthorized = () => notified++;
    ApiService.dio.httpClientAdapter = _ScriptedAdapter((_) => (401, {}));

    await expectLater(ApiService.dio.get('/auth/me'), throwsA(isA<DioException>()));

    expect(await SecureStorageService.getToken(), isNull);
    expect(await SecureStorageService.getRefreshToken(), isNull);
    expect(notified, 1);
  });

  test('sign-out revokes the refresh token on the server', () async {
    await SecureStorageService.saveRefreshToken('refresh-1');
    final adapter = _ScriptedAdapter((_) => (204, {}));
    ApiService.dio.httpClientAdapter = adapter;

    await ApiService.revokeRefreshToken();

    expect(adapter.requests.single.path, endsWith('/auth/logout'));
  });
}
