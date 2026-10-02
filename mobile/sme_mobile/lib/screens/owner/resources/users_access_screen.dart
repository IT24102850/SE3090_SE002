import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/managed_user_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../services/access_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Who can sign in, and as what — the mobile twin of the web app's
/// Users & Access screen.
///
/// Two lists, because there are two states that look alike and are not: people
/// who already have access, and people who registered themselves and cannot
/// sign in until an Admin gives them a role and a branch. A request that is
/// never actioned is someone locked out, so the waiting list comes first.
class UsersAccessScreen extends ConsumerStatefulWidget {
  const UsersAccessScreen({super.key});

  @override
  ConsumerState<UsersAccessScreen> createState() => _UsersAccessScreenState();
}

class _UsersAccessScreenState extends ConsumerState<UsersAccessScreen> {
  String? _busyId;
  String _message = '';
  bool _messageIsError = false;

  void _say(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
  }

  Future<void> _run(String id, Future<void> Function() action, String success) async {
    setState(() {
      _busyId = id;
      _message = '';
    });
    try {
      await action();
      _say(success);
      ref.invalidate(accessDirectoryProvider);
    } catch (e) {
      _say(accessErrorMessage(e, 'That change could not be saved.'), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(ManagedUser user, List<AccessBranch> branches) async {
    final branchId = user.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    if (branchId == null) {
      _say('Create a branch before approving this request.', isError: true);
      return;
    }
    await _run(
      user.id,
      () => ref.read(accessRepositoryProvider).approve(user, role: user.role, branchId: branchId),
      '${user.fullName} can now sign in.',
    );
  }

  Future<void> _changeRole(ManagedUser user, String role) => _run(
        user.id,
        () => ref.read(accessRepositoryProvider).update(user, role: role),
        '${user.fullName} is now a $role.',
      );

  Future<void> _delete(ManagedUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Remove ${user.fullName}?', style: AppTextStyles.title),
        content: Text(
          'They lose access immediately. Bookings they made stay on the diary.',
          style: AppTextStyles.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep them', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Remove',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(user.id, () => ref.read(accessRepositoryProvider).remove(user.id),
        '${user.fullName} was removed.');
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(accessDirectoryProvider);

    return OwnerScaffold(
      title: 'Users & Access',
      subtitle: 'Who can sign in, and as what',
      body: directory.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: accessErrorMessage(error, 'The directory could not be loaded.'),
          onRetry: () => ref.invalidate(accessDirectoryProvider),
        ),
        data: (data) => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async => ref.invalidate(accessDirectoryProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(
                  label: 'Waiting',
                  value: '${data.pending.length}',
                  sub: 'need a decision',
                  accent: data.pending.isEmpty ? AppColors.success : AppColors.warning,
                ),
                StatTile(label: 'With access', value: '${data.users.length}', sub: 'can sign in'),
              ]),
              const SizedBox(height: 16),
              if (_message.isNotEmpty) ...[
                _Notice(message: _message, isError: _messageIsError),
                const SizedBox(height: 12),
              ],
              if (data.pending.isNotEmpty) ...[
                const SectionHeader('Waiting for approval'),
                ...data.pending.map((u) => _PendingCard(
                      user: u,
                      busy: _busyId == u.id,
                      branchName: _branchName(u, data.branches),
                      onApprove: () => _approve(u, data.branches),
                      onReject: () => _delete(u),
                    )),
                const SizedBox(height: 18),
              ],
              const SectionHeader('People with access'),
              if (data.users.isEmpty)
                const EmptyState(
                  icon: Icons.people_outline,
                  title: 'Nobody has access yet',
                  message: 'Approved sign-ups and accounts you create appear here.',
                )
              else
                ...data.users.map((u) => _UserCard(
                      user: u,
                      busy: _busyId == u.id,
                      branchName: _branchName(u, data.branches),
                      onRoleChanged: (role) => _changeRole(u, role),
                      onDelete: () => _delete(u),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  static String _branchName(ManagedUser user, List<AccessBranch> branches) {
    if (user.branchId == null) return 'No branch';
    for (final branch in branches) {
      if (branch.id == user.branchId) return branch.name;
    }
    return 'No branch';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? AppColors.error : AppColors.cyan;
    return GlassCard(
      borderColor: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.user,
    required this.busy,
    required this.branchName,
    required this.onApprove,
    required this.onReject,
  });

  final ManagedUser user;
  final bool busy;
  final String branchName;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderColor: AppColors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName, style: AppTextStyles.subtitle),
            Text('${user.email} · asking for ${user.role} · $branchName',
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            NeonButton(
              label: 'Approve',
              icon: Icons.check_rounded,
              isLoading: busy,
              onPressed: busy ? null : onApprove,
            ),
            const SizedBox(height: 8),
            GhostButton(
              label: 'Reject',
              icon: Icons.close_rounded,
              color: AppColors.error,
              onPressed: busy ? null : onReject,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.busy,
    required this.branchName,
    required this.onRoleChanged,
    required this.onDelete,
  });

  final ManagedUser user;
  final bool busy;
  final String branchName;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: AppTextStyles.subtitle),
                      Text('${user.email} · $branchName',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${user.fullName}',
                  icon: const Icon(Icons.person_remove_outlined, size: 20, color: AppColors.error),
                  onPressed: busy ? null : onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Role', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(width: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.overlaySurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: DropdownButton<String>(
                        key: Key('role-${user.id}'),
                        value: ManagedUser.roles.contains(user.role) ? user.role : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: AppColors.overlaySurface,
                        items: ManagedUser.roles
                            .map((r) => DropdownMenuItem(
                                value: r, child: Text(r, style: AppTextStyles.body)))
                            .toList(),
                        onChanged: busy
                            ? null
                            : (role) {
                                if (role != null && role != user.role) onRoleChanged(role);
                              },
                      ),
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
}
