import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { SuppliersPage } from './SuppliersPage';

function renderPage() {
  const store = configureStore({
    reducer: { auth: authReducer },
    preloadedState: {
      auth: {
        user: {
          id: 'user-1',
          email: 'manager@example.test',
          fullName: 'Test Manager',
          role: 'Manager' as const,
          tenantId: 'tenant-1',
        },
        token: 'test-token',
        isAuthenticated: true,
        loading: false,
        error: null,
      },
    },
  });

  return render(
    <Provider store={store}>
      <AppToastProvider>
        <ToastProvider>
          <MemoryRouter>
            <SuppliersPage />
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

describe('SuppliersPage', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('saves and displays supplier profile details and links to that supplier’s orders', async () => {
    const supplier = {
      id: 'supplier-1',
      name: 'Central Supplies',
      contactPerson: 'Alex Silva',
      email: 'orders@example.test',
      phone: '+94112223333',
      address: '12 Main Street',
      paymentTerms: 'Net 30',
      notes: 'Deliver before noon',
      leadTimeDays: 5,
      createdAt: '2026-09-30T00:00:00Z',
      updatedAt: '2026-09-30T00:00:00Z',
    };
    let saveBody: Record<string, unknown> | undefined;

    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.startsWith('/api/purchase-orders?supplierId=supplier-1')) {
        return new Response(JSON.stringify({
          items: [{
            id: 'order-1',
            number: 'PO-1001',
            branch: 'Main branch',
            status: 'Received',
            totalAmount: 12500,
            lineItems: 2,
            createdAt: '2026-09-28T00:00:00Z',
          }, {
            id: 'order-2',
            number: 'PO-1002',
            branch: 'Main branch',
            status: 'Cancelled',
            totalAmount: 90000,
            lineItems: 1,
            createdAt: '2026-09-29T00:00:00Z',
          }],
          totalPages: 1,
          totalCount: 2,
        }), { status: 200 });
      }
      if (url === '/api/suppliers' && init?.method === 'POST') {
        saveBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        return new Response(JSON.stringify(supplier), { status: 201 });
      }
      if (url === '/api/suppliers') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    await screen.findByText('0 suppliers in your directory');
    fireEvent.click(screen.getByRole('button', { name: '＋ Add supplier' }));
    fireEvent.change(screen.getByLabelText('Supplier name'), { target: { value: supplier.name } });
    fireEvent.change(screen.getByLabelText('Contact person'), { target: { value: supplier.contactPerson } });
    fireEvent.change(screen.getByLabelText('Email address'), { target: { value: supplier.email } });
    fireEvent.change(screen.getByLabelText('Phone number'), { target: { value: supplier.phone } });
    fireEvent.change(screen.getByLabelText('Business address'), { target: { value: supplier.address } });
    fireEvent.change(screen.getByLabelText('Payment terms'), { target: { value: supplier.paymentTerms } });
    fireEvent.change(screen.getByLabelText('Supplier notes'), { target: { value: supplier.notes } });
    fireEvent.change(screen.getByLabelText('Usual lead time (days)'), { target: { value: '5' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save supplier' }));

    await waitFor(() => expect(saveBody).toMatchObject({
      contactPerson: supplier.contactPerson,
      address: supplier.address,
      paymentTerms: supplier.paymentTerms,
      notes: supplier.notes,
    }));
    expect(await screen.findByText('Central Supplies')).toBeInTheDocument();
    expect(screen.getByText('Net 30')).toBeInTheDocument();
    expect(screen.getByText('Contact: Alex Silva')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /View orders/ })).toHaveAttribute(
      'href',
      '/purchase-orders?supplier=Central%20Supplies',
    );
    fireEvent.click(screen.getByRole('button', { name: 'View details' }));

    expect(screen.getByRole('dialog', { name: 'Central Supplies' })).toBeInTheDocument();
    expect(await screen.findByText('12 Main Street')).toBeInTheDocument();
    expect(screen.getByText('Deliver before noon')).toBeInTheDocument();
    expect(await screen.findByText('PO-1001')).toBeInTheDocument();
    expect(screen.getByText('PO-1002')).toBeInTheDocument();
    expect(screen.getByText(/2 orders · .*12,500\.00 non-cancelled PO value/)).toBeInTheDocument();
    expect(screen.getByText('Cancelled orders are excluded from the value; payments are not tracked here.')).toBeInTheDocument();
  });
});
