import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

/// Central HTTP client for the ASP.NET Core backend.
/// Automatically attaches JWT from secure storage on every request.
class ApiService {
  // Change this to match your environment:
  // - Android Emulator:  http://10.0.2.2:5298/api
  // - iOS Simulator:     http://localhost:5298/api
  // - Physical device:   http://<your-lan-ip>:5298/api
  // - Deployed:          https://your-api.railway.app/api
  static const String baseUrl = 'http://localhost:5298/api';

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
              // Token expired / invalid → clear storage
              await SecureStorageService.clearAll();
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
