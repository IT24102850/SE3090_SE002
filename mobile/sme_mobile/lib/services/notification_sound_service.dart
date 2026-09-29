import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, debugPrint, TargetPlatform;
import 'package:flutter/services.dart';

const _notificationSoundChannel =
    MethodChannel('com.example.sme_mobile/notification_sound');

void playMobileNotificationSound({TargetPlatform? platform}) {
  final playback = (platform ?? defaultTargetPlatform) == TargetPlatform.android
      ? _notificationSoundChannel.invokeMethod<void>('play')
      : SystemSound.play(SystemSoundType.alert);
  unawaited(playback.catchError((Object error) {
    debugPrint('Notification sound unavailable: $error');
  }));
}
