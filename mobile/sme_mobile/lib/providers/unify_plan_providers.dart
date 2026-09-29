import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/unify_plan_models.dart';
import '../services/unify_plan_repository.dart';
import 'api_service_provider.dart';

/// Overridden in widget tests with a fake, the same way
/// `billingRepositoryProvider` is.
final unifyPlanRepositoryProvider = Provider<UnifyPlanRepository>(
  (ref) => DioUnifyPlanRepository(ref.watch(apiServiceProvider)),
);

/// The currency the plan screen is showing. Lives here rather than in the
/// screen so switching it refetches the catalogue on its own.
final planCurrencyProvider = StateProvider<String?>((ref) => null);

final unifySubscriptionProvider = FutureProvider.autoDispose<UnifySubscription>(
  (ref) => ref.watch(unifyPlanRepositoryProvider).current(),
);

final pricingCatalogProvider = FutureProvider.autoDispose<PricingCatalog>(
  (ref) => ref.watch(unifyPlanRepositoryProvider).catalog(currency: ref.watch(planCurrencyProvider)),
);

final unifyInvoicesProvider = FutureProvider.autoDispose<List<UnifyInvoice>>(
  (ref) => ref.watch(unifyPlanRepositoryProvider).invoices(),
);
