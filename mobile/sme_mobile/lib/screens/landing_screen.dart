import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'customer/book_business_list_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Hero Section ─────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.business_center_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'SME Platform',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Book appointments. Manage your business.\nAll in one place.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── For Business Owners ──────────────────────
            Padding(
              padding: const EdgeInsets.all(24),
              child: _AudienceCard(
                accentColor: const Color(0xFF059669),
                icon: Icons.storefront_outlined,
                title: 'For Business Owners',
                subtitle:
                    'Doctors, trainers, agents & tutors — manage staff, schedules & bookings.',
                primaryButton: _ActionButton(
                  label: 'Register My Business',
                  icon: Icons.add_business,
                  isFilled: true,
                  color: const Color(0xFF059669),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                ),
                secondaryButton: _ActionButton(
                  label: 'I Already Have an Account',
                  icon: Icons.login,
                  isFilled: false,
                  color: const Color(0xFF059669),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1),
            ),

            // ── For Customers ────────────────────────────
            Padding(
              padding: const EdgeInsets.all(24),
              child: _AudienceCard(
                accentColor: const Color(0xFF7C3AED),
                icon: Icons.calendar_month_outlined,
                title: 'For Customers',
                subtitle:
                    'Patients, students, diners & tourists — book instantly without signing up.',
                primaryButton: _ActionButton(
                  label: 'Find & Book Appointment',
                  icon: Icons.search,
                  isFilled: true,
                  color: const Color(0xFF7C3AED),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BookBusinessListScreen()),
                  ),
                ),
                secondaryButton: _ActionButton(
                  label: 'I Have a Booking Reference',
                  icon: Icons.qr_code_scanner,
                  isFilled: false,
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Track My Booking — coming soon')),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Trust Badges ─────────────────────────────
            const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _TrustBadge(
                      icon: Icons.local_hospital,
                      label: 'Clinic',
                      color: Colors.red),
                  SizedBox(width: 12),
                  _TrustBadge(
                      icon: Icons.restaurant,
                      label: 'Restaurant',
                      color: Colors.orange),
                  SizedBox(width: 12),
                  _TrustBadge(
                      icon: Icons.fitness_center,
                      label: 'Gym',
                      color: Colors.blue),
                  SizedBox(width: 12),
                  _TrustBadge(
                      icon: Icons.school,
                      label: 'Tuition',
                      color: Colors.green),
                  SizedBox(width: 12),
                  _TrustBadge(
                      icon: Icons.home_work,
                      label: 'Real Estate',
                      color: Colors.teal),
                  SizedBox(width: 12),
                  _TrustBadge(
                      icon: Icons.flight_takeoff,
                      label: 'Tourism',
                      color: Colors.purple),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Trusted by 500+ businesses',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),

            const SizedBox(height: 24),
            Text(
              '© 2026 SME Platform',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Reusable Widgets ───────────────────────────────────

class _AudienceCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final _ActionButton primaryButton;
  final _ActionButton secondaryButton;

  const _AudienceCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryButton,
    required this.secondaryButton,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: GlassStyle.elevatedCard(radius: 16),
      child: Row(
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: accentColor, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  primaryButton,
                  const SizedBox(height: 10),
                  secondaryButton,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isFilled;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isFilled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: isFilled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18, color: color),
              label: Text(
                label,
                style: TextStyle(fontSize: 15, color: color),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TrustBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
