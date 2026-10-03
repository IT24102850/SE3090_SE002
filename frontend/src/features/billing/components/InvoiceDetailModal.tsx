import { useState } from 'react';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type Invoice, type Receipt } from '../billingApi';
import { date, dateTime, downloadBlob, money } from '../format';
import StatusBadge from './StatusBadge';
import PaymentFlowModal from './PaymentFlowModal';
import InvoicePaper from './InvoicePaper';

type Panel = 'none' | 'record' | 'split' | 'adjust' | 'send' | 'receipt';

interface Props {
  invoice: Invoice;
  canManage: boolean;   // Staff+ : record payments, adjust, send
  canCancel: boolean;   // Manager+
  onClose: () => void;
  onChanged: (invoice: Invoice) => void;
}

export default function InvoiceDetailModal({ invoice: initial, canManage, canCancel, onClose, onChanged }: Props) {
  const toast = useToast();
  const [invoice, setInvoice] = useState(initial);
  const [panel, setPanel] = useState<Panel>('none');
  const [busy, setBusy] = useState(false);
  const [paying, setPaying] = useState(false);
  const [receipt, setReceipt] = useState<Receipt | null>(null);

  const [payAmount, setPayAmount] = useState('');
  const [payMethod, setPayMethod] = useState('Cash');
  const [payRef, setPayRef] = useState('');
  const [shares, setShares] = useState([{ amount: '', method: 'Cash', payerLabel: '' }, { amount: '', method: 'Card', payerLabel: '' }]);
  const [adjDiscount, setAdjDiscount] = useState(String(initial.discount));
  const [adjTax, setAdjTax] = useState(String(initial.tax));
  const [adjReason, setAdjReason] = useState('');
  const [channel, setChannel] = useState('Email');

  const open = ['Issued', 'PartiallyPaid', 'Overdue'].includes(invoice.status);
  const changed = (next: Invoice) => {
    setInvoice(next);
    onChanged(next);
  };

  const run = async (label: string, action: () => Promise<void>) => {
    setBusy(true);
    try {
      await action();
    } catch (err) {
      toast.show(errorMessage(err, `${label} failed.`), 'error');
    } finally {
      setBusy(false);
    }
  };

  const recordPayment = () => run('Recording the payment', async () => {
    const amount = payAmount.trim() ? Number(payAmount) : invoice.balanceDue;
    const result = await billingApi.recordPayment(invoice.id, { amount, method: payMethod, transactionRef: payRef || undefined });
    changed(result.invoice);
    setPanel('none');
    setPayAmount('');
    toast.show(`${money(amount, invoice.currency)} recorded.`, 'success');
  });

  const splitPay = () => run('Splitting the bill', async () => {
    const valid = shares.filter((s) => Number(s.amount) > 0);
    const result = await billingApi.splitPay(invoice.id, valid.map((s) => ({ amount: Number(s.amount), method: s.method, payerLabel: s.payerLabel || undefined })));
    changed(result);
    setPanel('none');
    toast.show(`Bill split ${valid.length} ways.`, 'success');
  });

  const evenSplit = (ways: number) => {
    const each = Math.floor((invoice.balanceDue / ways) * 100) / 100;
    const last = Math.round((invoice.balanceDue - each * (ways - 1)) * 100) / 100;
    setShares(Array.from({ length: ways }, (_, i) => ({ amount: String(i === ways - 1 ? last : each), method: 'Card', payerLabel: `Guest ${i + 1}` })));
  };

  const adjust = () => run('The adjustment', async () => {
    const result = await billingApi.adjustInvoice(invoice.id, { discount: Number(adjDiscount), tax: Number(adjTax), reason: adjReason });
    if (result.applied) changed(result.invoice);
    toast.show(result.message, result.requiresApproval ? 'warning' : 'success');
    setPanel('none');
  });

  const cancel = () => run('Cancelling', async () => {
    const reason = window.prompt('Why is this invoice being cancelled?') ?? undefined;
    changed(await billingApi.cancelInvoice(invoice.id, reason));
    toast.show('Invoice cancelled.', 'success');
  });

  const send = (reminder: boolean) => run('Sending', async () => {
    const result = reminder ? await billingApi.remind(invoice.id, channel) : await billingApi.send(invoice.id, channel);
    if (result.delivered) toast.show(`${reminder ? 'Reminder' : 'Invoice'} sent to ${result.recipient}.`, 'success');
    else if (result.simulated) toast.show(`${result.channel} is not configured on the server - the message to ${result.recipient} was logged, not sent.`, 'warning');
    else toast.show(result.error ?? 'The message could not be sent.', 'error');
    setPanel('none');
  });

  const pdf = () => run('Downloading the PDF', async () => {
    downloadBlob(await billingApi.receiptPdf(invoice.id), `${invoice.amountPaid > 0 ? 'REC-' : ''}${invoice.invoiceNumber}.pdf`);
  });

  const showReceipt = () => run('Loading the receipt', async () => {
    setReceipt(await billingApi.receipt(invoice.id));
    setPanel('receipt');
  });

  const shareTotal = shares.reduce((s, x) => s + (Number(x.amount) || 0), 0);

  return (
    <>
      <Modal title={invoice.invoiceNumber} onClose={onClose}>
        <div className="bl-stack">
          <div className="bl-spread">
            <div>
              <div style={{ fontWeight: 700, fontSize: 16 }}>{invoice.customerName ?? 'Customer'}</div>
              <div className="bl-muted bl-small">
                Issued {date(invoice.createdAt)} · due {date(invoice.dueDate)}
                {invoice.scheduleLabel && ` · ${invoice.scheduleLabel}`}
              </div>
            </div>
            <StatusBadge status={invoice.status} />
          </div>

          <div className="bl-kpis">
            <div className="bl-kpi"><div className="bl-kpi-label">Total</div><div className="bl-kpi-value">{money(invoice.finalAmount, invoice.currency)}</div></div>
            <div className="bl-kpi"><div className="bl-kpi-label">Paid</div><div className="bl-kpi-value">{money(invoice.amountPaid, invoice.currency)}</div></div>
            <div className="bl-kpi"><div className="bl-kpi-label">Balance</div><div className="bl-kpi-value">{money(invoice.balanceDue, invoice.currency)}</div></div>
          </div>

          <div className="bl-table-wrap">
            <table className="bl-table">
              <thead><tr><th>Item</th><th className="bl-num">Qty</th><th className="bl-num">Price</th><th className="bl-num">Amount</th></tr></thead>
              <tbody>
                {invoice.items.map((i) => (
                  <tr key={i.id}><td>{i.description}<div className="bl-small bl-muted">{i.category}</div></td><td className="bl-num">{i.quantity}</td><td className="bl-num">{i.unitPrice.toFixed(2)}</td><td className="bl-num">{i.amount.toFixed(2)}</td></tr>
                ))}
                {invoice.discount > 0 && <tr><td colSpan={3}>Discount{invoice.discountCode ? ` (${invoice.discountCode})` : ''}</td><td className="bl-num">-{invoice.discount.toFixed(2)}</td></tr>}
                {invoice.tax > 0 && <tr><td colSpan={3}>Tax</td><td className="bl-num">{invoice.tax.toFixed(2)}</td></tr>}
              </tbody>
            </table>
          </div>

          {invoice.payments.length > 0 && (
            <div className="bl-stack">
              <span className="bl-label">Payments</span>
              <ul className="bl-list">
                {invoice.payments.map((p) => (
                  <li key={p.id} className="bl-list-item">
                    <div className="bl-spread">
                      <span>{p.method}{p.payerLabel ? ` · ${p.payerLabel}` : ''}{p.provider && p.provider !== 'Manual' ? ` · ${p.provider}` : ''}</span>
                      <span className="bl-row"><StatusBadge status={p.status} /><strong className="bl-num">{money(p.amount, invoice.currency)}</strong></span>
                    </div>
                    <span className="bl-small bl-muted">{dateTime(p.paidAt ?? p.createdAt)}{p.transactionRef ? ` · ${p.transactionRef}` : ''}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {invoice.notes && <div className="bl-notice bl-small" style={{ whiteSpace: 'pre-wrap' }}>{invoice.notes}</div>}

          <div className="bl-row">
            {open && <button className="btn btn-primary btn-sm" onClick={() => setPaying(true)}>Pay online</button>}
            {canManage && open && <button className="btn btn-secondary btn-sm" onClick={() => setPanel(panel === 'record' ? 'none' : 'record')}>Record payment</button>}
            {canManage && open && <button className="btn btn-secondary btn-sm" onClick={() => { evenSplit(2); setPanel(panel === 'split' ? 'none' : 'split'); }}>Split bill</button>}
            <button className="btn btn-secondary btn-sm" onClick={showReceipt} disabled={busy}>Receipt</button>
            <button className="btn btn-secondary btn-sm" onClick={pdf} disabled={busy}>PDF</button>
            {canManage && <button className="btn btn-secondary btn-sm" onClick={() => setPanel(panel === 'send' ? 'none' : 'send')}>Send</button>}
            {canManage && invoice.status !== 'Cancelled' && <button className="btn btn-ghost btn-sm" onClick={() => setPanel(panel === 'adjust' ? 'none' : 'adjust')}>Adjust</button>}
            {canCancel && open && invoice.amountPaid === 0 && <button className="btn btn-danger btn-sm" onClick={cancel} disabled={busy}>Cancel invoice</button>}
          </div>

          {panel === 'record' && (
            <div className="card bl-stack" style={{ padding: 14 }}>
              <div className="bl-grid-3">
                <label className="bl-field"><span>Amount</span>
                  <input className="input" type="number" min={0} step="0.01" placeholder={invoice.balanceDue.toFixed(2)} value={payAmount} onChange={(e) => setPayAmount(e.target.value)} />
                </label>
                <label className="bl-field"><span>Method</span>
                  <select className="input" value={payMethod} onChange={(e) => setPayMethod(e.target.value)}>
                    {['Cash', 'Card', 'Bank transfer', 'Cheque', 'QR'].map((m) => <option key={m}>{m}</option>)}
                  </select>
                </label>
                <label className="bl-field"><span>Reference</span>
                  <input className="input" value={payRef} maxLength={200} onChange={(e) => setPayRef(e.target.value)} />
                </label>
              </div>
              <div><button className="btn btn-primary btn-sm" onClick={recordPayment} disabled={busy}>Record</button></div>
            </div>
          )}

          {panel === 'split' && (
            <div className="card bl-stack" style={{ padding: 14 }}>
              <div className="bl-row">
                <span className="bl-label">Split evenly:</span>
                {[2, 3, 4, 5, 6].map((n) => <button key={n} className="btn btn-ghost btn-sm" onClick={() => evenSplit(n)}>{n} ways</button>)}
              </div>
              {shares.map((s, i) => (
                <div key={i} className="bl-grid-3">
                  <input className="input" aria-label={`Share ${i + 1} payer`} placeholder={`Guest ${i + 1}`} value={s.payerLabel}
                    onChange={(e) => setShares(shares.map((x, j) => (j === i ? { ...x, payerLabel: e.target.value } : x)))} />
                  <input className="input" type="number" min={0} step="0.01" aria-label={`Share ${i + 1} amount`} value={s.amount}
                    onChange={(e) => setShares(shares.map((x, j) => (j === i ? { ...x, amount: e.target.value } : x)))} />
                  <select className="input" aria-label={`Share ${i + 1} method`} value={s.method}
                    onChange={(e) => setShares(shares.map((x, j) => (j === i ? { ...x, method: e.target.value } : x)))}>
                    {['Cash', 'Card', 'QR'].map((m) => <option key={m}>{m}</option>)}
                  </select>
                </div>
              ))}
              <div className="bl-spread">
                <button className="btn btn-ghost btn-sm" onClick={() => setShares([...shares, { amount: '', method: 'Card', payerLabel: '' }])}>+ Add share</button>
                <span className={Math.abs(shareTotal - invoice.balanceDue) > 0.005 && shareTotal > invoice.balanceDue ? 'bl-field-error' : 'bl-muted'}>
                  {money(shareTotal, invoice.currency)} of {money(invoice.balanceDue, invoice.currency)}
                </span>
              </div>
              <div><button className="btn btn-primary btn-sm" onClick={splitPay} disabled={busy || shareTotal <= 0 || shareTotal > invoice.balanceDue + 0.005}>Record all shares</button></div>
            </div>
          )}

          {panel === 'adjust' && (
            <div className="card bl-stack" style={{ padding: 14 }}>
              <div className="bl-notice bl-small">Changes that move the payable amount by more than 100 go to an Admin for approval.</div>
              <div className="bl-grid-3">
                <label className="bl-field"><span>Discount</span><input className="input" type="number" min={0} step="0.01" value={adjDiscount} onChange={(e) => setAdjDiscount(e.target.value)} /></label>
                <label className="bl-field"><span>Tax</span><input className="input" type="number" min={0} step="0.01" value={adjTax} onChange={(e) => setAdjTax(e.target.value)} /></label>
                <label className="bl-field"><span>Reason</span><input className="input" value={adjReason} maxLength={500} onChange={(e) => setAdjReason(e.target.value)} /></label>
              </div>
              <div><button className="btn btn-primary btn-sm" onClick={adjust} disabled={busy || !adjReason.trim()}>Submit adjustment</button></div>
            </div>
          )}

          {panel === 'send' && (
            <div className="card bl-row" style={{ padding: 14 }}>
              <select className="input" style={{ width: 160 }} value={channel} onChange={(e) => setChannel(e.target.value)} aria-label="Channel">
                <option value="Email">Email (SendGrid)</option>
                <option value="Sms">SMS (Twilio)</option>
                <option value="WhatsApp">WhatsApp (Twilio)</option>
              </select>
              <button className="btn btn-primary btn-sm" onClick={() => send(false)} disabled={busy}>Send {invoice.amountPaid > 0 ? 'receipt' : 'invoice'}</button>
              {open && <button className="btn btn-secondary btn-sm" onClick={() => send(true)} disabled={busy}>Send payment reminder</button>}
            </div>
          )}

          {panel === 'receipt' && receipt && (
            <InvoicePaper
              data={{
                businessName: receipt.businessName ?? 'Receipt',
                title: receipt.totalPaid > 0 ? 'RECEIPT' : 'INVOICE',
                number: receipt.totalPaid > 0 ? receipt.receiptNumber : receipt.invoiceNumber,
                issuedAt: receipt.issuedAt,
                dueDate: receipt.dueDate,
                status: receipt.paymentStatus,
                customerName: receipt.customerName ?? '',
                customerEmail: receipt.customerEmail,
                currency: receipt.currency,
                items: receipt.items,
                subtotal: receipt.totalAmount,
                discount: receipt.discount,
                tax: receipt.tax,
                total: receipt.finalAmount,
                paid: receipt.totalPaid,
                balance: receipt.balanceDue,
                payments: receipt.payments,
                notes: receipt.notes,
              }}
              blocks={receipt.template?.layout?.length ? receipt.template.layout : undefined}
              accentColor={receipt.template?.accentColor}
              headerText={receipt.template?.headerText}
              footerText={receipt.template?.footerText}
            />
          )}
        </div>
      </Modal>

      {paying && (
        <PaymentFlowModal
          invoice={invoice}
          onClose={() => setPaying(false)}
          onPaid={(next) => changed(next)}
        />
      )}
    </>
  );
}
