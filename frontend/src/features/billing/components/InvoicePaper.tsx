import type { InvoiceItem, Payment, TemplateBlock, TemplateBlockType } from '../billingApi';
import { date, money } from '../format';

/* An invoice/receipt drawn as a document, block by block in the template's
 * order - the same blocks, order and visibility the PDF uses. */

export interface PaperData {
  businessName: string;
  title: string;            // RECEIPT | INVOICE
  number: string;
  issuedAt: string;
  dueDate: string;
  status: string;
  customerName: string;
  customerEmail?: string | null;
  currency: string;
  items: Pick<InvoiceItem, 'description' | 'quantity' | 'unitPrice' | 'amount' | 'category'>[];
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  paid: number;
  balance: number;
  payments: Pick<Payment, 'amount' | 'method' | 'paidAt' | 'createdAt' | 'status' | 'payerLabel'>[];
  notes?: string | null;
}

export const DEFAULT_BLOCKS: TemplateBlock[] = [
  { id: 'header', type: 'header', label: 'Header & title', visible: true },
  { id: 'businessInfo', type: 'businessInfo', label: 'Business name', visible: false },
  { id: 'invoiceMeta', type: 'invoiceMeta', label: 'Invoice details', visible: true },
  { id: 'customerInfo', type: 'customerInfo', label: 'Billed to', visible: true },
  { id: 'items', type: 'items', label: 'Line items', visible: true },
  { id: 'totals', type: 'totals', label: 'Totals', visible: true },
  { id: 'payments', type: 'payments', label: 'Payments received', visible: true },
  { id: 'notes', type: 'notes', label: 'Notes', visible: true },
  { id: 'footer', type: 'footer', label: 'Footer', visible: true },
];

export const SAMPLE_PAPER: PaperData = {
  businessName: 'Your Business',
  title: 'INVOICE',
  number: 'INV-20260923-A1B2C3',
  issuedAt: new Date().toISOString(),
  dueDate: new Date(Date.now() + 14 * 864e5).toISOString(),
  status: 'Issued',
  customerName: 'Nimal Perera',
  customerEmail: 'nimal@example.com',
  currency: 'LKR',
  items: [
    { description: 'Consultation', quantity: 1, unitPrice: 3500, amount: 3500, category: 'Treatment' },
    { description: 'Scale & polish', quantity: 1, unitPrice: 6000, amount: 6000, category: 'Treatment' },
    { description: 'Mouthwash 250ml', quantity: 2, unitPrice: 850, amount: 1700, category: 'Retail' },
  ],
  subtotal: 11200,
  discount: 500,
  tax: 963,
  total: 11663,
  paid: 5000,
  balance: 6663,
  payments: [{ amount: 5000, method: 'Card', paidAt: new Date().toISOString(), createdAt: new Date().toISOString(), status: 'Succeeded', payerLabel: null }],
  notes: 'Next check-up in six months.',
};

export default function InvoicePaper({
  data,
  blocks = DEFAULT_BLOCKS,
  accentColor = '#2563eb',
  headerText,
  footerText,
}: {
  data: PaperData;
  blocks?: TemplateBlock[];
  accentColor?: string;
  headerText?: string | null;
  footerText?: string | null;
}) {
  const render: Record<TemplateBlockType, () => JSX.Element | null> = {
    header: () => (
      <div className="bl-paper-header" style={{ background: accentColor }}>
        <div>
          <h3>{data.businessName}</h3>
          {headerText && <div style={{ opacity: 0.9, marginTop: 4 }}>{headerText}</div>}
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontWeight: 700, fontSize: 16 }}>{data.title}</div>
          <div style={{ opacity: 0.9 }}>{data.number}</div>
        </div>
      </div>
    ),
    businessInfo: () => (
      <div className="bl-paper-section"><strong>{data.businessName}</strong></div>
    ),
    invoiceMeta: () => (
      <div className="bl-paper-section bl-paper-meta">
        {[['Invoice', data.number], ['Issued', date(data.issuedAt)], ['Due', date(data.dueDate)], ['Status', data.status]].map(([label, value]) => (
          <div key={label}>
            <div className="bl-paper-label">{label}</div>
            <div style={{ fontWeight: 600, overflowWrap: 'anywhere' }}>{value}</div>
          </div>
        ))}
      </div>
    ),
    customerInfo: () => (
      <div className="bl-paper-section">
        <div className="bl-paper-label">Billed to</div>
        <div style={{ fontWeight: 700 }}>{data.customerName}</div>
        {data.customerEmail && <div style={{ color: '#6b7280' }}>{data.customerEmail}</div>}
      </div>
    ),
    items: () => (
      <div className="bl-paper-section">
        <table>
          <thead>
            <tr><th>Description</th><th className="bl-num">Qty</th><th className="bl-num">Unit price</th><th className="bl-num">Amount</th></tr>
          </thead>
          <tbody>
            {data.items.map((item, i) => (
              <tr key={i}>
                <td>
                  {item.description}
                  {item.category && item.category !== 'General' && <div style={{ fontSize: 11, color: '#6b7280' }}>{item.category}</div>}
                </td>
                <td className="bl-num">{item.quantity}</td>
                <td className="bl-num">{item.unitPrice.toFixed(2)}</td>
                <td className="bl-num">{item.amount.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    ),
    totals: () => (
      <div className="bl-paper-section">
        <div className="bl-paper-totals">
          <span>Subtotal</span><span className="bl-num">{money(data.subtotal, data.currency)}</span>
          {data.discount > 0 && <><span>Discount</span><span className="bl-num">-{money(data.discount, data.currency)}</span></>}
          {data.tax > 0 && <><span>Tax</span><span className="bl-num">{money(data.tax, data.currency)}</span></>}
          <strong>Total</strong><strong className="bl-num">{money(data.total, data.currency)}</strong>
          <span>Paid</span><span className="bl-num">{money(data.paid, data.currency)}</span>
          <strong>Balance due</strong><strong className="bl-num">{money(data.balance, data.currency)}</strong>
        </div>
      </div>
    ),
    payments: () =>
      data.payments.length === 0 ? null : (
        <div className="bl-paper-section">
          <div className="bl-paper-label">Payments</div>
          {data.payments.map((p, i) => (
            <div key={i} style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
              <span>{date(p.paidAt ?? p.createdAt)} · {p.method}{p.payerLabel ? ` (${p.payerLabel})` : ''}{p.status !== 'Succeeded' ? ` · ${p.status}` : ''}</span>
              <span className="bl-num">{money(p.amount, data.currency)}</span>
            </div>
          ))}
        </div>
      ),
    notes: () =>
      !data.notes ? null : (
        <div className="bl-paper-section">
          <div className="bl-paper-label">Notes</div>
          <div style={{ whiteSpace: 'pre-wrap' }}>{data.notes}</div>
        </div>
      ),
    footer: () => (
      <div className="bl-paper-section" style={{ color: '#6b7280', fontSize: 12 }}>
        {footerText || 'Thank you for your business.'}
      </div>
    ),
  };

  return (
    <div className="bl-paper" aria-label={`${data.title} ${data.number}`}>
      {blocks.filter((b) => b.visible).map((b) => {
        const el = render[b.type]?.();
        return el ? <div key={b.id}>{el}</div> : null;
      })}
    </div>
  );
}
