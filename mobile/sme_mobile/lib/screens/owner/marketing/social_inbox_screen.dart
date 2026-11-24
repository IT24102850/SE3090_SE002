import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/social_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/social_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/route_transitions.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'social_widgets.dart';

/// Messenger and Instagram DMs from every connected account — the mobile twin
/// of the web Inbox. Messages arrive by webhook, so the list polls.
class SocialInboxScreen extends ConsumerStatefulWidget {
  const SocialInboxScreen({super.key});

  @override
  ConsumerState<SocialInboxScreen> createState() => _SocialInboxScreenState();
}

class _SocialInboxScreenState extends ConsumerState<SocialInboxScreen> {
  bool _archived = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) ref.invalidate(socialConversationsProvider(_archived));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = socialConversationsProvider(_archived);
    return OwnerScaffold(
      title: 'Inbox',
      subtitle: 'Messenger and Instagram DMs',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: FilterChips<bool>(
              options: const [(value: false, label: 'Open'), (value: true, label: 'Archived')],
              selected: _archived,
              onSelected: (v) => setState(() => _archived = v ?? false),
            ),
          ),
          Expanded(
            child: AsyncList<SocialConversation>(
              provider: provider,
              onRefresh: (ref) => ref.invalidate(provider),
              emptyIcon: Icons.forum_outlined,
              emptyMessage: _archived
                  ? 'No archived conversations.'
                  : 'No conversations yet. Connect a Facebook Page or Instagram account under Social Accounts.',
              errorMessage: 'Could not load the inbox.',
              builder: (threads) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: threads.length,
                itemBuilder: (context, i) => _ThreadTile(
                  thread: threads[i],
                  onTap: () async {
                    await Navigator.of(context).push(slideFadeRoute<void>(SocialThreadScreen(conversationId: threads[i].id)));
                    ref.invalidate(provider);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final SocialConversation thread;
  final VoidCallback onTap;
  const _ThreadTile({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = thread.unreadCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            PlatformMark(platform: thread.platform),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(thread.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      Text(relativeTime(thread.lastMessageAt), style: AppTextStyles.caption),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(thread.lastMessagePreview ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(color: unread ? AppColors.textBody : AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text('${thread.accountName}${thread.isSandbox ? ' · sandbox' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
                      ),
                      if (thread.linkedBookingId != null) ...[
                        const SizedBox(width: 8),
                        const OwnerStatusChip(status: 'Booked'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(999)),
                child: Text('${thread.unreadCount}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One conversation: the messages, a reply box, and a tracked booking link
/// that ties the booking that follows back to this chat.
class SocialThreadScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const SocialThreadScreen({super.key, required this.conversationId});

  @override
  ConsumerState<SocialThreadScreen> createState() => _SocialThreadScreenState();
}

class _SocialThreadScreenState extends ConsumerState<SocialThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  SocialConversation? _conversation;
  List<InboxMessage> _messages = const [];
  Object? _error;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final data = await ref.read(socialRepositoryProvider).messages(widget.conversationId);
      if (!mounted) return;
      final grew = data.messages.length != _messages.length;
      setState(() {
        _conversation = data.conversation;
        _messages = data.messages;
        _error = null;
      });
      if (grew) _scrollToEnd();
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() => _error = e);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final message = await ref.read(socialRepositoryProvider).reply(widget.conversationId, body);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, message];
        _text.clear();
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'The message was not sent.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _insertBookingLink(SocialConversation c) {
    final tenantId = ref.read(authProvider).user?.tenantId ?? '';
    if (tenantId.isEmpty) return;
    final link = buildBookingLink(
      tenantId: tenantId,
      source: c.platform.toLowerCase(),
      medium: 'dm',
      campaign: 'inbox',
      conversationId: c.id,
    );
    final current = _text.text.trimRight();
    _text.text = current.isEmpty
        ? 'Thanks for your message! You can pick a time and book here:\n$link'
        : '$current\n$link';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _archive(SocialConversation c) async {
    try {
      await ref.read(socialRepositoryProvider).archive(c.id, !c.isArchived);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppSnackBar.error(context, serverMessage(e, 'Could not update the conversation.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _conversation;
    return OwnerScaffold(
      title: c?.displayName ?? 'Conversation',
      subtitle: c == null ? null : 'via ${c.accountName}${c.isSandbox ? ' (sandbox)' : ''}',
      preferBackButton: true,
      actions: [
        if (c != null)
          IconButton(
            tooltip: c.isArchived ? 'Unarchive' : 'Archive',
            icon: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            onPressed: () => _archive(c),
          ),
      ],
      body: c == null
          ? (_error != null
              ? ErrorState(message: serverMessage(_error!, 'Could not open the conversation.'), onRetry: _load)
              : const AppLoader())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(message: _messages[i]),
                  ),
                ),
                _ReplyBar(
                  conversation: c,
                  controller: _text,
                  sending: _sending,
                  onSend: _send,
                  onBookingLink: () => _insertBookingLink(c),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final InboxMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final inbound = message.inbound;
    return Align(
      alignment: inbound ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: inbound ? AppColors.glassFill : AppColors.cyan.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: inbound ? AppColors.glassBorder : AppColors.cyan.withValues(alpha: .45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.text.isNotEmpty) SelectableText(message.text, style: AppTextStyles.body),
            if (message.attachmentUrl != null)
              GestureDetector(
                onTap: () => openExternal(context, message.attachmentUrl!),
                child: Text('Attachment', style: AppTextStyles.caption.copyWith(color: AppColors.cyan, decoration: TextDecoration.underline)),
              ),
            if (message.error != null)
              Text(message.error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
            if (message.sentAt != null) ...[
              const SizedBox(height: 3),
              Text(dateTimeLabel(message.sentAt!), style: AppTextStyles.caption.copyWith(fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  final SocialConversation conversation;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onBookingLink;

  const _ReplyBar({
    required this.conversation,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onBookingLink,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.overlaySurface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!c.canReply)
            SocialNotice('${c.platform} only lets businesses reply within 24 hours of the customer’s last message. '
                'Reply from the ${c.platform} app, or wait for them to write again.')
          else if (!c.isSandbox && c.replyWindowEndsAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Reply window closes ${relativeTime(c.replyWindowEndsAt)}', style: AppTextStyles.caption),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Insert booking link',
                icon: const Icon(Icons.event_available_outlined, color: AppColors.cyan),
                onPressed: c.canReply ? onBookingLink : null,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: c.canReply && !sending,
                  minLines: 1,
                  maxLines: 5,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Write a reply…',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Send',
                icon: sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: AppColors.cyan),
                onPressed: c.canReply && !sending ? onSend : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
