import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown when a session is restored but the account's profile hasn't been
/// completed yet. Not reachable in the current flow (registration marks the
/// profile complete immediately), but kept ready for when staff invites /
/// customer self-signup land and profile completion becomes a real step.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finish setting up')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_outlined, size: 48, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text(
                'A few more details needed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your profile setup will appear here once this step is required for your account.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
