import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/booking_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/booking_providers.dart';
import '../providers/notification_providers.dart';
import '../shared/color_utils.dart';
import '../shared/date_format.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/route_transitions.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui/ui.dart';
import 'business_profile_editor_screen.dart';
import 'customer/ai_planner_screen.dart';
import 'customer/book_business_list_screen.dart';
import 'customer/my_bookings_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'staff/check_in_scanner_screen.dart';
import 'staff/my_schedule_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    if (!auth.isAuthenticated || user == null) {
      // Should not happen – MyApp routes away – but guard anyway.
      return const AppBackgroundScaffold(child: AppLoader());
    }

    final role = RoleTheme.of(user.role);

    return AppBackgroundScaffold(
      // Particles only on the dashboard header area, per the design: they add
      // life behind the hero without cluttering the content below.
      showParticles: true,
      appBar: GlassAppBar(
        title: 'Unify',
        actions: [
          const _NotificationBellAction(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              // MyApp automatically routes back to the landing screen.
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _DashboardDrawer(user: user, role: role),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async {},
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _WelcomeHero(user: user, role: role),
              if (user.role == 'Customer') ...[
                const SizedBox(height: 16),
                const _UpcomingBookingSection(),
              ],
              const SizedBox(height: 24),
              const SectionHeader('Quick actions'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.35,
                children: _quickActionsFor(context, user.role, role.color),
              ),
              const SizedBox(height: 24),
              const SectionHeader('Account'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: 'Email', value: user.email),
                    _InfoRow(label: 'Role', value: role.title),
                    _InfoRow(label: 'Tenant ID', value: user.tenantId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The greeting panel. Carries the role hue as a gradient ramped into the
/// canvas, so each role still reads distinctly without breaking the palette.
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.user, required this.role});

  final User user;
  final RoleTheme role;

  @override
  Widget build(BuildContext context) {
    final photo = user.profilePictureUrl;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        gradient: AppColors.heroGradientFor(role.color),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.iconWell,
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo != null
                ? null
                : Text(
                    user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : '?',
                    style: AppTextStyles.title.copyWith(fontSize: 22),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back,', style: AppTextStyles.caption),
                Text(
                  user.fullName,
                  style: AppTextStyles.headlineSmall.copyWith(fontSize: 20),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(role.icon, size: 13, color: role.color),
                      const SizedBox(width: 5),
                      Text(
                        role.title,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation drawer. Painted over the app background rather than a solid
/// panel, so opening it reads as sliding glass across the same canvas.
class _DashboardDrawer extends ConsumerWidget {
  const _DashboardDrawer({required this.user, required this.role});

  final User user;
  final RoleTheme role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = user.profilePictureUrl;
    final isCustomer = user.role == 'Customer';

    return Drawer(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          const Positioned.fill(child: AppBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: role.color.withValues(alpha: 0.25),
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo != null
                            ? null
                            : Text(
                                user.fullName.isNotEmpty
                                    ? user.fullName[0].toUpperCase()
                                    : '?',
                                style: AppTextStyles.headlineSmall,
                              ),
                      ),
                      const SizedBox(height: 14),
                      Text(user.fullName, style: AppTextStyles.title),
                      const SizedBox(height: 2),
                      Text(user.email, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                _DrawerItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  onTap: () => Navigator.pop(context),
                ),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(slideFadeRoute(const ProfileScreen()));
                  },
                ),
                if (user.role == 'Admin' || user.role == 'Manager')
                  _DrawerItem(
                    icon: Icons.calendar_today_outlined,
                    label: 'Bookings',
                    onTap: () => Navigator.pop(context),
                  ),
                if (user.role == 'Admin' || user.role == 'Manager' || user.role == 'Staff')
                  _DrawerItem(
                    icon: Icons.schedule_outlined,
                    label: 'Schedule',
                    onTap: () => Navigator.pop(context),
                  ),
                if (user.role == 'Admin')
                  _DrawerItem(
                    icon: Icons.admin_panel_settings,
                    label: 'Admin Panel',
                    iconColor: role.color,
                    onTap: () => Navigator.pop(context),
                  ),
                if (isCustomer) ...[
                  _DrawerItem(
                    icon: Icons.search,
                    label: 'Find a Business',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(slideFadeRoute(const BookBusinessListScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.book_online_outlined,
                    label: 'My Bookings',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.auto_awesome,
                    label: 'Ask AI to book for you',
                    iconColor: AppColors.violet,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(slideFadeRoute(const AiPlannerScreen()));
                    },
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Divider(color: AppColors.hairline, height: 1),
                ),
                _DrawerItem(
                  icon: Icons.logout,
                  label: 'Logout',
                  iconColor: AppColors.danger,
                  labelColor: AppColors.danger,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(authProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.row),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor ?? AppColors.iconSecondary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    color: labelColor ?? AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds the quick-action tiles for a role. Customer actions are wired to
/// real screens. Admin/Manager tiles stay as "coming soon" stubs — that
/// management tooling lives in the web app — except Staff's "Mark
/// attendance"/"Process walk-ins", which FR-B7/FR-B8 require on mobile
/// specifically (QR check-in scanning, doctor's own schedule).
List<Widget> _quickActionsFor(BuildContext context, String role, Color color) {
  if (role == 'Customer') {
    return [
      _QuickActionCard(
        label: 'Book appointments',
        icon: Icons.calendar_month_outlined,
        color: color,
        onTap: () => Navigator.of(context).push(slideFadeRoute(const BookBusinessListScreen())),
      ),
      _QuickActionCard(
        label: 'View my bills',
        icon: Icons.receipt_long_outlined,
        color: color,
      ),
      _QuickActionCard(
        label: 'Cancel / reschedule',
        icon: Icons.event_busy_outlined,
        color: color,
        onTap: () => Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
      ),
      _QuickActionCard(
        label: 'Ask AI to book for you',
        icon: Icons.auto_awesome,
        color: AppColors.violet,
        onTap: () => Navigator.of(context).push(slideFadeRoute(const AiPlannerScreen())),
      ),
    ];
  }

  const icons = {
    'Business Profile': Icons.storefront_outlined,
    'Manage all branches': Icons.store_outlined,
    'View system analytics': Icons.insights_outlined,
    'Assign managers & staff': Icons.group_add_outlined,
    'Approve high-impact actions': Icons.verified_outlined,
    'Manage branch bookings': Icons.calendar_month_outlined,
    'Approve schedules': Icons.fact_check_outlined,
    'View branch reports': Icons.bar_chart_outlined,
    'Create / view bookings': Icons.event_note_outlined,
    'Mark attendance': Icons.how_to_reg_outlined,
    'Process walk-ins': Icons.directions_walk_outlined,
  };

  // Most Admin/Manager tiles stay as "coming soon" stubs — that management
  // tooling lives in the web app — except the ones with a real mobile
  // screen wired below (Staff's FR-B7/FR-B8 tasks, and Business Profile,
  // which was explicitly asked for on mobile too).
  final wiredTaps = <String, Widget Function()>{
    'Mark attendance': () => const MyScheduleScreen(),
    'Process walk-ins': () => const CheckInScannerScreen(),
    'Business Profile': () => const BusinessProfileEditorScreen(),
  };

  return RoleTheme.of(role)
      .actions
      .map((action) => _QuickActionCard(
            label: action,
            icon: icons[action] ?? Icons.check_circle_outline,
            color: color,
            onTap: wiredTaps.containsKey(action) ? () => Navigator.of(context).push(slideFadeRoute<void>(wiredTaps[action]!())) : null,
          ))
      .toList();
}

class _QuickActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionCard({required this.label, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: AppRadii.row,
      padding: const EdgeInsets.all(14),
      onTap: onTap ?? () => AppSnackBar.info(context, '$label — coming soon'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconWell(icon: icon, color: color, size: 36),
          Text(
            label,
            style: AppTextStyles.subtitle.copyWith(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Soonest upcoming booking, shown as a preview above the quick actions for
/// customers so the dashboard has something concrete to greet them with.
class _UpcomingBookingSection extends ConsumerWidget {
  const _UpcomingBookingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.maybeWhen(
      data: (bookings) {
        final upcoming = bookings.where((b) => b.isUpcoming).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return _UpcomingBookingCard(booking: upcoming.first);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _UpcomingBookingCard extends StatelessWidget {
  final Booking booking;
  const _UpcomingBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(booking.colorHex) ?? AppColors.violet;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: color.withValues(alpha: 0.35),
      onTap: () => Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
      child: Row(
        children: [
          IconWell(icon: Icons.event_available_rounded, color: color, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your next booking',
                  style: AppTextStyles.label.copyWith(color: color, fontSize: 11, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${booking.resourceName} · ${booking.bookingTypeName}',
                  style: AppTextStyles.subtitle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDayMonth(booking.startLocal)} · ${formatTimeOfDay(booking.startLocal)}',
                  style: AppTextStyles.caption.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          StatusBadge(status: booking.status),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: AppTextStyles.caption.copyWith(fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body.copyWith(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// FR-C11: bell + unread badge in the app bar, opening the in-app
/// notification center.
class _NotificationBellAction extends ConsumerWidget {
  const _NotificationBellAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(unreadNotificationCountProvider);
    final unread = countAsync.valueOrNull ?? 0;

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: 'Notifications',
          onPressed: () {
            Navigator.of(context).push(slideFadeRoute(const NotificationsScreen())).then((_) {
              ref.invalidate(unreadNotificationCountProvider);
            });
          },
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: const BoxDecoration(
                color: AppColors.magenta,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.dangerGlow, blurRadius: 8)],
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
