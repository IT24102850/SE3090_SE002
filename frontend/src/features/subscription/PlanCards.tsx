import { useMemo, useState } from 'react';
import { money } from '../billing/format';
import type { BillingPeriod, Plan, PlanPrice } from './subscriptionApi';
import './subscription.css';

/* The pricing ladder, drawn once and used by both the public pricing page and
 * the tenant's own subscription console, so the two can never quote different
 * numbers. */

const TERM_ORDER: BillingPeriod[] = ['Monthly', 'SemiAnnual', 'Annual'];

export function priceFor(plan: Plan, period: BillingPeriod): PlanPrice | null {
  return plan.prices.find((p) => p.period === period) ?? null;
}

/** The term segments, labelled with what each one saves. */
export function TermToggle({
  plans,
  period,
  onChange,
}: {
  plans: Plan[];
  period: BillingPeriod;
  onChange: (p: BillingPeriod) => void;
}) {
  // The saving shown on a segment is the deepest any plan offers on that
  // term. They are all equal by construction, but reading it from the data
  // means a future per-plan discount cannot make the label a lie.
  const savings = useMemo(() => {
    const map = new Map<BillingPeriod, { label: string; save: number }>();
    for (const term of TERM_ORDER) {
      let label = term === 'Monthly' ? 'Monthly' : term === 'SemiAnnual' ? '6 months' : '12 months';
      let save = 0;
      for (const plan of plans) {
        const price = priceFor(plan, term);
        if (!price) continue;
        label = price.periodLabel;
        save = Math.max(save, price.savingsPercent);
      }
      map.set(term, { label, save });
    }
    return map;
  }, [plans]);

  return (
    <div className="sub-terms" role="group" aria-label="Billing term">
      {TERM_ORDER.map((term) => {
        const info = savings.get(term);
        if (!info) return null;
        return (
          <button
            key={term}
            type="button"
            className="sub-term"
            aria-pressed={period === term}
            onClick={() => onChange(term)}
          >
            <span>{info.label}</span>
            {info.save > 0 && <span className="sub-term-save">Save {info.save}%</span>}
          </button>
        );
      })}
    </div>
  );
}

export function PlanCard({
  plan,
  period,
  currency,
  currentPlanCode,
  ctaLabel,
  onChoose,
  busy,
  disabled,
}: {
  plan: Plan;
  period: BillingPeriod;
  currency: string;
  currentPlanCode?: string;
  ctaLabel?: (plan: Plan) => string;
  onChoose?: (plan: Plan, price: PlanPrice | null) => void;
  busy?: boolean;
  disabled?: boolean;
}) {
  const price = priceFor(plan, period);
  const isCurrent = currentPlanCode === plan.code;
  const free = plan.tier === 0;

  const className = [
    'sub-plan',
    isCurrent ? 'sub-plan-current' : plan.isMostPopular ? 'sub-plan-featured' : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={className}>
      {isCurrent ? (
        <span className="sub-plan-flag sub-plan-flag-current">Your plan</span>
      ) : plan.isMostPopular ? (
        <span className="sub-plan-flag">Most popular</span>
      ) : null}

      <div>
        <div className="sub-plan-name">{plan.name}</div>
        <div className="sub-plan-tag">{plan.tagline}</div>
      </div>

      <div className="sub-price">
        {free ? (
          <>
            <span className="sub-price-free">Free</span>
            <span className="sub-price-term">No card, no expiry.</span>
          </>
        ) : price ? (
          <>
            <div className="sub-price-main">
              <span className="sub-price-amount">{money(price.monthlyEquivalent, currency)}</span>
              <span className="sub-price-unit">/ month</span>
              {price.savingsPercent > 0 && (
                <span className="sub-save-badge">−{price.savingsPercent}%</span>
              )}
            </div>
            <span className="sub-price-term">
              {money(price.amount, currency)} billed every {price.periodLabel.toLowerCase()}
              {price.comparedAtAmount > price.amount && (
                <>
                  {' · '}
                  <span className="sub-price-was">{money(price.comparedAtAmount, currency)}</span>
                </>
              )}
            </span>
          </>
        ) : (
          <span className="sub-price-term sub-muted">Not sold in {currency} on this term.</span>
        )}
      </div>

      <ul className="sub-bullets">
        {plan.highlights.map((h) => (
          <li key={h}>
            <span>{h}</span>
          </li>
        ))}
      </ul>

      {plan.trialDays > 0 && !isCurrent && (
        <div className="sub-small sub-muted">{plan.trialDays}-day free trial, no card needed.</div>
      )}

      {onChoose && (
        <div className="sub-plan-cta">
          <button
            type="button"
            className={`btn ${plan.isMostPopular && !isCurrent ? 'btn-primary' : 'btn-secondary'}`}
            style={{ width: '100%' }}
            disabled={busy || disabled || isCurrent || (!free && !price)}
            onClick={() => onChoose(plan, price)}
          >
            {isCurrent ? 'Current plan' : ctaLabel ? ctaLabel(plan) : `Choose ${plan.name}`}
          </button>
        </div>
      )}
    </div>
  );
}

/** The whole ladder: term toggle, currency picker and the cards. */
export function PlanLadder({
  plans,
  currency,
  currencies,
  onCurrencyChange,
  currentPlanCode,
  ctaLabel,
  onChoose,
  busy,
  initialPeriod = 'Annual',
}: {
  plans: Plan[];
  currency: string;
  currencies?: string[];
  onCurrencyChange?: (c: string) => void;
  currentPlanCode?: string;
  ctaLabel?: (plan: Plan) => string;
  onChoose?: (plan: Plan, price: PlanPrice | null, period: BillingPeriod) => void;
  busy?: boolean;
  /* Annual first. It is the best-value rung, and anchoring on it means the
     monthly price reads as the expensive option rather than the default. */
  initialPeriod?: BillingPeriod;
}) {
  const [period, setPeriod] = useState<BillingPeriod>(initialPeriod);

  return (
    <div className="sub-stack" style={{ gap: 18 }}>
      <div className="sub-spread">
        <TermToggle plans={plans} period={period} onChange={setPeriod} />
        {currencies && currencies.length > 1 && onCurrencyChange && (
          <label className="sub-row sub-small">
            <span className="sub-muted">Currency</span>
            <select
              className="input"
              value={currency}
              onChange={(e) => onCurrencyChange(e.target.value)}
              style={{ width: 'auto' }}
            >
              {currencies.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>

      <div className="sub-plans">
        {plans.map((plan) => (
          <PlanCard
            key={plan.code}
            plan={plan}
            period={period}
            currency={currency}
            currentPlanCode={currentPlanCode}
            ctaLabel={ctaLabel}
            busy={busy}
            onChoose={onChoose ? (p, price) => onChoose(p, price, period) : undefined}
          />
        ))}
      </div>
    </div>
  );
}
