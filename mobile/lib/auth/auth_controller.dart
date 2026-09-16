import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'auth_session.dart';
import 'authenticated_api_client.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);
  final AuthRepository _repository;

  AuthSession? session;
  bool isRestoring = true;

  /// Clears any previous-device session and exposes the login screen.
  ///
  /// Mobile devices are often shared in a workplace, so this app deliberately
  /// asks for credentials on every fresh launch instead of restoring a token.
  Future<void> startSignedOut() async {
    try {
      await _repository.logout();
    } catch (_) {
      // Storage cleanup is best-effort: lack of storage must not block login.
    } finally {
      session = null;
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    session = await _repository.login(email, password);
    notifyListeners();
  }

  Future<void> logout() async {
    await _repository.logout();
    session = null;
    notifyListeners();
  }

  AuthenticatedApiClient authenticatedClient() {
    final currentSession = session;
    if (currentSession == null) {
      throw StateError('An authenticated session is required.');
    }
    return _repository.authenticatedClient(currentSession);
  }
}
