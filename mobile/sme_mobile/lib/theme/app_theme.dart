import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Re-exported so the many screens that already `import 'theme/app_theme.dart'`
/// keep resolving [AppColors] and [AppRadii] from their existing import.
export 'app_colors.dart';

/// Frosted-glass decoration for callers that need a [BoxDecoration] rather
/// than the `GlassCard` widget — mostly places already composing their own
/// [Container].
///
/// Prefer `GlassCard` where you can: it adds the backdrop blur, which a bare
/// decoration cannot.
class GlassStyle {
  const GlassStyle._();

  /// Translucent panel over the app background.
  static BoxDecoration card({double radius = AppRadii.card, double alpha = 0.06}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
    );
  }

  /// The default panel for normal (non-hero) content. On a near-black canvas a
  /// drop shadow reads as nothing, so the card is defined by its rim and fill
  /// rather than by elevation.
  static BoxDecoration elevatedCard({double radius = AppRadii.card}) {
    return BoxDecoration(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.glassBorder, width: 1),
    );
  }
}

/// Cyan ink splashes at low opacity, so taps register without flashing a grey
/// Material ripple across the neon surfaces.
class _NeonSplash extends InteractiveInkFeatureFactory {
  const _NeonSplash();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return InkRipple.splashFactory.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: AppColors.cyan.withValues(alpha: 0.12),
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}

/// Bouncing overscroll everywhere, and no Material glow — the blue-grey
/// overscroll halo is one of the default accents this theme is removing.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class AppTheme {
  const AppTheme._();

  /// Light status-bar icons over the dark canvas. Applied by [dark] and by
  /// `GlassAppBar`, so screens don't each have to set it.
  static const overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.bgTop,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  /// The app's only theme. This design is dark-only by intent, so there is no
  /// light counterpart and `MaterialApp` pins `themeMode: ThemeMode.dark`.
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.cyan,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.magenta,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.bgTop,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: AppColors.textPrimary,
      outline: AppColors.glassBorder,
    );

    OutlineInputBorder fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // Transparent, not a flat fill: every screen paints AppBackground
      // underneath, and a solid scaffold colour would hide it.
      scaffoldBackgroundColor: AppColors.bgTop,
      canvasColor: AppColors.bgTop,
      splashFactory: const _NeonSplash(),
      textTheme: AppTextStyles.textTheme(ThemeData(brightness: Brightness.dark).textTheme),
      appBarTheme: AppBarTheme(
        // Glass chrome is drawn by GlassAppBar; the default bar is stripped
        // back so anything still using a plain AppBar doesn't paint a slab.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: AppTextStyles.title,
        iconTheme: const IconThemeData(color: AppColors.iconPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.iconSecondary),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.glassFill,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
        labelStyle: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        prefixIconColor: AppColors.iconSecondary,
        suffixIconColor: AppColors.iconSecondary,
        border: fieldBorder(AppColors.inputBorder),
        enabledBorder: fieldBorder(AppColors.inputBorder),
        focusedBorder: fieldBorder(AppColors.cyan, width: 1.6),
        errorBorder: fieldBorder(AppColors.danger),
        focusedErrorBorder: fieldBorder(AppColors.danger, width: 1.6),
        errorStyle: AppTextStyles.caption.copyWith(color: AppColors.danger),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.glassBorder,
          disabledForegroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
          textStyle: AppTextStyles.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cyan,
          side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.5), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
          textStyle: AppTextStyles.button.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.iconSecondary,
        textColor: AppColors.textPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.inputFill,
        contentTextStyle: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.overlaySurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.overlaySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.overlaySurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTextStyles.title,
        contentTextStyle: AppTextStyles.body,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.overlaySurface,
        surfaceTintColor: Colors.transparent,
        textStyle: AppTextStyles.body,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.row)),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.bgMid,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.cyan),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.bgTop : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.cyan : AppColors.inputFill,
        ),
        trackOutlineColor: WidgetStateProperty.all(AppColors.glassBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.cyan : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
        side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.cyan : AppColors.inputBorder,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.iconWell,
        selectedColor: AppColors.cyan,
        labelStyle: AppTextStyles.caption.copyWith(color: AppColors.textBody),
        side: const BorderSide(color: AppColors.glassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.image)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.cyan,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.cyan,
        dividerColor: AppColors.hairline,
        labelStyle: AppTextStyles.subtitle,
        unselectedLabelStyle: AppTextStyles.body,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.overlaySurface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.bgMid,
        headerForegroundColor: AppColors.textPrimary,
        todayForegroundColor: WidgetStateProperty.all(AppColors.cyan),
        todayBorder: const BorderSide(color: AppColors.cyan),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.textBody,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.cyan : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.overlaySurface,
        dialBackgroundColor: AppColors.inputFill,
        dialHandColor: AppColors.cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.cyan,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

/// Role → visual identity, shared between the dashboard and the drawer so they
/// can't drift out of sync with each other.
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
          color: AppColors.warning,
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
          color: AppColors.electricBlue,
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
          color: AppColors.violet,
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
          color: AppColors.cyan,
          title: 'User',
          icon: Icons.person_outline,
          actions: [],
        );
    }
  }
}

