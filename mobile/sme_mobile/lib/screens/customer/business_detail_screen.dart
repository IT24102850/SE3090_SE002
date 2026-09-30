import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../models/resource_model.dart';
import '../../models/tenant_profile_model.dart';
import '../../models/tourism_subtype.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_providers.dart';
import '../../providers/public_tenant_provider.dart';
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

  // A customer's account is global, but their token is scoped to one
  // business at a time and everything below (branches, resources, slots)
  // is filtered by it. So, before the first tenant-scoped request fires,
  // swap to a token for this business - creating the membership if this
  // is their first visit. Staff and admins never hit this path.
  bool _joining = false;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    if (user != null && user.role == 'Customer' && user.tenantId != widget.tenant.id) {
      _joining = true;
      Future.microtask(_join);
    }
  }

  Future<void> _join() async {
    final ok = await ref.read(authProvider.notifier).joinBusiness(widget.tenant.id);
    if (!mounted) return;
    setState(() {
      _joining = false;
      _joinError = ok ? null : 'Could not open this business right now.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    if (_joining || _joinError != null) {
      return AppBackgroundScaffold(
        appBar: GlassAppBar(title: tenant.businessName),
        child: Center(
          child: _joinError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_joinError!, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setState(() { _joining = true; _joinError = null; });
                          _join();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    final user = ref.watch(authProvider).user;
    final visual = BusinessTypeVisual.of(tenant.businessType);
    final profileAsync = ref.watch(tenantProfileProvider(tenant.id));

    // Branch and resource management APIs require authentication. Guests see
    // the actual public profile and catalog instead of a misleading error.
    if (user == null) {
      return _PublicBusinessPreview(
        tenant: tenant,
        visual: visual,
        profile: profileAsync,
        catalog: ref.watch(publicBusinessCatalogProvider(tenant.id)),
        onRetryProfile: () => ref.invalidate(tenantProfileProvider(tenant.id)),
        onRetryCatalog: () =>
            ref.invalidate(publicBusinessCatalogProvider(tenant.id)),
      );
    }

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

class _PublicBusinessPreview extends StatelessWidget {
  const _PublicBusinessPreview({
    required this.tenant,
    required this.visual,
    required this.profile,
    required this.catalog,
    required this.onRetryProfile,
    required this.onRetryCatalog,
  });

  final PublicTenant tenant;
  final BusinessTypeVisual visual;
  final AsyncValue<TenantProfile> profile;
  final AsyncValue<PublicBusinessCatalog> catalog;
  final VoidCallback onRetryProfile;
  final VoidCallback onRetryCatalog;

  @override
  Widget build(BuildContext context) => AppBackgroundScaffold(
        appBar: GlassAppBar(title: tenant.businessName),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BusinessProfileHeader(
                businessName: tenant.businessName,
                address: profile.valueOrNull?.address,
                profile: profile.valueOrNull,
                hasError: profile.hasError,
                onRetry: onRetryProfile,
                themeColor: visual.color,
                themeIcon: visual.icon,
              ),
            ),
            SliverToBoxAdapter(
              child: catalog.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Services are temporarily unavailable',
                    message: 'The public business profile is still available.',
                    actionLabel: 'Retry',
                    onAction: onRetryCatalog,
                  ),
                ),
                data: (data) => _PublicCatalogContent(
                  catalog: data,
                  accent: visual.color,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PublicCatalogContent extends StatelessWidget {
  const _PublicCatalogContent({required this.catalog, required this.accent});

  final PublicBusinessCatalog catalog;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hasOfferings =
        catalog.resources.isNotEmpty || catalog.departures.isNotEmpty;
    final offerings = <Widget>[
      ...catalog.resources.map((resource) => _PublicOfferingTile(
            icon: Icons.storefront_outlined,
            title: resource.name,
            subtitle: [
              if (resource.category.isNotEmpty) resource.category,
              if (resource.description?.trim().isNotEmpty == true)
                resource.description!.trim(),
            ].join(' • '),
            accent: accent,
          )),
      ...catalog.departures.map((departure) => _PublicOfferingTile(
            icon: Icons.event_available_outlined,
            title: departure.name,
            subtitle: [
              if (departure.bookingTypeName?.isNotEmpty == true)
                departure.bookingTypeName!,
              if (departure.startTime != null)
                MaterialLocalizations.of(context).formatMediumDate(
                  departure.startTime!.toLocal(),
                ),
              if (departure.seatsRemaining != null)
                '${departure.seatsRemaining} places left',
            ].join(' • '),
            accent: accent,
          )),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            hasOfferings ? 'Available services' : 'Explore this business',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          if (hasOfferings)
            ...offerings
          else if (catalog.bookingTypes.isNotEmpty)
            ...catalog.bookingTypes.map((type) => _PublicOfferingTile(
                  icon: Icons.event_note_rounded,
                  title: type.name,
                  subtitle: type.description ?? '',
                  accent: accent,
                ))
          else
            Text(
              'This business has not published its services yet. Check back soon for updates.',
              style: AppTextStyles.bodyMuted,
            ),
        ],
      ),
    );
  }
}

class _PublicOfferingTile extends StatelessWidget {
  const _PublicOfferingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: AppRadii.row,
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.subtitle),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: AppTextStyles.caption),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
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
