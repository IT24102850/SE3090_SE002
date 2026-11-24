import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social_models.dart';
import '../../../providers/social_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'social_widgets.dart';

/// Write once, publish now or schedule to any mix of accounts — the mobile
/// twin of the web Publisher. Publishing itself happens on the server's
/// worker, so this screen only creates posts and shows where each one got to.
class SocialPublisherScreen extends ConsumerWidget {
  const SocialPublisherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Publisher',
      subtitle: 'Facebook, Instagram and TikTok posts',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New post'),
        onPressed: () => _compose(context, ref),
      ),
      body: AsyncList<SocialPost>(
        provider: socialPostsProvider,
        onRefresh: (ref) => ref.invalidate(socialPostsProvider),
        emptyIcon: Icons.campaign_outlined,
        emptyMessage: 'No posts yet. Tap New post to write one.',
        errorMessage: 'Could not load the posts.',
        builder: (posts) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            StatGrid(tiles: [
              StatTile(
                label: 'Scheduled',
                value: '${posts.where((p) => p.status == 'Scheduled').length}',
                sub: 'waiting to go out',
              ),
              StatTile(
                label: 'Published',
                value: '${posts.where((p) => p.status == 'Published').length}',
                sub: 'live everywhere',
                accent: AppColors.success,
              ),
              StatTile(
                label: 'Need attention',
                value: '${posts.where((p) => p.status == 'Failed' || p.status == 'PartiallyPublished').length}',
                sub: 'failed somewhere',
                accent: AppColors.error,
              ),
            ]),
            const SizedBox(height: 14),
            ...posts.map((p) => _PostCard(post: p)),
          ],
        ),
      ),
    );
  }

  static Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _Composer(),
      ),
    );
    if (saved == true) ref.invalidate(socialPostsProvider);
  }
}

