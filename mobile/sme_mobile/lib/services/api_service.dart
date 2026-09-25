import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'secure_storage_service.dart';

/// Central HTTP client for the ASP.NET Core backend.
/// Automatically attaches JWT from secure storage on every request.
class ApiService {
  // Android's emulator networking sandboxes "localhost" to the emulator
  // itself, not the host machine - 10.0.2.2 is the documented alias back to
  // the host. Every other target (iOS simulator, Windows/web/physical
  // device on the same network as a manually-set host) keeps using
  // localhost as before.
  // - Physical device:   http://<your-lan-ip>:5298/api
  // - Deployed:          https://your-api.railway.app/api
  static String get baseUrl {
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5298/api';
    return 'http://localhost:5298/api';
  }

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
    ),
  );

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
            if (error.response?.statusCode == 401) {
              // Token expired / invalid → clear storage, then tell the app so
              // it can send the user back to the login screen. Guarded so a
              // burst of concurrent 401s (a screen fires several requests at
              // once) only tears the session down once.
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
