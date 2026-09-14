import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.notifications_none_rounded,
                message: 'Nothing here yet.',
              );
            }

            return RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.overlaySurface,
              onRefresh: () async {
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _NotificationTile(notification: items[i]),
              ),
            );
          },
        ),
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
