import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ghost_button.dart';
import '../widgets/ui/neon_button.dart';

enum AppNotificationTone { success, error, warning, info }

final appMessengerKey = PushNotificationService.messengerKey;

/// Displays a concise floating notification with a tone-matched accent.
void showAppNotification(
  String message, {
  AppNotificationTone tone = AppNotificationTone.info,
  String? title,
  Duration duration = const Duration(seconds: 5),
}) {
  HapticFeedback.lightImpact();
  _notificationQueue.add(_QueuedNotification(
    message: message,
    tone: tone,
    title: title,
    duration: duration,
  ));
  _pumpNotificationQueue();
}

void _pumpNotificationQueue() {
  if (_notificationShowing || _notificationQueue.isEmpty) return;

  final notification = _notificationQueue.first;
  final overlay = PushNotificationService.navigatorKey.currentState?.overlay;
  final messenger = appMessengerKey.currentState;

  if (overlay != null) {
    _notificationShowing = true;
    _notificationQueue.removeAt(0);
    _showOverlayNotification(
      notification.message,
      tone: notification.tone,
      title: notification.title,
      duration: notification.duration,
    );
    return;
  }

  if (messenger != null) {
    _notificationShowing = true;
    _notificationQueue.removeAt(0);
    _showMessengerNotification(
      messenger,
      notification.message,
      tone: notification.tone,
      title: notification.title,
      duration: notification.duration,
    );
    Future<void>.delayed(notification.duration, () {
      _notificationShowing = false;
      _pumpNotificationQueue();
    });
    return;
  }

  _scheduleNotificationRetry();
}

void _scheduleNotificationRetry() {
  if (_notificationRetryTimer != null || _notificationQueue.isEmpty) return;
  _notificationRetryTimer =
      Timer.periodic(const Duration(milliseconds: 180), (_) {
    if (_notificationQueue.isEmpty) {
      _notificationRetryTimer?.cancel();
      _notificationRetryTimer = null;
      return;
    }
    _pumpNotificationQueue();
  });
}

