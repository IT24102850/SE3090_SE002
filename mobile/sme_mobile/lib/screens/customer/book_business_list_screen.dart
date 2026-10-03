import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../providers/public_tenant_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'business_detail_screen.dart';

class BookBusinessListScreen extends ConsumerStatefulWidget {
  const BookBusinessListScreen({
    super.key,
    this.onBusinessSelected,
  });

  final Future<bool> Function(PublicTenant tenant)? onBusinessSelected;

  @override
  ConsumerState<BookBusinessListScreen> createState() =>
      _BookBusinessListScreenState();
}

class _BookBusinessListScreenState
    extends ConsumerState<BookBusinessListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedType = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onTenantTap(PublicTenant tenant) {
    final visual = BusinessTypeVisual.of(tenant.businessType);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          decoration: BoxDecoration(
            color: AppColors.overlaySurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.card),
            ),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: visual.color.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.title.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tenant.businessType,
                          style: AppTextStyles.caption.copyWith(
                            color: visual.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                _businessPreview(tenant.businessType),
                style: AppTextStyles.bodyMuted.copyWith(height: 1.45),
              ),
              const SizedBox(height: 18),
              const _PreviewStep(
                number: '1',
                label: 'Explore services and options',
              ),
              const SizedBox(height: 10),
              const _PreviewStep(
                number: '2',
                label: 'Choose what works for you',
              ),
              const SizedBox(height: 10),
              const _PreviewStep(
                number: '3',
                label: 'Book when you are ready',
              ),
              const SizedBox(height: 22),
              NeonButton(
                label: widget.onBusinessSelected == null
                    ? 'Explore business'
                    : 'Shop this business',
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final onBusinessSelected = widget.onBusinessSelected;
                  if (onBusinessSelected != null) {
                    final selected = await onBusinessSelected(tenant);
                    if (!selected && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not connect to this business. Please try again.',
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  Navigator.of(context).push(
                    slideFadeRoute(BusinessDetailScreen(tenant: tenant)),
                  );
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  String _businessPreview(String type) => switch (type) {
        'Clinic' =>
          'Find care, explore available services, and choose an appointment that suits you.',
        'Restaurant' =>
          'Explore dining options and find the right experience for your visit.',
        'Gym' =>
          'Discover facilities and sessions, then plan a visit at your convenience.',
        'School' =>
          'Explore learning services and find the right program for your needs.',
        'RealEstate' =>
          'Explore property services and connect with the team about your next move.',
        'Tourism' =>
          'Discover experiences and find a tour or activity for your next trip.',
        _ =>
          'Explore what this business offers, choose a service, and book when you are ready.',
      };

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(publicTenantsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Find a Business'),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: NeonInputField(
                controller: _searchController,
                hintText: 'Search by business or type…',
                icon: Icons.search,
                clearable: true,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            // Type filter dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: AppColors.chevron),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final tenantsAsync = ref.watch(publicTenantsProvider);
                        return tenantsAsync.when(
                          data: (tenants) {
                            final types = tenants
                                .map((t) => t.businessType)
                                .toSet()
                                .toList();
                            types.sort();
                            types.insert(0, 'All');
                            return DropdownButton<String>(
                              value: _selectedType,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down),
                              items: types
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedType = v ?? 'All'),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tenantsAsync.when(
                loading: () => const AppLoader(),
                error: (err, stack) => ErrorState(
                  message:
                      'Could not load businesses. Check your connection and try again.',
                  onRetry: () => ref.invalidate(publicTenantsProvider),
                ),
                data: (tenants) {
                  final filtered = tenants.where((t) {
                    final matchesQuery = _query.isEmpty ||
                        t.businessName.toLowerCase().contains(_query) ||
                        t.businessType.toLowerCase().contains(_query);
                    final matchesType = _selectedType == 'All' ||
                        t.businessType == _selectedType;
                    return matchesQuery && matchesType;
                  }).toList();

                  if (tenants.isEmpty) {
                    return const EmptyState(
                      icon: Icons.storefront_outlined,
                      title:
                          'No businesses are available for booking right now.',
                      message:
                          'Check back soon, or ask your business to register on Unify.',
                    );
                  }
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_rounded,
                      message: 'No businesses match "$_query".',
                    );
                  }

                  return Column(children: [
                    Text(filtered.length == tenants.length
                      ? "${tenants.length} businesses"
                      : "${filtered.length} of ${tenants.length} businesses"),
                    Expanded(child: RefreshIndicator(
                    color: AppColors.cyan,
                    backgroundColor: AppColors.overlaySurface,
                    onRefresh: () async =>
                        ref.invalidate(publicTenantsProvider),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount =
                            constraints.maxWidth > 600 ? 3 : 2;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            // The previous 3:1 tiles were shorter than the
                            // icon + name + category stack and overflowed on
                            // phones. Give each card enough height to breathe.
                            childAspectRatio: crossAxisCount == 2 ? 2.05 : 2.3,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _TenantCard(
                            tenant: filtered[index],
                            onTap: () => _onTenantTap(filtered[index]),
                          ),
                        );
                      },
                    ),
                  )),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.onTap});

  final PublicTenant tenant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = BusinessTypeVisual.of(tenant.businessType);

    return GlassCard(
      onTap: onTap,
      borderRadius: AppRadii.row,
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tenant.coverImageUrl?.trim().isNotEmpty == true)
            Image.network(
              tenant.coverImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradientFor(visual.color),
                ),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradientFor(visual.color),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x99050514), Color(0xCC050514)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border:
                        Border.all(color: visual.color.withValues(alpha: 0.45)),
                  ),
                  child: tenant.logoUrl?.trim().isNotEmpty == true
                      ? Image.network(
                          tenant.logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            visual.icon,
                            color: visual.color,
                            size: 21,
                          ),
                        )
                      : Icon(visual.icon, color: visual.color, size: 21),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.businessName,
                        style: AppTextStyles.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: visual.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: visual.color.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          tenant.businessType,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            color: visual.color,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textPrimary, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.32)),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(label, style: AppTextStyles.body.copyWith(fontSize: 13)),
          ),
        ],
      );
}
