import { useEffect, useMemo, useState, type FormEvent } from 'react';
import Modal from '../../../shared/components/Modal';
import { billingApi, errorMessage, type CustomerOption, type Invoice, type InvoiceTemplate, type InvoiceValidationResult } from '../billingApi';
import {
  computeTotals,
  emptyInvoiceForm,
  hasErrors,
  invoiceWarnings,
  newLine,
  toCreateRequest,
  validateInvoiceForm,
  type InvoiceFormErrors,
  type InvoiceFormState,
} from '../invoiceForm';
import { money } from '../format';

interface Props {
  customers: CustomerOption[];
  templates?: InvoiceTemplate[];
  initialCustomerId?: string;
  onClose: () => void;
  onCreated: (invoice: Invoice) => void;
  /** Injected in tests; defaults to the real API. */
  createInvoice?: typeof billingApi.createInvoice;
  validateInvoice?: typeof billingApi.validateInvoice;
}

export default function InvoiceFormModal({
  customers,
  templates = [],
  initialCustomerId,
  onClose,
  onCreated,
  createInvoice = billingApi.createInvoice,
  validateInvoice = billingApi.validateInvoice,
}: Props) {
  const [form, setForm] = useState<InvoiceFormState>(() => ({ ...emptyInvoiceForm(), customerId: initialCustomerId ?? '' }));
  const [errors, setErrors] = useState<InvoiceFormErrors>({});
  const [submitted, setSubmitted] = useState(false);
  const [saving, setSaving] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [agentCheck, setAgentCheck] = useState<InvoiceValidationResult | null>(null);

  const totals = useMemo(() => computeTotals(form), [form]);
  const warnings = useMemo(() => invoiceWarnings(form), [form]);

  const update = (patch: Partial<InvoiceFormState>) => {
    const next = { ...form, ...patch };
    setForm(next);
    if (submitted) setErrors(validateInvoiceForm(next));
  };
  const updateLine = (key: string, patch: Partial<InvoiceFormState['lines'][number]>) =>
    update({ lines: form.lines.map((l) => (l.key === key ? { ...l, ...patch } : l)) });

  // Ask the billing agent for its rule check once the form settles - the
  // same check the server runs when the invoice is created.
  useEffect(() => {
    if (hasErrors(validateInvoiceForm(form)) || totals.subtotal <= 0) {
      setAgentCheck(null);
      return;
    }
    const timer = setTimeout(() => {
      validateInvoice(toCreateRequest(form)).then(setAgentCheck).catch(() => setAgentCheck(null));
    }, 500);
    return () => clearTimeout(timer);
  }, [form, totals.subtotal, validateInvoice]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setSubmitted(true);
    const found = validateInvoiceForm(form);
    setErrors(found);
    if (hasErrors(found)) return;

    setSaving(true);
    setServerError(null);
    try {
      onCreated(await createInvoice(toCreateRequest(form)));
    } catch (err) {
      setServerError(errorMessage(err, 'The invoice could not be created.'));
    } finally {
      setSaving(false);
    }
  };

  const agentWarnings = agentCheck?.issues.filter((i) => i.severity !== 'info') ?? [];

  return (
    <Modal
      title="New invoice"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
          <button type="submit" form="invoice-form" className="btn btn-primary" disabled={saving}>
            {saving ? 'Creating…' : `Create invoice · ${money(totals.total, form.currency || 'LKR')}`}
          </button>
        </>
      }
    >
      <form id="invoice-form" className="bl-form" onSubmit={submit} noValidate>
        {serverError && <div className="bl-notice bl-notice-critical" role="alert">{serverError}</div>}

        <div className="bl-grid-3">
          <label className="bl-field">
            <span>Customer</span>
            <select className="input" value={form.customerId} aria-invalid={!!errors.customerId || undefined}
              onChange={(e) => update({ customerId: e.target.value })}>
              <option value="">Choose a customer…</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.fullName} · {c.email}</option>)}
            </select>
            {errors.customerId && <span className="bl-field-error">{errors.customerId}</span>}
          </label>
          <label className="bl-field">
            <span>Due date</span>
            <input className="input" type="date" value={form.dueDate} aria-invalid={!!errors.dueDate || undefined}
              onChange={(e) => update({ dueDate: e.target.value })} />
            {errors.dueDate && <span className="bl-field-error">{errors.dueDate}</span>}
          </label>
          <label className="bl-field">
            <span>Currency</span>
            <input className="input" value={form.currency} maxLength={3} aria-invalid={!!errors.currency || undefined}
              onChange={(e) => update({ currency: e.target.value.toUpperCase() })} />
            {errors.currency && <span className="bl-field-error">{errors.currency}</span>}
          </label>
        </div>

        <div className="bl-stack">
          <span className="bl-label">Items</span>
          <div className="bl-lines">
            {form.lines.map((line, index) => (
              <div key={line.key}>
                <div className="bl-line">
                  <input className="input" placeholder="Description" aria-label={`Item ${index + 1} description`} value={line.description}
                    onChange={(e) => updateLine(line.key, { description: e.target.value })} />
                  <input className="input" type="number" min={1} step={1} aria-label={`Item ${index + 1} quantity`} value={line.quantity}
                    onChange={(e) => updateLine(line.key, { quantity: e.target.value })} />
                  <input className="input" type="number" min={0} step="0.01" placeholder="Price" aria-label={`Item ${index + 1} unit price`} value={line.unitPrice}
                    onChange={(e) => updateLine(line.key, { unitPrice: e.target.value })} />
                  <input className="input" placeholder="Category" aria-label={`Item ${index + 1} category`} value={line.category}
                    onChange={(e) => updateLine(line.key, { category: e.target.value })} />
                  <button type="button" className="btn btn-ghost btn-sm" aria-label={`Remove item ${index + 1}`}
                    disabled={form.lines.length === 1}
                    onClick={() => update({ lines: form.lines.filter((l) => l.key !== line.key) })}>✕</button>
                </div>
                {errors.lineErrors?.[line.key] && <span className="bl-field-error">{errors.lineErrors[line.key]}</span>}
              </div>
            ))}
          </div>
          {errors.lines && <span className="bl-field-error">{errors.lines}</span>}
          <div>
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => update({ lines: [...form.lines, newLine()] })}>+ Add item</button>
          </div>
        </div>

        <div className="bl-grid-3">
          <label className="bl-field">
            <span>Discount</span>
            <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
              <input className="input" type="number" min={0} step="0.01" value={form.discount} aria-label="Discount"
                aria-invalid={!!errors.discount || undefined} onChange={(e) => update({ discount: e.target.value })} />
              <select className="input" style={{ width: 90 }} value={form.discountMode} aria-label="Discount type"
                onChange={(e) => update({ discountMode: e.target.value as 'amount' | 'percent' })}>
                <option value="amount">{form.currency || 'LKR'}</option>
                <option value="percent">%</option>
              </select>
            </div>
            {errors.discount && <span className="bl-field-error">{errors.discount}</span>}
          </label>
          <label className="bl-field">
            <span>Coupon / discount code</span>
            <input className="input" value={form.discountCode} maxLength={50} onChange={(e) => update({ discountCode: e.target.value })} />
          </label>
          <label className="bl-field">
            <span>Tax rate (%)</span>
            <input className="input" type="number" min={0} max={100} step="0.01" value={form.taxRatePercent}
              aria-invalid={!!errors.taxRatePercent || undefined} onChange={(e) => update({ taxRatePercent: e.target.value })} />
            {errors.taxRatePercent && <span className="bl-field-error">{errors.taxRatePercent}</span>}
          </label>
        </div>

        <div className="bl-grid-2">
          <label className="bl-field">
            <span>Notes</span>
            <textarea className="input" rows={2} value={form.notes} maxLength={2000} onChange={(e) => update({ notes: e.target.value })} />
          </label>
          {templates.length > 0 && (
            <label className="bl-field">
              <span>Template</span>
              <select className="input" value={form.templateId} onChange={(e) => update({ templateId: e.target.value })}>
                <option value="">Business default</option>
                {templates.map((t) => <option key={t.id} value={t.id}>{t.name}{t.isDefault ? ' (default)' : ''}</option>)}
              </select>
            </label>
          )}
        </div>

        <div className="bl-totals" aria-label="Invoice totals">
          <span>Subtotal</span><span className="bl-num">{money(totals.subtotal, form.currency)}</span>
          <span>Discount{totals.discountPercent > 0 ? ` (${totals.discountPercent}%)` : ''}</span><span className="bl-num">-{money(totals.discount, form.currency)}</span>
          <span>Tax</span><span className="bl-num">{money(totals.tax, form.currency)}</span>
          <span className="bl-total-final">Total</span><span className="bl-total-final bl-num" data-testid="invoice-total">{money(totals.total, form.currency)}</span>
        </div>

        {(warnings.length > 0 || agentWarnings.length > 0) && (
          <div className="bl-notice bl-notice-warning" role="status">
            <strong>Billing agent check</strong>
            <ul>
              {[...new Set([...warnings, ...agentWarnings.map((w) => w.message)])].map((w) => <li key={w}>{w}</li>)}
            </ul>
          </div>
        )}
      </form>
    </Modal>
  );
}
