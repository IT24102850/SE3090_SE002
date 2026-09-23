import { useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import Modal from '../../../shared/components/Modal';
import { billingApi, errorMessage, type AvailableProviders, type CheckoutResponse, type Invoice } from '../billingApi';
import { money } from '../format';
import { loadStripeJs, providerFor, resultStep, stepForSession, validateAmount, type PayMethod, type PaymentStep } from '../paymentFlow';

/* Select method -> start checkout -> provider step -> result.
 * Card goes through Stripe when the business has it set up, QR through
 * PayPal or the sandbox, and Cash is paid at the counter. */

interface StripeLike {
  elements: () => { create: (type: 'card', opts?: object) => { mount: (el: HTMLElement) => void; destroy: () => void } };
  confirmCardPayment: (secret: string, data: object) => Promise<{ error?: { message?: string }; paymentIntent?: { status: string } }>;
}

interface Props {
  invoice: Invoice;
  onClose: () => void;
  onPaid: (invoice: Invoice) => void;
  api?: Pick<typeof billingApi, 'availableProviders' | 'checkout' | 'confirmPayment'>;
}

const METHODS: { id: PayMethod; icon: string; title: string; hint: string }[] = [
  { id: 'Card', icon: '💳', title: 'Card', hint: 'Visa, Mastercard, Amex' },
  { id: 'QR', icon: '▦', title: 'QR / wallet', hint: 'Scan with your banking app' },
  { id: 'Cash', icon: '💵', title: 'Cash', hint: 'Pay at the counter' },
];

export default function PaymentFlowModal({ invoice, onClose, onPaid, api = billingApi }: Props) {
  const [available, setAvailable] = useState<AvailableProviders | null>(null);
  const [method, setMethod] = useState<PayMethod>('Card');
  const [amount, setAmount] = useState('');
  const [step, setStep] = useState<PaymentStep>({ kind: 'choose' });
  const cardRef = useRef<HTMLDivElement>(null);
  const stripeRef = useRef<{ stripe: StripeLike; card: { destroy: () => void } } | null>(null);
  const [cardError, setCardError] = useState<string | null>(null);

  useEffect(() => {
    api.availableProviders().then(setAvailable).catch(() => setAvailable({ providers: [], sandboxAvailable: true }));
  }, [api]);

  const amountError = validateAmount(amount, invoice.balanceDue);
  const payAmount = amount.trim() ? Number(amount) : invoice.balanceDue;

  const finish = (updated: Invoice, status: string) => {
    setStep(resultStep(status));
    if (status === 'Succeeded') onPaid(updated);
  };

  const start = async () => {
    if (amountError) return;
    if (method === 'Cash') {
      setStep({ kind: 'cash' });
      return;
    }
    setStep({ kind: 'starting' });
    try {
      const session = await api.checkout(invoice.id, {
        provider: providerFor(method, available),
        method,
        amount: amount.trim() ? payAmount : null,
        returnUrl: `${window.location.origin}${window.location.pathname}?paid=${invoice.id}`,
      });
      setStep(stepForSession(session));
    } catch (err) {
      setStep({ kind: 'error', message: errorMessage(err, 'The payment could not be started.') });
    }
  };

  const confirm = async (session: CheckoutResponse, simulateFailure = false) => {
    setStep({ kind: 'confirming', session });
    try {
      const result = await api.confirmPayment(session.paymentId, simulateFailure);
      finish(result.invoice, result.payment.status);
    } catch (err) {
      setStep({ kind: 'error', message: errorMessage(err, 'We could not confirm the payment.') });
    }
  };

  // Mount Stripe's card field when the Stripe step opens.
  useEffect(() => {
    if (step.kind !== 'stripe' || !cardRef.current) return;
    let cancelled = false;
    loadStripeJs()
      .then(() => {
        if (cancelled || !cardRef.current) return;
        const StripeCtor = (window as unknown as { Stripe: (key: string) => StripeLike }).Stripe;
        const stripe = StripeCtor(step.session.publicKey ?? '');
        const card = stripe.elements().create('card', { hidePostalCode: true });
        card.mount(cardRef.current);
        stripeRef.current = { stripe, card };
      })
      .catch((e: Error) => setCardError(e.message));
    return () => {
      cancelled = true;
      stripeRef.current?.card.destroy();
      stripeRef.current = null;
    };
  }, [step]);

  const payWithStripe = async (session: CheckoutResponse) => {
    if (!stripeRef.current || !session.clientSecret) return;
    setCardError(null);
    const { stripe, card } = stripeRef.current;
    const result = await stripe.confirmCardPayment(session.clientSecret, { payment_method: { card } });
    if (result.error) {
      setCardError(result.error.message ?? 'The card was declined.');
      return;
    }
    // Stripe also tells the server by webhook; confirm reads it back now.
    await confirm(session);
  };

  return (
    <Modal title={`Pay ${invoice.invoiceNumber}`} onClose={onClose}>
      <div className="bl-stack" aria-live="polite">
        <div className="bl-spread">
          <span className="bl-muted">Balance due</span>
          <strong style={{ fontSize: 20 }}>{money(invoice.balanceDue, invoice.currency)}</strong>
        </div>

        {step.kind === 'choose' && (
          <>
            <div className="bl-methods" role="group" aria-label="Payment method">
              {METHODS.map((m) => (
                <button key={m.id} type="button" className="bl-method" aria-pressed={method === m.id} onClick={() => setMethod(m.id)}>
                  <span className="bl-method-icon" aria-hidden="true">{m.icon}</span>
                  <span className="bl-method-title">{m.title}</span>
                  <span className="bl-small bl-muted">{m.hint}</span>
                </button>
              ))}
            </div>
            {method !== 'Cash' && (
              <label className="bl-field">
                <span>Amount (leave blank to pay the full balance)</span>
                <input className="input" type="number" min={0} step="0.01" placeholder={invoice.balanceDue.toFixed(2)}
                  value={amount} aria-invalid={!!amountError || undefined} onChange={(e) => setAmount(e.target.value)} />
                {amountError && <span className="bl-field-error">{amountError}</span>}
              </label>
            )}
            {method !== 'Cash' && available && providerFor(method, available) === 'Manual' && (
              <div className="bl-notice bl-small">This business has no live payment gateway yet, so this runs in the secure sandbox - no real money moves.</div>
            )}
            <button type="button" className="btn btn-primary" disabled={!!amountError} onClick={start}>
              {method === 'Cash' ? 'Continue' : `Pay ${money(payAmount, invoice.currency)}`}
            </button>
          </>
        )}

        {step.kind === 'starting' && <div className="loading-row"><span className="spinner spinner-dark" /> Starting payment…</div>}
        {step.kind === 'confirming' && <div className="loading-row"><span className="spinner spinner-dark" /> Confirming with {step.session.provider === 'Manual' ? 'the sandbox' : step.session.provider}…</div>}

        {step.kind === 'cash' && (
          <div className="bl-notice">
            Pay <strong>{money(invoice.balanceDue, invoice.currency)}</strong> at the counter and quote <strong>{invoice.invoiceNumber}</strong>.
            Staff will record it and your receipt will appear here.
          </div>
        )}

        {step.kind === 'sandbox' && (
          <div className="bl-stack">
            {method === 'QR' && (
              <div className="bl-qr" aria-label="Payment QR code">
                <QRCodeSVG value={`unify-pay:${step.session.externalReference}:${step.session.amount}:${step.session.currency}`} size={168} />
              </div>
            )}
            <div className="bl-notice bl-small">
              Sandbox payment {step.session.externalReference} for {money(step.session.amount, step.session.currency)} is ready.
            </div>
            <div className="bl-row">
              <button type="button" className="btn btn-primary" onClick={() => confirm(step.session)}>Complete payment</button>
              <button type="button" className="btn btn-ghost" onClick={() => confirm(step.session, true)}>Simulate a decline</button>
            </div>
          </div>
        )}

        {step.kind === 'stripe' && (
          <div className="bl-stack">
            <div className="bl-stripe-card" ref={cardRef} aria-label="Card details" />
            {cardError && <span className="bl-field-error" role="alert">{cardError}</span>}
            <button type="button" className="btn btn-primary" onClick={() => payWithStripe(step.session)}>
              Pay {money(step.session.amount, step.session.currency)}
            </button>
          </div>
        )}

        {step.kind === 'paypal' && (
          <div className="bl-stack">
            <p>You will finish on PayPal and come back here.</p>
            <div className="bl-row">
              <a className="btn btn-primary" href={step.session.redirectUrl ?? '#'}>Continue to PayPal</a>
              <button type="button" className="btn btn-secondary" onClick={() => confirm(step.session)}>I have paid - check now</button>
            </div>
          </div>
        )}

        {step.kind === 'done' && (
          <div className={`bl-notice ${step.status === 'Succeeded' ? 'bl-notice-good' : step.status === 'Failed' ? 'bl-notice-critical' : 'bl-notice-warning'}`} role="status">
            {step.message}
          </div>
        )}
        {step.kind === 'error' && <div className="bl-notice bl-notice-critical" role="alert">{step.message}</div>}

        {(step.kind === 'done' || step.kind === 'error' || step.kind === 'cash') && (
          <div className="bl-row">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Close</button>
            {step.kind !== 'done' || step.status !== 'Succeeded' ? (
              <button type="button" className="btn btn-ghost" onClick={() => setStep({ kind: 'choose' })}>Try another way</button>
            ) : null}
          </div>
        )}
      </div>
    </Modal>
  );
}
