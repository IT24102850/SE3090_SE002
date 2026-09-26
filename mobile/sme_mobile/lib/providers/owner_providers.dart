import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_billing_models.dart';
import '../models/agent_workflow_model.dart';
import '../models/billing_models.dart';
import '../models/booking_model.dart';
import '../models/booking_type_model.dart';
import '../models/branch_model.dart';
import '../models/inventory_models.dart';
import '../models/owner_models.dart';
import '../models/resource_model.dart';
import '../services/admin_billing_repository.dart';
import '../services/agent_repository.dart';
import '../services/inventory_repository.dart';
import '../services/owner_repository.dart';
import 'api_service_provider.dart';
import 'auth_provider.dart';

/// Wiring for every owner-side screen. The repositories hold the HTTP; the
/// providers below decide what each screen watches and — just as important
/// — what a write has to invalidate afterwards, so a list never shows a row
/// the server has already changed.

// ── Repositories ────────────────────────────────────────────────────────

final ownerRepositoryProvider = Provider<OwnerRepository>((ref) => OwnerRepository(ref.watch(apiServiceProvider)));
final inventoryRepositoryProvider =
    Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(apiServiceProvider)));
final adminBillingRepositoryProvider =
    Provider<AdminBillingRepository>((ref) => AdminBillingRepository(ref.watch(apiServiceProvider)));
final agentRepositoryProvider = Provider<AgentRepository>((ref) => AgentRepository(ref.watch(apiServiceProvider)));

/// The signed-in operator's tenant. Every owner screen is scoped to it, and
/// an empty string means "not signed in yet" — providers skip their fetch
/// rather than calling the API without a tenant.
final ownerTenantIdProvider = Provider<String>((ref) => ref.watch(authProvider).user?.tenantId ?? '');

/// Which branch the operator has narrowed to, or null for all of them.
/// Shared across the owner screens so a choice made on one carries over.
final ownerBranchFilterProvider = StateProvider<String?>((ref) => null);

// ── Scheduling ──────────────────────────────────────────────────────────

/// The booking desk's working window: two weeks back, six weeks forward.
/// One request feeds the KPI strip, the day filter and the "next up" list,
/// so those three can never disagree with each other.
final ownerBookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  final now = DateTime.now();
  return ref.watch(ownerRepositoryProvider).bookings(
        tenantId: tenantId,
        branchId: ref.watch(ownerBranchFilterProvider),
        from: now.subtract(const Duration(days: 14)),
        to: now.add(const Duration(days: 42)),
      );
});

final ownerConflictsProvider = FutureProvider.autoDispose<List<ConflictPair>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(ownerRepositoryProvider).conflicts(tenantId);
});

/// Every booking type including the retired ones — the manager screen has
/// to be able to see and reinstate an Inactive type.
final ownerBookingTypesProvider = FutureProvider.autoDispose<List<BookingType>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(ownerRepositoryProvider).bookingTypes(tenantId);
});

// ── Resources, staff, branches, settings ────────────────────────────────

final ownerResourcesProvider = FutureProvider.autoDispose<List<Resource>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(ownerRepositoryProvider).resources(
        tenantId: tenantId,
        branchId: ref.watch(ownerBranchFilterProvider),
      );
});

final ownerStaffProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(ownerRepositoryProvider).staff(tenantId);
});

final ownerBranchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(ownerRepositoryProvider).branches(tenantId);
});

final ownerTenantProvider = FutureProvider.autoDispose<TenantSettings>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  return ref.watch(ownerRepositoryProvider).tenant(tenantId);
});

// ── Reports ─────────────────────────────────────────────────────────────

final ownerNoShowStatsProvider = FutureProvider.autoDispose<NoShowStats>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  final now = DateTime.now();
  return ref.watch(ownerRepositoryProvider).noShowStats(
        tenantId: tenantId,
        from: now.subtract(const Duration(days: 30)),
        to: now,
      );
});

