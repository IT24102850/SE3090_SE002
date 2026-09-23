import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import InvoiceFormModal from './components/InvoiceFormModal';
import {
  computeTotals,
  emptyInvoiceForm,
  hasErrors,
  invoiceWarnings,
  newLine,
  toCreateRequest,
  validateInvoiceForm,
  type InvoiceFormState,
} from './invoiceForm';
import type { Invoice, InvoiceValidationResult } from './billingApi';

const TODAY = new Date(2026, 8, 23);

function form(patch: Partial<InvoiceFormState> = {}): InvoiceFormState {
  return {
    ...emptyInvoiceForm(TODAY),
    customerId: 'cust-1',
    lines: [{ ...newLine('Consultation', '3500'), quantity: '1' }],
    ...patch,
  };
}

describe('invoice form - totals', () => {
  it('adds lines, takes the discount off the subtotal and taxes the rest', () => {
    const t = computeTotals(form({
      lines: [{ ...newLine('Cleaning', '2500'), quantity: '2' }],
      discountMode: 'percent',
      discount: '10',
      taxRatePercent: '8',
    }));
    expect(t).toEqual({ subtotal: 5000, discount: 500, discountPercent: 10, tax: 360, total: 4860 });
  });

  it('never goes below zero', () => {
    expect(computeTotals(form({ discount: '99999' })).total).toBe(0);
  });
});

describe('invoice form - validation', () => {
  it('passes a complete invoice', () => {
    expect(hasErrors(validateInvoiceForm(form(), TODAY))).toBe(false);
  });

  it('requires a customer and at least one item', () => {
    const errors = validateInvoiceForm(form({ customerId: '', lines: [newLine()] }), TODAY);
    expect(errors.customerId).toBeTruthy();
    expect(errors.lines).toBe('Add at least one item.');
  });

  it('rejects a past due date', () => {
    expect(validateInvoiceForm(form({ dueDate: '2026-09-01' }), TODAY).dueDate).toMatch(/past/);
  });

  it('checks every line', () => {
    const bad = { ...newLine('', '100'), key: 'a' };
    const zeroQty = { ...newLine('Filling', '100'), key: 'b', quantity: '0' };
    const negative = { ...newLine('X-ray', '-5'), key: 'c' };
    const errors = validateInvoiceForm(form({ lines: [bad, zeroQty, negative] }), TODAY);
    expect(errors.lineErrors).toEqual({
      a: 'Describe the item.',
      b: 'Quantity must be a whole number of at least 1.',
      c: 'Enter a price of 0 or more.',
    });
  });

  it('rejects a discount larger than the items and a percentage over 100', () => {
    expect(validateInvoiceForm(form({ discount: '5000' }), TODAY).discount).toMatch(/larger than the items/);
    expect(validateInvoiceForm(form({ discountMode: 'percent', discount: '120' }), TODAY).discount).toMatch(/100%/);
  });

  it('rejects an out-of-range tax rate and a bad currency', () => {
    const errors = validateInvoiceForm(form({ taxRatePercent: '150', currency: 'RUPEES' }), TODAY);
    expect(errors.taxRatePercent).toBeTruthy();
    expect(errors.currency).toBeTruthy();
  });

  it('warns - but does not block - a discount above the 30% review cap (golden case: 50% off a $10 item)', () => {
    const f = form({ currency: 'USD', lines: [{ ...newLine('Toothbrush', '10') }], discount: '5' });
    expect(hasErrors(validateInvoiceForm(f, TODAY))).toBe(false);
    expect(invoiceWarnings(f)[0]).toMatch(/50% discount is above the 30% cap/);
  });
});

describe('invoice form - request', () => {
  it('sends percentages as percentages and drops blank lines', () => {
    const req = toCreateRequest(form({
      lines: [newLine('Consultation', '3500'), newLine()],
      discountMode: 'percent',
      discount: '10',
      taxRatePercent: '8',
      discountCode: ' spring ',
    }));
    expect(req.items).toHaveLength(1);
    expect(req.discountPercent).toBe(10);
    expect(req.discount).toBe(0);
    expect(req.taxRatePercent).toBe(8);
    expect(req.discountCode).toBe('spring');
  });
});

