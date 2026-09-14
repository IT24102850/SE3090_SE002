import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/api_service_provider.dart';
import '../providers/auth_provider.dart';

/// Wires up FCM push notifications. Fully real, but entirely inert until a
/// real Firebase project's config files (google-services.json /
/// GoogleService-Info.plist / firebase_options.dart) are added to this
/// project - matches the backend's IPushNotificationSender, which is the
/// same "configured or clean no-op" pattern. Every failure path here is
/// caught and logged, never rethrown - push notifications must never be
/// able to block app startup.
class PushNotificationService {
  /// Lets foreground push messages show a SnackBar without threading a
  /// BuildContext through here. Attach via MaterialApp(scaffoldMessengerKey:).
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  static Future<void> init(WidgetRef ref) async {
    if (kIsWeb) {
      // Web push needs a service worker + VAPID key, and there's no way to
      // verify it in this project's dev environment either (no Android/iOS
      // emulator, per earlier testing constraints) - skipped entirely
      // rather than half-wired and unverifiable.
      return;
    }

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push notifications unavailable (no Firebase project configured yet): $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission();
    } catch (e) {
      debugPrint('Push notification permission request failed: $e');
      return;
    }

    await _registerToken(ref, messaging);
    messaging.onTokenRefresh.listen((_) => _registerToken(ref, messaging));

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title;
      final body = message.notification?.body;
      final text = [title, body].where((s) => s != null && s.isNotEmpty).join(': ');
      if (text.isEmpty) return;
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  static Future<void> _registerToken(WidgetRef ref, FirebaseMessaging messaging) async {
    if (!ref.read(authProvider).isAuthenticated) return;

    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      final dio = ref.read(apiServiceProvider);
      await dio.post('/devicetokens', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('Could not register device token: $e');
    }
  }
}
