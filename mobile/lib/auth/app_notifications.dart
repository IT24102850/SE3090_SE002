import 'package:flutter/material.dart';

enum AppNotificationTone { success, error, warning, info }

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showAppNotification(String message,
    {AppNotificationTone tone = AppNotificationTone.info}) {
  final (accent, icon, title) = switch (tone) {
    AppNotificationTone.success => (
        const Color(0xFF34D399),
        Icons.check_circle_rounded,
        'Success'
      ),
    AppNotificationTone.error => (
        const Color(0xFFF87171),
        Icons.error_rounded,
        'Something went wrong'
      ),
    AppNotificationTone.warning => (
        const Color(0xFFFBBF24),
        Icons.warning_rounded,
        'Attention'
      ),
    AppNotificationTone.info => (
        const Color(0xFF60A5FA),
        Icons.info_rounded,
        'Information'
      ),
  };
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      content: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF172238),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: .42)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: .16),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          height: 1.25,
                          fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: () => messenger.hideCurrentSnackBar(),
              icon: const Icon(Icons.close_rounded,
                  color: Color(0xFF94A3B8), size: 19),
            ),
          ],
        ),
      ),
    ));
}

Future<bool> showAppConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  IconData icon = Icons.help_outline_rounded,
  Color accent = const Color(0xFF818CF8),
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: accent, size: 28),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
