import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_stream_service.dart';

/// Shows a notification on the device.
abstract class NotificationPresenter {
  Future<void> init();
  Future<void> show(int id, String title, String body);
}

/// System notifications on the phone for everything the backend announces -
/// booking confirmations and reminders, cancellations, low stock, and agent
/// workflow decisions ("your booking request was approved").
///
/// Why not Firebase Cloud Messaging: FCM needs a Firebase project whose
/// google-services.json is compiled into the APK, and this project has none
/// (PushNotificationService stays a clean no-op without it). The API already
/// streams every Notification row to the signed-in user over Server-Sent
/// Events (NotificationStreamService); this raises each one as an Android
/// notification while the app is running or in the background. What it cannot
/// do is wake an app the system has killed - that is exactly what FCM adds,
/// and the notification is still waiting in the in-app list either way.
class DeviceNotificationService {
  DeviceNotificationService({
    NotificationPresenter? presenter,
    Stream<LiveNotification>? source,
    Future<void> Function()? startStream,
    Future<void> Function()? stopStream,
  })  : _presenter = presenter ?? _LocalNotificationPresenter(),
        _source = source ?? NotificationStreamService().notifications,
        _startStream = startStream ?? NotificationStreamService().start,
        _stopStream = stopStream ?? NotificationStreamService().stop;

  static final DeviceNotificationService instance = DeviceNotificationService();

  final NotificationPresenter _presenter;
  final Stream<LiveNotification> _source;
  final Future<void> Function() _startStream;
  final Future<void> Function() _stopStream;

  StreamSubscription<LiveNotification>? _subscription;
  bool _initialised = false;
  final _shown = <String>{};

  bool get isRunning => _subscription != null;

  /// Called once the user is signed in. Never throws: notifications must not
  /// be able to break sign-in.
  Future<void> start() async {
    if (_subscription != null) return;
    try {
      if (!_initialised) {
        await _presenter.init();
        _initialised = true;
      }
    } catch (e) {
      debugPrint('Device notifications unavailable: $e');
    }
    _subscription = _source.listen(_present);
    await _startStream();
  }

  /// Called on sign-out, so the next user on this phone sees nothing of the last one's.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _shown.clear();
    await _stopStream();
  }

  Future<void> _present(LiveNotification n) async {
    // The stream can replay a notification after a reconnect; show it once.
    if (n.id.isNotEmpty && !_shown.add(n.id)) return;
    final title = n.title.trim().isEmpty ? 'Unify' : n.title.trim();
    try {
      await _presenter.show(n.id.hashCode & 0x7fffffff, title, n.message);
    } catch (e) {
      debugPrint('Could not show notification: $e');
    }
  }
}

class _LocalNotificationPresenter implements NotificationPresenter {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationDetails(
    'unify_updates',
    'Bookings and approvals',
    channelDescription: 'Booking confirmations, reminders, low-stock alerts and approval decisions',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  Future<void> init() async {
    if (kIsWeb) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    // Android 13+ asks the user; earlier versions grant it at install.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (kIsWeb) return;
    await _plugin.show(id, title, body,
        const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()));
  }
}
