import 'package:dio/dio.dart';

import '../models/social_models.dart';

/// HTTP for the Marketing & Social screens. The tenant always comes from the
/// token, exactly as on the web.
class SocialRepository {
  final Dio _dio;
  const SocialRepository(this._dio);

  static List<Map<String, dynamic>> _rows(Object? data) {
    final list = data is Map<String, dynamic> ? data['items'] : data;
    return (list as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(growable: false);
  }

  static Map<String, dynamic> _map(Object? data) => (data as Map<String, dynamic>?) ?? const {};

  // ── Accounts ──────────────────────────────────────────────────────────

  Future<SocialServerStatus> status() async =>
      SocialServerStatus.fromJson(_map((await _dio.get('/social/status')).data));

  Future<List<SocialAccount>> accounts() async =>
      _rows((await _dio.get('/social/accounts')).data).map(SocialAccount.fromJson).toList(growable: false);

  /// The provider's consent page. The OAuth callback returns the browser to
  /// the web app's `/social` page, which is why [webAppOrigin] is sent.
  Future<String> connectUrl(String provider) async {
    final response = await _dio.post('/social/accounts/connect/$provider', data: {'returnOrigin': webAppOrigin});
    return _map(response.data)['url']?.toString() ?? '';
  }

  Future<void> addSandbox(String platform) =>
      _dio.post('/social/accounts/sandbox', data: {'platform': platform});

  Future<void> refreshAccount(String id) => _dio.post('/social/accounts/$id/refresh');

  Future<void> disconnect(String id) => _dio.delete('/social/accounts/$id');

  // ── Posts ─────────────────────────────────────────────────────────────

  Future<List<SocialPost>> posts() async {
    final response = await _dio.get('/social/posts', queryParameters: {'pageSize': 50});
    return _rows(response.data).map(SocialPost.fromJson).toList(growable: false);
  }

  Future<void> createPost({
    required String caption,
    required String mediaType,
    String? mediaUrl,
    String? linkUrl,
    DateTime? scheduledAt,
    required List<String> accountIds,
    bool asDraft = false,
  }) =>
      _dio.post('/social/posts', data: {
        'caption': caption,
        'mediaType': mediaType,
        'mediaUrl': mediaType == 'None' ? null : mediaUrl,
        'linkUrl': linkUrl,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'accountIds': accountIds,
        'asDraft': asDraft,
      });

  Future<void> cancelPost(String id) => _dio.post('/social/posts/$id/cancel');
  Future<void> retryPost(String id) => _dio.post('/social/posts/$id/retry');
  Future<void> deletePost(String id) => _dio.delete('/social/posts/$id');

  // ── Inbox ─────────────────────────────────────────────────────────────

  Future<List<SocialConversation>> conversations({bool archived = false}) async {
    final response = await _dio.get('/social/inbox/conversations', queryParameters: {'archived': archived});
    return _rows(response.data).map(SocialConversation.fromJson).toList(growable: false);
  }

  /// Opening a thread marks it read on the server.
  Future<({SocialConversation conversation, List<InboxMessage> messages})> messages(String id) async {
    final data = _map((await _dio.get('/social/inbox/conversations/$id/messages')).data);
    return (
      conversation: SocialConversation.fromJson(_map(data['conversation'])),
      messages: _rows(data['messages']).map(InboxMessage.fromJson).toList(growable: false),
    );
  }

  Future<InboxMessage> reply(String id, String text) async {
    final response = await _dio.post('/social/inbox/conversations/$id/reply', data: {'text': text});
    return InboxMessage.fromJson(_map(response.data));
  }

  Future<void> archive(String id, bool archived) =>
      _dio.post('/social/inbox/conversations/$id/archive', data: {'archived': archived});

  // ── Ads & attribution ────────────────────────────────────────────────

  Future<AttributionReport> attribution() async =>
      AttributionReport.fromJson(_map((await _dio.get('/marketing/attribution')).data));

  Future<CampaignReport> campaigns() async =>
      CampaignReport.fromJson(_map((await _dio.get('/marketing/campaigns')).data));
}