void _showMessengerNotification(
  ScaffoldMessengerState messenger,
  String message, {
  required AppNotificationTone tone,
  String? title,
  required Duration duration,
}) {
  final (accent, icon, defaultTitle, glowColor) = switch (tone) {
    AppNotificationTone.success => (
        const Color(0xFF10B981),
        Icons.verified_rounded,
        'Success',
        const Color(0x6610B981),
      ),
    AppNotificationTone.error => (
        const Color(0xFFF43F5E),
        Icons.error_outline_rounded,
        'Attention Required',
        const Color(0x66F43F5E),
      ),
    AppNotificationTone.warning => (
        const Color(0xFFF59E0B),
        Icons.warning_amber_rounded,
        'Notice',
        const Color(0x66F59E0B),
      ),
    AppNotificationTone.info => (
        AppColors.cyan,
        Icons.info_outline_rounded,
        'Notification',
        const Color(0x6600E5FF),
      ),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        padding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
              decoration: BoxDecoration(
                color: const Color(0xFF142235),
                borderRadius: BorderRadius.circular(16),
                border: Border(
                  left: BorderSide(color: accent, width: 4),
                  top: const BorderSide(color: Color(0xFF34465C)),
                  right: const BorderSide(color: Color(0xFF34465C)),
                  bottom: const BorderSide(color: Color(0xFF34465C)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title ?? defaultTitle,
                          style: AppTextStyles.subtitle.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => messenger.hideCurrentSnackBar(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF94A3B8),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
}

OverlayEntry? _activeOverlayNotification;
final List<_QueuedNotification> _notificationQueue = [];
bool _notificationShowing = false;
Timer? _notificationRetryTimer;

class _QueuedNotification {
  const _QueuedNotification({
    required this.message,
    required this.tone,
    required this.title,
    required this.duration,
  });

  final String message;
  final AppNotificationTone tone;
  final String? title;
  final Duration duration;
}

void _showOverlayNotification(
  String message, {
  required AppNotificationTone tone,
  String? title,
  required Duration duration,
}) {
  final overlay = PushNotificationService.navigatorKey.currentState?.overlay;
  if (overlay == null) {
    _notificationShowing = false;
    _scheduleNotificationRetry();
    return;
  }

  final (accent, icon, defaultTitle, glow) = switch (tone) {
    AppNotificationTone.success => (
        const Color(0xFF34D399),
        Icons.celebration_rounded,
        'All set!',
        const Color(0x9934D399),
      ),
    AppNotificationTone.error => (
        const Color(0xFFFB7185),
        Icons.error_outline_rounded,
        'Let’s try that again',
        const Color(0x99FB7185),
      ),
    AppNotificationTone.warning => (
        const Color(0xFFFBBF24),
        Icons.warning_amber_rounded,
        'Quick note',
        const Color(0x99FBBF24),
      ),
    AppNotificationTone.info => (
        const Color(0xFF22D3EE),
        Icons.auto_awesome_rounded,
        'New update',
        const Color(0x9922D3EE),
      ),
  };

  _activeOverlayNotification?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _OverlayNotificationCard(
      message: message,
      title: title ?? defaultTitle,
      icon: icon,
      accent: accent,
      glow: glow,
      duration: duration,
      onDismiss: () {
        entry.remove();
        _activeOverlayNotification = null;
        _notificationShowing = false;
        _pumpNotificationQueue();
      },
    ),
  );
  _activeOverlayNotification = entry;
  overlay.insert(entry);
  Future<void>.delayed(duration, () {
    if (identical(_activeOverlayNotification, entry)) {
      entry.remove();
      _activeOverlayNotification = null;
      _notificationShowing = false;
      _pumpNotificationQueue();
    }
  });
}

class _OverlayNotificationCard extends StatefulWidget {
  const _OverlayNotificationCard({
    required this.message,
    required this.title,
    required this.icon,
    required this.accent,
    required this.glow,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final String title;
  final IconData icon;
  final Color accent;
  final Color glow;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_OverlayNotificationCard> createState() =>
      _OverlayNotificationCardState();
}

class _OverlayNotificationCardState extends State<_OverlayNotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -90 * (1 - curved.value)),
            child: Opacity(opacity: curved.value.clamp(0, 1), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF142235),
                    borderRadius: BorderRadius.circular(18),
                    border: Border(
                      left: BorderSide(color: widget.accent, width: 4),
                      top: const BorderSide(color: Color(0xFF34465C)),
                      right: const BorderSide(color: Color(0xFF34465C)),
                      bottom: const BorderSide(color: Color(0xFF34465C)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: widget.glow.withValues(alpha: 0.08),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(widget.icon, color: widget.accent, size: 23),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: AppTextStyles.subtitle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: 0.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss notification',
                        onPressed: widget.onDismiss,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays an ultra-attractive, frosted-glass confirmation dialog with neon glowing action buttons.
Future<bool> showAppConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  Color accent = AppColors.cyan,
  bool isDestructive = false,
}) async {
  HapticFeedback.mediumImpact();

  final effectiveAccent = isDestructive ? const Color(0xFFF43F5E) : accent;

  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss confirmation',
    barrierColor: Colors.black.withValues(alpha: 0.75),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (dialogContext, anim1, anim2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xF20B102B),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: effectiveAccent.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveAccent.withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: -4,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glowing hero icon
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              effectiveAccent.withValues(alpha: 0.3),
                              effectiveAccent.withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(
                            color: effectiveAccent.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: effectiveAccent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: effectiveAccent, size: 34),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.title.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: GhostButton(
                              label: cancelLabel,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              color: AppColors.textMuted,
                              height: 48,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: isDestructive
                                ? Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: const Color(0xFFE11D48),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFE11D48)
                                              .withValues(alpha: 0.4),
                                          blurRadius: 14,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: Center(
                                          child: Text(
                                            confirmLabel,
                                            style:
                                                AppTextStyles.subtitle.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : NeonButton(
                                    label: confirmLabel,
                                    height: 48,
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final curvedValue = Curves.easeOutBack.transform(anim1.value) - 1.0;
      return Transform(
        transform: Matrix4.translationValues(0.0, curvedValue * -20, 0.0)
          ..scaleByDouble(
            0.92 + (anim1.value * 0.08),
            0.92 + (anim1.value * 0.08),
            0.92 + (anim1.value * 0.08),
            1.0,
          ),
        child: Opacity(opacity: anim1.value, child: child),
      );
    },
  );

  return result ?? false;
}
