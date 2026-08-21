import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/booking_model.dart';
import '../providers/auth_provider.dart';
import '../providers/booking_providers.dart';
import '../providers/notification_providers.dart';
import '../shared/color_utils.dart';
import '../shared/date_format.dart';
import '../theme/app_theme.dart';
import '../widgets/route_transitions.dart';
import '../widgets/status_badge.dart';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final role = RoleTheme.of(user.role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SME Platform'),
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: AppColors.ink),
              accountName: Text(user.fullName),
              accountEmail: Text(user.email),
              currentAccountPicture: CircleAvatar(
                backgroundColor: role.color,
                child: Text(
                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(slideFadeRoute(const ProfileScreen()));
              },
            ),
            if (user.role == 'Admin' || user.role == 'Manager')
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Bookings'),
                onTap: () => Navigator.pop(context),
              ),
            if (user.role == 'Admin' || user.role == 'Manager' || user.role == 'Staff')
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Schedule'),
                onTap: () => Navigator.pop(context),
              ),
            if (user.role == 'Admin')
              ListTile(
                leading: Icon(Icons.admin_panel_settings, color: role.color),
                title: const Text('Admin Panel'),
                onTap: () => Navigator.pop(context),
              ),
            if (user.role == 'Customer') ...[
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Find a Business'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(slideFadeRoute(const BookBusinessListScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.book_online_outlined),
                title: const Text('My Bookings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.purple),
                title: const Text('Ask AI to book for you'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(slideFadeRoute(const AiPlannerScreen()));
                },
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [AppColors.ink, role.color.withValues(alpha: 0.85)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: Text(
                      user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                        ),
                        Text(
                          user.fullName,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(role.icon, size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(role.title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (user.role == 'Customer') ...[
              const SizedBox(height: 20),
              const _UpcomingBookingSection(),
            ],

            const SizedBox(height: 24),

            Text('Quick actions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: _quickActionsFor(context, user.role, role.color),
            ),

            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text('Account', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(label: 'Email', value: user.email),
                    _InfoRow(label: 'Role', value: role.title),
                    _InfoRow(label: 'Tenant ID', value: user.tenantId),
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
        color: AppColors.purple,
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ??
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label — coming soon')),
              );
            },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 22),
              Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
    final color = parseHexColor(booking.colorHex) ?? AppColors.purple;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(slideFadeRoute(const MyBookingsScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(Icons.event_available_rounded, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your next booking', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${booking.resourceName} · ${booking.bookingTypeName}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDayMonth(booking.startLocal)} · ${formatTimeOfDay(booking.startLocal)}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            StatusBadge(status: booking.status),
          ],
        ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
