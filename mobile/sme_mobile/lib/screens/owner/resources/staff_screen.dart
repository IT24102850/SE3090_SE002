import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/owner_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The staff register — the mobile twin of the web Staff page: who works
/// here, which branch they sit at, and whether their login still works.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(ownerStaffProvider);
    final branches = ref.watch(ownerBranchesProvider).valueOrNull ?? const [];
    final branchName = {for (final b in branches) b.id: b.name};

    return OwnerScaffold(
      title: 'Staff',
      subtitle: 'Who works here',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _invite(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add staff'),
      ),
      body: staffAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the staff list.',
          onRetry: () => ref.invalidate(ownerStaffProvider),
        ),
        data: (staff) => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async => ref.invalidate(ownerStaffProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              StatGrid(tiles: [
                StatTile(label: 'On the books', value: '${staff.length}', sub: 'staff logins'),
                StatTile(
                  label: 'Active',
                  value: '${staff.where((s) => s.isActive).length}',
                  sub: 'can sign in',
                  accent: AppColors.success,
                ),
                StatTile(label: 'Managers', value: '${staff.where((s) => s.role == 'Manager').length}', sub: 'can approve'),
                StatTile(label: 'Branches', value: '${branches.length}', sub: 'sites covered'),
              ]),
              const SizedBox(height: 16),
              if (staff.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(icon: Icons.groups_outlined, message: 'No staff yet. Add the first login.'),
                )
              else
                ...staff.map((member) => _StaffCard(member: member, branchName: branchName[member.branchId])),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _StaffForm(),
      ),
    );
    if (saved == true) ref.invalidate(ownerStaffProvider);
  }
}

class _StaffCard extends ConsumerWidget {
  final StaffMember member;
  final String? branchName;

  const _StaffCard({required this.member, this.branchName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.iconWell,
                  child: Text(
                    _initials(member.fullName),
                    style: AppTextStyles.caption.copyWith(color: AppColors.cyan, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(member.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                      if (branchName != null) Text(branchName!, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                OwnerStatusChip(status: member.isActive ? 'Active' : 'Disabled'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Pill(label: member.role, icon: Icons.badge_outlined),
                if (member.phone?.isNotEmpty == true) ...[
                  const SizedBox(width: 8),
                  _Pill(label: member.phone!, icon: Icons.call_outlined),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(ownerRepositoryProvider).updateStaff(member.id, isActive: !member.isActive);
                      ref.invalidate(ownerStaffProvider);
                      if (context.mounted) {
                        AppSnackBar.success(context, member.isActive ? 'Login disabled.' : 'Login re-enabled.');
                      }
                    } catch (_) {
                      if (context.mounted) AppSnackBar.error(context, 'Could not change this login.');
                    }
                  },
                  child: Text(
                    member.isActive ? 'Disable' : 'Enable',
                    style: AppTextStyles.caption.copyWith(
                      color: member.isActive ? AppColors.error : AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.iconSecondary),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm();

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'Staff';
  String? _branchId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_fullName, _email, _password, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).createStaff(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _fullName.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            branchId: _branchId,
            role: _role,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not create this login — the email may already be in use.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(ownerBranchesProvider).valueOrNull ?? const [];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a staff login', style: AppTextStyles.title),
              const SizedBox(height: 4),
              Text('They sign in with this email and can change the password after.', style: AppTextStyles.caption),
              const SizedBox(height: 14),
              NeonInputField(
                label: 'Full name',
                controller: _fullName,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Who is it?' : null,
              ),
              const SizedBox(height: 10),
              NeonInputField(
                label: 'Email',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v ?? '').contains('@') ? null : 'A valid email, please.',
              ),
              const SizedBox(height: 10),
              NeonInputField(
                label: 'Temporary password',
                controller: _password,
                obscurable: true,
                validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters.' : null,
              ),
              const SizedBox(height: 10),
              NeonInputField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              Text('Role', style: AppTextStyles.label),
              const SizedBox(height: 8),
              FilterChips<String>(
                options: const [(value: 'Staff', label: 'Staff'), (value: 'Manager', label: 'Manager')],
                selected: _role,
                onSelected: (v) => setState(() => _role = v ?? 'Staff'),
              ),
              if (branches.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Branch', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<String>(
                  options: [
                    (value: null, label: 'Any branch'),
                    for (final b in branches) (value: b.id, label: b.name),
                  ],
                  selected: _branchId,
                  onSelected: (v) => setState(() => _branchId = v),
                ),
              ],
              const SizedBox(height: 16),
              NeonButton(label: 'Create login', isLoading: _saving, onPressed: _saving ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}
