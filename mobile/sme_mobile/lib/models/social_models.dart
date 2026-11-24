/// Marketing & Social — the mobile side of `api/social/*` and
/// `api/marketing/*` (backend `Controllers/Marketing`, web
/// `features/social/socialApi.ts`). Field names follow the API's camelCase.
library;

String _s(Object? v) => v?.toString() ?? '';
String? _sn(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _dn(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(growable: false);

/// The web app's public origin. Booking links point at its `/embed/book`
/// page and OAuth sends the browser back to its `/social` page, so the phone
/// needs to know it even though it never renders it.
const String webAppOrigin = String.fromEnvironment(
  'WEB_APP_URL',
  defaultValue: 'https://se-3090-se-002.vercel.app',
);

/// Same shape as the web's `buildBookingLink`: the booking widget reads these
/// UTM tags (and `conv`, the inbox thread) and the booking is attributed to
/// that channel — and, with `conv`, tied back to the chat it came from.
String buildBookingLink({
  required String tenantId,
  required String source,
  required String medium,
  String? campaign,
  String? conversationId,
  String origin = webAppOrigin,
}) {
  final params = <String, String>{
    'utm_source': source,
    'utm_medium': medium,
    if (campaign != null && campaign.trim().isNotEmpty) 'utm_campaign': campaign.trim(),
    if (conversationId != null && conversationId.isNotEmpty) 'conv': conversationId,
  };
  final query = params.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '$origin/embed/book/${Uri.encodeComponent(tenantId)}?$query';
}

class SocialAccount {
  final String id;
  final String platform;
  final String displayName;
  final String? handle;
  final String status;
  final String? lastError;
  final bool isSandbox;
  final bool canMessage;
  final DateTime? tokenExpiresAt;

  const SocialAccount({
    required this.id,
    required this.platform,
    required this.displayName,
    this.handle,
    required this.status,
    this.lastError,
    this.isSandbox = false,
    this.canMessage = false,
    this.tokenExpiresAt,
  });

  bool get isConnected => status == 'Connected';
  bool get needsReconnect => status == 'NeedsReconnect';
  bool get isDisconnected => status == 'Disconnected';

  factory SocialAccount.fromJson(Map<String, dynamic> j) => SocialAccount(
        id: _s(j['id']),
        platform: _s(j['platform']),
        displayName: _s(j['displayName']),
        handle: _sn(j['handle']),
        status: _s(j['status']),
        lastError: _sn(j['lastError']),
        isSandbox: j['isSandbox'] == true,
        canMessage: j['canMessage'] == true,
        tokenExpiresAt: _t(j['tokenExpiresAt']),
      );
}

class SocialServerStatus {
  final bool metaConfigured;
  final bool tikTokConfigured;
  const SocialServerStatus({required this.metaConfigured, required this.tikTokConfigured});

  factory SocialServerStatus.fromJson(Map<String, dynamic> j) => SocialServerStatus(
        metaConfigured: (j['meta'] as Map?)?['configured'] == true,
        tikTokConfigured: (j['tiktok'] as Map?)?['configured'] == true,
      );
}

class PostTarget {
  final String id;
  final String platform;
  final String accountName;
  final bool isSandbox;
  final String status;
  final String? permalinkUrl;
  final String? error;
  final int attempts;

  const PostTarget({
    required this.id,
    required this.platform,
    required this.accountName,
    required this.isSandbox,
    required this.status,
    this.permalinkUrl,
    this.error,
    this.attempts = 0,
  });

  factory PostTarget.fromJson(Map<String, dynamic> j) => PostTarget(
        id: _s(j['id']),
        platform: _s(j['platform']),
        accountName: _s(j['accountName']),
        isSandbox: j['isSandbox'] == true,
        status: _s(j['status']),
        permalinkUrl: _sn(j['permalinkUrl']),
        error: _sn(j['error']),
        attempts: _i(j['attempts']),
      );
}

class SocialPost {
  final String id;
  final String caption;
  final String mediaType;
  final String? mediaUrl;
  final String? linkUrl;
  final DateTime? scheduledAt;
  final String status;
  final DateTime? createdAt;
  final bool editable;
  final List<PostTarget> targets;

  const SocialPost({
    required this.id,
    required this.caption,
    required this.mediaType,
    this.mediaUrl,
    this.linkUrl,
    this.scheduledAt,
    required this.status,
    this.createdAt,
    this.editable = false,
    this.targets = const [],
  });

  bool get canCancel => status == 'Scheduled' || status == 'Draft';
  bool get canRetry => targets.any((t) => t.status == 'Failed');

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
        id: _s(j['id']),
        caption: _s(j['caption']),
        mediaType: _s(j['mediaType']).isEmpty ? 'None' : _s(j['mediaType']),
        mediaUrl: _sn(j['mediaUrl']),
        linkUrl: _sn(j['linkUrl']),
        scheduledAt: _t(j['scheduledAt']),
        status: _s(j['status']),
        createdAt: _t(j['createdAt']),
        editable: j['editable'] == true,
        targets: _list(j['targets']).map(PostTarget.fromJson).toList(growable: false),
      );
}

class SocialConversation {
  final String id;
  final String platform;
  final String accountName;
  final bool isSandbox;
  final String? participantName;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final bool isArchived;
  final String? linkedBookingId;
  final bool canReply;
  final DateTime? replyWindowEndsAt;

  const SocialConversation({
    required this.id,
    required this.platform,
    required this.accountName,
    this.isSandbox = false,
    this.participantName,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isArchived = false,
    this.linkedBookingId,
    this.canReply = false,
    this.replyWindowEndsAt,
  });

  String get displayName => participantName ?? 'Customer';

  factory SocialConversation.fromJson(Map<String, dynamic> j) => SocialConversation(
        id: _s(j['id']),
        platform: _s(j['platform']),
        accountName: _s(j['accountName']),
        isSandbox: j['isSandbox'] == true,
        participantName: _sn(j['participantName']),
        lastMessagePreview: _sn(j['lastMessagePreview']),
        lastMessageAt: _t(j['lastMessageAt']),
        unreadCount: _i(j['unreadCount']),
        isArchived: j['isArchived'] == true,
        linkedBookingId: _sn(j['linkedBookingId']),
        canReply: j['canReply'] == true,
        replyWindowEndsAt: _t(j['replyWindowEndsAt']),
      );
}

class InboxMessage {
  final String id;
  final bool inbound;
  final String text;
  final String? attachmentUrl;
  final DateTime? sentAt;
  final String? error;

  const InboxMessage({
    required this.id,
    required this.inbound,
    required this.text,
    this.attachmentUrl,
    this.sentAt,
    this.error,
  });

  factory InboxMessage.fromJson(Map<String, dynamic> j) => InboxMessage(
        id: _s(j['id']),
        inbound: _s(j['direction']) == 'Inbound',
        text: _s(j['text']),
        attachmentUrl: _sn(j['attachmentUrl']),
        sentAt: _t(j['sentAt']),
        error: _sn(j['error']),
      );
}

class ChannelRow {
  final String channel;
  final int bookings;
  final int converted;
  final int lost;
  final double revenue;
  final double revenueShare;

  const ChannelRow({
    required this.channel,
    required this.bookings,
    required this.converted,
    required this.lost,
    required this.revenue,
    required this.revenueShare,
  });

  factory ChannelRow.fromJson(Map<String, dynamic> j) => ChannelRow(
        channel: _s(j['channel']),
        bookings: _i(j['bookings']),
        converted: _i(j['converted']),
        lost: _i(j['lost']),
        revenue: _d(j['revenue']),
        revenueShare: _d(j['revenueShare']),
      );
}

class AttributionReport {
  final int totalBookings;
  final double totalRevenue;
  final int socialBookings;
  final double socialRevenue;
  final List<ChannelRow> channels;

  const AttributionReport({
    required this.totalBookings,
    required this.totalRevenue,
    required this.socialBookings,
    required this.socialRevenue,
    required this.channels,
  });

  factory AttributionReport.fromJson(Map<String, dynamic> j) => AttributionReport(
        totalBookings: _i(j['totalBookings']),
        totalRevenue: _d(j['totalRevenue']),
        socialBookings: _i(j['socialBookings']),
        socialRevenue: _d(j['socialRevenue']),
        channels: _list(j['channels']).map(ChannelRow.fromJson).toList(growable: false),
      );
}

class CampaignRow {
  final String platform;
  final String campaign;
  final double? spend;
  final int? clicks;
  final double? ctr;
  final int bookings;
  final double revenue;
  final double? costPerBooking;
  final double? roas;

  const CampaignRow({
    required this.platform,
    required this.campaign,
    this.spend,
    this.clicks,
    this.ctr,
    required this.bookings,
    required this.revenue,
    this.costPerBooking,
    this.roas,
  });

  factory CampaignRow.fromJson(Map<String, dynamic> j) => CampaignRow(
        platform: _s(j['platform']),
        campaign: _s(j['campaign']),
        spend: _dn(j['spend']),
        clicks: j['clicks'] == null ? null : _i(j['clicks']),
        ctr: _dn(j['ctr']),
        bookings: _i(j['bookings']),
        revenue: _d(j['revenue']),
        costPerBooking: _dn(j['costPerBooking']),
        roas: _dn(j['roas']),
      );
}

class CampaignReport {
  final double totalSpend;
  final int attributedBookings;
  final double attributedRevenue;
  final double? blendedRoas;
  final List<CampaignRow> campaigns;
  final List<String> warnings;

  const CampaignReport({
    required this.totalSpend,
    required this.attributedBookings,
    required this.attributedRevenue,
    this.blendedRoas,
    required this.campaigns,
    required this.warnings,
  });

  factory CampaignReport.fromJson(Map<String, dynamic> j) => CampaignReport(
        totalSpend: _d(j['totalSpend']),
        attributedBookings: _i(j['attributedBookings']),
        attributedRevenue: _d(j['attributedRevenue']),
        blendedRoas: _dn(j['blendedRoas']),
        campaigns: _list(j['campaigns']).map(CampaignRow.fromJson).toList(growable: false),
        warnings: (j['warnings'] as List<dynamic>? ?? const []).map((w) => w.toString()).toList(growable: false),
      );
}

/// The checks that would make a platform refuse the post outright, run before
/// the request so the composer can say why instead of the server. The server
/// re-checks everything (`SocialPostRules.Validate`).
String? socialPostProblem(String platform, String caption, String mediaType, String? mediaUrl) {
  final hasMedia = mediaType != 'None';
  if (hasMedia) {
    final uri = Uri.tryParse(mediaUrl?.trim() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.host == 'localhost') {
      return 'The media link must be a public https URL.';
    }
  }
  switch (platform) {
    case 'Instagram':
      if (!hasMedia) return 'Instagram needs an image or a video.';
      if (caption.length > 2200) return 'Instagram captions are limited to 2,200 characters.';
      if (RegExp(r'#\w').allMatches(caption).length > 30) return 'Instagram allows at most 30 hashtags.';
    case 'TikTok':
      if (!hasMedia) return 'TikTok needs a video or a photo.';
      if (caption.length > 2200) return 'TikTok captions are limited to 2,200 characters.';
    default:
      if (!hasMedia && caption.trim().isEmpty) return 'Add text or media.';
  }
  return null;
}
