import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../models/resource_model.dart';
import '../../models/tourism_subtype.dart';
import '../../providers/booking_providers.dart';
import '../../providers/tenant_profile_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/business_profile_header.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/route_transitions.dart';
import '../booking_dashboard_screen.dart';
import 'booking_flow_screen.dart';

class BusinessDetailScreen extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  const BusinessDetailScreen({super.key, required this.tenant});

  @override
  ConsumerState<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<BusinessDetailScreen> {
  String? _selectedBranchId;
  bool _branchInitialized = false;

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final branchesAsync = ref.watch(branchesProvider(tenant.id));

    // Tourism tenants with a resolved sub-type get the themed dashboard
    // (distinct terminology/fields per sub-type) instead of the generic
    // resource list below. Tenants with no sub-type set yet (legacy data)
    // or non-Tourism business types keep the existing behavior unchanged.
    final resolvedSubType = tenant.businessType == 'Tourism'
        ? TourismSubTypeParsing.fromTenantSubType(tenant.subType)
        : null;
    if (resolvedSubType != null) {
      final branches = branchesAsync.valueOrNull ?? const [];
      return BookingDashboardScreen(
        tenant: tenant,
        address: branches.isNotEmpty ? branches.first.address : null,
        subType: resolvedSubType,
        fetchAvailableResources: () async {
          final resources = await ref.read(resourcesProvider((tenantId: tenant.id, branchId: null)).future);
          return resources.where((r) => r.status == 'Available').toList();
        },
      );
    }

    final visual = BusinessTypeVisual.of(tenant.businessType);
    final profileAsync = ref.watch(tenantProfileProvider(tenant.id));

    return AppBackgroundScaffold(
      appBar: GlassAppBar(title: tenant.businessName),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: BusinessProfileHeader(
              businessName: tenant.businessName,
              address: null, // the branch address row below already covers this for the generic path
              profile: profileAsync.valueOrNull,
              hasError: profileAsync.hasError,
              onRetry: () => ref.invalidate(tenantProfileProvider(tenant.id)),
              themeColor: visual.color,
              themeIcon: visual.icon,
            ),
          ),
          SliverToBoxAdapter(
            child: branchesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: AppLoader(),
              ),
              error: (err, stack) => ErrorState(
                message: 'Could not load this business.',
                onRetry: () => ref.invalidate(branchesProvider(tenant.id)),
              ),
              data: (branches) {
                if (!_branchInitialized) {
                  _branchInitialized = true;
                  if (branches.length == 1) _selectedBranchId = branches.first.id;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (branches.length > 1) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: SectionHeader('Branches', padding: EdgeInsets.zero),
                      ),
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          children: [
                            _BranchChip(
                              label: 'All branches',
                              selected: _selectedBranchId == null,
                              onTap: () => setState(() => _selectedBranchId = null),
                              color: visual.color,
                            ),
                            const SizedBox(width: 8),
                            ...branches.map((b) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _BranchChip(
                                    label: b.name,
                                    selected: _selectedBranchId == b.id,
                                    onTap: () => setState(() => _selectedBranchId = b.id),
                                    color: visual.color,
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ] else if (branches.length == 1) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16, color: AppColors.iconSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                branches.first.address.isNotEmpty ? branches.first.address : branches.first.name,
                                style: AppTextStyles.bodyMuted.copyWith(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: SectionHeader('Book a resource', padding: EdgeInsets.zero),
                    ),
                    _ResourceList(tenant: tenant, branchId: _selectedBranchId, visual: visual),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceList extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  final String? branchId;
  final BusinessTypeVisual visual;

  const _ResourceList({required this.tenant, required this.branchId, required this.visual});

  @override
  ConsumerState<_ResourceList> createState() => _ResourceListState();
}

class _ResourceListState extends ConsumerState<_ResourceList> {
  String? _specialtyFilter;

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final branchId = widget.branchId;
    final visual = widget.visual;
    final query = (tenantId: tenant.id, branchId: branchId);
    final resourcesAsync = ref.watch(resourcesProvider(query));

    return resourcesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: AppLoader(),
      ),
      error: (err, stack) => ErrorState(
        message: 'Could not load resources.',
        onRetry: () => ref.invalidate(resourcesProvider(query)),
      ),
      data: (resources) {
        final bookableAll = resources.where((r) => r.status == 'Available').toList();
        if (bookableAll.isEmpty) {
          return const EmptyState(
            icon: Icons.event_busy_outlined,
            message: 'Nothing available to book right now.',
          );
        }

        // FR-B1: filter doctors/resources by specialty.
        final specialties = bookableAll
            .map((r) => r.specialty)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final bookable = _specialtyFilter == null
            ? bookableAll
            : bookableAll.where((r) => r.specialty == _specialtyFilter).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (specialties.isNotEmpty) ...[
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _BranchChip(
                      label: 'All specialties',
                      selected: _specialtyFilter == null,
                      onTap: () => setState(() => _specialtyFilter = null),
                      color: visual.color,
                    ),
                    const SizedBox(width: 8),
                    ...specialties.map((s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _BranchChip(
                            label: s,
                            selected: _specialtyFilter == s,
                            onTap: () => setState(() => _specialtyFilter = s),
                            color: visual.color,
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: bookable
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ResourceCard(
                            resource: r,
                            visual: visual,
                            onTap: () => Navigator.of(context).push(
                              slideFadeRoute(BookingFlowScreen(tenant: tenant, resource: r)),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final Resource resource;
  final BusinessTypeVisual visual;
  final VoidCallback onTap;

  const _ResourceCard({required this.resource, required this.visual, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      borderRadius: AppRadii.row,
      padding: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.iconWell,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: Border.all(color: visual.color.withValues(alpha: 0.45)),
                ),
                child: Icon(visual.icon, color: visual.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(resource.name, style: AppTextStyles.subtitle),
                    if (resource.specialty != null && resource.specialty!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        resource.specialty!,
                        style: AppTextStyles.caption.copyWith(color: visual.color, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (resource.capacity != null) ...[
                          const Icon(Icons.groups_outlined, size: 13, color: AppColors.iconDisabled),
                          const SizedBox(width: 3),
                          Text('${resource.capacity}', style: AppTextStyles.caption),
                          const SizedBox(width: 10),
                        ],
                        if (resource.hourlyRate != null) ...[
                          const Icon(Icons.payments_outlined, size: 13, color: AppColors.iconDisabled),
                          const SizedBox(width: 3),
                          Text('LKR ${resource.hourlyRate!.toStringAsFixed(0)}/hr', style: AppTextStyles.caption),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  borderRadius: BorderRadius.circular(AppRadii.image),
                  boxShadow: const [
                    BoxShadow(color: AppColors.buttonGlow, blurRadius: 14, spreadRadius: -4),
                  ],
                ),
                child: Text(
                  'Book',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _BranchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _BranchChip({required this.label, required this.selected, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : AppColors.inputFill,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : AppColors.inputBorder),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}
