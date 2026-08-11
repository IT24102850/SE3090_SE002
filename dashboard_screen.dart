import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    if (!auth.isAuthenticated) return const LoginScreen();

    Color roleColor;
    String roleTitle;
    IconData roleIcon;
    List<String> roleActions;

    switch (user?.role) {
      case 'Admin':
        roleColor = Colors.amber;
        roleTitle = 'Admin Controls';
        roleIcon = Icons.admin_panel_settings;
        roleActions = ['Manage all branches', 'View system analytics', 'Assign managers & staff'];
        break;
      case 'Manager':
        roleColor = Colors.blue;
        roleTitle = 'Branch Manager';
        roleIcon = Icons.manage_accounts;
        roleActions = ['Manage branch bookings', 'Approve schedules', 'View branch reports'];
        break;
      case 'Staff':
        roleColor = Colors.green;
        roleTitle = 'Staff Panel';
        roleIcon = Icons.work;
        roleActions = ['Create/view bookings', 'Mark attendance', 'Process walk-ins'];
        break;
      case 'Customer':
        roleColor = Colors.purple;
        roleTitle = 'My Account';
        roleIcon = Icons.person;
        roleActions = ['Book appointments', 'View my bills', 'Cancel/reschedule'];
        break;
      default:
        roleColor = Colors.grey;
        roleTitle = 'User';
        roleIcon = Icons.person_outline;
        roleActions = [];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SME Platform'),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${user?.fullName ?? ''} (${user?.role ?? ''})',
              style: const TextStyle(fontSize: 14))),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
              accountName: Text(user?.fullName ?? ''),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: roleColor,
                child: Text((user?.fullName ?? '?')[0].toUpperCase(),
                  style: const TextStyle(fontSize: 24, color: Colors.white)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            if (user?.role == 'Admin' || user?.role == 'Manager')
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Bookings'),
                onTap: () {},
              ),
            if (user?.role == 'Admin' || user?.role == 'Manager' || user?.role == 'Staff')
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Schedule'),
                onTap: () {},
              ),
            if (user?.role == 'Admin')
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.amber),
                title: const Text('Admin Panel'),
                onTap: () {},
              ),
            if (user?.role == 'Customer')
              ListTile(
                leading: const Icon(Icons.book_online),
                title: const Text('My Bookings'),
                onTap: () {},
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
                }
              },
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${user?.fullName ?? ''}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Role: ${user?.role ?? ''}', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            Text('Tenant: ${user?.tenantId ?? ''}', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: roleColor.withOpacity(0.5), width: 2)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(roleIcon, color: roleColor, size: 28),
                      const SizedBox(width: 8),
                      Text(roleTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: roleColor)),
                    ]),
                    const SizedBox(height: 12),
                    ...roleActions.map((action) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Icon(Icons.check_circle, size: 16, color: roleColor),
                        const SizedBox(width: 8),
                        Text(action),
                      ]),
                    )),
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