/// Business-type → icon/colour, used anywhere a tenant is listed. Hues are
/// picked to stay legible against the near-black canvas.
class BusinessTypeVisual {
  final IconData icon;
  final Color color;

  const BusinessTypeVisual(this.icon, this.color);

  static BusinessTypeVisual of(String businessType) {
    switch (businessType) {
      case 'Clinic':
        return const BusinessTypeVisual(Icons.local_hospital, AppColors.magenta);
      case 'Restaurant':
        return const BusinessTypeVisual(Icons.restaurant, AppColors.warning);
      case 'Gym':
        return const BusinessTypeVisual(Icons.fitness_center, AppColors.electricBlue);
      case 'School':
        return const BusinessTypeVisual(Icons.school, AppColors.success);
      case 'RealEstate':
        return const BusinessTypeVisual(Icons.home_work, AppColors.cyan);
      case 'Tourism':
        return const BusinessTypeVisual(Icons.flight_takeoff, AppColors.violet);
      default:
        return const BusinessTypeVisual(Icons.store, AppColors.textMuted);
    }
  }
}

/// Booking status → colour/icon/label, shared by the status pill, "My
/// Bookings" cards, and the confirmation screen.
class BookingStatusVisual {
  final Color color;
  final IconData icon;
  final String label;

  const BookingStatusVisual({required this.color, required this.icon, required this.label});

  static BookingStatusVisual of(String status) {
    switch (status) {
      case 'Pending':
        return const BookingStatusVisual(color: AppColors.warning, icon: Icons.hourglass_top_rounded, label: 'Pending');
      case 'Confirmed':
        return const BookingStatusVisual(color: AppColors.cyan, icon: Icons.event_available_rounded, label: 'Confirmed');
      case 'CheckedIn':
        return const BookingStatusVisual(color: AppColors.violet, icon: Icons.how_to_reg_rounded, label: 'Checked in');
      case 'InProgress':
        return const BookingStatusVisual(color: AppColors.violet, icon: Icons.play_circle_outline_rounded, label: 'In progress');
      case 'Completed':
        return const BookingStatusVisual(color: AppColors.success, icon: Icons.task_alt_rounded, label: 'Completed');
      case 'Cancelled':
        return const BookingStatusVisual(color: AppColors.textMuted, icon: Icons.cancel_outlined, label: 'Cancelled');
      case 'NoShow':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.person_off_outlined, label: 'No-show');
      case 'Rejected':
        return const BookingStatusVisual(color: AppColors.danger, icon: Icons.block_rounded, label: 'Rejected');
      default:
        return const BookingStatusVisual(color: AppColors.textMuted, icon: Icons.help_outline, label: 'Unknown');
    }
  }
}
