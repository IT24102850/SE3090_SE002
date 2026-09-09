import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';

/// Shown when a session is restored but the account's profile hasn't been
/// completed yet. Not reachable in the current flow (registration marks the
/// profile complete immediately), but kept ready for when staff invites /
/// customer self-signup land and profile completion becomes a real step.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBackgroundScaffold(
      appBar: GlassAppBar(title: 'Finish setting up'),
      child: SafeArea(
        child: EmptyState(
          icon: Icons.badge_outlined,
          title: 'A few more details needed',
          message:
              'Your profile setup will appear here once this step is required for your account.',
        ),
      ),
    );
  }
}
