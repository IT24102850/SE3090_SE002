import 'package:flutter/material.dart';

/// Simple, reusable in-app notification helper using Material SnackBar.
/// Usage:
///   Notifier.success(context, 'Saved successfully');
///   Notifier.error(context, 'Failed to save');
/// Or via BuildContext extension:
///   context.notifySuccess('Saved successfully');

enum NotificationType { success, error, info, warning, invalid, failed }

class Notifier {
  Notifier._();

  static void show(
    BuildContext context,
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final theme = Theme.of(context);
    final color = _backgroundColorFor(type, theme);
    final icon = _iconFor(type, theme);

    final snack = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snack);
  }

  static void success(BuildContext context, String message,
          {Duration? duration}) =>
      show(context, message,
          type: NotificationType.success, duration: duration ?? const Duration(seconds: 3));

  static void error(BuildContext context, String message, {Duration? duration}) =>
      show(context, message,
          type: NotificationType.error, duration: duration ?? const Duration(seconds: 4));

  static void info(BuildContext context, String message, {Duration? duration}) =>
      show(context, message,
          type: NotificationType.info, duration: duration ?? const Duration(seconds: 3));

  static void warning(BuildContext context, String message, {Duration? duration}) =>
      show(context, message,
          type: NotificationType.warning, duration: duration ?? const Duration(seconds: 3));

  static void invalid(BuildContext context, String message, {Duration? duration}) =>
      show(context, message,
          type: NotificationType.invalid, duration: duration ?? const Duration(seconds: 3));

  static void failed(BuildContext context, String message, {Duration? duration}) =>
      show(context, message,
          type: NotificationType.failed, duration: duration ?? const Duration(seconds: 4));

  static IconData _iconFor(NotificationType type, ThemeData theme) {
    switch (type) {
      case NotificationType.success:
        return Icons.check_circle_outline;
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.info:
        return Icons.info_outline;
      case NotificationType.warning:
        return Icons.warning_amber_outlined;
      case NotificationType.invalid:
        return Icons.block;
      case NotificationType.failed:
        return Icons.cancel_outlined;
    }
  }

  static Color _backgroundColorFor(NotificationType type, ThemeData theme) {
    switch (type) {
      case NotificationType.success:
        return Colors.green.shade700;
      case NotificationType.error:
        return Colors.red.shade700;
      case NotificationType.info:
        return theme.colorScheme.primary;
      case NotificationType.warning:
        return Colors.orange.shade800;
      case NotificationType.invalid:
        return Colors.deepOrange.shade700;
      case NotificationType.failed:
        return Colors.purple.shade700;
    }
  }
}

extension NotifierExtension on BuildContext {
  void notifySuccess(String message, {Duration? duration}) =>
      Notifier.success(this, message, duration: duration);
  void notifyError(String message, {Duration? duration}) =>
      Notifier.error(this, message, duration: duration);
  void notifyInfo(String message, {Duration? duration}) =>
      Notifier.info(this, message, duration: duration);
  void notifyWarning(String message, {Duration? duration}) =>
      Notifier.warning(this, message, duration: duration);
  void notifyInvalid(String message, {Duration? duration}) =>
      Notifier.invalid(this, message, duration: duration);
  void notifyFailed(String message, {Duration? duration}) =>
      Notifier.failed(this, message, duration: duration);
}
