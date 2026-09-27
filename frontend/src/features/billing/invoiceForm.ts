import type { CreateInvoiceRequest } from './billingApi';

/* The invoice form's state, totals and validation - kept free of React so
 * the rules can be unit-tested and so the preview and the submit path can
 * never disagree about what an invoice costs. The server recalculates
 * everything anyway; this is for immediate feedback. */

export interface InvoiceLineDraft {
  key: string;
  description: string;
  quantity: string;
  unitPrice: string;
  category: string;
}

export interface InvoiceFormState {
  customerId: string;
  dueDate: string;
  currency: string;
  lines: InvoiceLineDraft[];
  discountMode: 'amount' | 'percent';
  discount: string;
  taxRatePercent: string;
  discountCode: string;
  notes: string;
  templateId: string;
}

export type InvoiceFormErrors = Partial<Record<'customerId' | 'dueDate' | 'currency' | 'lines' | 'discount' | 'taxRatePercent', string>> & {
  lineErrors?: Record<string, string>;
};

let lineCounter = 0;
export const newLine = (description = '', unitPrice = ''): InvoiceLineDraft => ({
  key: `line-${++lineCounter}`,
  description,
  quantity: '1',
  unitPrice,
  category: 'General',
});

export function emptyInvoiceForm(today = new Date()): InvoiceFormState {
  const due = new Date(today);
  due.setDate(due.getDate() + 14);
  const pad = (n: number) => String(n).padStart(2, '0');
  return {
    customerId: '',
    dueDate: `${due.getFullYear()}-${pad(due.getMonth() + 1)}-${pad(due.getDate())}`,
    currency: 'LKR',
    lines: [newLine()],
    discountMode: 'amount',
    discount: '',
    taxRatePercent: '',
    discountCode: '',
    notes: '',
    templateId: '',
  };
}

const num = (value: string) => (value.trim() === '' ? 0 : Number(value));
const round2 = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;

export interface InvoiceTotals {
  subtotal: number;
  discount: number;
  discountPercent: number;
  tax: number;
  total: number;
}

/** Same arithmetic as the server: line = qty × price (2dp), discount off the
 *  subtotal, tax on what is left. */
export function computeTotals(form: InvoiceFormState): InvoiceTotals {
  const subtotal = round2(
    form.lines.reduce((sum, l) => {
      const q = num(l.quantity);
      const p = num(l.unitPrice);
      return Number.isFinite(q) && Number.isFinite(p) ? sum + round2(q * round2(p)) : sum;
    }, 0),
  );
  const rawDiscount = num(form.discount);
  const discount = !Number.isFinite(rawDiscount) || rawDiscount < 0
    ? 0
    : form.discountMode === 'percent' ? round2((subtotal * rawDiscount) / 100) : round2(rawDiscount);
  const rate = num(form.taxRatePercent);
  const tax = Number.isFinite(rate) && rate > 0 ? round2((Math.max(0, subtotal - discount) * rate) / 100) : 0;
  const discountPercent = subtotal > 0 ? round2((discount / subtotal) * 100) : discount > 0 ? 100 : 0;
  return { subtotal, discount, discountPercent, tax, total: Math.max(0, round2(subtotal - discount + tax)) };
}

/** The caps the billing agent applies; above them the invoice is flagged. */
export const DISCOUNT_REVIEW_PERCENT = 30;

export function validateInvoiceForm(form: InvoiceFormState, today = new Date()): InvoiceFormErrors {
  const errors: InvoiceFormErrors = {};
  const lineErrors: Record<string, string> = {};

  if (!form.customerId) errors.customerId = 'Choose a customer.';
  if (!/^[A-Z]{3}$/.test(form.currency.trim().toUpperCase())) errors.currency = 'Use a 3-letter currency code, e.g. LKR.';

  if (!form.dueDate) {
    errors.dueDate = 'Pick a due date.';
  } else {
    const due = new Date(`${form.dueDate}T23:59:59`);
    const startOfToday = new Date(today);
    startOfToday.setHours(0, 0, 0, 0);
    if (Number.isNaN(due.getTime())) errors.dueDate = 'Pick a valid due date.';
    else if (due < startOfToday) errors.dueDate = 'The due date cannot be in the past.';
  }

  const filled = form.lines.filter((l) => l.description.trim() || l.unitPrice.trim());
  if (filled.length === 0) errors.lines = 'Add at least one item.';

  for (const line of filled) {
    const q = num(line.quantity);
    const p = num(line.unitPrice);
    if (!line.description.trim()) lineErrors[line.key] = 'Describe the item.';
    else if (line.description.trim().length > 500) lineErrors[line.key] = 'Keep the description under 500 characters.';
    else if (!Number.isInteger(q) || q < 1) lineErrors[line.key] = 'Quantity must be a whole number of at least 1.';
    else if (line.unitPrice.trim() === '' || !Number.isFinite(p) || p < 0) lineErrors[line.key] = 'Enter a price of 0 or more.';
  }
  if (Object.keys(lineErrors).length) errors.lineErrors = lineErrors;

  const d = num(form.discount);
  const totals = computeTotals(form);
  if (!Number.isFinite(d) || d < 0) errors.discount = 'The discount cannot be negative.';
  else if (form.discountMode === 'percent' && d > 100) errors.discount = 'A percentage discount cannot exceed 100%.';
  else if (totals.discount > totals.subtotal && totals.discount > 0) errors.discount = 'The discount is larger than the items.';

  const rate = num(form.taxRatePercent);
  if (!Number.isFinite(rate) || rate < 0 || rate > 100) errors.taxRatePercent = 'Tax rate must be between 0 and 100%.';

  return errors;
}

export const hasErrors = (e: InvoiceFormErrors) =>
  Object.entries(e).some(([k, v]) => (k === 'lineErrors' ? Object.keys(v as object).length > 0 : Boolean(v)));

/** Warnings don't block submission - the agent flags the invoice for review. */
export function invoiceWarnings(form: InvoiceFormState): string[] {
  const t = computeTotals(form);
  const warnings: string[] = [];
  if (t.discountPercent > DISCOUNT_REVIEW_PERCENT && t.discount <= t.subtotal)
    warnings.push(`A ${t.discountPercent}% discount is above the ${DISCOUNT_REVIEW_PERCENT}% cap - the invoice will be flagged for review.`);
  if (t.subtotal > 0 && t.total === 0) warnings.push('The invoice has priced items but nothing to pay.');
  return warnings;
}

export function toCreateRequest(form: InvoiceFormState): CreateInvoiceRequest {
  const lines = form.lines.filter((l) => l.description.trim() || l.unitPrice.trim());
  const discount = num(form.discount);
  const rate = num(form.taxRatePercent);
  return {
    customerId: form.customerId,
    dueDate: new Date(`${form.dueDate}T12:00:00`).toISOString(),
    currency: form.currency.trim().toUpperCase(),
    items: lines.map((l) => ({
      description: l.description.trim(),
      quantity: num(l.quantity),
      unitPrice: num(l.unitPrice),
      category: l.category.trim() || 'General',
    })),
    discount: form.discountMode === 'amount' ? discount : 0,
    discountPercent: form.discountMode === 'percent' && discount > 0 ? discount : null,
    taxRatePercent: rate > 0 ? rate : null,
    discountCode: form.discountCode.trim() || null,
    notes: form.notes.trim() || null,
    templateId: form.templateId || null,
  };
}
