import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/route_transitions.dart';
import '../../../widgets/ui/ui.dart';
import '../../business_profile_editor_screen.dart';
import '../owner_widgets.dart';

/// Business Settings — the mobile twin of the web Settings page: the name
/// customers see, and the two cutoffs that decide how late someone may
/// change their mind. The richer listing (logo, hours, gallery) stays in
/// the profile editor, which this links to rather than duplicating.
class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  final _name = TextEditingController();
  int? _rescheduleHours;
  int? _cancelHours;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateTenant(
            name: _name.text.trim(),
            rescheduleCutoffHours: _rescheduleHours,
            cancellationCutoffHours: _cancelHours,
          );
      ref.invalidate(ownerTenantProvider);
      if (mounted) AppSnackBar.success(context, 'Settings saved.');
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save these settings.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(ownerTenantProvider);

    return OwnerScaffold(
      title: 'Business Settings',
      subtitle: 'How the business behaves',
      body: tenantAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the settings.',
          onRetry: () => ref.invalidate(ownerTenantProvider),
        ),
        data: (tenant) {
          // Seed the form once; re-seeding on every rebuild would fight the
          // operator's own typing.
          if (!_loaded) {
            _name.text = tenant.name;
            _rescheduleHours = tenant.rescheduleCutoffHours;
            _cancelHours = tenant.cancellationCutoffHours;
            _loaded = true;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(label: 'Business type', value: tenant.businessType, sub: tenant.subType ?? 'no sub-type'),
                StatTile(
                  label: 'Status',
                  value: tenant.isActive ? 'Active' : 'Suspended',
                  sub: tenant.isActive ? 'taking bookings' : 'not taking bookings',
                  accent: tenant.isActive ? AppColors.success : AppColors.error,
                ),
              ]),
              const SizedBox(height: 18),
              const SectionHeader('Identity'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeonInputField(label: 'Business name', controller: _name),
                    const SizedBox(height: 10),
                    Text(
                      'The logo, cover photo, opening hours and gallery live in the Business Profile.',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Edit business profile',
                      icon: Icons.storefront_outlined,
                      height: 44,
                      onPressed: () => Navigator.of(context).push(
                        slideFadeRoute<void>(const BusinessProfileEditorScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeader('Change cutoffs'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How close to the appointment a customer may still move or drop it. The API enforces these, '
                      'so a tighter number really does stop last-minute changes.',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 14),
                    Text('Reschedule up to', style: AppTextStyles.label),
                    const SizedBox(height: 8),
                    FilterChips<int>(
                      options: const [
                        (value: 1, label: '1 h'),
                        (value: 2, label: '2 h'),
                        (value: 6, label: '6 h'),
                        (value: 24, label: '24 h'),
                      ],
                      selected: _rescheduleHours,
                      onSelected: (v) => setState(() => _rescheduleHours = v),
                    ),
                    const SizedBox(height: 14),
                    Text('Cancel up to', style: AppTextStyles.label),
                    const SizedBox(height: 8),
                    FilterChips<int>(
                      options: const [
                        (value: 1, label: '1 h'),
                        (value: 2, label: '2 h'),
                        (value: 6, label: '6 h'),
                        (value: 24, label: '24 h'),
                      ],
                      selected: _cancelHours,
                      onSelected: (v) => setState(() => _cancelHours = v),
                    ),
                    const SizedBox(height: 16),
                    NeonButton(label: 'Save settings', isLoading: _saving, onPressed: _saving ? null : _save),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
