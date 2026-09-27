import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/branch_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The site register — the mobile twin of the web Branches page. Each row
/// shows how much of the business actually sits at that branch, because a
/// branch with no resources takes no bookings however tidy its address is.
class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(ownerBranchesProvider);
    final resources = ref.watch(ownerResourcesProvider).valueOrNull ?? const [];
    final staff = ref.watch(ownerStaffProvider).valueOrNull ?? const [];

    return OwnerScaffold(
      title: 'Branches',
      subtitle: 'Where the business operates',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('New branch'),
      ),
      body: branchesAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the branches.',
          onRetry: () => ref.invalidate(ownerBranchesProvider),
        ),
        data: (branches) => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async {
            ref.invalidate(ownerBranchesProvider);
            ref.invalidate(ownerResourcesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (branches.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(icon: Icons.location_off_outlined, message: 'No branches yet. Add the first one.'),
                )
              else
                for (final branch in branches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => _edit(context, ref, branch),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const IconWell(icon: Icons.location_on_outlined, color: AppColors.magenta),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(branch.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                                    if (branch.address.isNotEmpty)
                                      Text(branch.address, style: AppTextStyles.caption),
                                    if (branch.phone.isNotEmpty) Text(branch.phone, style: AppTextStyles.caption),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: AppColors.hairline, height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _Count(
                                  label: 'Resources',
                                  value: resources.where((r) => r.branchId == branch.id).length,
                                ),
                              ),
                              Expanded(
                                child: _Count(
                                  label: 'Staff',
                                  value: staff.where((s) => s.branchId == branch.id).length,
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () => _confirmDelete(context, ref, branch),
                                  child: Text(
                                    'Delete',
                                    style: AppTextStyles.caption.copyWith(color: AppColors.error),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Branch branch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Delete "${branch.name}"?', style: AppTextStyles.title),
        content: Text('Resources and staff assigned here keep working; they just lose the branch.',
            style: AppTextStyles.caption),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).deleteBranch(branch.id);
      ref.invalidate(ownerBranchesProvider);
      if (context.mounted) AppSnackBar.success(context, 'Branch deleted.');
    } catch (_) {
      if (context.mounted) AppSnackBar.error(context, 'Could not delete this branch.');
    }
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, Branch? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _BranchForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(ownerBranchesProvider);
  }
}

class _Count extends StatelessWidget {
  final String label;
  final int value;
  const _Count({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

class _BranchForm extends ConsumerStatefulWidget {
  final Branch? existing;
  const _BranchForm({this.existing});

  @override
  ConsumerState<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<_BranchForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _address = TextEditingController(text: widget.existing?.address ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final repo = ref.read(ownerRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.createBranch(
          tenantId: ref.read(ownerTenantIdProvider),
          name: _name.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
        );
      } else {
        await repo.updateBranch(
          widget.existing!.id,
          name: _name.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save this branch.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New branch' : 'Edit branch', style: AppTextStyles.title),
              const SizedBox(height: 14),
              NeonInputField(
                label: 'Name',
                controller: _name,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
              ),
              const SizedBox(height: 10),
              NeonInputField(label: 'Address', controller: _address, maxLines: 2),
              const SizedBox(height: 10),
              NeonInputField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              NeonButton(label: 'Save', isLoading: _saving, onPressed: _saving ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}
