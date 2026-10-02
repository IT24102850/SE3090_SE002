import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../../store/authSlice';
import { bookingApi } from '../../api/bookingApi';
import CustomerShopPage from './CustomerShopPage';

const branchId = 'branch-main';
const itemId = 'item-tea';
const initialOrders: Array<Record<string, unknown>> = [];
let orders: Array<Record<string, unknown>>;
let placedBody: Record<string, unknown> | null;

const order = {
  id: 'order-1',
  branchId,
  number: 'ORD-261002-ABCD1234',
  status: 'Pending',
  paymentStatus: 'DueOnFulfillment',
  fulfillmentMethod: 'Pickup',
  deliveryAddress: null,
  deliveryLatitude: null,
  deliveryLongitude: null,
  notes: null,
  total: 150,
  createdAt: '2026-10-02T08:00:00Z',
  statusUpdates: [],
  items: [{
    inventoryItemId: itemId,
    itemName: 'Fresh tea leaves',
    sku: 'TEA-01',
    unit: 'pack',
    quantity: 2,
    unitPrice: 75,
    lineTotal: 150,
  }],
};

function renderPage() {
  const store = configureStore({
    reducer: { auth: authReducer, [bookingApi.reducerPath]: bookingApi.reducer },
    middleware: (getDefault) => getDefault().concat(bookingApi.middleware),
    preloadedState: {
      auth: {
        user: {
          id: 'customer-1',
          tenantId: 'tenant-1',
          branchId,
          role: 'Customer',
          fullName: 'Taylor Customer',
          email: 'customer@example.test',
        },
        token: 'fake-token',
        isAuthenticated: true,
      } as never,
    },
  });
  return render(
    <Provider store={store}>
      <CustomerShopPage />
    </Provider>,
  );
}

