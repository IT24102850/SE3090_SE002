import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for JWT tokens and user data.
/// Uses encrypted SharedPreferences on Android and Keychain on iOS.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _tokenKey = 'access_token';
  static const _userKey = 'user_data';
  static const _refreshTokenKey = 'refresh_token';

  // ── Token ──────────────────────────────────────────────
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  // ── Refresh Token (optional) ───────────────────────────
  static Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  // ── User JSON ──────────────────────────────────────────
  static Future<void> saveUser(String userJson) async {
    await _storage.write(key: _userKey, value: userJson);
  }

  static Future<String?> getUser() async {
    return _storage.read(key: _userKey);
  }

  static Future<void> deleteUser() async {
    await _storage.delete(key: _userKey);
  }

  // ── Clear everything (logout) ──────────────────────────
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
