import { useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../store/store';
import { billingApi, errorMessage, type Subscription } from '../billing/billingApi';
import { date, money } from '../billing/format';
import '../billing/billing.css';
import './customer.css';

export default function CustomerSubscriptionsPage() {
  const user = useSelector((state: RootState) => state.auth.user);
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError('');
    try {
      const result = await billingApi.listSubscriptions({ pageSize: 100 });
      setSubscriptions(result.items);
    } catch (err) {
      setError(errorMessage(err, 'We could not load your subscriptions.'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const requestCancellation = async (subscription: Subscription) => {
    if (!window.confirm('Request cancellation for this subscription?')) return;
    setBusyId(subscription.id);
    try {
      await billingApi.cancelSubscription(subscription.id, { reason: 'Customer requested cancellation' });
      await load();
    } catch (err) {
      setError(errorMessage(err, 'We could not submit the cancellation request.'));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="cust-page bl-page">
      <div className="page-header">
        <div>
          <p className="cust-eyebrow">YOUR MEMBERSHIPS</p>
          <h1 className="page-title">My subscriptions</h1>
          <p className="page-subtitle">View your active memberships, renewal dates and payment status.</p>
        </div>
      </div>

      {error && <div className="bl-notice bl-notice-critical" role="alert">{error}</div>}
      {loading ? (
        <div className="card cust-shop-message" aria-busy="true"><span className="spinner spinner-dark" /> Loading subscriptions…</div>
      ) : subscriptions.length === 0 ? (
        <div className="card cust-empty-state">
          <h2>No subscriptions yet</h2>
          <p>Your business memberships will appear here after they are created.</p>
        </div>
      ) : (
        <div className="bl-stack">
          {subscriptions.map((subscription) => (
            <article className="card cust-booking-card" key={subscription.id}>
              <div className="cust-spread">
                <div>
                  <h2>{subscription.planName}</h2>
                  <p className="bl-muted">{subscription.billingCycle} · {subscription.customerName ?? user?.email ?? 'Customer'}</p>
                </div>
                <span className={`status-badge status-${subscription.status.toLowerCase()}`}>{subscription.status}</span>
              </div>
              <div className="cust-booking-meta">
                <span><strong>{money(subscription.amount)}</strong> per {subscription.billingCycle.toLowerCase()}</span>
                <span>Started {date(subscription.startDate)}</span>
                <span>{subscription.nextBillingAt ? `Renews ${date(subscription.nextBillingAt)}` : `Ends ${date(subscription.endDate)}`}</span>
                <span>Payment: {subscription.paymentStatus}</span>
              </div>
              {subscription.status === 'Active' && (
                <div className="cust-booking-actions">
                  <button className="btn btn-secondary" type="button" disabled={busyId === subscription.id} onClick={() => void requestCancellation(subscription)}>
                    {busyId === subscription.id ? 'Submitting…' : 'Request cancellation'}
                  </button>
                </div>
              )}
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
