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
    String? subType,
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
          if (subType != null && subType.isNotEmpty) 'subType': subType,
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

  /// POST /api/auth/register — customer self-registration, scoped to a
  /// single existing tenant (never creates a new business). The backend
  /// always assigns Role=Customer regardless of what's sent.
  Future<bool> registerCustomer({
    required String tenantId,
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await ApiService.dio.post(
        '/auth/register',
        data: {
          'tenantId': tenantId,
          'fullName': fullName.trim(),
          'email': email.trim(),
          'password': password,
          'phone': phone?.trim() ?? '',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String? ?? data['token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'Invalid response from server');
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
        isProfileComplete: true,
      );
      return true;
    } on DioException catch (e) {
      final message = _extractError(e) ?? 'Could not create your account.';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  /// PUT /api/auth/me — FR-C2 self-service profile update.
  Future<bool> updateProfile({
    String? fullName,
    String? phone,
    String? address,
    String? insuranceProvider,
    String? insuranceNumber,
    String? medicalNotes,
    String? profilePictureUrl,
    /// Send an explicit empty string to clear the photo; null just leaves
    /// it untouched, matching how the other optional fields behave.
    bool removeProfilePicture = false,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await ApiService.dio.put('/auth/me', data: {
        if (fullName != null) 'fullName': fullName,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (insuranceProvider != null) 'insuranceProvider': insuranceProvider,
        if (insuranceNumber != null) 'insuranceNumber': insuranceNumber,
        if (medicalNotes != null) 'medicalNotes': medicalNotes,
        if (removeProfilePicture) 'profilePictureUrl': ''
        else if (profilePictureUrl != null) 'profilePictureUrl': profilePictureUrl,
      });

      final user = User.fromJson(response.data as Map<String, dynamic>);
      await SecureStorageService.saveUser(jsonEncode(user.toJson()));
      state = state.copyWith(user: user, isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e) ?? 'Could not update your profile.');
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

  /// Drops the session locally after the backend has already rejected it.
  ///
  /// Distinct from logout(): the token is gone by the time this runs (the
  /// Dio interceptor cleared it), and there is no server call to make - this
  /// only flips the in-memory state so main.dart routes back to the login
  /// screen instead of leaving the user on a screen that can no longer load
  /// anything. Ignores repeat calls once already logged out.
  void onSessionExpired() {
    if (!state.isAuthenticated) return;
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
  final notifier = AuthNotifier();
  // A 401 from any request now ends the session everywhere, rather than
  // leaving each screen to fail on its own.
  ApiService.onUnauthorized = notifier.onSessionExpired;
  return notifier;
});
