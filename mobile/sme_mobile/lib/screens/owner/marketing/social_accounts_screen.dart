import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/social_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'social_widgets.dart';

/// Connected Facebook Pages, Instagram and TikTok accounts, and the tracked
/// booking links to put in their bios — the mobile twin of the web Social
/// Accounts page. Staff can read it; Admins and Managers change it.
class SocialAccountsScreen extends ConsumerStatefulWidget {
  const SocialAccountsScreen({super.key});

  @override
  ConsumerState<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends ConsumerState<SocialAccountsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(socialAccountsProvider);
      if (mounted) AppSnackBar.success(context, done);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'That did not go through.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// OAuth runs in the browser: the provider's consent page, then back to the
  /// web app's Social Accounts page. Pull to refresh here afterwards.
  Future<void> _connect(String provider) async {
    setState(() => _busy = true);
    try {
      final url = await ref.read(socialRepositoryProvider).connectUrl(provider);
      if (!mounted) return;
      if (url.isEmpty) {
        AppSnackBar.error(context, 'The server did not return a sign-in link.');
        return;
      }
      await openExternal(context, url);
      if (mounted) AppSnackBar.info(context, 'Finish in the browser, then pull down here to refresh.');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'Could not start connecting.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSandbox() async {
    final platform = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
              child: Text('Sandbox accounts behave like real ones but never call the network. '
                  'Use them to try the publisher and inbox before your app is approved.',
                  style: AppTextStyles.caption),
            ),
            for (final p in const ['Facebook', 'Instagram', 'TikTok'])
              ListTile(
                leading: PlatformMark(platform: p, size: 30),
                title: Text('Sandbox $p', style: AppTextStyles.body),
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (platform == null) return;
    await _run(() => ref.read(socialRepositoryProvider).addSandbox(platform), 'Sandbox $platform account added.');
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).user?.role ?? '';
    final tenantId = ref.watch(authProvider).user?.tenantId ?? '';
    final canManage = role == 'Admin' || role == 'Manager';
    final accountsAsync = ref.watch(socialAccountsProvider);
    final status = ref.watch(socialStatusProvider).valueOrNull;

    Future<void> refresh() async {
      ref.invalidate(socialAccountsProvider);
      ref.invalidate(socialStatusProvider);
    }

    return OwnerScaffold(
      title: 'Social Accounts',
      subtitle: 'Facebook, Instagram and TikTok',
      body: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (canManage) ...[
              const SectionHeader('Connect'),
              NeonButton(
                label: 'Continue with Facebook',
                icon: Icons.facebook,
                onPressed: _busy || status?.metaConfigured != true ? null : () => _connect('meta'),
              ),
              const SizedBox(height: 6),
              Text('Adds every Facebook Page you manage and the Instagram business account linked to each.',
                  style: AppTextStyles.caption),
              const SizedBox(height: 12),
              GhostButton(
                label: 'Continue with TikTok',
                icon: Icons.music_note_outlined,
                onPressed: _busy || status?.tikTokConfigured != true ? null : () => _connect('tiktok'),
              ),
              if (status != null && (!status.metaConfigured || !status.tikTokConfigured)) ...[
                const SizedBox(height: 10),
                SocialNotice(
                  '${[if (!status.metaConfigured) 'Facebook/Instagram', if (!status.tikTokConfigured) 'TikTok'].join(' and ')} '
                  'is not set up on the server yet. Sandbox accounts work in the meantime.',
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addSandbox,
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Add a sandbox account'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SectionHeader('Accounts'),
            accountsAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(30), child: AppLoader()),
              error: (e, _) => ErrorState(message: serverMessage(e, 'Could not load the accounts.'), onRetry: refresh),
              data: (accounts) {
                final visible = accounts.where((a) => !a.isDisconnected).toList();
                if (visible.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(icon: Icons.link_off, message: 'No social account is connected yet.'),
                  );
                }
                return Column(
                  children: [
                    for (final a in visible)
                      _AccountCard(
                        account: a,
                        canManage: canManage,
                        busy: _busy,
                        onRefresh: () => _run(() => ref.read(socialRepositoryProvider).refreshAccount(a.id), 'Account refreshed.'),
                        onReconnect: () => _connect(a.platform == 'TikTok' ? 'tiktok' : 'meta'),
                        onDisconnect: () async {
                          final ok = await confirmAction(context,
                              title: 'Disconnect ${a.displayName}?',
                              message: 'Its scheduled posts are cancelled and its stored tokens are deleted. '
                                  'Past posts and conversations stay.',
                              confirm: 'Disconnect',
                              destructive: true);
                          if (ok) await _run(() => ref.read(socialRepositoryProvider).disconnect(a.id), 'Disconnected.');
                        },
                      ),
                  ],
                );
              },
            ),
            if (tenantId.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionHeader('Tracked booking links'),
              Text('Put these in your bios and Page button. Bookings made through them are credited to that network.',
                  style: AppTextStyles.caption),
              const SizedBox(height: 10),
              for (final p in const [
                (platform: 'Instagram', where: 'Instagram bio', campaign: 'bio'),
                (platform: 'Facebook', where: 'Facebook Page "Book now" button', campaign: 'page_button'),
                (platform: 'TikTok', where: 'TikTok bio', campaign: 'bio'),
              ])
                _LinkTile(
                  platform: p.platform,
                  where: p.where,
                  link: buildBookingLink(
                    tenantId: tenantId,
                    source: p.platform.toLowerCase(),
                    medium: 'social',
                    campaign: p.campaign,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final SocialAccount account;
  final bool canManage;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  const _AccountCard({
    required this.account,
    required this.canManage,
    required this.busy,
    required this.onRefresh,
    required this.onReconnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final a = account;
    final statusLabel = a.needsReconnect ? 'Reconnect' : (a.isSandbox ? 'Sandbox' : a.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderColor: a.needsReconnect ? AppColors.warning.withValues(alpha: .6) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlatformMark(platform: a.platform),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.displayName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text([a.platform, if (a.handle != null) '@${a.handle}'].join(' · '), style: AppTextStyles.caption),
                    ],
                  ),
                ),
                OwnerStatusChip(status: statusLabel),
              ],
            ),
            if (a.lastError != null && !a.isConnected) ...[
              const SizedBox(height: 8),
              Text(a.lastError!, style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
            ],
            if (canManage) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  if (a.needsReconnect && !a.isSandbox)
                    TextButton.icon(onPressed: busy ? null : onReconnect, icon: const Icon(Icons.link, size: 18), label: const Text('Reconnect')),
                  if (!a.isSandbox && a.isConnected)
                    TextButton.icon(onPressed: busy ? null : onRefresh, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    onPressed: busy ? null : onDisconnect,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Disconnect'),
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

class _LinkTile extends StatelessWidget {
  final String platform;
  final String where;
  final String link;
  const _LinkTile({required this.platform, required this.where, required this.link});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            PlatformMark(platform: platform, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(where, style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
                  Text(link, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.cyan),
              onPressed: () => copyToClipboard(context, link, 'Link copied.'),
            ),
          ],
        ),
      ),
    );
  }
}
