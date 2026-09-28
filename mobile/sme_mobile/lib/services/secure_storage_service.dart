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

  // ── PIN & Biometrics ──────────────────────────────────
  static const _pinKey = 'security_pin';
  static const _biometricsKey = 'biometrics_enabled';

  static Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  static Future<String?> getPin() async {
    return _storage.read(key: _pinKey);
  }

  static Future<bool> hasPin() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> deletePin() async {
    await _storage.delete(key: _pinKey);
  }

  /// Clears the account session while preserving this device's Quick PIN.
  /// After the next email sign-in, the PIN can unlock the saved session again.
  static Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  static Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(key: _biometricsKey, value: enabled ? 'true' : 'false');
  }

  static Future<bool> isBiometricsEnabled() async {
    final val = await _storage.read(key: _biometricsKey);
    return val == 'true' || val == null; // default enabled
  }

  // ── Clear everything (corrupt storage / reset) ─────────
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