class _PostCard extends ConsumerStatefulWidget {
  final SocialPost post;
  const _PostCard({required this.post});

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(socialPostsProvider);
      if (mounted) AppSnackBar.success(context, done);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'That did not go through.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final repo = ref.read(socialRepositoryProvider);
    final when = p.scheduledAt != null
        ? (p.status == 'Scheduled' ? 'Scheduled for ${dateTimeLabel(p.scheduledAt!)}' : dateTimeLabel(p.scheduledAt!))
        : (p.createdAt != null ? 'Created ${relativeTime(p.createdAt)}' : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(when, style: AppTextStyles.caption)),
                OwnerStatusChip(status: p.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(p.caption.isEmpty ? '(no caption)' : p.caption,
                maxLines: 4, overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
            if (p.mediaType != 'None')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${p.mediaType} attached', style: AppTextStyles.caption),
              ),
            const Divider(color: AppColors.hairline, height: 20),
            for (final t in p.targets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlatformMark(platform: t.platform, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${t.accountName}${t.isSandbox ? ' · sandbox' : ''}', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
                          if (t.error != null)
                            Text(t.error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                        ],
                      ),
                    ),
                    if (t.permalinkUrl != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Open post',
                        icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.cyan),
                        onPressed: () => openExternal(context, t.permalinkUrl!),
                      ),
                    OwnerStatusChip(status: t.status),
                  ],
                ),
              ),
            if (p.canRetry || p.canCancel || p.editable) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (p.canRetry)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _run(() => repo.retryPost(p.id), 'Retrying the failed destinations.'),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry failed'),
                    ),
                  if (p.canCancel)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _run(() => repo.cancelPost(p.id), 'Post cancelled.'),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Cancel'),
                    ),
                  if (p.editable)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await confirmAction(context,
                                  title: 'Delete this post?',
                                  message: 'It has not been published anywhere, so nothing changes on the networks.',
                                  confirm: 'Delete',
                                  destructive: true);
                              if (ok) await _run(() => repo.deletePost(p.id), 'Post deleted.');
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer();

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _caption = TextEditingController();
  final _mediaUrl = TextEditingController();
  final _linkUrl = TextEditingController();
  final Set<String> _selected = {};
  String _mediaType = 'None';
  DateTime? _scheduledAt;
  bool _saving = false;

  @override
  void dispose() {
    _caption.dispose();
    _mediaUrl.dispose();
    _linkUrl.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
      initialDate: _scheduledAt ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save(List<SocialAccount> accounts, {required bool asDraft}) async {
    setState(() => _saving = true);
    try {
      final link = _linkUrl.text.trim();
      await ref.read(socialRepositoryProvider).createPost(
            caption: _caption.text.trim(),
            mediaType: _mediaType,
            mediaUrl: _mediaUrl.text.trim(),
            linkUrl: link.isEmpty ? null : link,
            scheduledAt: _scheduledAt,
            accountIds: _selected.toList(),
            asDraft: asDraft,
          );
      if (!mounted) return;
      AppSnackBar.success(
          context,
          asDraft
              ? 'Draft saved.'
              : _scheduledAt != null
                  ? 'Scheduled for ${dateTimeLabel(_scheduledAt!)}.'
                  : 'Publishing now — statuses update as each network confirms.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'The post was not saved.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(socialAccountsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: accountsAsync.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(message: 'Could not load your accounts.', onRetry: () => ref.invalidate(socialAccountsProvider)),
          data: (all) {
            final accounts = all.where((a) => a.isConnected).toList();
            final chosen = accounts.where((a) => _selected.contains(a.id)).toList();
            final problems = [
              for (final a in chosen)
                if (socialPostProblem(a.platform, _caption.text, _mediaType, _mediaUrl.text) case final problem?)
                  '${a.platform}: $problem',
            ];
            final scheduleInPast = _scheduledAt != null && _scheduledAt!.isBefore(DateTime.now());
            final canPublish = chosen.isNotEmpty && problems.isEmpty && !scheduleInPast && !_saving;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New post', style: AppTextStyles.title),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  const SocialNotice('No connected account. Connect one (or add a sandbox account) under Social Accounts.')
                else ...[
                  Text('Post to', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in accounts)
                        FilterChip(
                          avatar: Icon(platformStyle(a.platform).icon, size: 16, color: platformStyle(a.platform).color),
                          label: Text('${a.displayName}${a.isSandbox ? ' (sandbox)' : ''}'),
                          selected: _selected.contains(a.id),
                          onSelected: (on) => setState(() => on ? _selected.add(a.id) : _selected.remove(a.id)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                NeonInputField(
                  label: 'Caption',
                  controller: _caption,
                  maxLines: 6,
                  minLines: 3,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text('Media', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<String>(
                  options: const [(value: 'None', label: 'None'), (value: 'Image', label: 'Image'), (value: 'Video', label: 'Video')],
                  selected: _mediaType,
                  onSelected: (v) => setState(() => _mediaType = v ?? 'None'),
                ),
                if (_mediaType != 'None') ...[
                  const SizedBox(height: 10),
                  NeonInputField(
                    label: '${_mediaType == 'Image' ? 'Image' : 'Video'} URL',
                    controller: _mediaUrl,
                    keyboardType: TextInputType.url,
                    helperText: 'A public https link. The networks download it from there.',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 10),
                NeonInputField(
                  label: 'Link (optional)',
                  controller: _linkUrl,
                  keyboardType: TextInputType.url,
                  helperText: 'Facebook shows a link preview; elsewhere it is added to the caption.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _scheduledAt == null ? 'Publish immediately' : 'Scheduled for ${dateTimeLabel(_scheduledAt!)}',
                        style: AppTextStyles.body.copyWith(color: scheduleInPast ? AppColors.error : null),
                      ),
                    ),
                    if (_scheduledAt != null)
                      TextButton(onPressed: () => setState(() => _scheduledAt = null), child: const Text('Now instead')),
                    TextButton.icon(
                      onPressed: _pickSchedule,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(_scheduledAt == null ? 'Schedule' : 'Change'),
                    ),
                  ],
                ),
                for (final p in problems) SocialNotice(p, color: AppColors.error, icon: Icons.error_outline),
                if (scheduleInPast) const SocialNotice('Pick a time in the future.', color: AppColors.error, icon: Icons.error_outline),
                const SizedBox(height: 8),
                NeonButton(
                  label: _scheduledAt == null ? 'Publish now' : 'Schedule',
                  isLoading: _saving,
                  onPressed: canPublish ? () => _save(accounts, asDraft: false) : null,
                ),
                const SizedBox(height: 8),
                GhostButton(
                  label: 'Save as draft',
                  onPressed: _saving || chosen.isEmpty ? null : () => _save(accounts, asDraft: true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
