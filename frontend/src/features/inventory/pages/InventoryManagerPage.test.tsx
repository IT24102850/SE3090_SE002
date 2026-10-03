import { configureStore } from '@reduxjs/toolkit';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authReducer from '../../../store/authSlice';
import { ToastProvider as AppToastProvider } from '../../../shared/components/Toast';
import { ToastProvider } from '../ui/ToastContext';
import { InventoryManagerPage } from './InventoryManagerPage';

const itemId = '6aa6b7bd-32d6-44be-9382-fb2e790375f2';

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
            <InventoryManagerPage />
          </MemoryRouter>
        </ToastProvider>
      </AppToastProvider>
    </Provider>,
  );
}

describe('InventoryManagerPage price editing', () => {
  beforeEach(() => {
    localStorage.setItem('token', 'test-token');
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it('saves a selling price for an existing uncategorized item', async () => {
    let item: Record<string, unknown> = {
      id: itemId,
      name: 'Tea Leaves',
      sku: 'TEA-001',
      categoryId: null,
      category: null,
      unitId: null,
      unit: null,
      branchId: 'branch-1',
      branch: 'Main branch',
      quantity: 12,
      reorderLevel: 2,
      unitCost: 50,
      sellingPrice: null,
    };
    let updateBody: Record<string, unknown> | undefined;

    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url === '/api/inventory/categories') {
        return new Response(JSON.stringify([{ id: 'category-1', name: 'Tea' }]), { status: 200 });
      }
      if (url === '/api/suppliers') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url.startsWith('/api/inventory?page=')) {
        return new Response(JSON.stringify({ items: [item], totalPages: 1 }), { status: 200 });
      }
      if (url === `/api/inventory/${itemId}` && init?.method === 'PUT') {
        updateBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        item = { ...item, sellingPrice: Number(updateBody.sellingPrice) };
        return new Response(JSON.stringify(item), { status: 200 });
      }
      return new Response(JSON.stringify({ message: `Unexpected request: ${url}` }), { status: 404 });
    }));

    renderPage();
    await screen.findByText('Tea Leaves');

    fireEvent.click(screen.getByRole('button', { name: 'Edit Tea Leaves' }));
    fireEvent.change(screen.getByLabelText('Selling price (LKR)'), {
      target: { value: '75' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Save item' }));

    expect(screen.queryByText('Choose a category for this inventory item.'))
      .not.toBeInTheDocument();
    fireEvent.click(await screen.findByRole('button', { name: 'Save changes' }));

    await waitFor(() => {
      expect(updateBody?.sellingPrice).toBe(75);
      expect(screen.getByText('LKR 75')).toBeInTheDocument();
    });
  }, 15000);
});
