import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

// Auth State
class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.token, this.isLoading = false, this.error});

  bool get isAuthenticated => token != null && user != null;

  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      token: token ?? this.token,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Auth Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  // Initialize auth from secure storage on app start
  Future<void> initializeAuth() async {
    final token = await SecureStorageService.getToken();
    final userJson = await SecureStorageService.getUser();

    if (token != null && userJson != null) {
      final user = User.fromJson(jsonDecode(userJson));
      state = AuthState(user: user, token: token);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await ApiService.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      final accessToken = response.data['accessToken'] as String;
      final user = User.fromJson(response.data['user']);

      await SecureStorageService.saveToken(accessToken);
      await SecureStorageService.saveUser(jsonEncode(user.toJson()));

      state = AuthState(user: user, token: accessToken);
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? 'Invalid email or password';
      state = state.copyWith(isLoading: false, error: message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong');
    }
  }

  Future<void> register({
    required String businessName,
    required String businessType,
    required String address,
    required String phone,
    required String adminEmail,
    required String adminPassword,
    required String adminFullName,
    String? adminPhone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await ApiService.dio.post(
        '/tenant/onboard',
        data: {
          'businessName': businessName,
          'businessType': businessType,
          'address': address,
          'phone': phone,
          'adminEmail': adminEmail,
          'adminPassword': adminPassword,
          'adminFullName': adminFullName,
          'adminPhone': adminPhone,
        },
      );

      final accessToken = response.data['accessToken'] as String;
      final user = User.fromJson(response.data['user']);

      await SecureStorageService.saveToken(accessToken);
      await SecureStorageService.saveUser(jsonEncode(user.toJson()));

      state = AuthState(user: user, token: accessToken);
    } on DioException catch (e) {
      final message = e.response?.data?['message'] ?? 'Registration failed';
      state = state.copyWith(isLoading: false, error: message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Something went wrong');
    }
  }

  Future<void> logout() async {
    await SecureStorageService.clearAll();
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
