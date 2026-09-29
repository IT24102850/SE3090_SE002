import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '../../store/store';
import { money, date } from '../billing/format';
import { useAsync } from '../billing/useAsync';
import { PlanLadder } from './PlanCards';
import { subscriptionApi, type AddOn } from './subscriptionApi';
import '../marketing/landing.css';
import './subscription.css';

/* The public price list.
 *
 * It reads the same catalogue endpoint the checkout prices against, rather
 * than a hardcoded copy, so a marketing page that quotes the wrong number is
 * not a thing that can happen here. */

const FAQ: { q: string; a: string }[] = [
  {
    q: 'Is the free plan really free?',
    a: 'Yes, and it has no expiry date. Starter runs one branch with two team members and up to 60 bookings a month, with invoices, receipts and email reminders. No card is needed to sign up.',
  },
  {
    q: 'What happens if I stop paying?',
    a: 'Nothing is deleted and nothing is locked. A failed renewal starts a two-week grace window where everything keeps working, and after that you drop back to Starter with all your data intact. Resubscribe whenever you like and it all switches back on.',
  },
  {
    q: 'Can I change plans mid-term?',
    a: 'Any time. Whatever you have already paid for and not used is credited against the new plan before you are charged anything, so you never pay twice for the same days.',
  },
  {
    q: 'Why is the 12-month price so much lower?',
    a: 'Because a year of commitment is genuinely worth that much to us: it is one payment to process, no monthly churn risk, and a business that plans a year ahead is one we can support properly. The monthly price is what flexibility costs.',
  },
  {
    q: 'Do you charge per customer?',
    a: 'No. Your customers are never seats. You pay for your team, your branches and your AI usage — growing your own customer base never costs you more.',
  },
  {
    q: 'What is a Spotlight?',
    a: 'Twenty-four hours at the top of the Unify directory for your business. Paid plans include a few every month, and you can buy more in packs. They are the one thing on this page that free tenants can buy too.',
  },
];

export default function PricingPage() {
  const navigate = useNavigate();
  const token = useSelector((s: RootState) => s.auth.token);
  const [currency, setCurrency] = useState<string | undefined>(undefined);
  const { data, loading, error } = useAsync(() => subscriptionApi.catalog(currency), [currency]);

  const go = () => navigate(token ? '/subscription' : '/register');

  return (
    <div className="landing" style={{ paddingBottom: 80 }}>
      <header className="sub-stack" style={{ padding: '56px 24px 8px', maxWidth: 1180, margin: '0 auto', gap: 10 }}>
        <Link to="/" className="sub-small sub-muted" style={{ textDecoration: 'none' }}>
          ← Back to Unify
        </Link>
        <h1 className="page-title" style={{ fontSize: 'clamp(2rem, 4vw, 2.9rem)' }}>
          Start free. Pay when it pays you back.
        </h1>
        <p className="page-subtitle" style={{ fontSize: 17 }}>
          Every plan runs the whole platform — bookings, invoices, customers, stock. What you pay for is scale, the AI
          copilots, and being found.
        </p>
      </header>

      <main style={{ maxWidth: 1180, margin: '0 auto', padding: '24px' }} className="sub-stack">
        {error && <div className="bl-notice bl-notice-critical">{error}</div>}
        {loading && !data && (
          <div className="loading-row">
            <span className="spinner spinner-dark" />
          </div>
        )}

        {data && (
          <>
            {data.featuredOffer && (
              <div className="bl-notice bl-notice-good">
                <strong>{data.featuredOffer.name}</strong> — {data.featuredOffer.description}, applied automatically
                {data.featuredOffer.endsAt ? ` until ${date(data.featuredOffer.endsAt)}` : ''}. The renewal after that is
                at the standard price.
              </div>
            )}

            <PlanLadder
              plans={data.plans}
              currency={data.currency}
              currencies={data.currencies}
              onCurrencyChange={setCurrency}
              onChoose={go}
              ctaLabel={(p) => (p.tier === 0 ? 'Start free' : `Choose ${p.name}`)}
            />

            <section className="sub-stack" style={{ marginTop: 28 }}>
              <h2 className="page-title" style={{ fontSize: '1.3rem' }}>
                Buy what you need, when you need it
              </h2>
              <p className="page-subtitle">
                No subscription, no commitment. Bigger packs cost less per unit, and Spotlight is on sale to every
                business on Unify — including the free ones.
              </p>
              <div className="sub-addons">
                {data.addOns.map((a) => (
                  <AddOnTile key={a.code} addOn={a} currency={data.currency} />
                ))}
              </div>
            </section>

            <section className="sub-stack" style={{ marginTop: 36 }}>
              <h2 className="page-title" style={{ fontSize: '1.3rem' }}>
                What everything includes
              </h2>
              <ComparisonTable plans={data.plans} />
            </section>

            <section className="sub-stack" style={{ marginTop: 36 }}>
              <h2 className="page-title" style={{ fontSize: '1.3rem' }}>
                Questions we get asked
              </h2>
              {FAQ.map((f) => (
                <details key={f.q} className="card card-pad">
                  <summary style={{ cursor: 'pointer', fontWeight: 700 }}>{f.q}</summary>
                  <p style={{ margin: '10px 0 0', color: 'var(--color-text-secondary)', lineHeight: 1.6 }}>{f.a}</p>
                </details>
              ))}
            </section>

            <div className="sub-row" style={{ justifyContent: 'center', marginTop: 32 }}>
              <button className="btn btn-primary" onClick={go} style={{ minWidth: 220 }}>
                {token ? 'Manage my plan' : 'Create a free account'}
              </button>
            </div>
          </>
        )}
      </main>
    </div>
  );
}