final ownerRevenueProvider = FutureProvider.autoDispose<RevenueReport>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  return ref.watch(ownerRepositoryProvider).revenue(
        tenantId: tenantId,
        branchId: ref.watch(ownerBranchFilterProvider),
      );
});

// ── Inventory ───────────────────────────────────────────────────────────

final inventoryItemsProvider = FutureProvider.autoDispose<List<InventoryItem>>((ref) async =>
    ref.watch(inventoryRepositoryProvider).items(branchId: ref.watch(ownerBranchFilterProvider)));

final lowStockProvider =
    FutureProvider.autoDispose<List<InventoryItem>>((ref) async => ref.watch(inventoryRepositoryProvider).lowStock());

final stockMovementsProvider =
    FutureProvider.autoDispose<List<StockMovement>>((ref) async => ref.watch(inventoryRepositoryProvider).movements());

final purchaseOrdersProvider = FutureProvider.autoDispose<List<PurchaseOrder>>((ref) async =>
    ref.watch(inventoryRepositoryProvider).purchaseOrders(branchId: ref.watch(ownerBranchFilterProvider)));

final purchaseOrderOptionsProvider = FutureProvider.autoDispose<PurchaseOrderOptions>(
    (ref) async => ref.watch(inventoryRepositoryProvider).purchaseOrderOptions());

final inventoryUsageProvider = FutureProvider.autoDispose<InventoryUsageReport>((ref) async =>
    ref.watch(inventoryRepositoryProvider).usage(branchId: ref.watch(ownerBranchFilterProvider)));

// ── Billing (owner side) ────────────────────────────────────────────────

final billingDashboardProvider = FutureProvider.autoDispose<BillingDashboard>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  return ref.watch(adminBillingRepositoryProvider).dashboard(tenantId, branchId: ref.watch(ownerBranchFilterProvider));
});

final outstandingReportProvider = FutureProvider.autoDispose<OutstandingReport>((ref) async =>
    ref.watch(adminBillingRepositoryProvider).outstanding(ref.watch(ownerTenantIdProvider)));

final billingCustomersProvider =
    FutureProvider.autoDispose<List<BillingCustomer>>((ref) async => ref.watch(adminBillingRepositoryProvider).customers());

/// The invoice list's status filter — '' means every status.
final invoiceStatusFilterProvider = StateProvider.autoDispose<String>((ref) => '');

final adminInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).invoices(
        tenantId: tenantId,
        status: ref.watch(invoiceStatusFilterProvider),
      );
});

final adminSubscriptionsProvider = FutureProvider.autoDispose<List<Subscription>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).subscriptions(tenantId: tenantId);
});

final subscriptionRenewalsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).renewals(tenantId);
});

final adminClaimsProvider = FutureProvider.autoDispose<List<InsuranceClaim>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).claims(tenantId: tenantId);
});

final commissionRulesProvider = FutureProvider.autoDispose<List<CommissionRule>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).commissionRules(tenantId);
});

final paymentGatewaysProvider = FutureProvider.autoDispose<List<PaymentGatewayConfig>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).gateways(tenantId);
});

final dynamicFormsProvider =
    FutureProvider.autoDispose<List<DynamicFormDefinition>>((ref) async => ref.watch(adminBillingRepositoryProvider).forms());

final invoiceTemplatesProvider = FutureProvider.autoDispose<List<InvoiceTemplate>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).templates(tenantId);
});

final billingAgentWorkflowsProvider = FutureProvider.autoDispose<List<BillingAgentWorkflow>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(adminBillingRepositoryProvider).agentWorkflows(tenantId);
});

final billingAgentToolsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async => ref.watch(adminBillingRepositoryProvider).agentTools());

// ── Scheduling agent ────────────────────────────────────────────────────

final agentWorkflowsProvider = FutureProvider.autoDispose<List<AgentWorkflow>>((ref) async {
  final tenantId = ref.watch(ownerTenantIdProvider);
  if (tenantId.isEmpty) return const [];
  return ref.watch(agentRepositoryProvider).workflows(tenantId: tenantId);
});
