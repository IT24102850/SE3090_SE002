import 'package:flutter/material.dart';

enum AppNotificationTone { success, error, info }

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showAppNotification(String message,
    {AppNotificationTone tone = AppNotificationTone.info}) {
  final (color, icon) = switch (tone) {
    AppNotificationTone.success =>
      (const Color(0xFF087F5B), Icons.check_circle_outline_rounded),
    AppNotificationTone.error =>
      (const Color(0xFFB42318), Icons.error_outline_rounded),
    AppNotificationTone.info =>
      (const Color(0xFF1D4ED8), Icons.info_outline_rounded),
  };
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: color,
      duration: const Duration(seconds: 4),
      content: Row(children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}