function AddOnTile({ addOn, currency }: { addOn: AddOn; currency: string }) {
  return (
    <div className={`sub-addon ${addOn.isBestValue ? 'sub-addon-best' : ''}`}>
      <div className="sub-spread">
        <span className="sub-addon-name">{addOn.name}</span>
        {addOn.isBestValue && <span className="sub-save-badge">Best value</span>}
      </div>
      <div className="sub-addon-price">
        <span className="sub-addon-amount">{money(addOn.amount, currency)}</span>
        {addOn.comparedAtAmount > addOn.amount && (
          <>
            <span className="sub-price-was">{money(addOn.comparedAtAmount, currency)}</span>
            <span className="sub-save-badge">−{addOn.savingsPercent}%</span>
          </>
        )}
      </div>
      <span className="sub-small sub-muted">{addOn.tagline}</span>
      {addOn.minimumTier > 0 && <span className="sub-small sub-muted">Needs a paid plan.</span>}
    </div>
  );
}

/* One row per limit and per feature, ticked across the ladder. Text in every
 * cell, never a bare tick on its own for the numbers, so the table still
 * reads correctly to a screen reader. */
function ComparisonTable({ plans }: { plans: Awaited<ReturnType<typeof subscriptionApi.catalog>>['plans'] }) {
  const cap = (v: number | null) => (v === null ? 'Unlimited' : v.toLocaleString());

  const rows: { label: string; value: (p: (typeof plans)[number]) => string }[] = [
    { label: 'Branches', value: (p) => cap(p.maxBranches) },
    { label: 'Team members', value: (p) => cap(p.maxStaffSeats) },
    { label: 'Bookings a month', value: (p) => cap(p.maxBookingsPerMonth) },
    { label: 'AI copilot runs a month', value: (p) => (p.aiRunsPerMonth === 0 ? 'Not included' : cap(p.aiRunsPerMonth)) },
    { label: 'SMS / WhatsApp a month', value: (p) => (p.smsPerMonth === 0 ? 'Not included' : cap(p.smsPerMonth)) },
    { label: 'Spotlights a month', value: (p) => (p.spotlightsPerMonth === 0 ? 'None' : String(p.spotlightsPerMonth)) },
    {
      label: 'Support response',
      value: (p) => (p.supportResponseHours === null ? 'Community' : `Within ${p.supportResponseHours}h`),
    },
  ];

  const featureRows: { label: string; code: string }[] = [
    { label: 'Public directory listing', code: 'public-directory' },
    { label: 'Website booking widget', code: 'embed-widget' },
    { label: 'Card payments from your customers', code: 'payment-gateways' },
    { label: 'SMS and WhatsApp reminders', code: 'sms-reminders' },
    { label: 'Custom forms and invoice branding', code: 'custom-branding' },
    { label: 'AI copilots', code: 'ai-agents' },
    { label: 'Purchase orders and suppliers', code: 'inventory-pro' },
    { label: 'Advanced analytics and exports', code: 'advanced-analytics' },
    { label: 'Claims, commissions, schedules', code: 'advanced-billing' },
    { label: 'API access and webhooks', code: 'api-access' },
    { label: 'Priority support', code: 'priority-support' },
  ];

  return (
    <div className="bl-table-wrap">
      <table className="bl-table">
        <thead>
          <tr>
            <th>&nbsp;</th>
            {plans.map((p) => (
              <th key={p.code} style={{ textAlign: 'center' }}>
                {p.name}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label}>
              <td style={{ fontWeight: 600 }}>{r.label}</td>
              {plans.map((p) => (
                <td key={p.code} style={{ textAlign: 'center' }}>
                  {r.value(p)}
                </td>
              ))}
            </tr>
          ))}
          {featureRows.map((r) => (
            <tr key={r.code}>
              <td style={{ fontWeight: 600 }}>{r.label}</td>
              {plans.map((p) => {
                const has = p.features.includes(r.code);
                return (
                  <td key={p.code} style={{ textAlign: 'center' }}>
                    <span
                      aria-label={has ? `${r.label}: included in ${p.name}` : `${r.label}: not in ${p.name}`}
                      style={{ color: has ? 'var(--color-good)' : 'var(--color-text-muted)', fontWeight: 700 }}
                    >
                      {has ? '✓' : '—'}
                    </span>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
