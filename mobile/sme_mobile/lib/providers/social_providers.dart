import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import '../services/social_repository.dart';
import 'api_service_provider.dart';
import 'owner_providers.dart';

final socialRepositoryProvider =
    Provider<SocialRepository>((ref) => SocialRepository(ref.watch(apiServiceProvider)));

final socialAccountsProvider = FutureProvider.autoDispose<List<SocialAccount>>((ref) async {
  if (ref.watch(ownerTenantIdProvider).isEmpty) return const [];
  return ref.watch(socialRepositoryProvider).accounts();
});

final socialStatusProvider = FutureProvider.autoDispose<SocialServerStatus>(
    (ref) => ref.watch(socialRepositoryProvider).status());

final socialPostsProvider = FutureProvider.autoDispose<List<SocialPost>>((ref) async {
  if (ref.watch(ownerTenantIdProvider).isEmpty) return const [];
  return ref.watch(socialRepositoryProvider).posts();
});

final socialConversationsProvider =
    FutureProvider.autoDispose.family<List<SocialConversation>, bool>((ref, archived) async {
  if (ref.watch(ownerTenantIdProvider).isEmpty) return const [];
  return ref.watch(socialRepositoryProvider).conversations(archived: archived);
});

final marketingAttributionProvider = FutureProvider.autoDispose<AttributionReport>(
    (ref) => ref.watch(socialRepositoryProvider).attribution());

final marketingCampaignsProvider = FutureProvider.autoDispose<CampaignReport>(
    (ref) => ref.watch(socialRepositoryProvider).campaigns());
