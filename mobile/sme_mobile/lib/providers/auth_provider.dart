import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

// ─────────────────────────────────────────────────────────
// Auth State
// ─────────────────────────────────────────────────────────
class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;
  final bool isInitialized;
  final bool isProfileComplete;
  final String? error;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.isInitialized = false,
    this.isProfileComplete = false,
    this.error,
  });

  bool get isAuthenticated => token != null && token!.isNotEmpty && user != null;


  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    bool? isInitialized,
    String? error,
    bool? isProfileComplete,
    bool clearUser = false,
    bool clearToken = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      token: clearToken ? null : (token ?? this.token),
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Auth Notifier (Riverpod StateNotifier)
// ─────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  /// Restore session from flutter_secure_storage on cold start.
  Future<void> initializeAuth() async {
    try {
      final token = await SecureStorageService.getToken();
      final userJson = await SecureStorageService.getUser();

      if (token != null && token.isNotEmpty && userJson != null) {
        final user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        state = AuthState(
          user: user,
          token: token,
          isInitialized: true,
          isProfileComplete: true, // Assume complete for now
        );
      } else {
        state = const AuthState(isInitialized: true);
      }
    } catch (_) {
      // Corrupted storage → start clean
      await SecureStorageService.clearAll();
      state = const AuthState(isInitialized: true);
    }
  }

  /// POST /api/auth/login
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await ApiService.dio.post(
        '/auth/login',
        data: {'email': email.trim(), 'password': password},
      );

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String? ?? data['token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid response from server',
        );
        return false;
      }

      final userMap = data['user'] as Map<String, dynamic>? ?? data;
      final user = User.fromJson(userMap);

      await SecureStorageService.saveToken(accessToken);
      await SecureStorageService.saveUser(jsonEncode(user.toJson()));

      // Optional refresh token
      final refresh = data['refreshToken'] as String?;
      if (refresh != null) {
        await SecureStorageService.saveRefreshToken(refresh);
      }

      state = AuthState(
        user: user,
        token: accessToken,
        isLoading: false,
        isInitialized: true,
        isProfileComplete: true, // Assume complete for now
      );
      return true;
    } on DioException catch (e) {
      final message = _extractError(e) ?? 'Invalid email or password';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  /// POST /api/tenant/onboard  (business registration)
  Future<bool> register({
    required String businessName,
    required String businessType,
    required String address,
    required String phone,
    required String adminEmail,
    required String adminPassword,
    required String adminFullName,
    String? adminPhone,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await ApiService.dio.post(
        '/tenant/onboard',
        data: {
          'businessName': businessName.trim(),
          'businessType': businessType,
          'address': address.trim(),
          'phone': phone.trim(),
          'adminEmail': adminEmail.trim(),
          'adminPassword': adminPassword,
          'adminFullName': adminFullName.trim(),
          if (adminPhone != null && adminPhone.isNotEmpty) 'adminPhone': adminPhone.trim(),
        },
      );

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String? ?? data['token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid response from server',
        );
        return false;
      }

      final userMap = data['user'] as Map<String, dynamic>? ?? data;
      final user = User.fromJson(userMap);

      await SecureStorageService.saveToken(accessToken);
      await SecureStorageService.saveUser(jsonEncode(user.toJson()));

      final refresh = data['refreshToken'] as String?;
      if (refresh != null) {
        await SecureStorageService.saveRefreshToken(refresh);
      }

      state = AuthState(
        user: user,
        token: accessToken,
        isLoading: false,
        isInitialized: true,
        isProfileComplete: true, // Assume complete for now
      );
      return true;
    } on DioException catch (e) {
      final message = _extractError(e) ?? 'Registration failed';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  /// Clear secure storage + reset state
  Future<void> logout() async {
    await SecureStorageService.clearAll();
    state = const AuthState(isInitialized: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  String? _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return data['message']?.toString() ??
          data['title']?.toString() ??
          data['error']?.toString();
    }
    if (data is String && data.isNotEmpty) return data;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Server is not responding. Check your connection.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Is the API running?';
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
