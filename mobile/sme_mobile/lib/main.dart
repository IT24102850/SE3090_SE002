import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/landing_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

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
      home = const LandingScreen(); // <-- THIS IS THE FIX
    } else if (!auth.isProfileComplete) {
      home = const ProfileSetupScreen();
    } else {
      home = const DashboardScreen();
    }

    return MaterialApp(
      title: 'Unify',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      theme: AppTheme.light(),
      home: home,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_center_rounded,
                size: 64, color: Color(0xFF2563EB)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
