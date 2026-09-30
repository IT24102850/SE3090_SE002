import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/notification_sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requests playback of the Android default notification sound', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.example.sme_mobile/notification_sound'),
        (call) async {
      calls.add(call);
      return null;
    });

    try {
      playMobileNotificationSound(platform: TargetPlatform.android);
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'play');
    } finally {
      messenger.setMockMethodCallHandler(
          const MethodChannel('com.example.sme_mobile/notification_sound'),
          null);
    }
  });
}
