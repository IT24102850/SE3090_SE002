import 'package:flutter/material.dart';

/// Shared design tokens for the SME Platform mobile app, so every screen
/// pulls from the same palette instead of hardcoding hex values inline.
class AppColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1E3A8A);
  static const ink = Color(0xFF0F172A);
  static const success = Color(0xFF059669);
  static const purple = Color(0xFF7C3AED);
  static const amber = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const surface = Color(0xFFF4F6FB);
  static const border = Color(0xFFE2E8F0);

  /// The dark navy → blue hero gradient used on the landing screen, reused
  /// across auth screens and booking flow headers for a consistent premium
  /// identity.
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient heroGradientFor(Color accent) => LinearGradient(
        colors: [ink, accent.withValues(alpha: 0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Frosted-glass container decoration for use on top of [AppColors.heroGradient]
/// (or any dark/colored background) — a translucent white fill with a soft
/// white border, the glassmorphism look used throughout the booking flow.
class GlassStyle {
  static BoxDecoration card({double radius = 20, double alpha = 0.1}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: alpha * 2), width: 1),
    );
  }

  static BoxDecoration elevatedCard({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Role → visual identity, shared between the dashboard and the drawer so
/// they can't drift out of sync with each other.
class RoleTheme {
  final Color color;
  final String title;
  final IconData icon;
  final List<String> actions;

  const RoleTheme({
    required this.color,
    required this.title,
    required this.icon,
    required this.actions,
  });

  static RoleTheme of(String role) {
    switch (role) {
      case 'Admin':
        return const RoleTheme(
          color: AppColors.amber,
          title: 'Tenant Admin',
          icon: Icons.admin_panel_settings,
          actions: [
            'Business Profile',
            'Manage all branches',
            'View system analytics',
            'Assign managers & staff',
            'Approve high-impact actions',
          ],
        );
      case 'Manager':
        return const RoleTheme(
          color: AppColors.primary,
          title: 'Branch Manager',
          icon: Icons.manage_accounts,
          actions: [
            'Business Profile',
            'Manage branch bookings',
            'Approve schedules',
            'View branch reports',
          ],
        );
      case 'Staff':
        return const RoleTheme(
          color: AppColors.success,
          title: 'Staff',
          icon: Icons.badge_outlined,
          actions: [
            'Create / view bookings',
            'Mark attendance',
            'Process walk-ins',
          ],
        );
      case 'Customer':
        return const RoleTheme(
          color: AppColors.purple,
          title: 'Customer',
          icon: Icons.person_outline,
          actions: [
            'Book appointments',
            'View my bills',
            'Cancel / reschedule',
          ],
        );
      default:
        return const RoleTheme(
          color: Colors.grey,
          title: 'User',
          icon: Icons.person_outline,
          actions: [],
        );
    }
  }
}

/// Business-type → icon/color, used anywhere a tenant is listed.
class BusinessTypeVisual {
  final IconData icon;
  final Color color;

  const BusinessTypeVisual(this.icon, this.color);

  static BusinessTypeVisual of(String businessType) {
    switch (businessType) {
      case 'Clinic':
        return const BusinessTypeVisual(Icons.local_hospital, Colors.red);
      case 'Restaurant':
        return const BusinessTypeVisual(Icons.restaurant, Colors.orange);
      case 'Gym':
        return const BusinessTypeVisual(Icons.fitness_center, Colors.blue);
      case 'School':
        return const BusinessTypeVisual(Icons.school, Colors.green);
      case 'RealEstate':
        return const BusinessTypeVisual(Icons.home_work, Colors.teal);
      case 'Tourism':
        return const BusinessTypeVisual(Icons.flight_takeoff, Colors.purple);
      default:
        return const BusinessTypeVisual(Icons.store, Colors.blueGrey);
    }
  }
}

/// Booking status → color/icon/label, shared by the status pill, "My
/// Bookings" cards, and the confirmation screen.
class BookingStatusVisual {
  final Color color;
  final IconData icon;
  final String label;

  const BookingStatusVisual({required this.color, required this.icon, required this.label});

  static BookingStatusVisual of(String status) {
    switch (status) {
      case 'Pending':
        return const BookingStatusVisual(color: AppColors.amber, icon: Icons.hourglass_top_rounded, label: 'Pending');
      case 'Confirmed':
        return const BookingStatusVisual(color: AppColors.primary, icon: Icons.event_available_rounded, label: 'Confirmed');
      case 'CheckedIn':
        return const BookingStatusVisual(color: AppColors.purple, icon: Icons.how_to_reg_rounded, label: 'Checked in');
      case 'InProgress':
        return const BookingStatusVisual(color: AppColors.purple, icon: Icons.play_circle_outline_rounded, label: 'In progress');
      case 'Completed':
        return const BookingStatusVisual(color: AppColors.success, icon: Icons.task_alt_rounded, label: 'Completed');
      case 'Cancelled':
        return const BookingStatusVisual(color: Colors.grey, icon: Icons.cancel_outlined, label: 'Cancelled');
      case 'NoShow':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.person_off_outlined, label: 'No-show');
      case 'Rejected':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.block_rounded, label: 'Rejected');
      default:
        return const BookingStatusVisual(color: Colors.grey, icon: Icons.help_outline, label: 'Unknown');
    }
  }
}
