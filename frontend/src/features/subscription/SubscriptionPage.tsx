import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '../../store/store';
import Modal from '../../shared/components/Modal';
import { useToast } from '../../shared/components/Toast';
import { errorMessage } from '../billing/billingApi';
import { money, date, dateTime } from '../billing/format';
import { useAsync } from '../billing/useAsync';
import { PlanLadder } from './PlanCards';
import {
  CREDIT_LABELS,
  limitLabel,
  subscriptionApi,
  type AddOn,
  type BillingPeriod,
  type CheckoutResult,
  type Plan,
  type PlanPrice,
  type Quote,
} from './subscriptionApi';
import './subscription.css';

/* The tenant admin's own subscription console: what they are on, what they
 * have used, what a change costs, and paying for it.
 *
 * The one rule this screen obeys: it never says a plan is active. It asks the
 * server, and the server asks the gateway. Everything here is a view of what
 * came back. */

type Tab = 'plan' | 'addons' | 'invoices';

export default function SubscriptionPage() {
  const toast = useToast();
  const role = useSelector((s: RootState) => s.auth.user?.role);
  const isAdmin = role === 'Admin';

  const [params, setParams] = useSearchParams();
  const [tab, setTab] = useState<Tab>('plan');
  const [currency, setCurrency] = useState<string | undefined>(undefined);
  const [pending, setPending] = useState<Quote | null>(null);
  const [promoInput, setPromoInput] = useState('');
  const [provider, setProvider] = useState<string | undefined>(undefined);
  const [busy, setBusy] = useState(false);
  const [cancelOpen, setCancelOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState('');

  const subscription = useAsync(() => subscriptionApi.current(), []);
  const catalog = useAsync(() => subscriptionApi.catalog(currency), [currency]);
  const invoices = useAsync(() => subscriptionApi.invoices(), []);
  const providers = useAsync(() => subscriptionApi.providers(), []);

  const reloadAll = useCallback(() => {
    subscription.reload();
    catalog.reload();
    invoices.reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subscription.reload, catalog.reload, invoices.reload]);

  const sub = subscription.data;
  const cat = catalog.data;
  const activeCurrency = cat?.currency ?? sub?.currency ?? 'LKR';

  /* ── Coming back from a hosted checkout ───────────────────────────────
   * The gateway sends the tenant here with ?payment=&result=. The result is
   * a hint about what to say, never the source of truth: either way we ask
   * the server to read the payment back from the provider. */
  const returningPaymentId = params.get('payment');
  useEffect(() => {
    if (!returningPaymentId || !isAdmin) return;
    let cancelled = false;
    (async () => {
      setBusy(true);
      try {
        const invoice = await subscriptionApi.confirm(returningPaymentId);
        if (cancelled) return;
        if (invoice.status === 'Paid') toast.show(`Payment received - ${invoice.number} is settled.`, 'success');
        else if (invoice.status === 'Failed') toast.show('That payment did not go through. Nothing has changed on your plan.', 'error');
        else toast.show('The payment is still being processed. We will update your plan as soon as it settles.', 'info');
      } catch (err) {
        if (!cancelled) toast.show(errorMessage(err, 'We could not check that payment.'), 'error');
      } finally {
        if (!cancelled) {
          setBusy(false);
          const next = new URLSearchParams(params);
          next.delete('payment');
          next.delete('result');
          setParams(next, { replace: true });
          reloadAll();
        }
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [returningPaymentId]);

  const returnUrl = useMemo(() => `${window.location.origin}/subscription`, []);

  // ── Actions ────────────────────────────────────────────────────────────

  const openQuote = async (plan: Plan, _price: PlanPrice | null, period: BillingPeriod) => {
    if (plan.tier === 0) {
      setCancelOpen(true);
      return;
    }
    setBusy(true);
    try {
      const quote = await subscriptionApi.quote({
        planCode: plan.code,
        period,
        currency: activeCurrency,
        promotionCode: promoInput.trim() || undefined,
      });
      setPending(quote);
    } catch (err) {
      toast.show(errorMessage(err, 'We could not price that change.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const applyPromo = async () => {
    if (!pending) return;
    setBusy(true);
    try {
      const result = await subscriptionApi.validatePromotion({
        code: promoInput.trim(),
        planCode: pending.planCode,
        period: pending.period,
        currency: pending.currency,
      });
      setPending(result.quote);
      toast.show(result.message, result.valid ? 'success' : 'error');
    } catch (err) {
      toast.show(errorMessage(err, 'We could not check that code.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const handleCheckout = (result: CheckoutResult) => {
    if (result.completed) {
      toast.show('Your plan is live.', 'success');
      setPending(null);
      reloadAll();
      return;
    }
    if (result.redirectUrl) {
      window.location.href = result.redirectUrl;
      return;
    }
    if (result.simulated) {
      // The sandbox has no page to send anybody to: confirm it here so the
      // whole flow is demonstrable without real gateway credentials.
      void (async () => {
        try {
          const invoice = await subscriptionApi.confirm(result.paymentId);
          toast.show(
            invoice.status === 'Paid'
              ? `Sandbox payment accepted - ${invoice.number} settled. No real money moved.`
              : 'The sandbox payment did not settle.',
            invoice.status === 'Paid' ? 'success' : 'error',
          );
        } catch (err) {
          toast.show(errorMessage(err, 'The sandbox payment could not be confirmed.'), 'error');
        } finally {
          setPending(null);
          reloadAll();
        }
      })();
      return;
    }
    toast.show('The payment was started but the gateway gave us nowhere to send you.', 'error');
  };

  const pay = async () => {
    if (!pending) return;
    setBusy(true);
    try {
      handleCheckout(
        await subscriptionApi.checkout({
          planCode: pending.planCode,
          period: pending.period,
          currency: pending.currency,
          promotionCode: pending.promotionCode ?? undefined,
          provider,
          returnUrl,
        }),
      );
    } catch (err) {
      toast.show(errorMessage(err, 'The payment could not be started.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const buyAddOn = async (addOn: AddOn) => {
    setBusy(true);
    try {
      handleCheckout(
        await subscriptionApi.buyAddOn({
          addOnCode: addOn.code,
          quantity: 1,
          currency: activeCurrency,
          provider,
          returnUrl,
        }),
      );
    } catch (err) {
      toast.show(errorMessage(err, 'That purchase could not be started.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const payInvoice = async (invoiceId: string) => {
    setBusy(true);
    try {
      handleCheckout(await subscriptionApi.payInvoice(invoiceId, { provider, returnUrl }));
    } catch (err) {
      toast.show(errorMessage(err, 'That invoice could not be paid.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const startTrial = async () => {
    setBusy(true);
    try {
      await subscriptionApi.startTrial();
      toast.show('Your trial has started. Everything is switched on.', 'success');
      reloadAll();
    } catch (err) {
      toast.show(errorMessage(err, 'The trial could not be started.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const confirmCancel = async () => {
    setBusy(true);
    try {
      const updated = await subscriptionApi.cancel(cancelReason.trim() || undefined, sub?.status === 'Trialing');
      toast.show(
        updated.cancelAtPeriodEnd
          ? `Cancelled. You keep ${sub?.planName} until ${date(updated.currentPeriodEnd)}.`
          : 'You are back on Starter. All your data is still here.',
        'info',
      );
      setCancelOpen(false);
      setCancelReason('');
      reloadAll();
    } catch (err) {
      toast.show(errorMessage(err, 'The cancellation did not go through.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  const resume = async () => {
    setBusy(true);
    try {
      await subscriptionApi.resume();
      toast.show('Your plan will keep renewing.', 'success');
      reloadAll();
    } catch (err) {
      toast.show(errorMessage(err, 'That could not be undone.'), 'error');
    } finally {
      setBusy(false);
    }
  };

  // ── Render ─────────────────────────────────────────────────────────────

  const openInvoices = (invoices.data ?? []).filter((i) => i.status === 'Issued' || i.status === 'Failed');

  return (
    <div className="sub-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Your Unify plan</h1>
          <p className="page-subtitle">
            What your business pays Unify for the platform. Separate from Billing, which is what you charge your own
            customers.
          </p>
        </div>
      </div>

      {subscription.error && <div className="bl-notice bl-notice-critical">{subscription.error}</div>}
      {subscription.loading && !sub && (
        <div className="loading-row">
          <span className="spinner spinner-dark" />
        </div>
      )}

      {sub && (
        <>
          <StatusBanners sub={sub} openInvoiceCount={openInvoices.length} />

          <div className="sub-hero">
            <div>
              <div className="sub-hero-plan">
                {sub.planName}
                {sub.isComplimentary && <span className="bl-badge bl-badge-primary" style={{ marginLeft: 8 }}>Complimentary</span>}
              </div>
              <div className="sub-hero-meta">
                {sub.tier === 0
                  ? 'Free forever. Upgrade whenever you need more.'
                  : sub.status === 'Trialing'
                    ? `Trial ends ${date(sub.trialEndsAt)}`
                    : `${money(sub.amount, sub.currency)} every ${sub.periodLabel.toLowerCase()} · ${
                        sub.cancelAtPeriodEnd ? 'ends' : 'renews'
                      } ${date(sub.currentPeriodEnd)}`}
              </div>
            </div>
            <div className="sub-row">
              {sub.trialAvailable && isAdmin && (
                <button className="btn btn-primary" onClick={startTrial} disabled={busy}>
                  Start {sub.trialDays}-day free trial
                </button>
              )}
              {sub.cancelAtPeriodEnd && isAdmin && (
                <button className="btn btn-secondary" onClick={resume} disabled={busy}>
                  Keep my plan
                </button>
              )}
              {sub.tier > 0 && !sub.cancelAtPeriodEnd && isAdmin && !sub.isComplimentary && (
                <button className="btn btn-ghost" onClick={() => setCancelOpen(true)} disabled={busy}>
                  Cancel plan
                </button>
              )}
            </div>
          </div>

          <section className="sub-stack">
            <h2 className="page-title" style={{ fontSize: '1.15rem' }}>
              This month
            </h2>
            <div className="sub-meters">
              {sub.usage.map((m) => (
                <Meter key={m.metric} label={m.label} used={m.used} limit={m.limit} credits={m.credits} />
              ))}
            </div>
            {Object.keys(sub.credits).length > 0 && (
              <div className="sub-row sub-small">
                {Object.entries(sub.credits).map(([type, n]) => (
                  <span key={type} className="bl-badge">
                    {n.toLocaleString()} {CREDIT_LABELS[type] ?? type}
                  </span>
                ))}
                {sub.extraSeats > 0 && <span className="bl-badge">+{sub.extraSeats} extra seats</span>}
              </div>
            )}
          </section>

          <div className="bl-tabs" role="tablist">
            <button role="tab" aria-selected={tab === 'plan'} className="bl-tab" onClick={() => setTab('plan')}>
              Plans
            </button>
            <button role="tab" aria-selected={tab === 'addons'} className="bl-tab" onClick={() => setTab('addons')}>
              Add-ons<span className="bl-tab-count">{cat?.addOns.length ?? 0}</span>
            </button>
            <button role="tab" aria-selected={tab === 'invoices'} className="bl-tab" onClick={() => setTab('invoices')}>
              Invoices<span className="bl-tab-count">{invoices.data?.length ?? 0}</span>
            </button>
          </div>

          {tab === 'plan' && cat && (
            <>
              {cat.featuredOffer && (
                <div className="bl-notice bl-notice-good">
                  <strong>{cat.featuredOffer.name}</strong> — {cat.featuredOffer.description}. Applied automatically at
                  checkout
                  {cat.featuredOffer.endsAt ? `, until ${date(cat.featuredOffer.endsAt)}` : ''}.
                </div>
              )}
              <PlanLadder
                plans={cat.plans}
                currency={cat.currency}
                currencies={cat.currencies}
                onCurrencyChange={setCurrency}
                currentPlanCode={sub.planCode}
                busy={busy || !isAdmin}
                onChoose={isAdmin ? openQuote : undefined}
                ctaLabel={(p) => (p.tier === 0 ? 'Move to Starter' : p.tier > sub.tier ? `Upgrade to ${p.name}` : `Switch to ${p.name}`)}
              />
              {!isAdmin && (
                <div className="bl-notice">
                  Only an Admin can change the plan. Ask the business owner to make the change.
                </div>
              )}
            </>
          )}

          {tab === 'addons' && cat && (
            <AddOnStore addOns={cat.addOns} currency={cat.currency} onBuy={buyAddOn} busy={busy} canBuy={isAdmin} />
          )}

          {tab === 'invoices' && (
            <InvoiceList
              invoices={invoices.data ?? []}
              loading={invoices.loading}
              error={invoices.error}
              onPay={isAdmin ? payInvoice : undefined}
              busy={busy}
            />
          )}
        </>
      )}

      {providers.data && providers.data.providers.length > 1 && isAdmin && (
        <label className="sub-row sub-small">
          <span className="sub-muted">Pay with</span>
          <select
            className="input"
            style={{ width: 'auto' }}
            value={provider ?? providers.data.defaultProvider}
            onChange={(e) => setProvider(e.target.value)}
          >
            {providers.data.providers.map((p) => (
              <option key={p.provider} value={p.provider}>
                {p.label}
              </option>
            ))}
          </select>
        </label>
      )}

      {/* ── Confirm a plan change ─────────────────────────────────────── */}
      {pending && (
        <Modal title="Confirm your plan" onClose={() => setPending(null)}>
          <div className="sub-stack">
            <div>
              <div style={{ fontWeight: 700, fontSize: 17 }}>
                {pending.planName} · {pending.periodLabel}
              </div>
              <div className="sub-small sub-muted">
                {date(pending.periodStart)} to {date(pending.periodEnd)}
              </div>
            </div>

            <div className="bl-totals">
              {pending.lines.map((line, i) => (
                <div key={`${line.description}-${i}`} style={{ display: 'contents' }}>
                  <span>{line.description}</span>
                  <span className="bl-num">{money(line.amount, pending.currency)}</span>
                </div>
              ))}
              <span className="bl-total-final">Due now</span>
              <span className="bl-total-final bl-num">{money(pending.total, pending.currency)}</span>
            </div>

            <div className="bl-field">
              <span>Offer code</span>
              <div className="sub-row">
                <input
                  className="input"
                  value={promoInput}
                  onChange={(e) => setPromoInput(e.target.value.toUpperCase())}
                  placeholder="Optional"
                  style={{ flex: 1 }}
                />
                <button className="btn btn-secondary" onClick={applyPromo} disabled={busy || !promoInput.trim()}>
                  Apply
                </button>
              </div>
              {pending.promotionMessage && <span className="bl-field-hint">{pending.promotionMessage}</span>}
            </div>

            <div className="bl-notice">
              Renews at {money(pending.renewalAmount, pending.currency)} every {pending.periodLabel.toLowerCase()}. You
              can cancel any time and keep access until the term ends.
            </div>

            <div className="sub-row" style={{ justifyContent: 'flex-end' }}>
              <button className="btn btn-ghost" onClick={() => setPending(null)} disabled={busy}>
                Not now
              </button>
              <button className="btn btn-primary" onClick={pay} disabled={busy}>
                {pending.total <= 0 ? 'Activate' : `Pay ${money(pending.total, pending.currency)}`}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* ── Cancel ────────────────────────────────────────────────────── */}
      {cancelOpen && (
        <Modal title="Cancel your plan" onClose={() => setCancelOpen(false)}>
          <div className="sub-stack">
          <p style={{ margin: 0 }}>
            {sub?.status === 'Trialing'
              ? 'Your trial ends straight away and you move to Starter.'
              : `You keep everything in ${sub?.planName} until ${date(sub?.currentPeriodEnd)}, then move to Starter.`}{' '}
            Nothing is deleted — your bookings, invoices and stock all stay exactly where they are.
          </p>
          <label className="bl-field">
            <span>What made you cancel? (optional)</span>
            <textarea
              className="input"
              rows={3}
              value={cancelReason}
              onChange={(e) => setCancelReason(e.target.value)}
              placeholder="It helps us fix the right thing."
            />
          </label>
          <div className="sub-row" style={{ justifyContent: 'flex-end' }}>
              <button className="btn btn-secondary" onClick={() => setCancelOpen(false)} disabled={busy}>
                Keep my plan
              </button>
              <button className="btn btn-danger" onClick={confirmCancel} disabled={busy}>
                Cancel plan
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}

// ── Pieces ───────────────────────────────────────────────────────────────

function StatusBanners({
  sub,
  openInvoiceCount,
}: {
  sub: NonNullable<Awaited<ReturnType<typeof subscriptionApi.current>>>;
  openInvoiceCount: number;
}) {
  return (
    <>
      {sub.status === 'PastDue' && (
        <div className="bl-notice bl-notice-warning">
          <strong>Your renewal is unpaid.</strong> Nothing has switched off — everything keeps working until{' '}
          {date(sub.graceEndsAt)}. Pay the open invoice and your plan carries on as normal.
        </div>
      )}
      {sub.status === 'Expired' && sub.tier === 0 && (
        <div className="bl-notice">
          Your paid plan has ended and you are on Starter. All your data is still here — resubscribe and everything
          switches back on.
        </div>
      )}
      {sub.status === 'Trialing' && (
        <div className="bl-notice bl-notice-good">
          You are trialling <strong>{sub.planName}</strong> until {date(sub.trialEndsAt)}. No card was taken, so nothing
          will be charged when it ends.
        </div>
      )}
      {sub.cancelAtPeriodEnd && (
        <div className="bl-notice bl-notice-warning">
          This plan ends on {date(sub.currentPeriodEnd)}. Until then nothing changes.
        </div>
      )}
      {openInvoiceCount > 0 && sub.status !== 'PastDue' && (
        <div className="bl-notice">
          You have {openInvoiceCount} open invoice{openInvoiceCount === 1 ? '' : 's'} — see the Invoices tab.
        </div>
      )}
    </>
  );
}

function Meter({ label, used, limit, credits }: { label: string; used: number; limit: number | null; credits: number }) {
  const unlimited = limit === null;
  const pct = unlimited || limit === 0 ? 0 : Math.min(100, Math.round((used / limit) * 100));
  const tone = pct >= 100 ? 'sub-bar-fill-full' : pct >= 80 ? 'sub-bar-fill-warn' : '';

  return (
    <div className="sub-meter">
      <div className="sub-meter-head">
        <span className="sub-meter-label">{label}</span>
        <span className="sub-meter-value">
          {used.toLocaleString()} <span className="sub-muted">/ {limitLabel(limit)}</span>
        </span>
      </div>
      {!unlimited && (
        <div
          className="sub-bar"
          role="progressbar"
          aria-valuenow={used}
          aria-valuemin={0}
          aria-valuemax={limit ?? undefined}
          aria-label={`${label}: ${used} of ${limitLabel(limit)} used`}
        >
          <div className={`sub-bar-fill ${tone}`} style={{ width: `${pct}%` }} />
        </div>
      )}
      <span className="sub-small sub-muted">
        {unlimited
          ? 'No limit on your plan.'
          : limit === 0
            ? 'Not included on your plan.'
            : pct >= 100
              ? credits > 0
                ? `Allowance spent — ${credits.toLocaleString()} bought credits will cover the next ones.`
                : 'Allowance spent for this month.'
              : `${(limit - used).toLocaleString()} left this month${credits > 0 ? `, plus ${credits.toLocaleString()} bought` : ''}.`}
      </span>
    </div>
  );
}

function AddOnStore({
  addOns,
  currency,
  onBuy,
  busy,
  canBuy,
}: {
  addOns: AddOn[];
  currency: string;
  onBuy: (a: AddOn) => void;
  busy: boolean;
  canBuy: boolean;
}) {
  const categories = useMemo(() => {
    const groups = new Map<string, AddOn[]>();
    for (const a of addOns) {
      const list = groups.get(a.category) ?? [];
      list.push(a);
      groups.set(a.category, list);
    }
    return [...groups.entries()];
  }, [addOns]);

  return (
    <div className="sub-stack" style={{ gap: 22 }}>
      <div className="bl-notice">
        Bought once, used whenever you need them. The bigger pack is always the better unit price, and credits from a
        pack are spent only after your monthly plan allowance runs out.
      </div>
      {categories.map(([category, items]) => (
        <section key={category} className="sub-stack">
          <h3 className="page-title" style={{ fontSize: '1.05rem' }}>
            {category}
          </h3>
          <div className="sub-addons">
            {items.map((a) => (
              <div
                key={a.code}
                className={`sub-addon ${a.isBestValue ? 'sub-addon-best' : ''} ${a.availableOnCurrentPlan ? '' : 'sub-addon-locked'}`}
              >
                <div className="sub-spread">
                  <span className="sub-addon-name">{a.name}</span>
                  {a.isBestValue && <span className="sub-save-badge">Best value</span>}
                </div>
                <div className="sub-addon-price">
                  <span className="sub-addon-amount">{money(a.amount, currency)}</span>
                  {a.comparedAtAmount > a.amount && (
                    <>
                      <span className="sub-price-was">{money(a.comparedAtAmount, currency)}</span>
                      <span className="sub-save-badge">−{a.savingsPercent}%</span>
                    </>
                  )}
                </div>
                <span className="sub-small sub-muted">{a.tagline}</span>
                {a.expiryDays > 0 && (
                  <span className="sub-small sub-muted">Valid for {Math.round(a.expiryDays / 30)} months.</span>
                )}
                <button
                  className="btn btn-secondary"
                  onClick={() => onBuy(a)}
                  disabled={busy || !canBuy || !a.availableOnCurrentPlan || a.amount <= 0}
                >
                  {!a.availableOnCurrentPlan ? 'Needs a paid plan' : 'Buy'}
                </button>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function InvoiceList({
  invoices,
  loading,
  error,
  onPay,
  busy,
}: {
  invoices: Awaited<ReturnType<typeof subscriptionApi.invoices>>;
  loading: boolean;
  error: string | null;
  onPay?: (id: string) => void;
  busy: boolean;
}) {
  if (error) return <div className="bl-notice bl-notice-critical">{error}</div>;
  if (loading && invoices.length === 0)
    return (
      <div className="loading-row">
        <span className="spinner spinner-dark" />
      </div>
    );
  if (invoices.length === 0) return <div className="bl-empty">No Unify invoices yet.</div>;

  return (
    <div className="bl-table-wrap">
      <table className="bl-table">
        <thead>
          <tr>
            <th>Invoice</th>
            <th>For</th>
            <th>Issued</th>
            <th className="bl-num">Total</th>
            <th>Status</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {invoices.map((i) => (
            <tr key={i.id}>
              <td className="bl-mono bl-small">{i.number}</td>
              <td>
                {i.kind === 'Subscription' ? `${i.planCode ?? 'Plan'} · ${i.period ?? ''}` : 'Add-on'}
                {i.promotionCode && <span className="bl-badge bl-badge-good" style={{ marginLeft: 6 }}>{i.promotionCode}</span>}
              </td>
              <td className="bl-small">{dateTime(i.issuedAt)}</td>
              <td className="bl-num">{money(i.total, i.currency)}</td>
              <td>
                <span
                  className={`bl-badge ${
                    i.status === 'Paid'
                      ? 'bl-badge-good'
                      : i.status === 'Failed'
                        ? 'bl-badge-critical'
                        : i.status === 'Issued'
                          ? 'bl-badge-warning'
                          : ''
                  }`}
                >
                  {i.status}
                </span>
              </td>
              <td>
                {onPay && (i.status === 'Issued' || i.status === 'Failed') && i.total > 0 && (
                  <button className="btn btn-primary btn-sm" onClick={() => onPay(i.id)} disabled={busy}>
                    Pay
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
