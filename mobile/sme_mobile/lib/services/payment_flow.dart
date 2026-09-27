import '../models/billing_models.dart';

/// The payment flow's decisions, separate from its widgets so they can be
/// unit-tested: which gateway a method goes through, and what a typed
/// amount means. Mirrors frontend/src/features/billing/paymentFlow.ts.
enum PayMethod { card, qr, cash }

extension PayMethodX on PayMethod {
  String get apiName => switch (this) { PayMethod.card => 'Card', PayMethod.qr => 'QR', PayMethod.cash => 'Cash' };
  String get title => switch (this) { PayMethod.card => 'Card', PayMethod.qr => 'QR / wallet', PayMethod.cash => 'Cash' };

  static PayMethod fromSaved(String type) => switch (type) {
        'QR' || 'PayPal' => PayMethod.qr,
        'Cash' => PayMethod.cash,
        _ => PayMethod.card,
      };
}

/// Cash never touches a gateway. Card goes to Stripe (its hosted page) when
/// the business has it, QR to PayPal when set up; otherwise the sandbox.
String? providerFor(PayMethod method, AvailableProviders? available) {
  if (method == PayMethod.cash) return null;
  final providers = available?.providers ?? const <ProviderOption>[];
  if (method == PayMethod.card) {
    if (available?.has('Stripe') ?? false) return 'Stripe';
    return providers.isNotEmpty ? providers.first.provider : 'Manual';
  }
  return (available?.has('PayPal') ?? false) ? 'PayPal' : 'Manual';
}

/// Null when the typed amount is fine (blank means "the full balance").
String? validatePayAmount(String raw, double balance) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value <= 0) return 'Enter an amount greater than 0.';
  if ((value * 100).round() > (balance * 100).round()) return 'You can pay at most ${balance.toStringAsFixed(2)}.';
  return null;
}

double amountToPay(String raw, double balance) => raw.trim().isEmpty ? balance : double.parse(raw.trim());

/// What the customer is told after the provider answers.
String resultMessage(String status) => switch (status) {
      'Succeeded' => 'Payment received - your receipt is ready.',
      'Failed' => 'The payment did not go through. No money was taken.',
      _ => 'The payment is still processing. It will update once the provider confirms it.',
    };
