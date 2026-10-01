import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'secure_storage_service.dart';

/// Central HTTP client for the ASP.NET Core backend.
/// Automatically attaches JWT from secure storage on every request.
class ApiService {
  static String get baseUrl => _dio.options.baseUrl;

  /// The server root without the trailing /api, for URLs the *browser* opens
  /// rather than the app calling - such as the page a payment gateway sends
  /// the customer back to after a hosted checkout.
  static String get origin {
    final url = baseUrl;
    return url.endsWith('/api') ? url.substring(0, url.length - 4) : url;
  }

  static set baseUrl(String url) {
    _dio.options.baseUrl = _normaliseBaseUrl(url);
  }

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _defaultBaseUrl(),
      // Generous on purpose. A free-tier host (Render, Railway) parks an
      // idle instance and takes 30-60s to wake on the next request -
      // measured at 41s cold against 6s warm. At the old 15s the very
      // first sign-in of a session always aborted, and the app blamed the
      // phone: "server is not responding, check your connection". The
      // request was fine; we simply were not waiting for it.
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
    ),
  );

  static String _defaultBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return _normaliseBaseUrl(configured);
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5298/api';
    return 'http://localhost:5298/api';
  }

  static String _normaliseBaseUrl(String url) {
    var normalised = url.trim();
    while (normalised.endsWith('/')) {
      normalised = normalised.substring(0, normalised.length - 1);
    }
    if (!normalised.endsWith('/api')) normalised = '$normalised/api';
    return normalised;
  }

  /// Per-request options for the endpoints that run an LLM pipeline.
  ///
  /// The 15-second default above is right for CRUD: if a list of bookings has
  /// not arrived by then something is wrong, and failing fast beats a spinner.
  /// It is far too short for the agent endpoints - a four-agent run makes
  /// several Gemini calls and a dozen tool calls back into this same API, and
  /// takes well past a minute when Gemini is rate-limiting and the client
  /// falls back across models.
  ///
  /// This was not theoretical: "Ask AI to book for you" timed out at 15s on
  /// every attempt while the pipeline went on to finish successfully and
  /// return 200, so the customer saw a failure for a booking the server had
  /// actually planned.
  ///
  /// Raised per request rather than on BaseOptions, so an ordinary screen
  /// still gives up quickly when the API is genuinely down.
  static Options get aiPipelineOptions =>
      Options(receiveTimeout: const Duration(minutes: 3));

  static bool _interceptorAttached = false;

  /// Called once when the backend rejects the session (401).
  ///
  /// The interceptor can clear the token, but it has no way to reach the
  /// Riverpod auth state, so without this the app kept rendering the
  /// logged-in shell over a dead session and every screen just showed its
  /// "Something went wrong" state - which reads as a server fault rather
  /// than an expired login. AuthNotifier wires itself in here at startup.
  /// The web client already does the equivalent (see the baseQueryWithAuth
  /// comment in frontend/src/api/bookingApi.ts).
  static void Function()? onUnauthorized;

  static bool _sessionExpiring = false;

  static const _retriedKey = 'refresh-retried';

  /// Only one refresh runs at a time: when a screen fires several requests
  /// and they all come back 401, they wait on the same refresh instead of
  /// each spending the (single-use) refresh token.
  static Future<String?>? _refreshing;

  static bool _canRefresh(RequestOptions request) =>
      request.extra[_retriedKey] != true &&
      !request.path.contains('/auth/login') &&
      !request.path.contains('/auth/refresh') &&
      !request.path.contains('/auth/logout');

  static Future<String?> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  static Future<String?> _doRefresh() async {
    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      // Straight through the same transport, but not through the interceptor:
      // a 401 from /auth/refresh itself must not trigger another refresh.
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {_retriedKey: true}),
      );
      final access = response.data?['accessToken'] as String?;
      final nextRefresh = response.data?['refreshToken'] as String?;
      if (access == null || access.isEmpty) return null;
      await SecureStorageService.saveToken(access);
      if (nextRefresh != null) await SecureStorageService.saveRefreshToken(nextRefresh);
      return access;
    } on DioException {
      return null;
    }
  }

  /// Best-effort server-side sign-out: revokes the refresh token so it cannot
  /// be used again even if the device is compromised later.
  static Future<void> revokeRefreshToken() async {
    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return;
    try {
      await dio.post('/auth/logout', data: {'refreshToken': refreshToken});
    } on DioException {
      // Offline or the server is down: the local sign-out still happens.
    }
  }

  static Dio get dio {
    if (!_interceptorAttached) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = await SecureStorageService.getToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            return handler.next(options);
          },
          onError: (DioException error, handler) async {
            final request = error.requestOptions;
            if (error.response?.statusCode == 401 && _canRefresh(request)) {
              // The access token expired: trade the refresh token for a new
              // pair once, then replay the request that failed.
              final fresh = await _refreshAccessToken();
              if (fresh != null) {
                request.headers['Authorization'] = 'Bearer $fresh';
                request.extra[_retriedKey] = true;
                try {
                  return handler.resolve(await _dio.fetch(request));
                } on DioException catch (retryError) {
                  return handler.next(retryError);
                }
              }
            }
            // A refused /auth/refresh is reported by the request that asked
            // for it, below - handling it here too would sign out twice.
            if (error.response?.statusCode == 401 && !request.path.contains('/auth/refresh')) {
              // No refresh token, or the server refused it → clear storage,
              // then tell the app so it can send the user back to the login
              // screen. Guarded so a burst of concurrent 401s (a screen fires
              // several requests at once) only tears the session down once.
              if (!_sessionExpiring) {
                _sessionExpiring = true;
                await SecureStorageService.clearAll();
                try {
                  onUnauthorized?.call();
                } finally {
                  _sessionExpiring = false;
                }
              }
            }
            return handler.next(error);
          },
        ),
      );
      _interceptorAttached = true;
    }
    return _dio;
  }
}
