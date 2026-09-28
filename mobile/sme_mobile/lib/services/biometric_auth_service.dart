import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

/// Real device biometric authentication service (Face ID & Fingerprint)
/// paired with secure hardware storage.
class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Checks if the physical device or emulator has biometric hardware.
  static Future<bool> isBiometricsAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();
      return canCheck && types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Lists available biometric types (e.g. face, fingerprint, iris).
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Returns true if device has Face ID hardware.
  static Future<bool> hasFaceId() async {
    final types = await getAvailableBiometrics();
    return types.contains(BiometricType.face);
  }

  /// Returns true if device has Fingerprint sensor.
  static Future<bool> hasFingerprint() async {
    final types = await getAvailableBiometrics();
    return types.contains(BiometricType.fingerprint);
  }

  /// Authenticate using device biometrics (Face ID or Fingerprint).
  static Future<bool> authenticate({
    String localizedReason = 'Unlock Unify Enterprise Workspace with Biometrics',
  }) async {
    try {
      final enabled = await SecureStorageService.isBiometricsEnabled();
      if (!enabled) return false;

      final canCheck = await isBiometricsAvailable();
      if (!canCheck) return false;

      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
      );
    } on PlatformException catch (_) {
      // Platform failure (e.g. user cancelled or biometric not enrolled)
      return false;
    } catch (_) {
      return false;
    }
  }
}
