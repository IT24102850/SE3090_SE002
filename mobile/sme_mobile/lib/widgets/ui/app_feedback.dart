import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'ghost_button.dart';

/// On-theme snackbars. Screens call these instead of building a [SnackBar] so
/// success and failure always look the same everywhere.
class AppSnackBar {
  const AppSnackBar._();

  static void success(BuildContext context, String message) =>
      _show(context, message, Icons.check_circle_outline_rounded, AppColors.cyan);

  static void error(BuildContext context, String message) =>
      _show(context, message, Icons.error_outline_rounded, AppColors.magenta);

  static void info(BuildContext context, String message) =>
      _show(context, message, Icons.info_outline_rounded, AppColors.textSecondary);

  static void _show(BuildContext context, String message, IconData icon, Color accent) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.inputFill,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// Inline failure inside a form. Magenta rather than Material red — the danger
/// hue on this theme is the accent, and a red-on-navy banner reads as a
/// foreign element.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, onDismiss == null ? 12 : 4, 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.image),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.iconSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

/// Centred glyph, muted caption, optional action — the shape every "nothing
/// here yet" state in the app takes.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Scrollable, not just centred: an empty state can be handed a short
    // viewport (a sliver fill on a small screen, a sheet, landscape) and a
    // bare Column would overflow rather than shrink.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.iconGhost),
            const SizedBox(height: 18),
            if (title != null) ...[
              Text(title!, style: AppTextStyles.title, textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            Text(message, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              GhostButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's only spinner, so loading never falls back to the Material default
/// blue.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.size = 28, this.strokeWidth = 2.6, this.message});

  final double size;
  final double strokeWidth;

  /// Optional caption under the spinner for longer waits.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: strokeWidth,
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// An error panel with a retry, for the `AsyncValue.error` branch of a
/// Riverpod-backed screen.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Something went wrong',
      message: message,
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
    );
  }
}
