import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'customer/book_business_list_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      showParticles: true,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Hero Section ─────────────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 40, 24, 36),
                child: _Hero(),
              ),

              // ── For Business Owners ──────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _AudienceCard(
                  accentColor: AppColors.cyan,
                  icon: Icons.storefront_outlined,
                  title: 'For Business Owners',
                  subtitle:
                      'Doctors, trainers, agents & tutors — manage staff, schedules & bookings.',
                  primaryLabel: 'Register My Business',
                  primaryIcon: Icons.add_business,
                  onPrimary: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  secondaryLabel: 'I Already Have an Account',
                  secondaryIcon: Icons.login,
                  onSecondary: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
              ),

              // ── For Customers ────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _AudienceCard(
                  accentColor: AppColors.magenta,
                  icon: Icons.calendar_month_outlined,
                  title: 'For Customers',
                  subtitle:
                      'Patients, students, diners & tourists — browse for free, sign up in seconds to book.',
                  primaryLabel: 'Find & Book Appointment',
                  primaryIcon: Icons.search,
                  onPrimary: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BookBusinessListScreen()),
                  ),
                  secondaryLabel: 'I Have a Booking Reference',
                  secondaryIcon: Icons.qr_code_scanner,
                  onSecondary: () =>
                      AppSnackBar.info(context, 'Track My Booking — coming soon'),
                ),
              ),

              // ── Trust Badges ─────────────────────────────
              const SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _TrustBadge(icon: Icons.local_hospital, label: 'Clinic'),
                    SizedBox(width: 12),
                    _TrustBadge(icon: Icons.restaurant, label: 'Restaurant'),
                    SizedBox(width: 12),
                    _TrustBadge(icon: Icons.fitness_center, label: 'Gym'),
                    SizedBox(width: 12),
                    _TrustBadge(icon: Icons.school, label: 'Tuition'),
                    SizedBox(width: 12),
                    _TrustBadge(icon: Icons.home_work, label: 'Real Estate'),
                    SizedBox(width: 12),
                    _TrustBadge(icon: Icons.flight_takeoff, label: 'Tourism'),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Text('Trusted by 500+ businesses', style: AppTextStyles.caption),
              const SizedBox(height: 20),
              Text('© 2026 Unify', style: AppTextStyles.caption.copyWith(fontSize: 11)),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: const [
              BoxShadow(color: AppColors.buttonGlow, blurRadius: 40, spreadRadius: -10),
            ],
          ),
          child: const Icon(Icons.business_center_rounded, size: 56, color: AppColors.cyan),
        ),
        const SizedBox(height: 24),
        Text('Unify', style: AppTextStyles.headline.copyWith(letterSpacing: -0.5)),
        const SizedBox(height: 12),
        Text(
          'Book appointments. Manage your business.\nAll in one place.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
      ],
    );
  }
}

// ── Reusable Widgets ───────────────────────────────────

class _AudienceCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  const _AudienceCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The accent rail: the one place each audience's hue is stated
            // outright, so the two cards stay distinguishable at a glance.
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: accentColor, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(title, style: AppTextStyles.title.copyWith(fontSize: 17)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(subtitle, style: AppTextStyles.bodyMuted.copyWith(fontSize: 13)),
                    const SizedBox(height: 18),
                    NeonButton(
                      label: primaryLabel,
                      icon: primaryIcon,
                      height: 50,
                      onPressed: onPrimary,
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: secondaryLabel,
                      icon: secondaryIcon,
                      height: 48,
                      color: accentColor,
                      onPressed: onSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    // Business-type hues come from the shared visual map rather than being
    // re-picked here, so a badge can't drift from the same type's card icon
    // elsewhere in the app.
    final visual = BusinessTypeVisual.of(_typeFor(label));

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.iconWell,
            shape: BoxShape.circle,
            border: Border.all(color: visual.color.withValues(alpha: 0.45)),
          ),
          child: Icon(visual.icon, color: visual.color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
      ],
    );
  }

  /// The badge labels are display copy ("Tuition", "Real Estate"); map them
  /// back to the backend's business-type keys.
  static String _typeFor(String label) {
    switch (label) {
      case 'Tuition':
        return 'School';
      case 'Real Estate':
        return 'RealEstate';
      default:
        return label;
    }
  }
}
