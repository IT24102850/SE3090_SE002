import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../inventory/app_notifications.dart';
import '../models/notification_model.dart';
import '../providers/api_service_provider.dart';
import '../providers/notification_providers.dart';
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
                // Row 0 is the live-updates banner, so the tiles are offset by
                // one; with no notifications the second row carries the empty
                // state instead, which is why itemCount is 2 in that case.
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
                  return _NotificationTile(notification: items[i - 1]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiveUpdatesBanner extends StatelessWidget {
  final int unreadCount;

  const _LiveUpdatesBanner({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      borderRadius: AppRadii.row,
      borderColor: AppColors.cyan.withValues(alpha: 0.38),
      fill: AppColors.cyan.withValues(alpha: 0.07),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.45),
                  blurRadius: 9,
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE UPDATES',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Automatically checks every 15 seconds',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.magenta.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: AppColors.magenta.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '$unreadCount unread',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  Future<void> _handleTap(WidgetRef ref) async {
    if (notification.isRead) return;
    await markNotificationRead(ref.read(apiServiceProvider), notification.id);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationCountProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notification.isRead;

    return GlassCard(
      onTap: () => _handleTap(ref),
      padding: const EdgeInsets.all(14),
      borderRadius: AppRadii.row,
      // Unread rows carry a cyan rim rather than a different fill — on glass a
      // fill change is almost invisible, a lit edge is not.
      borderColor: unread ? AppColors.cyan.withValues(alpha: 0.45) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: const BoxDecoration(
                color: AppColors.cyan,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.buttonGlow, blurRadius: 8)],
              ),
            )
          else
            const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification.title, style: AppTextStyles.subtitle.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(notification.message, style: AppTextStyles.bodyMuted.copyWith(fontSize: 13)),
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
    );
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
