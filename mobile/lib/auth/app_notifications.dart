import 'package:flutter/material.dart';

enum AppNotificationTone { success, error, warning, info }

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showAppNotification(String message,
    {AppNotificationTone tone = AppNotificationTone.info}) {
  final (color, icon) = switch (tone) {
    AppNotificationTone.success =>
      (const Color(0xFF087F5B), Icons.check_circle_outline_rounded),
    AppNotificationTone.error =>
      (const Color(0xFFB42318), Icons.error_outline_rounded),
    AppNotificationTone.warning =>
      (const Color(0xFF9A6700), Icons.warning_amber_rounded),
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    ));
}
