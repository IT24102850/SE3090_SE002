import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type Invoice } from '../billingApi';
import { date, downloadBlob, money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import InvoiceDetailModal from '../components/InvoiceDetailModal';
import PaymentFlowModal from '../components/PaymentFlowModal';
import '../billing.css';

type Tab = 'bills' | 'memberships' | 'claims';

/* The customer's side of billing - the web twin of the Flutter "My Bills",
 * "Subscription" and "Insurance tracker" screens. */
export default function MyBillsPage() {
  const toast = useToast();
  const [tab, setTab] = useState<Tab>('bills');
  const [filter, setFilter] = useState<'open' | 'all'>('open');
  const [viewing, setViewing] = useState<Invoice | null>(null);
  const [paying, setPaying] = useState<Invoice | null>(null);

  const bills = useAsync(() => billingApi.myInvoices(), []);
  const subs = useAsync(() => billingApi.listSubscriptions({ pageSize: 50 }), []);
  const claims = useAsync(() => billingApi.listClaims(undefined, 50), []);

  const all = bills.data?.items ?? [];
  const open = all.filter((i) => ['Issued', 'PartiallyPaid', 'Overdue'].includes(i.status));
  const shown = filter === 'open' ? open : all;
  const owed = open.reduce((s, i) => s + i.balanceDue, 0);
  const currency = all[0]?.currency ?? 'LKR';

  const pdf = async (inv: Invoice) => {
    try {
      downloadBlob(await billingApi.receiptPdf(inv.id), `${inv.amountPaid > 0 ? 'REC-' : ''}${inv.invoiceNumber}.pdf`);
    } catch (err) {
      toast.show(errorMessage(err, 'Could not download the receipt.'), 'error');
    }
  };

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">My bills</h1>
          <p className="page-subtitle">Pay what you owe, download receipts, and keep track of your memberships and insurance claims.</p>
        </div>
      </div>

      <div className="bl-kpis">
        <div className="bl-kpi"><div className="bl-kpi-label">You owe</div><div className="bl-kpi-value">{money(owed, currency)}</div><div className="bl-kpi-sub">{open.length} open bills</div></div>
        <div className="bl-kpi"><div className="bl-kpi-label">Overdue</div><div className="bl-kpi-value" style={{ color: open.some((i) => i.isOverdue) ? 'var(--color-critical)' : undefined }}>{open.filter((i) => i.isOverdue).length}</div></div>
        <div className="bl-kpi"><div className="bl-kpi-label">Memberships</div><div className="bl-kpi-value">{subs.data?.items.filter((s) => s.status === 'Active').length ?? '…'}</div></div>
      </div>

      <div className="bl-tabs" role="tablist">
        <button role="tab" className="bl-tab" aria-selected={tab === 'bills'} onClick={() => setTab('bills')}>Bills</button>
        <button role="tab" className="bl-tab" aria-selected={tab === 'memberships'} onClick={() => setTab('memberships')}>Memberships</button>
        <button role="tab" className="bl-tab" aria-selected={tab === 'claims'} onClick={() => setTab('claims')}>Insurance claims</button>
      </div>

      {tab === 'bills' && (
        <>
          <div className="bl-row">
            <button className={`btn btn-sm ${filter === 'open' ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setFilter('open')}>To pay</button>
            <button className={`btn btn-sm ${filter === 'all' ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setFilter('all')}>All bills</button>
          </div>
          {bills.error && <div className="bl-notice bl-notice-critical">{bills.error}</div>}
          {bills.loading && !bills.data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}
          {bills.data && shown.length === 0 && <div className="bl-empty">{filter === 'open' ? 'You are all paid up.' : 'No bills yet.'}</div>}
          <ul className="bl-list">
            {shown.map((inv) => (
              <li key={inv.id} className="bl-list-item">
                <div className="bl-spread">
                  <div>
                    <strong>{inv.invoiceNumber}</strong>{inv.scheduleLabel && <span className="bl-muted"> · {inv.scheduleLabel}</span>}
                    <div className="bl-small bl-muted">{inv.items.map((i) => i.description).join(', ')}</div>
                  </div>
                  <StatusBadge status={inv.status} />
                </div>
                <div className="bl-spread">
                  <span className="bl-small bl-muted">Due {date(inv.dueDate)} · total {money(inv.finalAmount, inv.currency)}</span>
                  <div className="bl-row">
                    <button className="btn btn-ghost btn-sm" onClick={() => setViewing(inv)}>Details</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => pdf(inv)}>{inv.amountPaid > 0 ? 'Receipt PDF' : 'PDF'}</button>
                    {inv.balanceDue > 0 && inv.status !== 'Cancelled' && (
                      <button className="btn btn-primary btn-sm" onClick={() => setPaying(inv)}>Pay {money(inv.balanceDue, inv.currency)}</button>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      {tab === 'memberships' && (
        <ul className="bl-list">
          {(subs.data?.items ?? []).map((s) => (
            <li key={s.id} className="bl-list-item">
              <div className="bl-spread"><strong>{s.planName}</strong><StatusBadge status={s.status} /></div>
              <span>{money(s.amount)} {s.billingCycle.toLowerCase()} · {s.autoRenew ? `renews ${date(s.nextBillingAt ?? s.endDate)}` : `ends ${date(s.endDate)}`}</span>
            </li>
          ))}
          {subs.data && subs.data.items.length === 0 && <div className="bl-empty">No memberships.</div>}
        </ul>
      )}

      {tab === 'claims' && (
        <div className="bl-stack">
          <Link className="btn btn-secondary btn-sm" style={{ width: 'fit-content' }} to="/insurance-claims">Open the claim tracker</Link>
          <ul className="bl-list">
            {(claims.data?.items ?? []).map((c) => (
              <li key={c.id} className="bl-list-item">
                <div className="bl-spread"><strong>{c.provider} · {money(c.claimAmount, c.currency ?? 'LKR')}</strong><StatusBadge status={c.status} /></div>
                <span className="bl-small bl-muted">{c.invoiceNumber} · submitted {date(c.submittedAt)}</span>
                {c.rejectionReason && <span className="bl-field-error">{c.rejectionReason}</span>}
              </li>
            ))}
            {claims.data && claims.data.items.length === 0 && <div className="bl-empty">No claims.</div>}
          </ul>
        </div>
      )}

      {viewing && (
        <InvoiceDetailModal invoice={viewing} canManage={false} canCancel={false} onClose={() => setViewing(null)} onChanged={() => bills.reload()} />
      )}
      {paying && (
        <PaymentFlowModal invoice={paying} onClose={() => setPaying(null)} onPaid={() => bills.reload()} />
      )}
    </div>
  );
}
