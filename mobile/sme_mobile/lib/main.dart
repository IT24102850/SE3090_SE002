import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory/app_notifications.dart';
import 'models/notification_model.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_providers.dart';
import 'screens/unify_auth/welcome_flow_screen.dart';
import 'screens/role_home.dart';
import 'services/device_notification_service.dart';
import 'screens/profile_setup_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/ui/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Restore JWT + user from flutter_secure_storage on cold start
    Future.microtask(() async {
      await ref.read(authProvider.notifier).initializeAuth();
      // Never allowed to block/crash startup - see PushNotificationService's
      // own internal try/catch guards for why this is safe to call unconditionally.
      unawaited(PushNotificationService.init(ref));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    ref.listen(authProvider.select((state) => state.isAuthenticated), (was, now) {
      if (now) {
        unawaited(DeviceNotificationService.instance.start());
      } else if (was == true) {
        unawaited(DeviceNotificationService.instance.stop());
      }
    });
    ref.listen<AuthState>(authProvider, (previous, next) {
      final signedIn = previous?.isAuthenticated != true &&
          next.isAuthenticated &&
          next.user != null;
      final signedOut =
          previous?.isAuthenticated == true && !next.isAuthenticated;
      if (!signedIn && !signedOut) return;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Wait for AnimatedSwitcher to finish replacing the auth screen so
        // the notification is attached to the newly visible page.
        await Future<void>.delayed(const Duration(milliseconds: 520));
        if (!mounted) return;
        final name = signedIn
            ? (next.user!.fullName.trim().isNotEmpty
                ? next.user!.fullName.trim()
                : next.user!.email.split('@').first)
            : null;
        showAppNotification(
          signedIn
              ? 'Welcome back, $name!'
              : 'You are back at the secure sign-in screen. Use your Quick PIN or work email to continue.',
          tone: AppNotificationTone.success,
          title: signedIn ? 'Great to see you!' : 'Session secured',
          duration: const Duration(seconds: 5),
        );
      });
    });

    late final Widget home;
    if (!auth.isInitialized) {
      home = const _SplashScreen();
    } else if (!auth.isAuthenticated) {
      home = const WelcomeFlowScreen();
    } else if (!auth.isProfileComplete) {
      home = const ProfileSetupScreen();
    } else {
      home = DashboardEntryAnimation(child: roleHome(auth.user?.role));
    }

    final homeKey = ValueKey<String>(
      !auth.isInitialized
          ? 'splash'
          : !auth.isAuthenticated
              ? 'login'
              : !auth.isProfileComplete
                  ? 'profile-setup'
                  : 'dashboard',
    );

    return MaterialApp(
      title: 'Unify',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      navigatorKey: PushNotificationService.navigatorKey,
      theme: AppTheme.dark(),
      // Dark-only by design: there is no light counterpart to fall back to,
      // so the system setting must not be able to switch it.
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) => _NotificationLiveListener(
        child: child ?? const SizedBox.shrink(),
      ),
      home: AnimatedSwitcher(
        // Dashboard entry: elastic depth-reveal that pairs with the VFX overlay.
        // Auth-out: swift dissolve so the lock screen snaps back crisply.
        duration: const Duration(milliseconds: 900),
        reverseDuration: const Duration(milliseconds: 900),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final isDashboard = child.key == const ValueKey<String>('dashboard');
          if (isDashboard) {
            if (animation.status == AnimationStatus.reverse) {
              // Logout: soften the dashboard, then let it drift down and
              // recede as the welcome screen comes back into view.
              final exit = CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              );
              return AnimatedBuilder(
                animation: exit,
                child: child,
                builder: (context, child) {
                  final progress = exit.value;
                  final retreat = 1 - progress;
                  return Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, retreat * 34),
                      child: Transform.scale(
                        scale: 0.94 + progress * 0.06,
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: retreat * 5,
                            sigmaY: retreat * 5,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            // Elastic spring scale: starts deep (0.82), overshoots and settles.
            final scaleCurve = CurvedAnimation(
              parent: animation,
              curve: Curves.elasticOut,
              reverseCurve: Curves.easeInCubic,
            );
            final fadeCurve = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
              reverseCurve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: fadeCurve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.045),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
                )),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1.0).animate(scaleCurve),
                  child: child,
                ),
              ),
            );
          }
          // Auth / login screen transition: simple fade + slight scale-out.
          final eased = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: eased,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.04, end: 1.0).animate(eased),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: homeKey, child: home),
      ),
    );
  }
}

class _NotificationLiveListener extends ConsumerStatefulWidget {
  const _NotificationLiveListener({required this.child});

  final Widget child;

  @override
  ConsumerState<_NotificationLiveListener> createState() =>
      _NotificationLiveListenerState();
}

class _NotificationLiveListenerState
    extends ConsumerState<_NotificationLiveListener> {
  Set<String>? _knownNotificationIds;

  @override
  Widget build(BuildContext context) {
    final authenticated = ref.watch(authProvider).isAuthenticated;
    if (!authenticated) {
      _knownNotificationIds = null;
      return widget.child;
    }

    ref.listen<AsyncValue<List<AppNotification>>>(
      notificationsProvider,
      (previous, next) {
        final items = next.asData?.value;
        if (items == null || !ref.read(authProvider).isAuthenticated) return;

        final previousIds = _knownNotificationIds;
        _knownNotificationIds =
            items.map((notification) => notification.id).toSet();
        if (previousIds == null) return;

        final arriving = items
            .where((notification) =>
                !notification.isRead &&
                !previousIds.contains(notification.id))
            .toList();
        if (arriving.isEmpty) return;

        final title = arriving.first.title.trim();
        showAppNotification(
          arriving.length == 1
              ? 'New update: ${title.isEmpty ? 'You have a new notification.' : title}'
              : '${arriving.length} new updates. Open Notifications to review them.',
          tone: AppNotificationTone.info,
          title: arriving.length == 1 ? 'New notification' : 'Notifications',
          duration: const Duration(seconds: 6),
        );
      },
    );
    ref.watch(notificationsProvider);

    return widget.child;
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const AppBackgroundScaffold(
      showParticles: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_center_rounded,
                size: 64, color: AppColors.cyan),
            SizedBox(height: 24),
            AppLoader(message: 'Loading…'),
          ],
        ),
      ),
    );
  }
}
