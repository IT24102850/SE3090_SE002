import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/booking_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/booking_providers.dart';
import '../providers/clinic_providers.dart';
import '../providers/notification_providers.dart';
import '../shared/color_utils.dart';
import '../shared/date_format.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import '../widgets/route_transitions.dart';
import '../widgets/status_badge.dart';
import '../widgets/ui/ui.dart';
import 'billing/insurance_tracker_screen.dart';
import 'billing/my_bills_screen.dart';
import 'billing/subscription_screen.dart';
import 'business_profile_editor_screen.dart';
import 'clinic/clinic_desk_screen.dart';
import 'customer/ai_planner_screen.dart';
import 'customer/book_business_list_screen.dart';
import 'customer/my_bookings_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'staff/check_in_scanner_screen.dart';
import 'staff/my_schedule_screen.dart';
import '../inventory/authenticated_api_client.dart';
import '../inventory/app_notifications.dart';
import '../inventory/inventory_dashboard.dart';
import '../inventory/stock_count_screen.dart';
import '../inventory/stock_check_screen.dart';
import '../inventory/purchase_order_approval_screen.dart';
import '../inventory/equipment_maintenance_screen.dart';
import '../inventory/analytics_screen.dart';

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
    // Admin/Manager/Staff of a clinic get the operations desk on their home
    // screen; every other business type's dashboard is exactly as before.
    final isClinicDesk =
        user.role != 'Customer' && ref.watch(isClinicTenantProvider);

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
              final confirmed = await showAppConfirmation(
                context: context,
                title: 'Log out of Unify?',
                message:
                    'Are you sure you want to log out? You will need to sign in again to access your account.',
                confirmLabel: 'Log Out',
                icon: Icons.logout_rounded,
                accent: AppColors.danger,
                isDestructive: true,
              );
              if (!confirmed || !context.mounted) return;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final horizontalPadding = compact ? 12.0 : 16.0;
              final tileSpacing = compact ? 12.0 : 16.0;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  32,
                ),
                children: [
                  _WelcomeHero(user: user, role: role),
                  if (user.role == 'Customer') ...[
                    const SizedBox(height: 16),
                    const _UpcomingBookingSection(),
                  ],
                  if (isClinicDesk) ...[
                    const SizedBox(height: 16),
                    const _ClinicDeskCard(),
                  ],
                  const SizedBox(height: 24),
                  const SectionHeader('Quick actions'),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: tileSpacing,
                      crossAxisSpacing: tileSpacing,
                      mainAxisExtent: compact ? 132 : 140,
                    ),
                    children: _quickActionsFor(
                      context,
                      user.role,
                      role.color,
                      clinic: isClinicDesk,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('Account'),
                  _AccountCard(user: user, role: role),
                  const SizedBox(height: 18),
                  const _HomeFooter(),
                ],
              );
            },
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
        gradient: LinearGradient(
          colors: [
            role.color.withValues(alpha: 0.3),
            AppColors.violet.withValues(alpha: 0.2),
            AppColors.overlaySurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: role.color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: role.color.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -24,
            child: Icon(
              role.icon,
              size: 118,
              color: Colors.white.withValues(alpha: 0.045),
            ),
          ),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: role.color.withValues(alpha: 0.25),
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo != null
                    ? null
                    : Text(
                        user.fullName.isNotEmpty
                            ? user.fullName[0].toUpperCase()
                            : '?',
                        style: AppTextStyles.title.copyWith(
                          fontSize: 24,
                          color: role.color,
                        ),
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
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontSize: 21,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your workspace is ready',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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

    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.86)
        .clamp(280.0, 360.0)
        .toDouble();

    return Drawer(
      width: drawerWidth,
      backgroundColor: AppColors.bgMid,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
              child: AppBackground(),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          role.color.withValues(alpha: 0.22),
                          AppColors.violet.withValues(alpha: 0.14),
                          AppColors.overlaySurface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: role.color.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: role.color.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: role.color.withValues(alpha: 0.25),
                            backgroundImage:
                                photo != null ? NetworkImage(photo) : null,
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
                          Text(
                            user.email,
                            style: AppTextStyles.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: role.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: role.color.withValues(alpha: 0.35)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(role.icon, size: 14, color: role.color),
                                  const SizedBox(width: 6),
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    isCustomer ? 'YOUR SPACE' : 'WORKSPACE',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                _DrawerItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  accent: role.color,
                  emphasized: true,
                  onTap: () => Navigator.pop(context),
                ),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'My Profile',
                  accent: role.color,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context)
                        .push(slideFadeRoute(const ProfileScreen()));
                  },
                ),
                if (user.role == 'Admin' || user.role == 'Manager')
                  _DrawerItem(
                    icon: Icons.calendar_today_outlined,
                    label: 'Bookings',
                    accent: AppColors.cyan,
                    onTap: () => Navigator.pop(context),
                  ),
                if (user.role == 'Admin' ||
                    user.role == 'Manager' ||
                    user.role == 'Staff')
                  _DrawerItem(
                    icon: Icons.schedule_outlined,
                    label: 'Schedule',
                    accent: AppColors.violet,
                    onTap: () => Navigator.pop(context),
                  ),
                if (user.role == 'Admin')
                  _DrawerItem(
                    icon: Icons.admin_panel_settings,
                    label: 'Admin Panel',
                    accent: role.color,
                    iconColor: role.color,
                    onTap: () => Navigator.pop(context),
                  ),
                if (user.role != 'Customer')
                  _DrawerItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventory operations',
                    accent: AppColors.cyan,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(slideFadeRoute(
                        InventoryDashboard(
                          client: AuthenticatedApiClient(),
                          canApprove:
                              user.role == 'Admin' || user.role == 'Manager',
                        ),
                      ));
                    },
                  ),
                if (user.role == 'Admin' || user.role == 'Manager')
                  _DrawerItem(
                    icon: Icons.fact_check_outlined,
                    label: 'Purchase approvals',
                    accent: AppColors.success,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(slideFadeRoute(
                        PurchaseOrderApprovalScreen(
                          client: AuthenticatedApiClient(),
                          canApprove: true,
                        ),
                      ));
                    },
                  ),
                if (isCustomer) ...[
                  _DrawerItem(
                    icon: Icons.search,
                    label: 'Find a Business',
                    accent: AppColors.cyan,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const BookBusinessListScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.book_online_outlined,
                    label: 'My Bookings',
                    accent: AppColors.violet,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const MyBookingsScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'My Bills',
                    accent: AppColors.success,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const MyBillsScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.autorenew_rounded,
                    label: 'My Subscriptions',
                    accent: AppColors.cyan,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const SubscriptionScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.health_and_safety_outlined,
                    label: 'Insurance Claims',
                    accent: AppColors.success,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const InsuranceTrackerScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.auto_awesome,
                    label: 'Ask AI to book for you',
                    accent: AppColors.violet,
                    iconColor: AppColors.violet,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context)
                          .push(slideFadeRoute(const AiPlannerScreen()));
                    },
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Divider(color: AppColors.hairline, height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'ACCOUNT',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                _DrawerItem(
                  icon: Icons.logout,
                  label: 'Logout',
                  iconColor: AppColors.danger,
                  labelColor: AppColors.danger,
                  accent: AppColors.danger,
                  emphasized: true,
                  onTap: () async {
                    final confirmed = await showAppConfirmation(
                      context: context,
                      title: 'Log out of Unify?',
                      message:
                          'Are you sure you want to log out? You will need to sign in again to access your account.',
                      confirmLabel: 'Log Out',
                      icon: Icons.logout_rounded,
                      accent: AppColors.danger,
                      isDestructive: true,
                    );
                    if (!confirmed || !context.mounted) return;
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
    this.accent,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  final Color? accent;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? iconColor ?? AppColors.cyan;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset((1 - value) * 22, 0),
          child: child,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.row),
          onTap: onTap,
          splashColor: tint.withValues(alpha: 0.18),
          highlightColor: tint.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              gradient: emphasized
                  ? LinearGradient(
                      colors: [
                        tint.withValues(alpha: 0.2),
                        tint.withValues(alpha: 0.06),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadii.row),
              border: emphasized
                  ? Border.all(color: tint.withValues(alpha: 0.3))
                  : null,
              boxShadow: emphasized
                  ? [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.1),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        tint.withValues(alpha: 0.3),
                        tint.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(color: tint.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, size: 20, color: iconColor ?? tint),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: labelColor ?? AppColors.textPrimary,
                      fontWeight:
                          emphasized ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: tint.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork behind each quick-action tile, keyed by the tile's label.
///
/// Remote (Unsplash) rather than bundled: the asset bundle stays small, and a
/// tile that can't reach the network just falls back to plain glass. Requested
/// at 400px because these render at roughly 176x140 logical pixels.
const _quickActionImages = <String, String>{
  'Book appointments':
      'https://images.unsplash.com/photo-1506784983877-45594efa4cbe?auto=format&fit=crop&w=400&q=60',
  'View my bills':
      'https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=400&q=60',
  'Cancel / reschedule':
      'https://images.unsplash.com/photo-1501139083538-0139583c060f?auto=format&fit=crop&w=400&q=60',
  'Ask AI to book for you':
      'https://images.unsplash.com/photo-1677442136019-21780ecad995?auto=format&fit=crop&w=400&q=60',
  'Business Profile':
      'https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=400&q=60',
  'Manage all branches':
      'https://images.unsplash.com/photo-1517502884422-41eaead166d4?auto=format&fit=crop&w=400&q=60',
  'View system analytics':
      'https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=400&q=60',
  'Assign managers & staff':
      'https://images.unsplash.com/photo-1522071820081-009f0129c71c?auto=format&fit=crop&w=400&q=60',
  'Approve high-impact actions':
      'https://images.unsplash.com/photo-1521791136064-7986c2920216?auto=format&fit=crop&w=400&q=60',
  'Manage branch bookings':
      'https://images.unsplash.com/photo-1506784983877-45594efa4cbe?auto=format&fit=crop&w=400&q=60',
  'Approve schedules':
      'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?auto=format&fit=crop&w=400&q=60',
  'View branch reports':
      'https://images.unsplash.com/photo-1560472354-b33ff0c44a43?auto=format&fit=crop&w=400&q=60',
  'Create / view bookings':
      'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=400&q=60',
  'Mark attendance':
      'https://images.unsplash.com/photo-1541746972996-4e0b0f43e02a?auto=format&fit=crop&w=400&q=60',
  'Process walk-ins':
      'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?auto=format&fit=crop&w=400&q=60',
  'Inventory dashboard':
      'https://th.bing.com/th/id/OIP.f339Mfff1xtyBJelmSCekQHaEO?w=312&h=180&c=7&r=0&o=7&dpr=1.3&pid=1.7&rm=3',
  'Stock movements':
      'https://images.unsplash.com/photo-1494412651409-8963ce7935a7?auto=format&fit=crop&w=400&q=60',
  'Physical stock count':
      'https://images.unsplash.com/photo-1553413077-190dd305871c?auto=format&fit=crop&w=400&q=60',
  'Purchase approvals':
      'https://images.unsplash.com/photo-1554224154-26032ffc0d07?auto=format&fit=crop&w=400&q=60',
  'Equipment maintenance':
      'https://images.unsplash.com/photo-1581092160607-ee22621dd758?auto=format&fit=crop&w=400&q=60',
  'Inventory analytics':
      'https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=400&q=60',
};

/// Builds the quick-action tiles for a role. Customer actions are wired to
/// real screens. Admin/Manager tiles stay as "coming soon" stubs — that
/// management tooling lives in the web app — except Staff's "Mark
/// attendance"/"Process walk-ins", which FR-B7/FR-B8 require on mobile
/// specifically (QR check-in scanning, doctor's own schedule).
List<Widget> _quickActionsFor(BuildContext context, String role, Color color,
    {bool clinic = false}) {
  if (role == 'Customer') {
    return [
      _QuickActionCard(
        label: 'Book appointments',
        icon: Icons.calendar_month_outlined,
        color: color,
        imageUrl: _quickActionImages['Book appointments'],
        onTap: () => Navigator.of(context)
            .push(slideFadeRoute(const BookBusinessListScreen())),
      ),
      _QuickActionCard(
        label: 'View my bills',
        icon: Icons.receipt_long_outlined,
        color: color,
        imageUrl: _quickActionImages['View my bills'],
        onTap: () =>
            Navigator.of(context).push(slideFadeRoute(const MyBillsScreen())),
      ),
      _QuickActionCard(
        label: 'Cancel / reschedule',
        icon: Icons.event_busy_outlined,
        color: color,
        imageUrl: _quickActionImages['Cancel / reschedule'],
        onTap: () => Navigator.of(context)
            .push(slideFadeRoute(const MyBookingsScreen())),
      ),
      _QuickActionCard(
        label: 'Ask AI to book for you',
        icon: Icons.auto_awesome,
        color: AppColors.violet,
        imageUrl: _quickActionImages['Ask AI to book for you'],
        onTap: () =>
            Navigator.of(context).push(slideFadeRoute(const AiPlannerScreen())),
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
    // For a clinic the analytics / reports / bookings tiles have a real
    // screen behind them: the clinic desk's Reports and Today tabs.
    if (clinic) ...{
      'View system analytics': () => const ClinicDeskScreen(initialTab: 1),
      'View branch reports': () => const ClinicDeskScreen(initialTab: 1),
      'Manage branch bookings': () => const ClinicDeskScreen(),
      'Create / view bookings': () => const ClinicDeskScreen(),
    },
  };

  final actions = RoleTheme.of(role)
      .actions
      .map((action) => _QuickActionCard(
            label: action,
            icon: icons[action] ?? Icons.check_circle_outline,
            color: color,
            imageUrl: _quickActionImages[action],
            onTap: wiredTaps.containsKey(action)
                ? () => Navigator.of(context)
                    .push(slideFadeRoute<void>(wiredTaps[action]!()))
                : null,
          ))
      .toList();

  final client = AuthenticatedApiClient();
  actions.addAll([
    _QuickActionCard(
      label: 'Inventory dashboard',
      icon: Icons.inventory_2_outlined,
      color: color,
      imageUrl: _quickActionImages['Inventory dashboard'],
      onTap: () => Navigator.of(context).push(slideFadeRoute(
        InventoryDashboard(
          client: client,
          canApprove: role == 'Admin' || role == 'Manager',
        ),
      )),
    ),
    _QuickActionCard(
      label: 'Stock movements',
      icon: Icons.qr_code_scanner_rounded,
      color: color,
      imageUrl: _quickActionImages['Stock movements'],
      onTap: () => Navigator.of(context).push(
        slideFadeRoute(StockCheckScreen(client: client)),
      ),
    ),
    _QuickActionCard(
      label: 'Physical stock count',
      icon: Icons.fact_check_outlined,
      color: color,
      imageUrl: _quickActionImages['Physical stock count'],
      onTap: () => Navigator.of(context).push(
        slideFadeRoute(StockCountScreen(client: client)),
      ),
    ),
    if (role == 'Admin' || role == 'Manager')
      _QuickActionCard(
        label: 'Purchase approvals',
        icon: Icons.approval_outlined,
        color: color,
        imageUrl: _quickActionImages['Purchase approvals'],
        onTap: () => Navigator.of(context).push(slideFadeRoute(
          PurchaseOrderApprovalScreen(client: client, canApprove: true),
        )),
      ),
    _QuickActionCard(
      label: 'Equipment maintenance',
      icon: Icons.build_outlined,
      color: color,
      imageUrl: _quickActionImages['Equipment maintenance'],
      onTap: () => Navigator.of(context).push(
        slideFadeRoute(EquipmentMaintenanceScreen(client: client)),
      ),
    ),
    if (role == 'Admin' || role == 'Manager')
      _QuickActionCard(
        label: 'Inventory analytics',
        icon: Icons.insights_outlined,
        color: color,
        imageUrl: _quickActionImages['Inventory analytics'],
        onTap: () => Navigator.of(context).push(
          slideFadeRoute(InsightsScreen(client: client)),
        ),
      ),
  ]);
  return actions;
}

/// A quick-action tile: photo, scrim, icon well and label, inside a card the
/// grid gives a fixed size to. Without [imageUrl] — or while one loads, or if
/// it fails — it degrades to the plain glass card it used to be.
class _QuickActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String? imageUrl;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.row);
    final tap =
        onTap ?? () => AppSnackBar.info(context, '$label — coming soon');

    final content = Padding(
      padding: const EdgeInsets.all(15),
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
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              Icons.arrow_outward_rounded,
              size: 17,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );

    final url = imageUrl;
    if (url == null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: GlassCard(
          borderRadius: AppRadii.row,
          padding: EdgeInsets.zero,
          onTap: tap,
          child: content,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The glass fill sits under the photo, so a slow or failed load still
          // reads as a card rather than a hole in the grid.
          const ColoredBox(color: AppColors.glassFill),
          Image.network(
            url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // Fade in rather than pop — the four tiles resolve at slightly
            // different moments otherwise.
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                wasSynchronouslyLoaded
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        child: child,
                      ),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.tileScrimGradient),
          ),
          content,
          // Rim last so the photo can't paint over the hairline.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppColors.glassBorder),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: tap,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The clinic desk summary for Admin/Manager/Staff of a Clinic tenant: how
/// many patients are still to see, who is waiting, and how many alerts are
/// open - one tap into [ClinicDeskScreen]. Renders nothing until the flow
/// has loaded, and a compact retry if it cannot.
class _ClinicDeskCard extends ConsumerWidget {
  const _ClinicDeskCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowAsync = ref.watch(clinicFlowProvider);
    final alerts = ref.watch(clinicAlertsProvider).valueOrNull ?? const [];
    final critical = alerts.where((a) => a.severity == 'critical').length;

    void open([int tab = 0]) => Navigator.of(context)
        .push(slideFadeRoute(ClinicDeskScreen(initialTab: tab)));

    return flowAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => GlassCard(
        padding: const EdgeInsets.all(14),
        onTap: () => ref.invalidate(clinicFlowProvider),
        child: Row(children: [
          const IconWell(
              icon: Icons.local_hospital_outlined,
              color: AppColors.textMuted,
              size: 40),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Clinic desk is unavailable. Tap to retry.',
                  style: AppTextStyles.caption.copyWith(fontSize: 13))),
        ]),
      ),
      data: (flow) {
        final longWait = (flow.longestWaitMinutes ?? 0) >= 20;
        final accent =
            critical > 0 || longWait ? AppColors.danger : AppColors.cyan;
        final stats = <(String, String)>[
          ('To see', '${flow.remaining}'),
          ('Waiting', '${flow.waiting}'),
          ('In consult', '${flow.inConsultation}'),
          ('Alerts', '${alerts.length}'),
        ];
        final headline = flow.remaining == 0
            ? "Everyone on today's list has been seen."
            : longWait
                ? 'Longest wait ${flow.longestWaitMinutes} min - check the queue.'
                : '${flow.doctorsOnDuty} doctor${flow.doctorsOnDuty == 1 ? '' : 's'} on duty · ${flow.patientsToday} patients today';
        return GlassCard(
          padding: const EdgeInsets.all(16),
          borderColor: accent.withValues(alpha: 0.4),
          onTap: open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconWell(
                      icon: Icons.local_hospital_outlined,
                      color: accent,
                      size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinic desk',
                          style: AppTextStyles.label.copyWith(
                              color: accent, fontSize: 11, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 3),
                        Text(headline,
                            style: AppTextStyles.subtitle
                                .copyWith(fontSize: 13.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.chevron),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (label, value) in stats)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value,
                              style: AppTextStyles.stat.copyWith(
                                  fontSize: 20,
                                  color: label == 'Alerts' && critical > 0
                                      ? AppColors.danger
                                      : AppColors.textPrimary)),
                          Text(label.toUpperCase(),
                              style:
                                  AppTextStyles.label.copyWith(fontSize: 9.5)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: GhostButton(
                          label: 'Reports',
                          icon: Icons.insights_outlined,
                          height: 40,
                          onPressed: () => open(1))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: GhostButton(
                          label: 'Reminders',
                          icon: Icons.notifications_active_outlined,
                          height: 40,
                          onPressed: () => open(2))),
                ],
              ),
            ],
          ),
        );
      },
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
      onTap: () =>
          Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
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
                  style: AppTextStyles.label
                      .copyWith(color: color, fontSize: 11, letterSpacing: 1.5),
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
  final IconData? icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool canCopy;

  const _InfoRow({
    this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.canCopy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 82,
            child: Text(label,
                style: AppTextStyles.caption.copyWith(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: valueColor != null ? FontWeight.w700 : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canCopy)
            IconButton(
              tooltip: 'Copy workspace ID',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                AppSnackBar.success(context, 'Workspace ID copied.');
              },
              icon: const Icon(Icons.copy_rounded,
                  size: 17, color: AppColors.cyan),
            ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.role});

  final User user;
  final RoleTheme role;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.97, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderColor: role.color.withValues(alpha: 0.35),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    role.color.withValues(alpha: 0.2),
                    AppColors.violet.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.card),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: role.color.withValues(alpha: 0.2),
                      border: Border.all(
                        color: role.color.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Icon(role.icon, color: role.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account overview',
                          style: AppTextStyles.subtitle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Your Unify workspace identity',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _ActiveStatusPill(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'Email',
                    value: user.email,
                  ),
                  _InfoRow(
                    icon: role.icon,
                    label: 'Role',
                    value: role.title,
                    valueColor: role.color,
                  ),
                  _InfoRow(
                    icon: Icons.business_rounded,
                    label: 'Workspace ID',
                    value: user.tenantId,
                    canCopy: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveStatusPill extends StatefulWidget {
  const _ActiveStatusPill();

  @override
  State<_ActiveStatusPill> createState() => _ActiveStatusPillState();
}

class _ActiveStatusPillState extends State<_ActiveStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.78 + (_controller.value * 0.22);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.28 * pulse),
                blurRadius: 12 + (pulse * 7),
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.55 * pulse),
                  width: 1.2,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      widthFactor: 0.3,
                      alignment: Alignment(-1 + (_controller.value * 4), 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.34),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle,
                          size: 8, color: AppColors.success),
                      const SizedBox(width: 5),
                      Text(
                        'Active',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.cyan.withValues(alpha: 0.5),
                AppColors.violet.withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0x3314B8A6),
                  Color(0x332D1B69),
                  Color(0x221D4ED8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.24),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 38,
                      height: 38,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.buttonGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.buttonGlow,
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.onPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'UNIFY',
                      style: AppTextStyles.title.copyWith(
                        color: Colors.white,
                        letterSpacing: 2.2,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your work, in flow.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 14),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FooterPill(
                      icon: Icons.verified_user_outlined,
                      label: 'Secure workspace',
                    ),
                    _FooterPill(
                      icon: Icons.cloud_done_outlined,
                      label: 'Connected',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => AppSnackBar.info(
                    context,
                    'Support is ready to help you — check your notifications for updates.',
                  ),
                  icon: const Icon(Icons.support_agent_rounded, size: 17),
                  label: const Text('Need help? Contact support'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.cyan,
                    textStyle: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Made for simpler, smarter business operations',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'UNIFY  •  WORKSPACE',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FooterPill extends StatelessWidget {
  const _FooterPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.success),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
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
            Navigator.of(context)
                .push(slideFadeRoute(const NotificationsScreen()))
                .then((_) {
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
                boxShadow: [
                  BoxShadow(color: AppColors.dangerGlow, blurRadius: 8)
                ],
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
