import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

/// Central HTTP client for the ASP.NET Core backend.
/// Automatically attaches JWT from secure storage on every request.
class ApiService {


  static String get baseUrl => _dio.options.baseUrl;

  static set baseUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    _dio.options.baseUrl = u;
  }

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
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
              // Token expired / invalid → clear the account session, then tell the app so
              // it can send the user back to the login screen. Guarded so a
              // burst of concurrent 401s (a screen fires several requests at
              // once) only tears the session down once.
              if (!_sessionExpiring) {
                _sessionExpiring = true;
                await SecureStorageService.clearSession();
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
