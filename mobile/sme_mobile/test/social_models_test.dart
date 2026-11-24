import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/social_models.dart';

void main() {
  group('buildBookingLink', () {
    test('matches the web link the booking widget attributes', () {
      expect(
        buildBookingLink(
          origin: 'https://app.example',
          tenantId: 't 1',
          source: 'instagram',
          medium: 'dm',
          campaign: ' inbox ',
          conversationId: 'c1',
        ),
        'https://app.example/embed/book/t%201?utm_source=instagram&utm_medium=dm&utm_campaign=inbox&conv=c1',
      );
    });

    test('leaves out an empty campaign and conversation', () {
      expect(
        buildBookingLink(origin: 'https://app.example', tenantId: 't', source: 'facebook', medium: 'social', campaign: '  '),
        'https://app.example/embed/book/t?utm_source=facebook&utm_medium=social',
      );
    });
  });

  group('socialPostProblem', () {
    test('Instagram and TikTok need media, Facebook needs text or media', () {
      expect(socialPostProblem('Instagram', 'Hi', 'None', null), contains('image or a video'));
      expect(socialPostProblem('TikTok', 'Hi', 'None', null), contains('video or a photo'));
      expect(socialPostProblem('Facebook', 'Hi', 'None', null), isNull);
      expect(socialPostProblem('Facebook', '  ', 'None', null), contains('text or media'));
    });

    test('media must be a public https link', () {
      expect(socialPostProblem('Instagram', '', 'Image', 'http://cdn.example/x.jpg'), contains('https'));
      expect(socialPostProblem('Instagram', '', 'Image', 'https://localhost/x.jpg'), contains('https'));
      expect(socialPostProblem('Instagram', '', 'Image', 'https://cdn.example/x.jpg'), isNull);
    });

    test('caption and hashtag limits', () {
      expect(socialPostProblem('Instagram', 'x' * 2201, 'Image', 'https://cdn.example/x.jpg'), contains('2,200'));
      expect(socialPostProblem('Facebook', 'x' * 2201, 'None', null), isNull);
      final tags = List.generate(31, (i) => '#t$i').join(' ');
      expect(socialPostProblem('Instagram', tags, 'Image', 'https://cdn.example/x.jpg'), contains('30 hashtags'));
    });
  });

  group('parsing', () {
    test('a post with its destinations', () {
      final post = SocialPost.fromJson({
        'id': 'p1',
        'caption': 'Whale season',
        'mediaType': 'Image',
        'mediaUrl': 'https://cdn.example/w.jpg',
        'status': 'PartiallyPublished',
        'scheduledAt': '2026-12-01T03:30:00Z',
        'editable': false,
        'targets': [
          {'id': 't1', 'platform': 'Instagram', 'accountName': 'Mirissa', 'status': 'Published', 'permalinkUrl': 'https://instagram.com/p/x'},
          {'id': 't2', 'platform': 'Facebook', 'accountName': 'Mirissa Page', 'status': 'Failed', 'error': 'Token expired', 'attempts': 5},
        ],
      });
      expect(post.targets, hasLength(2));
      expect(post.canRetry, isTrue);
      expect(post.canCancel, isFalse);
      expect(post.scheduledAt!.isUtc, isFalse);
      expect(post.targets[1].attempts, 5);
    });

    test('a conversation and its reply window', () {
      final c = SocialConversation.fromJson({
        'id': 'c1',
        'platform': 'Facebook',
        'accountName': 'Page',
        'participantName': null,
        'unreadCount': 2,
        'canReply': false,
        'linkedBookingId': 'b1',
      });
      expect(c.displayName, 'Customer');
      expect(c.canReply, isFalse);
      expect(c.linkedBookingId, 'b1');
    });

    test('campaign report keeps nulls as unknown, not zero', () {
      final r = CampaignReport.fromJson({
        'totalSpend': 120.5,
        'attributedBookings': 3,
        'attributedRevenue': 300,
        'blendedRoas': null,
        'campaigns': [
          {'platform': 'Facebook', 'campaign': 'Summer', 'spend': null, 'bookings': 3, 'revenue': 300, 'roas': null},
        ],
        'warnings': ['No ad account is connected.'],
      });
      expect(r.blendedRoas, isNull);
      expect(r.campaigns.single.spend, isNull);
      expect(r.campaigns.single.revenue, 300);
      expect(r.warnings.single, contains('ad account'));
    });
  });
}
