import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import Modal from '../../shared/components/Modal';
import api from '../../api/axiosConfig';
import type { Paywall } from './subscriptionApi';
import './subscription.css';

/* The paywall, shown at the moment of need.
 *
 * Every plan gate on the backend answers 402 with a PaywallInfo body that
 * names what was blocked and the cheapest plan that unblocks it. One response
 * interceptor catches all of them, so a screen never has to know it is behind
 * a plan - it makes its call, and if the plan does not cover it the sheet
 * comes up over whatever the user was doing, explaining that one thing.
 *
 * Deliberately not a redirect to the pricing page: a person who gets bounced
 * out of the form they were filling in has lost their work and their train of
 * thought, and that is a worse outcome for them and for us. */

const PaywallContext = createContext<{ show: (p: Paywall) => void } | null>(null);

export function usePaywall() {
  const ctx = useContext(PaywallContext);
  if (!ctx) throw new Error('usePaywall must be used inside PaywallProvider');
  return ctx;
}

export function PaywallProvider({ children }: { children: ReactNode }) {
  const [paywall, setPaywall] = useState<Paywall | null>(null);
  const navigate = useNavigate();

  const show = useCallback((p: Paywall) => setPaywall(p), []);

  useEffect(() => {
    const id = api.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error?.response?.status === 402) {
          const body = error.response.data?.paywall as Paywall | undefined;
          if (body) setPaywall(body);
        }
        return Promise.reject(error);
      },
    );
    return () => {
      api.interceptors.response.eject(id);
    };
  }, []);

  const value = useMemo(() => ({ show }), [show]);

  return (
    <PaywallContext.Provider value={value}>
      {children}
      {paywall && <PaywallSheet paywall={paywall} onClose={() => setPaywall(null)} onGo={() => {
        setPaywall(null);
        navigate('/subscription');
      }} />}
    </PaywallContext.Provider>
  );
}

function headline(p: Paywall): string {
  switch (p.reason) {
    case 'cap':
      return 'You have used your plan allowance';
    case 'quota':
      return 'That is all of this month’s allowance';
    default:
      return 'This is part of a paid plan';
  }
}

function PaywallSheet({ paywall, onClose, onGo }: { paywall: Paywall; onClose: () => void; onGo: () => void }) {
  const body = paywallBody(paywall);

  return (
    <Modal title={headline(paywall)} onClose={onClose}>
      <div className="sub-paywall">
        <p className="sub-paywall-lead">{body}</p>

        {paywall.requiredPlanName && (
          <div className="sub-paywall-plan">
            <strong>{paywall.requiredPlanName}</strong>
            <span className="sub-small">
              The cheapest plan that covers this. You can change or cancel at any time, and whatever you have already
              paid for is credited first.
            </span>
          </div>
        )}

        {paywall.addOnCode && (
          <p className="sub-small sub-muted" style={{ margin: 0 }}>
            If you would rather not change plan, you can buy a one-off pack from the add-ons tab instead.
          </p>
        )}

        <div className="sub-row" style={{ justifyContent: 'flex-end' }}>
          <button className="btn btn-ghost" onClick={onClose}>
            Not now
          </button>
          <button className="btn btn-primary" onClick={onGo}>
            {paywall.requiredPlanName ? `See ${paywall.requiredPlanName}` : 'See plans'}
          </button>
        </div>
      </div>
    </Modal>
  );
}

function paywallBody(p: Paywall): string {
  if (p.reason === 'quota' && p.limit !== null && p.limit !== undefined) {
    return p.limit === 0
      ? `Your current plan does not include this. ${p.requiredPlanName ?? 'A paid plan'} does.`
      : `You have used all ${p.limit.toLocaleString()} this month. Everything already in your account keeps working — this is only about doing more of it right now.`;
  }
  if (p.reason === 'cap' && p.limit !== null && p.limit !== undefined) {
    return `Your plan allows ${p.limit.toLocaleString()}, and you are using ${(p.used ?? p.limit).toLocaleString()}. Nothing you have set up is affected.`;
  }
  return `This is not switched on for your current plan${p.requiredPlanName ? `, but it is part of ${p.requiredPlanName}` : ''}.`;
}
