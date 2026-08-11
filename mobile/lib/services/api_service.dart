import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      // For Android Emulator: use 10.0.2.2
      // For iOS Simulator: use localhost
      // For physical device: use your machine's IP address
      baseUrl: 'http://10.0.2.2:5298/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static Dio get dio {
    _dio.interceptors.clear();

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await SecureStorageService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            await SecureStorageService.clearAll();
            // Router will handle redirect based on auth state
          }
          return handler.next(error);
        },
      ),
    );

    return _dio;
  }
}
