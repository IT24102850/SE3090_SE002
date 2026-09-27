import type { AvailableProviders, CheckoutResponse } from './billingApi';

/* The payment flow's state machine, separate from its UI so the steps can
 * be tested: choose method -> (start checkout) -> provider step -> result. */

export type PayMethod = 'Card' | 'QR' | 'Cash';

export type PaymentStep =
  | { kind: 'choose' }
  | { kind: 'starting' }
  | { kind: 'sandbox'; session: CheckoutResponse }
  | { kind: 'stripe'; session: CheckoutResponse }
  | { kind: 'paypal'; session: CheckoutResponse }
  | { kind: 'cash' }
  | { kind: 'confirming'; session: CheckoutResponse }
  | { kind: 'done'; status: 'Succeeded' | 'Failed' | 'Pending'; message: string }
  | { kind: 'error'; message: string };

/** Which provider a method goes through. Cash never touches a gateway -
 *  it is paid at the counter and recorded by staff. */
export function providerFor(method: PayMethod, available: AvailableProviders | null): 'Stripe' | 'PayPal' | 'Manual' | null {
  if (method === 'Cash') return null;
  const providers = available?.providers ?? [];
  if (method === 'Card') return providers.find((p) => p.provider === 'Stripe')?.provider ?? providers[0]?.provider ?? 'Manual';
  // QR payments (LankaQR and similar) settle through the business's own
  // acquirer; online we run them through the sandbox unless PayPal is set up.
  return providers.find((p) => p.provider === 'PayPal')?.provider ?? 'Manual';
}

/** After checkout starts, where the flow goes next. */
export function stepForSession(session: CheckoutResponse): PaymentStep {
  if (session.status === 'Succeeded') return { kind: 'done', status: 'Succeeded', message: 'Payment received.' };
  if (session.status === 'Failed') return { kind: 'done', status: 'Failed', message: 'The payment could not be started.' };
  if (session.provider === 'Stripe' && session.clientSecret) return { kind: 'stripe', session };
  if (session.provider === 'PayPal' && session.redirectUrl) return { kind: 'paypal', session };
  return { kind: 'sandbox', session };
}

export function resultStep(status: string): PaymentStep {
  if (status === 'Succeeded') return { kind: 'done', status: 'Succeeded', message: 'Payment received - your receipt is ready.' };
  if (status === 'Failed') return { kind: 'done', status: 'Failed', message: 'The payment did not go through. No money was taken.' };
  return { kind: 'done', status: 'Pending', message: 'The payment is still processing. It will update once the provider confirms it.' };
}

/** Validates a part-payment amount typed by the payer. */
export function validateAmount(raw: string, balance: number): string | null {
  if (raw.trim() === '') return null; // blank = pay the full balance
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) return 'Enter an amount greater than 0.';
  if (Math.round(value * 100) > Math.round(balance * 100)) return `You can pay at most ${balance.toFixed(2)}.`;
  return null;
}

/** Loads Stripe.js once, from Stripe's CDN (it must not be self-hosted). */
let stripeScript: Promise<void> | null = null;
export function loadStripeJs(): Promise<void> {
  if ((window as unknown as { Stripe?: unknown }).Stripe) return Promise.resolve();
  stripeScript ??= new Promise<void>((resolve, reject) => {
    const s = document.createElement('script');
    s.src = 'https://js.stripe.com/v3/';
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => {
      stripeScript = null;
      reject(new Error('Could not load Stripe.'));
    };
    document.head.appendChild(s);
  });
  return stripeScript;
}
