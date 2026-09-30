import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
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

  it('shows order summaries in the directory and detailed history in the supplier profile', async () => {
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
      orderCount: 2,
      activeOrderCount: 1,
      totalOrderValue: 12500,
      lastOrderAt: '2026-09-29T00:00:00Z',
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
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getByText(/12,500\.00 PO value/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'View details' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Order history & details/ })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Order history/ }));

    expect(screen.getByRole('dialog', { name: 'Central Supplies' })).toBeInTheDocument();
    expect(screen.getByText('All orders')).toBeInTheDocument();
    expect(screen.getByText('Non-cancelled orders')).toBeInTheDocument();
    expect(screen.getByText('Total PO value')).toBeInTheDocument();
    expect(await screen.findByText('12 Main Street')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Edit supplier details' })).not.toBeInTheDocument();
    expect(within(screen.getByRole('dialog', { name: 'Central Supplies' })).getByRole('link', { name: /Open purchase orders/ })).toHaveAttribute(
      'href',
      '/purchase-orders?supplier=Central%20Supplies',
    );
    expect(screen.getByText('Deliver before noon')).toBeInTheDocument();
    expect(within(screen.getByRole('dialog', { name: 'Central Supplies' })).getByRole('button', { name: 'Delete supplier' })).toBeDisabled();
    expect(screen.getByText(/Suppliers with purchase order history cannot be deleted/)).toBeInTheDocument();
    expect(await screen.findAllByText('PO-1001')).toHaveLength(1);
    expect(screen.getAllByText('PO-1002')).toHaveLength(1);
    expect(within(screen.getByRole('dialog', { name: 'Central Supplies' })).getAllByRole('columnheader').map((header) => header.textContent)).toEqual([
      'Order',
      'Date',
      'Branch',
      'Status',
      'Lines',
      'Order value',
    ]);
    expect(screen.queryByText('No order history yet')).not.toBeInTheDocument();
    expect(screen.getByText('Total PO value').parentElement).toHaveTextContent('12,500.00');
    expect(screen.getByText('Cancelled orders are excluded from value; supplier payments are not tracked.')).toBeInTheDocument();
  });

  it('deletes a supplier with no purchase order history after confirmation', async () => {
    const supplier = {
      id: 'supplier-2',
      name: 'Solo Supplies',
      contactPerson: null,
      email: '',
      phone: '',
      address: null,
      paymentTerms: null,
      notes: null,
      leadTimeDays: null,
      createdAt: '2026-09-30T00:00:00Z',
      updatedAt: '2026-09-30T00:00:00Z',
      orderCount: 0,
      activeOrderCount: 0,
      totalOrderValue: 0,
      lastOrderAt: null,
    };
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === '/api/suppliers' && init?.method !== 'DELETE') {
        return new Response(JSON.stringify({ items: [supplier] }), { status: 200 });
      }
      if (url.startsWith('/api/purchase-orders?supplierId=supplier-2')) {
        return new Response(JSON.stringify({ items: [], totalPages: 1, totalCount: 0 }), { status: 200 });
      }
      if (url === '/api/suppliers/supplier-2' && init?.method === 'DELETE') {
        return new Response(null, { status: 204 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    });
    vi.stubGlobal('fetch', fetchMock);

    renderPage();
    fireEvent.click(await screen.findByRole('button', { name: /Order history & details/ }));
    fireEvent.click(await screen.findByRole('button', { name: 'Delete supplier' }));

    const confirmation = screen.getByRole('alertdialog', { name: 'Delete Solo Supplies?' });
    fireEvent.click(within(confirmation).getByRole('button', { name: 'Delete supplier' }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith('/api/suppliers/supplier-2', expect.objectContaining({ method: 'DELETE' })));
    expect(await screen.findByText('0 suppliers in your directory')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Order history & details/ })).not.toBeInTheDocument();
  });
});
