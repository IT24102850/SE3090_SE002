import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/biometric_auth_service.dart';
import 'package:sme_mobile/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('does not allow biometric unlock until a Quick PIN is configured',
      () async {
    await SecureStorageService.setBiometricsEnabled(true);

    expect(await BiometricAuthService.canUseBiometrics(), isFalse);
    expect(await BiometricAuthService.authenticate(), isFalse);
  });

  test('does not allow biometric unlock when its setting is disabled',
      () async {
    await SecureStorageService.savePin('1234');
    await SecureStorageService.setBiometricsEnabled(false);

    expect(await BiometricAuthService.canUseBiometrics(), isFalse);
    expect(await BiometricAuthService.authenticate(), isFalse);
  });
}
