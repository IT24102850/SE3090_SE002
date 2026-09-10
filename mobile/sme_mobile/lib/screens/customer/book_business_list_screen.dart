import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/public_tenant_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import '../login_screen.dart';
import 'business_detail_screen.dart';
import 'customer_register_screen.dart';

class BookBusinessListScreen extends ConsumerStatefulWidget {
  const BookBusinessListScreen({super.key});

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
    final isAuthenticated = ref.read(authProvider).isAuthenticated;
    if (isAuthenticated) {
      Navigator.of(context)
          .push(slideFadeRoute(BusinessDetailScreen(tenant: tenant)));
      return;
    }
    _showSignInPrompt(tenant);
  }

  void _showSignInPrompt(PublicTenant tenant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.magenta.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.magenta.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: AppColors.magenta, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sign in to book with ${tenant.businessName}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a free account or sign in to see availability and book instantly.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 24),
                NeonButton(
                  label: 'Sign In',
                  height: 48,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'Create Account',
                  height: 48,
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final signedUp = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) =>
                              CustomerRegisterScreen(tenant: tenant)),
                    );
                    // Signed up as this tenant's customer — continue straight
                    // into their business page instead of dropping back to the list.
                    if (signedUp == true && mounted) {
                      Navigator.of(context).push(
                          slideFadeRoute(BusinessDetailScreen(tenant: tenant)));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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

                  return RefreshIndicator(
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
                            childAspectRatio: 3,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _TenantCard(
                            tenant: filtered[index],
                            onTap: () => _onTenantTap(filtered[index]),
                          ),
                        );
                      },
                    ),
                  );
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
      padding: const EdgeInsets.all(14),
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
            child: Icon(visual.icon, color: visual.color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenant.businessName,
                  style: AppTextStyles.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // The type pill carries the business hue, which is why this
                // row is built by hand rather than as a GlassListTile.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: visual.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: visual.color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    tenant.businessType,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: visual.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.chevron, size: 22),
        ],
      ),
    );
  }
}
