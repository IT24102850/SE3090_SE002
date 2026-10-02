import { useState } from 'react';
import {
  useGetManagedCustomerOrdersQuery,
  useUpdateCustomerOrderStatusMutation,
  type CustomerOrder,
} from '../../api/bookingApi';
import './customer.css';

function nextStatuses(order: CustomerOrder) {
  switch (order.status) {
    case 'Pending': return ['Confirmed', 'Cancelled'];
    case 'Confirmed': return ['Preparing', 'Cancelled'];
    case 'Preparing': return [order.fulfillmentMethod === 'Delivery' ? 'OutForDelivery' : 'ReadyForPickup', 'Cancelled'];
    case 'ReadyForPickup':
    case 'OutForDelivery': return ['Completed'];
    default: return [];
  }
}

function statusLabel(status: string) {
  return ({
    OutForDelivery: 'Out for delivery',
    ReadyForPickup: 'Ready for pickup',
  } as Record<string, string>)[status] ?? status;
}

function errorMessage(error: unknown) {
  if (error && typeof error === 'object' && 'data' in error) {
    const data = (error as { data?: { message?: string } }).data;
    if (data?.message) return data.message;
  }
  return 'We could not update this order. Please refresh and try again.';
}

export default function CustomerOrderManagementPage() {
  const { data: orders = [], isLoading, isError, refetch } = useGetManagedCustomerOrdersQuery(undefined, { pollingInterval: 30000 });
  const [updateStatus, { isLoading: isUpdating }] = useUpdateCustomerOrderStatusMutation();
  const [error, setError] = useState('');
  const [updatingId, setUpdatingId] = useState('');

  async function changeStatus(order: CustomerOrder, status: string) {
    if (status === 'Cancelled' && !window.confirm(`Cancel ${order.number} and release its reserved stock?`)) return;
    setError('');
    setUpdatingId(order.id);
    try {
      await updateStatus({ orderId: order.id, status }).unwrap();
    } catch (failure) {
      setError(errorMessage(failure));
    } finally {
      setUpdatingId('');
    }
  }

  return (
    <main className="cust-page cust-order-ops">
      <header className="cust-order-ops-hero">
        <div><span className="cust-shop-kicker">A smoother handoff starts here</span><h1>Customer orders</h1><p>Confirm, prepare and keep customers in the loop as each order moves forward.</p></div>
        <span className="cust-order-ops-icon" aria-hidden="true">📦</span>
      </header>
      {error && <p className="cust-shop-error" role="alert">{error}</p>}
      {isLoading ? (
        <div className="card cust-shop-message" aria-busy="true">Loading customer orders…</div>
      ) : isError ? (
        <div className="card cust-shop-message" role="alert">Orders could not be loaded. <button className="btn btn-secondary" type="button" onClick={() => refetch()}>Try again</button></div>
      ) : orders.length === 0 ? (
        <div className="card cust-shop-message"><strong>All quiet for now</strong><span>New customer orders will appear here.</span></div>
      ) : (
        <section className="cust-order-ops-list" aria-live="polite">
          {orders.map(({ order, customerName, branchName }) => {
            const actions = nextStatuses(order);
            return (
              <article className="cust-order-ops-card card" key={order.id}>
                <div className="cust-shop-order-top">
                  <div><span className="cust-shop-kicker">{new Date(order.createdAt).toLocaleString()}</span><h2>{order.number}</h2><p>{customerName} · {branchName} · {order.fulfillmentMethod}</p></div>
                  <span className={`cust-shop-status ${order.status.toLowerCase()}`}>{statusLabel(order.status)}</span>
                </div>
                <div className="cust-shop-order-items">
                  {order.items.map((item) => <div key={`${order.id}-${item.inventoryItemId}`}><span>{item.quantity.toLocaleString()} × {item.itemName}</span><b>LKR {item.lineTotal.toFixed(2)}</b></div>)}
                </div>
                {order.fulfillmentMethod === 'Delivery' && <div className="cust-order-ops-delivery">
                  <span>⌖ {order.deliveryAddress}</span>
                  {order.deliveryLatitude != null && order.deliveryLongitude != null && <a href={`https://www.google.com/maps/search/?api=1&query=${order.deliveryLatitude},${order.deliveryLongitude}`} target="_blank" rel="noreferrer">Open delivery pin ↗</a>}
                </div>}
                <div className="cust-order-ops-footer">
                  <strong>LKR {order.total.toFixed(2)}</strong>
                  {actions.length > 0 && <div className="cust-order-ops-actions">
                    {actions.map((status) => <button
                      key={status}
                      type="button"
                      className={status === 'Cancelled' ? 'btn btn-secondary cust-order-cancel' : 'btn btn-primary'}
                      disabled={isUpdating}
                      onClick={() => void changeStatus(order, status)}
                      aria-label={`${status === 'Cancelled' ? 'Cancel' : 'Mark'} order ${order.number} as ${statusLabel(status)}`}
                    >{updatingId === order.id ? 'Saving…' : statusLabel(status)}</button>)}
                  </div>}
                  {actions.length === 0 && <span className="cust-order-ops-done">This order is complete</span>}
                </div>
              </article>
            );
          })}
        </section>
      )}
    </main>
  );
}
