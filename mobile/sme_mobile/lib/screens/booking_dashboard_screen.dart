import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_tenant_model.dart';
import '../models/resource_model.dart';
import '../models/tourism_subtype.dart';
import '../models/subtype_dashboard_config.dart';
import '../providers/tenant_profile_provider.dart';
import '../registry/tourism_dashboard_registry.dart';
import '../screens/customer/booking_flow_screen.dart';
import '../widgets/business_profile_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/resource_card.dart';
import '../widgets/route_transitions.dart';
import '../widgets/ui/ui.dart';

/// Replaces the generic "Book a resource" screen for Tourism tenants with a
/// resolved sub-type. This ONE widget renders 11 visually and functionally
/// distinct dashboards - which config it uses is the only thing that
/// changes per tenant. Booking itself still goes through the existing
/// BookingFlowScreen wizard (Slot/Night/DateRange/Package-aware) - this
/// screen is a themed front door onto it, not a second booking path.
class BookingDashboardScreen extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  final String? address;
  final TourismSubType subType;
  final Future<List<Resource>> Function() fetchAvailableResources;

  const BookingDashboardScreen({
    super.key,
    required this.tenant,
    required this.address,
    required this.subType,
    required this.fetchAvailableResources,
  });

  @override
  ConsumerState<BookingDashboardScreen> createState() => _BookingDashboardScreenState();
}

class _BookingDashboardScreenState extends ConsumerState<BookingDashboardScreen> {
  late final SubtypeDashboardConfig _config;
  List<Resource> _resources = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _config = TourismDashboardRegistry.configFor(widget.subType);
    _loadResources();
  }

  Future<void> _loadResources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resources = await widget.fetchAvailableResources();
      setState(() {
        _resources = resources;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load availability. Pull down to retry.';
        _loading = false;
      });
    }
  }

  /// Merges the resource's native fields with its parsed CustomAttributes
  /// into the flat map ResourceCard's config-driven cardFields read from -
  /// e.g. `capacity` comes from the native field, `depth`/`bedCount`/
  /// `transmission` come from CustomAttributes.
  Map<String, dynamic> _displayMap(Resource r) => {
        ...?r.attributes,
        'name': r.name,
        if (r.capacity != null) 'capacity': r.capacity,
      };

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(tenantProfileProvider(widget.tenant.id));

    return AppBackgroundScaffold(
      appBar: GlassAppBar(title: widget.tenant.businessName),
      child: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: () async {
          ref.invalidate(tenantProfileProvider(widget.tenant.id));
          await _loadResources();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BusinessProfileHeader(
                businessName: widget.tenant.businessName,
                address: widget.address,
                profile: profileAsync.valueOrNull,
                hasError: profileAsync.hasError,
                onRetry: () => ref.invalidate(tenantProfileProvider(widget.tenant.id)),
                themeColor: _config.themeColor,
                themeIcon: _config.icon,
              ),
            ),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SliverFillRemaining(child: AppLoader());
    }
    if (_error != null) {
      return SliverFillRemaining(
        child: ErrorState(message: _error!, onRetry: _loadResources),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          Text(_config.heroActionLabel, style: AppTextStyles.title),
          const SizedBox(height: 16),
          if (_resources.isEmpty)
            _buildEmptyState()
          else
            ..._resources.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ResourceCard(
                    resource: _displayMap(r),
                    config: _config,
                    onBook: () => _openBookingForm(r),
                  ),
                )),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Still sub-type-aware, unlike the old generic "Nothing available" screen
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(_config.icon, size: 48, color: AppColors.iconGhost),
            const SizedBox(height: 12),
            Text(
              'No ${_config.resourceTermPlural.toLowerCase()} available right now.',
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _openBookingForm(Resource resource) {
    // Hands off into the existing BookingFlowScreen wizard rather than a
    // second booking-creation path - it already knows how to drive
    // Slot/Night/DateRange/Package availability. The sub-type's
    // bookingFormFields (certificationLevel, bedCount, ...) are collected
    // as an extra step inside that same wizard - see _ExtraFieldsStep in
    // booking_flow_screen.dart.
    Navigator.of(context).push(slideFadeRoute(
      BookingFlowScreen(tenant: widget.tenant, resource: resource, subType: widget.subType),
    ));
  }
}