describe('CustomerShopPage', () => {
  beforeEach(() => {
    orders = [...initialOrders];
    placedBody = null;
    localStorage.clear();
    localStorage.setItem('token', 'fake-token');
    localStorage.setItem('user', JSON.stringify({
      id: 'customer-1',
      tenantId: 'tenant-1',
      role: 'Customer',
      fullName: 'Taylor Customer',
      email: 'customer@example.test',
    }));
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = input instanceof Request ? input : new Request(input, init);
      const url = new URL(request.url);
      if (url.hostname === 'nominatim.openstreetmap.org') {
        return Response.json([{
          place_id: 42,
          lat: '6.9271',
          lon: '79.8612',
          display_name: 'Colombo, Sri Lanka',
        }]);
      }
      if (url.pathname.endsWith('/tenant/public')) {
        return Response.json([
          { id: 'tenant-1', name: 'Willow Market', businessType: 'Retail' },
          { id: 'tenant-2', name: 'Bramble Books', businessType: 'Bookshop' },
        ]);
      }
      if (url.pathname.endsWith('/auth/join/tenant-2')) {
        return Response.json({
          accessToken: 'tenant-two-token',
          user: {
            id: 'customer-1',
            tenantId: 'tenant-2',
            role: 'Customer',
            fullName: 'Taylor Customer',
            email: 'customer@example.test',
          },
        });
      }
      if (url.pathname.endsWith('/tenant')) {
        return Response.json({ id: 'tenant-1', name: 'Willow Market' });
      }
      if (url.pathname.endsWith('/customer-orders/branches')) {
        return Response.json([{ id: branchId, name: 'Main store', address: 'Town' }]);
      }
      if (url.pathname.endsWith('/customer-orders/products')) {
        return Response.json([{
          id: itemId,
          name: 'Fresh tea leaves',
          description: 'A bright, fragrant blend.',
          sku: 'TEA-01',
          category: 'Pantry',
          unit: 'pack',
          quantityAvailable: 5,
          price: 75,
          imageUrl: 'https://images.example.test/tea.jpg',
        }]);
      }
      if (url.pathname.endsWith('/customer-orders') && request.method === 'POST') {
        placedBody = await request.clone().json() as Record<string, unknown>;
        orders = [order];
        return Response.json(order, { status: 201 });
      }
      if (url.pathname.endsWith('/customer-orders')) {
        return Response.json(orders);
      }
      return Response.json({});
    }));
  });

  afterEach(() => vi.unstubAllGlobals());

  it('lets a customer add products and place an order for pickup', async () => {
    renderPage();

    expect(await screen.findByText('Fresh tea leaves')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /add fresh tea leaves to basket/i }));
    fireEvent.click(screen.getByRole('button', { name: /add one fresh tea leaves/i }));
    expect(screen.getAllByText('LKR 150.00')).toHaveLength(2);

    fireEvent.click(screen.getByRole('button', { name: /place my order/i }));

    await waitFor(() => expect(placedBody).not.toBeNull());
    expect(placedBody).toMatchObject({
      branchId,
      fulfillmentMethod: 'Pickup',
      items: [{ inventoryItemId: itemId, quantity: 2 }],
    });
    expect(await screen.findByText('ORD-261002-ABCD1234')).toBeTruthy();
    expect(screen.getByText(/Pay when you receive it/)).toBeTruthy();
  });

  it('requires a delivery address before order submission', async () => {
    renderPage();

    expect(await screen.findByText('Fresh tea leaves')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /add fresh tea leaves to basket/i }));
    fireEvent.click(screen.getByLabelText('Deliver to me'));
    fireEvent.click(screen.getByRole('button', { name: /place my order/i }));

    expect(placedBody).toBeNull();
    expect(screen.getByLabelText('Delivery address')).toBeTruthy();
  });

  it('searches for a place and submits its delivery pin only after selection', async () => {
    renderPage();
    expect(await screen.findByText('Fresh tea leaves')).toBeTruthy();
    expect(document.querySelector('.cust-shop-product-art img'))
      .toHaveAttribute('src', 'https://images.example.test/tea.jpg');
    fireEvent.click(screen.getByRole('button', { name: /add fresh tea leaves to basket/i }));
    fireEvent.click(screen.getByLabelText('Deliver to me'));
    fireEvent.change(screen.getByLabelText('Delivery address'), { target: { value: '12 Main Road' } });
    const placeSearch = screen.getByRole('textbox', { name: /search delivery location/i });
    fireEvent.change(placeSearch, { target: { value: 'Colombo' } });
    expect(await screen.findByRole(
      'button',
      { name: /colombo, sri lanka/i },
      { timeout: 3000 },
    )).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Clear search' }));
    expect(placeSearch).toHaveValue('');
    expect(screen.queryByRole('button', { name: /colombo, sri lanka/i })).not.toBeInTheDocument();
    fireEvent.change(placeSearch, { target: { value: 'Colombo' } });
    fireEvent.click(screen.getByRole('button', { name: 'Search', exact: true }));
    fireEvent.click(await screen.findByRole('button', { name: /colombo, sri lanka/i }));
    expect(screen.getByText(/Pin set · 6\.92710, 79\.86120/)).toBeTruthy();
    expect(document.querySelector('.leaflet-marker-draggable')).toBeTruthy();
    expect(screen.getByRole('link', { name: /open in google maps/i }))
      .toHaveAttribute('href', 'https://www.google.com/maps/search/?api=1&query=6.9271,79.8612');
    fireEvent.click(screen.getByRole('button', { name: /place my order/i }));

    await waitFor(() => expect(placedBody).not.toBeNull());
    expect(placedBody).toMatchObject({
      fulfillmentMethod: 'Delivery',
      deliveryLatitude: 6.9271,
      deliveryLongitude: 79.8612,
    });
  });

  it('lets a customer switch business from the shop and refreshes the session', async () => {
    renderPage();

    fireEvent.click(screen.getByRole('button', { name: /switch business/i }));
    fireEvent.click(await screen.findByRole('button', { name: /bramble books/i }));

    await waitFor(() => expect(localStorage.getItem('token')).toBe('tenant-two-token'));
    expect(JSON.parse(localStorage.getItem('user') ?? '{}').tenantId).toBe('tenant-2');
  });
});
