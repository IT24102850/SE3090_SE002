import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  static const _accessTokenKey = 'sme.access-token';
  final FlutterSecureStorage _storage;

  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  Future<String?> read() => _storage.read(key: _accessTokenKey);
  Future<void> write(String token) =>
      _storage.write(key: _accessTokenKey, value: token);
  Future<void> clear() => _storage.delete(key: _accessTokenKey);
}
