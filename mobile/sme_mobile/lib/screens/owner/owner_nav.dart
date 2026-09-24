import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../business_profile_editor_screen.dart';
import '../dashboard_screen.dart';
import '../staff/check_in_scanner_screen.dart';
import '../staff/my_schedule_screen.dart';
import 'billing/billing_agent_screen.dart';
import 'billing/claims_pipeline_screen.dart';
import 'billing/billing_dashboard_screen.dart';
import 'billing/commission_rules_screen.dart';
import 'billing/form_builder_screen.dart';
import 'billing/invoice_designer_screen.dart';
import 'billing/invoices_screen.dart';
import 'billing/payment_gateways_screen.dart';
import 'billing/subscription_manager_screen.dart';
import 'business/business_settings_screen.dart';
import 'inventory/branch_overview_screen.dart';
import 'inventory/inventory_analytics_screen.dart';
import 'inventory/inventory_manager_screen.dart';
import 'inventory/low_stock_alerts_screen.dart';
import 'inventory/purchase_orders_screen.dart';
import 'inventory/stock_movements_screen.dart';
import 'owner_home_screen.dart';
import 'reports/reports_screen.dart';
import 'resources/branches_screen.dart';
import 'resources/resource_manager_screen.dart';
import 'resources/staff_screen.dart';
import 'scheduling/booking_manager_screen.dart';
import 'scheduling/booking_types_screen.dart';
import 'scheduling/multi_branch_schedule_screen.dart';
import 'automation/agent_workflows_screen.dart';
import 'automation/ai_planner_screen.dart';

/// One owner destination — the mobile counterpart of an entry in the web
/// app's sidebar. `roles` mirrors that sidebar's own role list exactly, so
/// a manager sees on the phone precisely what they see on the desktop.
class OwnerDestination {
  final String label;
  final IconData icon;
  final List<String> roles;
  final Widget Function() build;

  const OwnerDestination({required this.label, required this.icon, required this.roles, required this.build});

  bool visibleTo(String role) => roles.contains(role);
}

class OwnerSection {
  final String label;
  final List<OwnerDestination> items;
  const OwnerSection({required this.label, required this.items});

  List<OwnerDestination> forRole(String role) => items.where((i) => i.visibleTo(role)).toList();
}

const _admin = ['Admin'];
const _adminManager = ['Admin', 'Manager'];
const _staffUp = ['Admin', 'Manager', 'Staff'];

