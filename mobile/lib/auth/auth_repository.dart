import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'authenticated_api_client.dart';
import 'secure_token_store.dart';

class AuthRepository {
  AuthRepository({required String apiBaseUrl, SecureTokenStore? tokenStore})
      : _apiBaseUrl = apiBaseUrl.replaceFirst(RegExp(r'/$'), ''),
        _tokenStore = tokenStore ?? SecureTokenStore();

  final String _apiBaseUrl;
  final SecureTokenStore _tokenStore;

  Future<AuthSession?> restoreSession() async {
    final token = await _tokenStore.read();
    final session = token == null ? null : AuthSession.fromToken(token);
    if (session == null && token != null) await _tokenStore.clear();
    return session;
  }

  Future<AuthSession> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = jsonDecode(response.body.isEmpty ? '{}' : response.body)
        as Map<String, dynamic>;
    final token = body['accessToken'] ?? body['token'];
    final session = token is String ? AuthSession.fromToken(token) : null;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        session == null) {
      throw const AuthException(
          'Login failed. Check your credentials and try again.');
    }

    await _tokenStore.write(token);
    return session;
  }

  Future<void> logout() => _tokenStore.clear();

  /// Creates the shared authenticated client used by inventory feature screens.
  AuthenticatedApiClient authenticatedClient(AuthSession session) =>
      AuthenticatedApiClient(
          apiBaseUrl: _apiBaseUrl, accessToken: session.token);
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
