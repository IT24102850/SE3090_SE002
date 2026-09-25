import { useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import type { RootState } from '../../../store/store';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type CustomerOption, type Subscription } from '../billingApi';
import { addDays, date, isoDay, money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

type View = 'list' | 'calendar' | 'requests';
const CYCLES = ['Weekly', 'Monthly', 'Quarterly', 'Yearly', 'OneOff'];

export default function SubscriptionManagerPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const toast = useToast();
  const [view, setView] = useState<View>('list');
  const [status, setStatus] = useState('Active');
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<{ sub: Subscription; mode: 'cancel' | 'plan' } | null>(null);
  const [month, setMonth] = useState(() => { const d = new Date(); d.setDate(1); return d; });

  const subs = useAsync(() => billingApi.listSubscriptions({ status: status === 'All' ? undefined : status, pageSize: 100 }), [status]);
  const requests = useAsync(() => billingApi.listSubscriptions({ status: 'PendingCancel', pageSize: 100 }), []);

  const monthStart = new Date(month);
  const gridStart = addDays(monthStart, -((monthStart.getDay() + 6) % 7)); // Monday first
  const gridEnd = addDays(gridStart, 41);
  const renewals = useAsync(() => billingApi.renewals(isoDay(gridStart), isoDay(gridEnd)), [isoDay(gridStart)]);

  const refresh = () => { subs.reload(); requests.reload(); renewals.reload(); };

  const byDay = useMemo(() => {
    const map = new Map<string, NonNullable<typeof renewals.data>>();
    for (const r of renewals.data ?? []) {
      const key = isoDay(new Date(r.renewalDate));
      map.set(key, [...(map.get(key) ?? []), r]);
    }
    return map;
  }, [renewals.data]);

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Subscriptions</h1>
          <p className="page-subtitle">Memberships and recurring fees - renewals run automatically and raise their own invoices.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>+ New subscription</button>
      </div>

      <div className="bl-tabs" role="tablist">
        <button role="tab" className="bl-tab" aria-selected={view === 'list'} onClick={() => setView('list')}>Subscriptions</button>
        <button role="tab" className="bl-tab" aria-selected={view === 'calendar'} onClick={() => setView('calendar')}>Renewal calendar</button>
        <button role="tab" className="bl-tab" aria-selected={view === 'requests'} onClick={() => setView('requests')}>
          Cancellation requests<span className="bl-tab-count">{requests.data?.totalCount ?? ''}</span>
        </button>
      </div>

      {view === 'list' && (
        <>
          <div className="bl-row">
            {['Active', 'PendingCancel', 'Cancelled', 'Expired', 'All'].map((s) => (
              <button key={s} className={`btn btn-sm ${status === s ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setStatus(s)}>
                {s === 'PendingCancel' ? 'Pending cancel' : s}
              </button>
            ))}
          </div>
          {subs.error && <div className="bl-notice bl-notice-critical">{subs.error}</div>}
          <SubscriptionTable rows={subs.data?.items ?? []} loading={subs.loading} onCancel={(sub) => setEditing({ sub, mode: 'cancel' })} onPlan={(sub) => setEditing({ sub, mode: 'plan' })} />
        </>
      )}

      {view === 'calendar' && (
        <div className="card" style={{ padding: 16 }}>
          <div className="bl-spread" style={{ marginBottom: 12 }}>
            <button className="btn btn-ghost btn-sm" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}>‹ Previous</button>
            <strong>{month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</strong>
            <button className="btn btn-ghost btn-sm" onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}>Next ›</button>
          </div>
          <div className="bl-cal" role="grid" aria-label="Renewal calendar">
            {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => <div key={d} className="bl-cal-dow">{d}</div>)}
            {Array.from({ length: 42 }, (_, i) => {
              const day = addDays(gridStart, i);
              const key = isoDay(day);
              const entries = byDay.get(key) ?? [];
              const out = day.getMonth() !== month.getMonth();
              const today = key === isoDay();
              return (
                <div key={key} className={`bl-cal-day${out ? ' bl-out' : ''}${today ? ' bl-today' : ''}`} role="gridcell">
                  <span className="bl-cal-num">{day.getDate()}</span>
                  {entries.slice(0, 3).map((e) => (
                    <span key={e.subscriptionId} className={`bl-cal-chip${e.autoRenew ? '' : ' bl-chip-warning'}`}
                      title={`${e.customerName ?? ''} · ${e.planName} · ${money(e.amount)} · ${e.autoRenew ? 'auto-renews' : 'ends'}`}>
                      {e.autoRenew ? '↻' : '⏹'} {e.customerName ?? e.planName}
                    </span>
                  ))}
                  {entries.length > 3 && <span className="bl-small bl-muted">+{entries.length - 3} more</span>}
                </div>
              );
            })}
          </div>
          <p className="bl-small bl-muted" style={{ marginTop: 8 }}>↻ renews automatically (an invoice is raised) · ⏹ ends without renewing</p>
        </div>
      )}

      {view === 'requests' && (
        <div className="bl-stack">
          <div className="bl-notice bl-small">
            Cancellations with a refund need an Admin's approval. Approve or reject them in the <Link to="/billing-agent">billing agent monitor</Link>.
          </div>
          <SubscriptionTable rows={requests.data?.items ?? []} loading={requests.loading} />
        </div>
      )}

      {creating && <CreateSubscriptionModal onClose={() => setCreating(false)} onCreated={() => { setCreating(false); refresh(); toast.show('Subscription created.', 'success'); }} />}
      {editing?.mode === 'cancel' && (
        <CancelModal sub={editing.sub} isAdmin={user?.role === 'Admin'} onClose={() => setEditing(null)} onDone={(msg, tone) => { setEditing(null); refresh(); toast.show(msg, tone); }} />
      )}
      {editing?.mode === 'plan' && (
        <ChangePlanModal sub={editing.sub} onClose={() => setEditing(null)} onDone={() => { setEditing(null); refresh(); toast.show('Plan changed.', 'success'); }} />
      )}
    </div>
  );
}

function SubscriptionTable({ rows, loading, onCancel, onPlan }: {
  rows: Subscription[];
  loading: boolean;
  onCancel?: (s: Subscription) => void;
  onPlan?: (s: Subscription) => void;
}) {
  return (
    <div className="bl-table-wrap">
      <table className="bl-table">
        <thead>
          <tr><th>Member</th><th>Plan</th><th className="bl-num">Amount</th><th>Period</th><th>Next billing</th><th>Status</th><th>Payment</th>{onCancel && <th />}</tr>
        </thead>
        <tbody>
          {loading && rows.length === 0 && <tr><td colSpan={8}><div className="loading-row"><span className="spinner spinner-dark" /></div></td></tr>}
          {rows.map((s) => (
            <tr key={s.id}>
              <td>{s.customerName ?? '—'}</td>
              <td>{s.planName}<div className="bl-small bl-muted">{s.billingCycle}{s.autoRenew ? ' · auto-renew' : ''}</div></td>
              <td className="bl-num">{money(s.amount)}</td>
              <td className="bl-small">{date(s.startDate)} – {date(s.endDate)}</td>
              <td>{date(s.nextBillingAt)}</td>
              <td><StatusBadge status={s.status} /></td>
              <td><StatusBadge status={s.paymentStatus} /></td>
              {onCancel && (
                <td>
                  {s.status === 'Active' && (
                    <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => onPlan?.(s)}>Change plan</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => onCancel(s)}>Cancel</button>
                    </div>
                  )}
                </td>
              )}
            </tr>
          ))}
          {!loading && rows.length === 0 && <tr><td colSpan={8}><div className="bl-empty">Nothing here.</div></td></tr>}
        </tbody>
      </table>
    </div>
  );
}

function CreateSubscriptionModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const toast = useToast();
  const [customers, setCustomers] = useState<CustomerOption[]>([]);
  const [form, setForm] = useState({
    customerId: '', planName: '', amount: '', billingCycle: 'Monthly', startDate: isoDay(), endDate: isoDay(addDays(new Date(), 30)),
    autoRenew: true, generateInvoice: true, currency: 'LKR', notes: '',
  });
  const [saving, setSaving] = useState(false);
  useEffect(() => { billingApi.customers().then(setCustomers).catch(() => setCustomers([])); }, []);

  // Keep the end date in step with the cycle unless it was edited by hand.
  const setCycle = (cycle: string) => {
    const start = new Date(`${form.startDate}T00:00:00`);
    const end = cycle === 'Weekly' ? addDays(start, 7) : cycle === 'Quarterly' ? new Date(start.getFullYear(), start.getMonth() + 3, start.getDate())
      : cycle === 'Yearly' ? new Date(start.getFullYear() + 1, start.getMonth(), start.getDate()) : cycle === 'OneOff' ? addDays(start, 1)
      : new Date(start.getFullYear(), start.getMonth() + 1, start.getDate());
    setForm({ ...form, billingCycle: cycle, endDate: isoDay(end), autoRenew: cycle !== 'OneOff' && form.autoRenew });
  };

  const valid = form.customerId && form.planName.trim() && Number(form.amount) >= 0 && form.amount !== '' && form.endDate > form.startDate;

  const save = async () => {
    setSaving(true);
    try {
      await billingApi.createSubscription({
        ...form,
        amount: Number(form.amount),
        startDate: new Date(`${form.startDate}T00:00:00`).toISOString(),
        endDate: new Date(`${form.endDate}T00:00:00`).toISOString(),
        notes: form.notes || undefined,
      });
      onCreated();
    } catch (err) {
      toast.show(errorMessage(err, 'The subscription could not be created.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="New subscription" onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={!valid || saving} onClick={save}>{saving ? 'Saving…' : 'Create'}</button>
      </>
    }>
      <div className="bl-form">
        <div className="bl-grid-2">
          <label className="bl-field"><span>Member</span>
            <select className="input" value={form.customerId} onChange={(e) => setForm({ ...form, customerId: e.target.value })}>
              <option value="">Choose…</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.fullName}</option>)}
            </select>
          </label>
          <label className="bl-field"><span>Plan</span>
            <input className="input" value={form.planName} maxLength={100} placeholder="Standard, Premium, Grade 10 tuition…" onChange={(e) => setForm({ ...form, planName: e.target.value })} />
          </label>
          <label className="bl-field"><span>Amount per cycle</span>
            <input className="input" type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
          </label>
          <label className="bl-field"><span>Billing cycle</span>
            <select className="input" value={form.billingCycle} onChange={(e) => setCycle(e.target.value)}>
              {CYCLES.map((c) => <option key={c} value={c}>{c === 'OneOff' ? 'One-off / day pass' : c}</option>)}
            </select>
          </label>
          <label className="bl-field"><span>Starts</span>
            <input className="input" type="date" value={form.startDate} onChange={(e) => setForm({ ...form, startDate: e.target.value })} />
          </label>
          <label className="bl-field"><span>First period ends</span>
            <input className="input" type="date" value={form.endDate} onChange={(e) => setForm({ ...form, endDate: e.target.value })} />
          </label>
        </div>
        <label className="bl-row"><input type="checkbox" checked={form.autoRenew} disabled={form.billingCycle === 'OneOff'} onChange={(e) => setForm({ ...form, autoRenew: e.target.checked })} /> Renew automatically</label>
        <label className="bl-row"><input type="checkbox" checked={form.generateInvoice} onChange={(e) => setForm({ ...form, generateInvoice: e.target.checked })} /> Invoice the first period now</label>
      </div>
    </Modal>
  );
}

function CancelModal({ sub, isAdmin, onClose, onDone }: { sub: Subscription; isAdmin: boolean; onClose: () => void; onDone: (msg: string, tone: 'success' | 'warning') => void }) {
  const toast = useToast();
  const [reason, setReason] = useState('');
  const [refund, setRefund] = useState('');
  const [saving, setSaving] = useState(false);
  const refundNum = Number(refund) || 0;

  const save = async () => {
    setSaving(true);
    try {
      const result = await billingApi.cancelSubscription(sub.id, { reason: reason || undefined, refundAmount: refundNum });
      onDone(result.message, result.requiresApproval ? 'warning' : 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'The subscription could not be cancelled.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={`Cancel ${sub.planName} for ${sub.customerName ?? 'member'}`} onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Keep it</button>
        <button className="btn btn-danger" disabled={saving} onClick={save}>{refundNum > 0 && !isAdmin ? 'Request cancellation' : 'Cancel subscription'}</button>
      </>
    }>
      <div className="bl-form">
        <label className="bl-field"><span>Reason</span><input className="input" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} /></label>
        <label className="bl-field"><span>Refund (optional)</span>
          <input className="input" type="number" min={0} step="0.01" value={refund} onChange={(e) => setRefund(e.target.value)} />
        </label>
        {refundNum > 0 && (
          <div className="bl-notice bl-notice-warning bl-small">
            {isAdmin ? 'As an Admin, this refund is approved as you submit it and recorded in the audit trail.' : 'A cancellation with a refund needs an Admin to approve it. The membership stays active until then.'}
          </div>
        )}
      </div>
    </Modal>
  );
}

function ChangePlanModal({ sub, onClose, onDone }: { sub: Subscription; onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const { data: plans } = useAsync(() => billingApi.planOptions(), []);
  const [planName, setPlanName] = useState(sub.planName);
  const [amount, setAmount] = useState(String(sub.amount));
  const [saving, setSaving] = useState(false);
  const upgrade = Number(amount) > sub.amount;

  const save = async () => {
    setSaving(true);
    try {
      await billingApi.changePlan(sub.id, { planName, amount: Number(amount) });
      onDone();
    } catch (err) {
      toast.show(errorMessage(err, 'The plan could not be changed.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="Change plan" onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={saving || !planName.trim()} onClick={save}>Change plan</button>
      </>
    }>
      <div className="bl-form">
        {plans && plans.length > 0 && (
          <div className="bl-row">
            {plans.filter((p) => p.billingCycle === sub.billingCycle).map((p) => (
              <button key={`${p.planName}-${p.amount}`} className="btn btn-ghost btn-sm" onClick={() => { setPlanName(p.planName); setAmount(String(p.amount)); }}>
                {p.planName} · {money(p.amount)}
              </button>
            ))}
          </div>
        )}
        <div className="bl-grid-2">
          <label className="bl-field"><span>Plan</span><input className="input" value={planName} onChange={(e) => setPlanName(e.target.value)} /></label>
          <label className="bl-field"><span>Amount per {sub.billingCycle.toLowerCase()}</span><input className="input" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></label>
        </div>
        <div className="bl-notice bl-small">
          {upgrade ? 'An upgrade is charged pro rata for the rest of the current period - an invoice is raised now.' : 'A downgrade takes effect from the next renewal.'}
        </div>
      </div>
    </Modal>
  );
}