/// The whole owner side, in the same order and the same grouping as the web
/// sidebar: Overview, Scheduling, Billing, Resources, Inventory,
/// Automation, Business.
const List<OwnerSection> ownerSections = [
  OwnerSection(label: 'Overview', items: [
    OwnerDestination(label: 'Dashboard', icon: Icons.space_dashboard_outlined, roles: _staffUp, build: OwnerHomeScreen.new),
    OwnerDestination(label: 'Reports', icon: Icons.insights_outlined, roles: _adminManager, build: ReportsScreen.new),
    // The business-type dashboard (clinic desk, departure board, and the
    // rest of the sub-type registry) already existed; it stays reachable
    // rather than being replaced by the generic workspace home.
    OwnerDestination(
        label: 'Business Dashboard', icon: Icons.dashboard_customize_outlined, roles: _staffUp, build: DashboardScreen.new),
  ]),
  OwnerSection(label: 'Scheduling', items: [
    OwnerDestination(
        label: 'Booking Manager', icon: Icons.event_note_outlined, roles: _staffUp, build: BookingManagerScreen.new),
    OwnerDestination(label: 'My Schedule', icon: Icons.badge_outlined, roles: ['Staff'], build: MyScheduleScreen.new),
    OwnerDestination(
        label: 'Check-in Scanner', icon: Icons.qr_code_scanner_outlined, roles: _staffUp, build: CheckInScannerScreen.new),
    OwnerDestination(
        label: 'Multi-Branch Schedule',
        icon: Icons.account_tree_outlined,
        roles: _adminManager,
        build: MultiBranchScheduleScreen.new),
    OwnerDestination(
        label: 'Booking Types', icon: Icons.sell_outlined, roles: _adminManager, build: BookingTypesScreen.new),
  ]),
  OwnerSection(label: 'Billing', items: [
    OwnerDestination(
        label: 'Billing Dashboard', icon: Icons.query_stats_outlined, roles: _adminManager, build: BillingDashboardScreen.new),
    OwnerDestination(label: 'Invoices', icon: Icons.receipt_long_outlined, roles: _staffUp, build: InvoicesScreen.new),
    OwnerDestination(
        label: 'Subscriptions', icon: Icons.autorenew_outlined, roles: _staffUp, build: SubscriptionManagerScreen.new),
    OwnerDestination(
        label: 'Insurance Claims',
        icon: Icons.shield_outlined,
        roles: _staffUp,
        build: ClaimsPipelineScreen.new),
    OwnerDestination(
        label: 'Commission Rules', icon: Icons.handshake_outlined, roles: _staffUp, build: CommissionRulesScreen.new),
    OwnerDestination(
        label: 'Billing Agent', icon: Icons.psychology_outlined, roles: _adminManager, build: BillingAgentScreen.new),
    OwnerDestination(
        label: 'Invoice Designer', icon: Icons.palette_outlined, roles: _adminManager, build: InvoiceDesignerScreen.new),
    OwnerDestination(
        label: 'Form Builder', icon: Icons.extension_outlined, roles: _adminManager, build: FormBuilderScreen.new),
    OwnerDestination(
        label: 'Payment Gateways', icon: Icons.lock_outline, roles: _admin, build: PaymentGatewaysScreen.new),
  ]),
  OwnerSection(label: 'Resources', items: [
    OwnerDestination(
        label: 'Resource Manager', icon: Icons.meeting_room_outlined, roles: _adminManager, build: ResourceManagerScreen.new),
    OwnerDestination(label: 'Staff', icon: Icons.groups_outlined, roles: _adminManager, build: StaffScreen.new),
    OwnerDestination(label: 'Branches', icon: Icons.location_on_outlined, roles: _admin, build: BranchesScreen.new),
  ]),
  OwnerSection(label: 'Inventory', items: [
    OwnerDestination(
        label: 'Inventory Manager', icon: Icons.inventory_2_outlined, roles: _staffUp, build: InventoryManagerScreen.new),
    OwnerDestination(
        label: 'Stock Movements', icon: Icons.swap_vert_outlined, roles: _staffUp, build: StockMovementsScreen.new),
    OwnerDestination(
        label: 'Purchase Orders', icon: Icons.local_shipping_outlined, roles: _staffUp, build: PurchaseOrdersScreen.new),
    OwnerDestination(
        label: 'Low Stock Alerts', icon: Icons.warning_amber_outlined, roles: _staffUp, build: LowStockAlertsScreen.new),
    OwnerDestination(
        label: 'Branch Overview', icon: Icons.store_outlined, roles: _staffUp, build: BranchOverviewScreen.new),
    OwnerDestination(
        label: 'Inventory Analytics', icon: Icons.stacked_line_chart_outlined, roles: _adminManager, build: InventoryAnalyticsScreen.new),
  ]),
  OwnerSection(label: 'Automation', items: [
    OwnerDestination(label: 'AI Planner', icon: Icons.auto_awesome_outlined, roles: _adminManager, build: AiPlannerAdminScreen.new),
    OwnerDestination(
        label: 'Agent Workflows', icon: Icons.satellite_alt_outlined, roles: _staffUp, build: AgentWorkflowsScreen.new),
  ]),
  OwnerSection(label: 'Business', items: [
    OwnerDestination(
        label: 'Business Profile', icon: Icons.storefront_outlined, roles: _adminManager, build: BusinessProfileEditorScreen.new),
    OwnerDestination(
        label: 'Business Settings', icon: Icons.settings_outlined, roles: _admin, build: BusinessSettingsScreen.new),
  ]),
];

/// Every destination the given role can reach, flattened — used by the home
/// screen's search and by the parity test.
List<OwnerDestination> ownerDestinationsFor(String role) =>
    ownerSections.expand((s) => s.forRole(role)).toList();

/// Opens a destination, replacing the current owner screen rather than
/// stacking: moving from Invoices to Inventory through the drawer should
/// not leave Invoices on the back stack, exactly as clicking a sidebar link
/// on the web does not.
void openOwnerDestination(BuildContext context, OwnerDestination destination, {bool replace = true}) {
  final route = slideFadeRoute<void>(destination.build());
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// The workspace drawer — the sidebar, on a phone.
class OwnerDrawer extends ConsumerWidget {
  const OwnerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final role = user?.role ?? 'Customer';

    return Drawer(
      backgroundColor: AppColors.bgMid,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workspace', style: AppTextStyles.title),
                  const SizedBox(height: 2),
                  Text(
                    '${user?.fullName ?? ''} · $role',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            for (final section in ownerSections)
              if (section.forRole(role).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                  child: Text(
                    section.label.toUpperCase(),
                    style: AppTextStyles.label.copyWith(color: AppColors.textMuted, letterSpacing: 1.1),
                  ),
                ),
                for (final destination in section.forRole(role))
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Icon(destination.icon, size: 20, color: AppColors.iconPrimary),
                    title: Text(destination.label, style: AppTextStyles.body),
                    onTap: () {
                      Navigator.of(context).pop();
                      openOwnerDestination(context, destination);
                    },
                  ),
              ],
            const Divider(height: 28, color: AppColors.hairline),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
              title: Text('Sign out', style: AppTextStyles.body.copyWith(color: AppColors.error)),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
