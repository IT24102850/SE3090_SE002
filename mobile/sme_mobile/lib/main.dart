import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    Widget home;
    if (!auth.isInitialized) {
      home = const _SplashScreen();
    } else if (!auth.isAuthenticated) {
      home = const UnifyLoginScreen();
    } else if (!auth.isProfileComplete) {
      home = const ProfileSetupScreen();
    } else {
      home = const DashboardScreen();
    }

    return MaterialApp(
      title: 'Unify',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      theme: AppTheme.dark(),
      // Dark-only by design: there is no light counterpart to fall back to,
      // so the system setting must not be able to switch it.
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      scrollBehavior: const AppScrollBehavior(),
      home: home,
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
            Icon(Icons.business_center_rounded, size: 64, color: AppColors.cyan),
            SizedBox(height: 24),
            AppLoader(message: 'Loading…'),
          ],
        ),
      ),
    );
  }
}
