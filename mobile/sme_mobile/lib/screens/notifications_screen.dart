import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
import '../providers/api_service_provider.dart';
import '../providers/notification_providers.dart';
import '../inventory/app_notifications.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Notifications'),
      child: SafeArea(
        child: notificationsAsync.when(
          loading: () => const AppLoader(),
          error: (err, stack) => ErrorState(
            message: 'Could not load notifications.',
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (items) {
            final unreadCount = items.where((item) => !item.isRead).length;

            return RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.overlaySurface,
              onRefresh: () async {
                try {
                  await Future.wait<Object>([
                    ref.refresh(notificationsProvider.future),
                    ref.refresh(unreadNotificationCountProvider.future),
                  ]);
                } catch (_) {
                  if (context.mounted) {
                    showAppNotification(
                      'Could not refresh notifications. Please try again.',
                      tone: AppNotificationTone.error,
                      title: 'Refresh failed',
                    );
                  }
                }
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.isEmpty ? 2 : items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _LiveUpdatesBanner(unreadCount: unreadCount);
                  }
                  if (items.isEmpty) {
                    return const SizedBox(
                      height: 300,
                      child: EmptyState(
                        icon: Icons.notifications_none_rounded,
                        message:
                            'Nothing here yet. New updates will appear automatically.',
                      ),
                    );
                  }
                  return _NotificationTile(
                    key: ValueKey(items[i - 1].id),
                    notification: items[i - 1],
                    index: i - 1,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiveUpdatesBanner extends StatefulWidget {
  final int unreadCount;
  const _LiveUpdatesBanner({required this.unreadCount});
  @override
  State<_LiveUpdatesBanner> createState() => _LiveUpdatesBannerState();
}

class _LiveUpdatesBannerState extends State<_LiveUpdatesBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.unreadCount;
    final headline = unread == 0
        ? 'You’re all caught up'
        : '$unread new ${unread == 1 ? 'update' : 'updates'}';
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      borderColor: AppColors.cyan.withValues(alpha: 0.35),
      fill: AppColors.cyan.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  border: Border.all(
                      color: AppColors.cyan
                          .withValues(alpha: 0.2 + _pulse.value * 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan
                          .withValues(alpha: 0.06 + _pulse.value * 0.12),
                      blurRadius: 10 + _pulse.value * 12,
                    )
                  ],
                ),
                child: child,
              ),
              child: const Icon(Icons.notifications_active_outlined,
                  color: AppColors.cyan, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('YOUR UPDATES',
                    style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99)),
              child: const Text('AUTO',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            child: Align(
              key: ValueKey(unread),
              alignment: Alignment.centerLeft,
              child: Text(headline,
                  style: AppTextStyles.subtitle.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              unread == 0
                  ? 'Your latest activity will appear here.'
                  : 'Bookings, approvals and more — all in one place.',
              style:
                  AppTextStyles.bodyMuted.copyWith(fontSize: 13, height: 1.5)),
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.swipe_down_rounded,
                size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 7),
            Expanded(
                child: Text('Pull down to refresh · Checks every 15 seconds',
                    style: AppTextStyles.caption.copyWith(fontSize: 11))),
          ]),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final int index;
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.index,
  });

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    if (notification.isRead) return;
    try {
      await markNotificationRead(
        ref.read(apiServiceProvider),
        notification.id,
      );
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);
    } catch (_) {
      if (context.mounted) {
        showAppNotification(
          'We could not update this notification yet. Please try again.',
          tone: AppNotificationTone.error,
          title: 'Almost there',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notification.isRead;

    final accent = _accentFor(notification.type, unread);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: 350 + (index * 55).clamp(0, 350)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: child,
        ),
      ),
      child: GlassCard(
        onTap: () => _handleTap(context, ref),
        padding: const EdgeInsets.all(15),
        borderRadius: AppRadii.row,
        fill: unread ? accent.withValues(alpha: 0.12) : null,
        borderColor: unread ? accent.withValues(alpha: 0.65) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.42),
                    accent.withValues(alpha: 0.1)
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.6)),
                boxShadow: unread
                    ? [
                        BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 14)
                      ]
                    : null,
              ),
              child: Icon(_iconFor(notification.type), color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            if (unread)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 7, right: 8),
                decoration: const BoxDecoration(
                  color: AppColors.cyan,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.buttonGlow, blurRadius: 8)
                  ],
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: AppTextStyles.subtitle.copyWith(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      color: unread ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: AppTextStyles.bodyMuted.copyWith(
                      fontSize: 13,
                      color:
                          unread ? Colors.white.withValues(alpha: 0.88) : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _relativeTime(notification.createdAtLocal),
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    final value = type.toLowerCase();
    if (value.contains('booking')) return Icons.event_available_rounded;
    if (value.contains('inventory') || value.contains('stock')) {
      return Icons.inventory_2_rounded;
    }
    if (value.contains('payment') || value.contains('bill')) {
      return Icons.payments_rounded;
    }
    if (value.contains('approval')) return Icons.verified_rounded;
    if (value.contains('cancel')) return Icons.event_busy_rounded;
    return Icons.auto_awesome_rounded;
  }

  Color _accentFor(String type, bool unread) {
    final value = type.toLowerCase();
    if (value.contains('error') || value.contains('fail')) {
      return AppColors.error;
    }
    if (value.contains('warning')) return AppColors.warning;
    if (value.contains('success') || value.contains('confirm')) {
      return AppColors.success;
    }
    return unread ? AppColors.cyan : AppColors.electricBlue;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
