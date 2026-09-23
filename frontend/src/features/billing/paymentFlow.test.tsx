import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import PaymentFlowModal from './components/PaymentFlowModal';
import { providerFor, resultStep, stepForSession, validateAmount } from './paymentFlow';
import type { AvailableProviders, CheckoutResponse, Invoice } from './billingApi';

const invoice = {
  id: 'inv-1',
  invoiceNumber: 'INV-20260923-ABC123',
  currency: 'LKR',
  finalAmount: 4500,
  balanceDue: 4500,
  amountPaid: 0,
  status: 'Issued',
} as Invoice;

const session = (patch: Partial<CheckoutResponse> = {}): CheckoutResponse => ({
  paymentId: 'pay-1',
  invoiceId: 'inv-1',
  provider: 'Manual',
  status: 'Pending',
  amount: 4500,
  currency: 'LKR',
  clientSecret: null,
  redirectUrl: null,
  publicKey: null,
  externalReference: 'SIM-ABC',
  simulated: true,
  ...patch,
});

const none: AvailableProviders = { providers: [], sandboxAvailable: true };
const stripe: AvailableProviders = { providers: [{ provider: 'Stripe', name: 'Stripe', publicKey: 'pk_test', isTestMode: true, currency: 'LKR' }], sandboxAvailable: true };

describe('payment flow - routing', () => {
  it('sends card payments to Stripe when it is configured, otherwise the sandbox', () => {
    expect(providerFor('Card', stripe)).toBe('Stripe');
    expect(providerFor('Card', none)).toBe('Manual');
    expect(providerFor('QR', stripe)).toBe('Manual');
    expect(providerFor('Cash', stripe)).toBeNull();
  });

  it('picks the next step from the checkout session', () => {
    expect(stepForSession(session()).kind).toBe('sandbox');
    expect(stepForSession(session({ provider: 'Stripe', clientSecret: 'pi_secret' })).kind).toBe('stripe');
    expect(stepForSession(session({ provider: 'PayPal', redirectUrl: 'https://paypal.test/approve' })).kind).toBe('paypal');
    expect(stepForSession(session({ status: 'Succeeded' }))).toMatchObject({ kind: 'done', status: 'Succeeded' });
  });

  it('describes each outcome', () => {
    expect(resultStep('Failed')).toMatchObject({ status: 'Failed' });
    expect(resultStep('Pending')).toMatchObject({ status: 'Pending' });
  });

  it('validates a part payment against the balance', () => {
    expect(validateAmount('', 100)).toBeNull();
    expect(validateAmount('40', 100)).toBeNull();
    expect(validateAmount('0', 100)).toMatch(/greater than 0/);
    expect(validateAmount('100.01', 100)).toMatch(/at most 100.00/);
  });
});

describe('<PaymentFlowModal />', () => {
  const makeApi = (confirmStatus: 'Succeeded' | 'Failed' = 'Succeeded') => ({
    availableProviders: vi.fn().mockResolvedValue(none),
    checkout: vi.fn().mockResolvedValue(session()),
    confirmPayment: vi.fn().mockResolvedValue({
      payment: { id: 'pay-1', status: confirmStatus },
      invoice: { ...invoice, status: confirmStatus === 'Succeeded' ? 'Paid' : 'Issued', balanceDue: confirmStatus === 'Succeeded' ? 0 : 4500 },
    }),
  });

  it('pays by QR through the sandbox: method -> checkout -> confirm -> receipt', async () => {
    const api = makeApi();
    const onPaid = vi.fn();
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={onPaid} api={api} />);

    fireEvent.click(screen.getByRole('button', { name: /QR \/ wallet/ }));
    fireEvent.click(await screen.findByRole('button', { name: /Pay LKR 4,500.00/ }));

    expect(await screen.findByLabelText('Payment QR code')).toBeInTheDocument();
    expect(api.checkout).toHaveBeenCalledWith('inv-1', expect.objectContaining({ method: 'QR', provider: 'Manual', amount: null }));

    fireEvent.click(screen.getByRole('button', { name: 'Complete payment' }));
    await waitFor(() => expect(onPaid).toHaveBeenCalledWith(expect.objectContaining({ status: 'Paid' })));
    expect(screen.getByRole('status')).toHaveTextContent(/Payment received/);
    expect(api.confirmPayment).toHaveBeenCalledWith('pay-1', false);
  });

  it('reports a declined payment without marking the bill paid', async () => {
    const api = makeApi('Failed');
    const onPaid = vi.fn();
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={onPaid} api={api} />);

    fireEvent.click(await screen.findByRole('button', { name: /Pay LKR/ }));
    fireEvent.click(await screen.findByRole('button', { name: 'Simulate a decline' }));

    expect(await screen.findByText(/did not go through/)).toBeInTheDocument();
    expect(onPaid).not.toHaveBeenCalled();
    expect(api.confirmPayment).toHaveBeenCalledWith('pay-1', true);
    expect(screen.getByRole('button', { name: 'Try another way' })).toBeInTheDocument();
  });

  it('pays part of the balance when an amount is entered', async () => {
    const api = makeApi();
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={() => {}} api={api} />);

    fireEvent.change(screen.getByLabelText(/Amount/), { target: { value: '1500' } });
    fireEvent.click(await screen.findByRole('button', { name: /Pay LKR 1,500.00/ }));

    await waitFor(() => expect(api.checkout).toHaveBeenCalledWith('inv-1', expect.objectContaining({ amount: 1500 })));
  });

  it('will not start a payment larger than the balance', () => {
    const api = makeApi();
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={() => {}} api={api} />);

    fireEvent.change(screen.getByLabelText(/Amount/), { target: { value: '9000' } });

    expect(screen.getByText(/at most 4500.00/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Pay LKR 9,000.00/ })).toBeDisabled();
  });

  it('explains how to pay cash without calling any gateway', async () => {
    const api = makeApi();
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={() => {}} api={api} />);

    fireEvent.click(screen.getByRole('button', { name: /Cash/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Continue' }));

    expect(await screen.findByText(/at the counter/)).toBeInTheDocument();
    expect(api.checkout).not.toHaveBeenCalled();
  });

  it('shows the server error when checkout fails', async () => {
    const api = { ...makeApi(), checkout: vi.fn().mockRejectedValue({ response: { data: { message: 'Invoice is already fully paid.' } } }) };
    render(<PaymentFlowModal invoice={invoice} onClose={() => {}} onPaid={() => {}} api={api} />);
    fireEvent.click(await screen.findByRole('button', { name: /Pay LKR/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Invoice is already fully paid.');
  });
});
