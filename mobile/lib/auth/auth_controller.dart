import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'auth_session.dart';
import 'authenticated_api_client.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);
  final AuthRepository _repository;

  AuthSession? session;
  bool isRestoring = true;

  Future<void> restore() async {
    session = await _repository.restoreSession();
    isRestoring = false;
    notifyListeners();
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
