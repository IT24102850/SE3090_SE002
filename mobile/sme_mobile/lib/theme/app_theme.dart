import 'package:flutter/material.dart';

/// Shared design tokens for the Unify mobile app, so every screen
/// pulls from the same palette instead of hardcoding hex values inline.
///
/// Warm light theme: an off-white canvas, white cards on generous radii,
/// dark navy chrome, and coral as the single highlight against Unify blue.
/// Mirrors the web app's frontend/src/shared/style/tokens.css value for
/// value, so the two clients stay in step.
class AppColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);

  /// Foreground for anything sitting *on* [primary]. Blue is dark enough
  /// that white clears contrast comfortably.
  static const onPrimary = Color(0xFFFFFFFF);

  /// Highlight used for chart peaks and emphasis — the coral the light
  /// dashboard pattern reserves for the one element that should pull focus.
  static const accentHigh = Color(0xFFF2596F);

  /// Third hue, for sections that must read as distinct from [primary].
  static const accentCyan = Color(0xFF06B6D4);

  /// Dark chrome — app bars, drawer headers, gradient starts. Kept dark on
  /// purpose: with no sidebar on mobile, the app bar is what carries the
  /// dark-rail-against-light-content contrast the web layout gets from its
  /// sidebar. Not a text colour: use [textPrimary] for foreground.
  static const ink = Color(0xFF111827);

  static const success = Color(0xFF16A34A);
  static const purple = Color(0xFF7C3AED);
  static const amber = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);

  /// Scaffold background — warm off-white, not pure white, so white cards
  /// read as raised above it.
  static const surface = Color(0xFFF1EFEC);

  /// Raised surfaces: cards, sheets, list rows.
  static const card = Color(0xFFFFFFFF);
  static const cardMuted = Color(0xFFF7F5F2);

  static const border = Color(0x12101828);
  static const borderStrong = Color(0x24101828);

  static const textPrimary = Color(0xFF131A24);
  static const textSecondary = Color(0xFF5B6472);
  static const textMuted = Color(0xFF8A93A0);

  /// The hero gradient used on the landing screen, reused across auth
  /// screens and booking flow headers. Coral, matching the web hero card —
  /// these surfaces carry white text, so they stay saturated even though
  /// the rest of the theme went light.
  static const heroGradient = LinearGradient(
    colors: [Color(0xFFFF9A6C), Color(0xFFF2596F), Color(0xFFD93A5B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Ramps [accent] toward near-black rather than starting from it, so the
  /// role/business hue stays recognisable at the top-left while the far
  /// corner is still dark enough for white text to clear contrast.
  static LinearGradient heroGradientFor(Color accent) => LinearGradient(
        colors: [accent, Color.lerp(accent, const Color(0xFF0B1020), 0.45)!],
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

  /// A solid raised card for the normal (non-hero) parts of a screen. On the
  /// light canvas this is white lifted by a wide, faint shadow — the inverse
  /// of the dark theme, where a shadow read as nothing against near-black and
  /// the card had to be defined by its border alone.
  static BoxDecoration elevatedCard({double radius = 20}) {
    return BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F101828),
          blurRadius: 24,
          offset: Offset(0, 8),
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
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      // Without this, fromSeed picks its own near-black and text drifts away
      // from the token value the rest of the app uses.
      onSurface: AppColors.textPrimary,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ink,
        // NOT textPrimary — that token is near-black now, and this bar is
        // dark navy. Foreground here has to be written literally.
        foregroundColor: Color(0xFFF3F4F6),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF3F4F6),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardMuted,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
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
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 15),
          // Pill CTAs, matching the web theme's `border-radius: 999px`.
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        // Stays dark: a light snackbar on a light canvas barely registers as
        // an overlay, and this is transient feedback that must be noticed.
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Color(0xFFF3F4F6)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.cardMuted,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.cardMuted,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
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
          color: AppColors.textSecondary,
          title: 'User',
          icon: Icons.person_outline,
          actions: [],
        );
    }
  }
}

/// Business-type → icon/color, used anywhere a tenant is listed.
/// Hues are the saturated variants: the pale tints these used to carry were
/// chosen to survive a near-black canvas, and they wash out entirely on the
/// light one.
class BusinessTypeVisual {
  final IconData icon;
  final Color color;

  const BusinessTypeVisual(this.icon, this.color);

  static BusinessTypeVisual of(String businessType) {
    switch (businessType) {
      case 'Clinic':
        return const BusinessTypeVisual(Icons.local_hospital, Color(0xFFDC2626));
      case 'Restaurant':
        return const BusinessTypeVisual(Icons.restaurant, Color(0xFFEA580C));
      case 'Gym':
        return const BusinessTypeVisual(Icons.fitness_center, Color(0xFF2563EB));
      case 'School':
        return const BusinessTypeVisual(Icons.school, Color(0xFF16A34A));
      case 'RealEstate':
        return const BusinessTypeVisual(Icons.home_work, Color(0xFF0D9488));
      case 'Tourism':
        return const BusinessTypeVisual(Icons.flight_takeoff, Color(0xFF7C3AED));
      default:
        return const BusinessTypeVisual(Icons.store, Color(0xFF64748B));
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
        return const BookingStatusVisual(color: AppColors.textSecondary, icon: Icons.cancel_outlined, label: 'Cancelled');
      case 'NoShow':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.person_off_outlined, label: 'No-show');
      case 'Rejected':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.block_rounded, label: 'Rejected');
      default:
        return const BookingStatusVisual(color: AppColors.textSecondary, icon: Icons.help_outline, label: 'Unknown');
    }
  }
}