describe('<InvoiceFormModal />', () => {
  const customers = [{ id: 'cust-1', fullName: 'Nimal Perera', email: 'nimal@example.com' }];
  const noCheck = vi.fn<(...a: unknown[]) => Promise<InvoiceValidationResult>>().mockRejectedValue(new Error('offline'));

  it('shows field errors instead of submitting an incomplete invoice', async () => {
    const create = vi.fn();
    render(<InvoiceFormModal customers={customers} onClose={() => {}} onCreated={() => {}} createInvoice={create} validateInvoice={noCheck} />);

    fireEvent.click(screen.getByRole('button', { name: /create invoice/i }));

    expect(await screen.findByText('Choose a customer.')).toBeInTheDocument();
    expect(screen.getByText('Add at least one item.')).toBeInTheDocument();
    expect(create).not.toHaveBeenCalled();
  });

  it('updates the total as lines are typed', () => {
    render(<InvoiceFormModal customers={customers} onClose={() => {}} onCreated={() => {}} validateInvoice={noCheck} />);
    fireEvent.change(screen.getByLabelText('Item 1 unit price'), { target: { value: '1250.5' } });
    fireEvent.change(screen.getByLabelText('Item 1 quantity'), { target: { value: '2' } });
    expect(screen.getByTestId('invoice-total')).toHaveTextContent('2,501.00');
  });

  it('flags a large discount while typing', () => {
    render(<InvoiceFormModal customers={customers} onClose={() => {}} onCreated={() => {}} validateInvoice={noCheck} />);
    fireEvent.change(screen.getByLabelText('Item 1 description'), { target: { value: 'Whitening' } });
    fireEvent.change(screen.getByLabelText('Item 1 unit price'), { target: { value: '100' } });
    fireEvent.change(screen.getByLabelText('Discount'), { target: { value: '60' } });
    expect(screen.getByRole('status')).toHaveTextContent(/60% discount is above the 30% cap/);
  });

  it('submits a valid invoice and hands back the created one', async () => {
    const created = { id: 'inv-1', invoiceNumber: 'INV-1' } as Invoice;
    const create = vi.fn().mockResolvedValue(created);
    const onCreated = vi.fn();
    render(<InvoiceFormModal customers={customers} initialCustomerId="cust-1" onClose={() => {}} onCreated={onCreated} createInvoice={create} validateInvoice={noCheck} />);

    fireEvent.change(screen.getByLabelText('Item 1 description'), { target: { value: 'Consultation' } });
    fireEvent.change(screen.getByLabelText('Item 1 unit price'), { target: { value: '3500' } });
    fireEvent.click(screen.getByRole('button', { name: /create invoice/i }));

    await waitFor(() => expect(onCreated).toHaveBeenCalledWith(created));
    expect(create.mock.calls[0][0]).toMatchObject({
      customerId: 'cust-1',
      currency: 'LKR',
      items: [{ description: 'Consultation', quantity: 1, unitPrice: 3500, category: 'General' }],
    });
  });

  it('shows the server message when creation fails', async () => {
    const create = vi.fn().mockRejectedValue({ response: { data: { message: 'Customer not found in this business.' } } });
    render(<InvoiceFormModal customers={customers} initialCustomerId="cust-1" onClose={() => {}} onCreated={() => {}} createInvoice={create} validateInvoice={noCheck} />);
    fireEvent.change(screen.getByLabelText('Item 1 description'), { target: { value: 'Consultation' } });
    fireEvent.change(screen.getByLabelText('Item 1 unit price'), { target: { value: '3500' } });
    fireEvent.click(screen.getByRole('button', { name: /create invoice/i }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Customer not found in this business.');
  });
});
