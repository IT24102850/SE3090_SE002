import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory/app_notifications.dart';
import 'providers/auth_provider.dart';
import 'screens/unify_auth/unify_login_screen.dart';
import 'screens/dashboard_screen.dart';
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
              : 'You have been signed out safely. See you next time!',
          tone: AppNotificationTone.success,
          title: signedIn ? 'Great to see you!' : 'See you soon!',
          duration: const Duration(seconds: 5),
        );
      });
    });

    late final Widget home;
    if (!auth.isInitialized) {
      home = const _SplashScreen();
    } else if (!auth.isAuthenticated) {
      home = const UnifyLoginScreen();
    } else if (!auth.isProfileComplete) {
      home = const ProfileSetupScreen();
    } else {
      home = const DashboardScreen();
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
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 460),
        reverseDuration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: homeKey, child: home),
      ),
    );
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
