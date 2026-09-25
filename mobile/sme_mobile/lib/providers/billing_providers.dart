import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/billing_models.dart';
import '../services/billing_repository.dart';
import '../services/payment_method_store.dart';
import 'api_service_provider.dart';
import 'auth_provider.dart';

/// Overridden in widget tests with a fake.
final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => DioBillingRepository(ref.watch(apiServiceProvider)),
);

final myInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>(
  (ref) => ref.watch(billingRepositoryProvider).myInvoices(),
);

final invoiceProvider = FutureProvider.autoDispose.family<Invoice, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).invoice(id),
);

final receiptProvider = FutureProvider.autoDispose.family<Receipt, String>(
  (ref, invoiceId) => ref.watch(billingRepositoryProvider).receipt(invoiceId),
);

final availableProvidersProvider = FutureProvider.autoDispose<AvailableProviders>(
  (ref) => ref.watch(billingRepositoryProvider).availableProviders(),
);

final mySubscriptionsProvider = FutureProvider.autoDispose<List<Subscription>>(
  (ref) => ref.watch(billingRepositoryProvider).mySubscriptions(),
);

final planOptionsProvider = FutureProvider.autoDispose<List<PlanOption>>(
  (ref) => ref.watch(billingRepositoryProvider).planOptions(),
);

final subscriptionInvoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).subscriptionInvoices(id),
);

final myClaimsProvider = FutureProvider.autoDispose<List<InsuranceClaim>>(
  (ref) => ref.watch(billingRepositoryProvider).myClaims(),
);

/// Saved payment methods live per signed-in user; overridden in tests.
final paymentMethodStoreProvider = Provider<PaymentMethodStore>((ref) {
  final userId = ref.watch(authProvider).user?.id ?? 'anonymous';
  return PaymentMethodStore(userId: userId);
});

final savedPaymentMethodsProvider = FutureProvider.autoDispose<List<SavedPaymentMethod>>(
  (ref) => ref.watch(paymentMethodStoreProvider).load(),
);
