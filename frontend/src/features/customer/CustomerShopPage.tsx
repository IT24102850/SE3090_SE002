import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import type { RootState } from '../../store/store';
import { switchBusinessSession } from '../../store/authSlice';
import {
  bookingApi,
  useGetPublicCustomerBusinessesQuery,
  useGetCustomerOrderBranchesQuery,
  useGetCustomerProductsQuery,
  useJoinCustomerBusinessMutation,
  useGetMyCustomerOrdersQuery,
  usePlaceCustomerOrderMutation,
  type CustomerOrder,
  type CustomerOrderProduct,
  useGetTenantQuery,
} from '../../api/bookingApi';
import DeliveryLocationPicker, { type DeliveryPin } from './DeliveryLocationPicker';
import './customer.css';

type FulfillmentMethod = 'Pickup' | 'Delivery';
const currency = new Intl.NumberFormat('en-LK', { style: 'currency', currency: 'LKR', maximumFractionDigits: 2 });

function getErrorMessage(error: unknown, fallback = 'We could not place that order. Please try again.') {
  if (error && typeof error === 'object' && 'data' in error) {
    const data = (error as { data?: { message?: string } }).data;
    if (data?.message) return data.message;
  }
  return fallback;
}

function orderDate(value: string) {
  return new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

export default function CustomerShopPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const dispatch = useDispatch();
  const { data: tenant } = useGetTenantQuery({ tenantId: user?.tenantId ?? '' }, { skip: !user?.tenantId });
  const { data: branches = [], isLoading: branchesLoading, isError: branchesError } = useGetCustomerOrderBranchesQuery();
  const [selectedBranchId, setSelectedBranchId] = useState(user?.branchId ?? '');
  const [activeTab, setActiveTab] = useState<'shop' | 'orders'>('shop');
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('All items');
  const [cart, setCart] = useState<Record<string, number>>({});
  const [fulfillmentMethod, setFulfillmentMethod] = useState<FulfillmentMethod>('Pickup');
  const [deliveryAddress, setDeliveryAddress] = useState('');
  const [notes, setNotes] = useState('');
  const [deliveryPin, setDeliveryPin] = useState<DeliveryPin | null>(null);
  const [businessPickerOpen, setBusinessPickerOpen] = useState(false);
  const [businessError, setBusinessError] = useState('');
  const {
    data: businesses = [],
    isLoading: businessesLoading,
    isError: businessesError,
    refetch: refetchBusinesses,
  } = useGetPublicCustomerBusinessesQuery();
  const [joinBusiness, { isLoading: isJoiningBusiness }] = useJoinCustomerBusinessMutation();
  const [orderError, setOrderError] = useState('');
  const [placeOrder, { isLoading: isPlacingOrder }] = usePlaceCustomerOrderMutation();
  const { data: products = [], isLoading: productsLoading, isError: productsError, refetch: refetchProducts } =
    useGetCustomerProductsQuery({ branchId: selectedBranchId }, { skip: !selectedBranchId });
  const { data: orders = [], isLoading: ordersLoading, isError: ordersError, refetch: refetchOrders } =
    useGetMyCustomerOrdersQuery(undefined, { pollingInterval: 30000, refetchOnFocus: true });

  useEffect(() => {
    if (!branches.length) return;
    setSelectedBranchId((current) =>
      branches.find((branch) => branch.id === current)?.id
      ?? branches.find((branch) => branch.id === user?.branchId)?.id
      ?? branches[0].id,
    );
  }, [branches, user?.branchId]);

  const categories = useMemo(
    () => ['All items', ...new Set(products.map((product) => product.category))],
    [products],
  );
  const visibleProducts = useMemo(() => {
    const term = search.trim().toLowerCase();
    return products.filter((product) => {
      const matchesCategory = category === 'All items' || product.category === category;
      const matchesSearch = !term || `${product.name} ${product.description ?? ''} ${product.sku} ${product.category}`.toLowerCase().includes(term);
      return matchesCategory && matchesSearch;
    });
  }, [category, products, search]);
  const productById = useMemo(() => new Map(products.map((product) => [product.id, product])), [products]);
  const cartItems = Object.entries(cart)
    .map(([id, quantity]) => ({ product: productById.get(id), quantity }))
    .filter((line): line is { product: CustomerOrderProduct; quantity: number } => Boolean(line.product));
  const cartTotal = cartItems.reduce((sum, line) => sum + line.product.price * line.quantity, 0);
  const cartCount = Object.values(cart).reduce((sum, quantity) => sum + quantity, 0);
  const selectedBranch = branches.find((branch) => branch.id === selectedBranchId);

  function setQuantity(product: CustomerOrderProduct, quantity: number) {
    setCart((current) => {
      const next = { ...current };
      if (quantity <= 0) delete next[product.id];
      else next[product.id] = Math.min(quantity, product.quantityAvailable);
      return next;
    });
  }

  async function submitOrder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setOrderError('');
    try {
      await placeOrder({
        branchId: selectedBranchId,
        fulfillmentMethod,
        deliveryAddress: fulfillmentMethod === 'Delivery' ? deliveryAddress.trim() : undefined,
        deliveryLatitude: fulfillmentMethod === 'Delivery' ? deliveryPin?.latitude : undefined,
        deliveryLongitude: fulfillmentMethod === 'Delivery' ? deliveryPin?.longitude : undefined,
        notes: notes.trim() || undefined,
        items: cartItems.map(({ product, quantity }) => ({ inventoryItemId: product.id, quantity })),
      }).unwrap();
      setCart({});
      setDeliveryAddress('');
      setDeliveryPin(null);
      setNotes('');
      setActiveTab('orders');
      await Promise.all([refetchOrders(), refetchProducts()]);
    } catch (error) {
      setOrderError(getErrorMessage(error));
    }
  }

  async function switchBusiness(tenantId: string) {
    if (cartCount > 0 && !window.confirm('Switching businesses clears your current basket. Continue?')) return;
    setBusinessError('');
    try {
      const session = await joinBusiness(tenantId).unwrap();
      dispatch(switchBusinessSession(session));
      dispatch(bookingApi.util.resetApiState());
      setCart({});
      setSelectedBranchId('');
      setBusinessPickerOpen(false);
    } catch (error) {
      setBusinessError(getErrorMessage(error, 'Could not connect to that business. Please try again.'));
    }
  }

  return (
    <div className="cust-page cust-shop-page">
      <section className="cust-shop-hero">
        <div className="cust-shop-orbit" aria-hidden="true">✦</div>
        <div>
          <span className="cust-shop-kicker">A little something for you</span>
          <h1>Shop {tenant?.name ?? 'the store'}</h1>
          <p>Find something you love, then choose pickup or delivery. Pay when your order arrives.</p>
        </div>
        <div className="cust-shop-hero-icon" aria-hidden="true">🛍️</div>
      </section>

      <div className="cust-shop-toolbar">
        <div className="cust-tabs" role="tablist" aria-label="Shop sections">
          <button type="button" role="tab" aria-selected={activeTab === 'shop'} className={activeTab === 'shop' ? 'active' : ''} onClick={() => setActiveTab('shop')}>Browse items</button>
          <button type="button" role="tab" aria-selected={activeTab === 'orders'} className={activeTab === 'orders' ? 'active' : ''} onClick={() => setActiveTab('orders')}>My orders <span className="cust-shop-order-count">{orders.length}</span></button>
        </div>
        {activeTab === 'shop' && (
          <label className="cust-shop-location">
            <span>Shopping at</span>
            <select
              aria-label="Shopping location"
              value={selectedBranchId}
              disabled={branchesLoading || branches.length === 0}
              onChange={(event) => {
                setCart({});
                setCategory('All items');
                setSelectedBranchId(event.target.value);
              }}
            >
              {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
            </select>
          </label>
        )}
        <button type="button" className="btn btn-secondary cust-shop-switch" onClick={() => setBusinessPickerOpen(true)}>
          <span aria-hidden="true">↗</span> Switch business
        </button>
      </div>

      {activeTab === 'shop' ? (
        branchesError ? (
          <div className="card cust-shop-message" role="alert">We could not load store locations. Please refresh and try again.</div>
        ) : branchesLoading ? (
          <div className="card cust-shop-message" aria-busy="true"><span className="spinner spinner-dark" /> Finding your store…</div>
        ) : branches.length === 0 ? (
          <div className="card cust-shop-message">This business has not set up a shopping location yet.</div>
        ) : (
          <div className="cust-shop-layout">
            <section className="cust-shop-main">
              <div className="cust-shop-search-row">
                <label className="cust-shop-search">
                  <span aria-hidden="true">⌕</span>
                  <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search the collection…" aria-label="Search products" />
                  {search && <button type="button" aria-label="Clear search" onClick={() => setSearch('')}>×</button>}
                </label>
                <span className="cust-shop-result-count">{visibleProducts.length} {visibleProducts.length === 1 ? 'find' : 'finds'}</span>
              </div>
              <div className="cust-chips cust-shop-categories" aria-label="Product categories">
                {categories.map((item) => (
                  <button key={item} type="button" className={`cust-chip ${category === item ? 'active' : ''}`} onClick={() => setCategory(item)}>{item}</button>
                ))}
              </div>

              {productsLoading ? (
                <div className="card cust-shop-message" aria-busy="true"><span className="spinner spinner-dark" /> Gathering the good stuff…</div>
              ) : productsError ? (
                <div className="card cust-shop-message" role="alert">The catalog did not load. <button className="btn btn-secondary" type="button" onClick={() => refetchProducts()}>Try again</button></div>
              ) : visibleProducts.length === 0 ? (
                <div className="card cust-shop-message">
                  <span className="cust-shop-empty-icon" aria-hidden="true">🌱</span>
                  <strong>{products.length ? 'No matches just yet' : 'Nothing on the shelves just yet'}</strong>
                  <span>{products.length ? 'Try another search or category.' : 'Check back soon — new finds may be on the way.'}</span>
                </div>
              ) : (
                <div className="cust-shop-products">
                  {visibleProducts.map((product, index) => (
                    <article key={product.id} className="cust-shop-product" style={{ animationDelay: `${Math.min(index, 8) * 45}ms` }}>
                      <div className="cust-shop-product-art"><span aria-hidden="true">✦</span><small>{product.category}</small></div>
                      <div className="cust-shop-product-body">
                        <div className="cust-shop-product-meta"><span>{product.sku}</span><span>{product.quantityAvailable} available</span></div>
                        <h2>{product.name}</h2>
                        <p>{product.description || `A lovely ${product.category.toLowerCase()} pick, ready for you.`}</p>
                        <div className="cust-shop-product-foot">
                          <strong>{currency.format(product.price)}{product.unit ? <small> / {product.unit}</small> : null}</strong>
                          {cart[product.id] ? (
                            <div className="cust-shop-stepper" aria-label={`${product.name} quantity`}>
                              <button type="button" aria-label={`Remove one ${product.name}`} onClick={() => setQuantity(product, cart[product.id] - 1)}>−</button>
                              <span>{cart[product.id].toLocaleString()}</span>
                              <button type="button" aria-label={`Add one ${product.name}`} disabled={cart[product.id] >= product.quantityAvailable} onClick={() => setQuantity(product, cart[product.id] + 1)}>+</button>
                            </div>
                          ) : (
                            <button type="button" className="cust-shop-add" onClick={() => setQuantity(product, Math.min(1, product.quantityAvailable))} aria-label={`Add ${product.name} to basket`}>Add <span aria-hidden="true">+</span></button>
                          )}
                        </div>
                      </div>
                    </article>
                  ))}
                </div>
              )}
            </section>

            <aside className="cust-shop-cart card">
              <div className="cust-shop-cart-heading">
                <div><span className="cust-shop-kicker">Your picks</span><h2>Basket <span>{cartCount}</span></h2></div>
                <span className="cust-shop-bag" aria-hidden="true">🧺</span>
              </div>
              {cartItems.length === 0 ? (
                <div className="cust-shop-cart-empty"><span aria-hidden="true">🪄</span><strong>Your basket is ready</strong><small>Add a few favorites and they’ll appear here.</small></div>
              ) : (
                <form className="cust-shop-checkout" onSubmit={submitOrder}>
                  <div className="cust-shop-cart-lines">
                    {cartItems.map(({ product, quantity }) => (
                      <div className="cust-shop-cart-line" key={product.id}>
                        <div><strong>{product.name}</strong><small>{quantity.toLocaleString()} × {currency.format(product.price)}</small></div>
                        <b>{currency.format(product.price * quantity)}</b>
                      </div>
                    ))}
                  </div>
                  <div className="cust-shop-total"><span>Estimated total</span><strong>{currency.format(cartTotal)}</strong></div>
                  <fieldset className="cust-shop-fulfillment">
                    <legend>How would you like it?</legend>
                    <label><input type="radio" name="fulfillment" checked={fulfillmentMethod === 'Pickup'} onChange={() => setFulfillmentMethod('Pickup')} /> Pick up at {selectedBranch?.name ?? 'the store'}</label>
                    <label><input type="radio" name="fulfillment" checked={fulfillmentMethod === 'Delivery'} onChange={() => setFulfillmentMethod('Delivery')} /> Deliver to me</label>
                  </fieldset>
                  {fulfillmentMethod === 'Delivery' && (
                    <>
                      <label className="cust-shop-field">Delivery address
                        <textarea value={deliveryAddress} onChange={(event) => setDeliveryAddress(event.target.value)} required maxLength={500} placeholder="Street, town, and a helpful landmark" />
                      </label>
                      <p className="cust-shop-gps-note">Adding a pin is optional. It is shared with this business for this order only.</p>
                      <DeliveryLocationPicker value={deliveryPin} onChange={setDeliveryPin} />
                    </>
                  )}
                  <label className="cust-shop-field">A note for the team <span>(optional)</span>
                    <textarea value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={1000} placeholder="Anything we should know?" />
                  </label>
                  <p className="cust-shop-pay-note">No payment needed now. Pay at pickup or when your order is delivered.</p>
                  {orderError && <p className="cust-shop-error" role="alert">{orderError}</p>}
                  <button className="btn btn-primary cust-shop-place-order" type="submit" disabled={isPlacingOrder || !selectedBranchId}>
                    {isPlacingOrder ? 'Placing your order…' : <>Place my order <span aria-hidden="true">→</span></>}
                  </button>
                </form>
              )}
            </aside>
          </div>
        )
      ) : (
        <section className="cust-shop-orders" aria-live="polite">
          {ordersLoading ? (
            <div className="card cust-shop-message" aria-busy="true"><span className="spinner spinner-dark" /> Loading your orders…</div>
          ) : ordersError ? (
            <div className="card cust-shop-message" role="alert">We could not load your orders. <button className="btn btn-secondary" type="button" onClick={() => refetchOrders()}>Try again</button></div>
          ) : orders.length === 0 ? (
            <div className="card cust-shop-message"><span className="cust-shop-empty-icon" aria-hidden="true">📦</span><strong>Your first order is waiting</strong><span>When you find something you love, your order details will be here.</span><button className="btn btn-primary" type="button" onClick={() => setActiveTab('shop')}>Explore the shop</button></div>
          ) : (
            orders.map((order) => (
              <OrderCard
                key={order.id}
                order={order}
                branchName={branches.find((branch) => branch.id === order.branchId)?.name ?? 'the store'}
              />
            ))
          )}
        </section>
      )}
      {businessPickerOpen && (
        <div className="cust-shop-modal-backdrop" onMouseDown={(event) => {
          if (event.target === event.currentTarget) setBusinessPickerOpen(false);
        }}>
          <section className="cust-shop-business-modal card" role="dialog" aria-modal="true" aria-labelledby="business-switch-title">
            <button type="button" className="cust-shop-modal-close" aria-label="Close business picker" onClick={() => setBusinessPickerOpen(false)}>×</button>
            <span className="cust-shop-kicker">Your next favorite</span>
            <h2 id="business-switch-title">Choose a business</h2>
            <p>Switching connects your shopping session to another business. Your other memberships stay saved.</p>
            {businessError && <p className="cust-shop-error" role="alert">{businessError}</p>}
            {businessesLoading ? (
              <div className="cust-shop-message" aria-busy="true">Finding businesses…</div>
            ) : businessesError ? (
              <div className="cust-shop-message" role="alert">We could not load businesses. <button className="btn btn-secondary" type="button" onClick={() => refetchBusinesses()}>Try again</button></div>
            ) : (
              <div className="cust-shop-business-list">
                {businesses.map((business) => (
                  <button key={business.id} type="button" disabled={isJoiningBusiness || business.id === user?.tenantId} onClick={() => void switchBusiness(business.id)}>
                    <span className="cust-shop-business-icon" aria-hidden="true">🏪</span>
                    <span><strong>{business.name}</strong><small>{business.businessType}{business.id === user?.tenantId ? ' · Current business' : ''}</small></span>
                    <span aria-hidden="true">{business.id === user?.tenantId ? '✓' : '→'}</span>
                  </button>
                ))}
              </div>
            )}
            {isJoiningBusiness && <p className="cust-shop-message" aria-live="polite">Connecting to your business…</p>}
          </section>
        </div>
      )}
    </div>
  );
}

function OrderCard({ order, branchName }: { order: CustomerOrder; branchName: string }) {
  return (
    <article className="cust-shop-order card">
      <div className="cust-shop-order-top">
        <div><span className="cust-shop-kicker">{orderDate(order.createdAt)}</span><h2>{order.number}</h2></div>
        <span className={`cust-shop-status ${order.status.toLowerCase()}`}>{order.status}</span>
      </div>
      <div className="cust-shop-order-items">
        {order.items.map((item) => (
          <div key={`${order.id}-${item.inventoryItemId}`}><span>{item.quantity.toLocaleString()} × {item.itemName}</span><b>{currency.format(item.lineTotal)}</b></div>
        ))}
      </div>
      <div className="cust-shop-order-bottom">
        <span>{order.fulfillmentMethod === 'Delivery' ? `Delivery · ${order.deliveryAddress}` : `Pickup at ${branchName}`} · Pay when you receive it</span>
        <strong>{currency.format(order.total)}</strong>
      </div>
      {order.statusUpdates?.length > 0 && (
        <ol className="cust-shop-timeline" aria-label={`Tracking updates for ${order.number}`}>
          {order.statusUpdates.map((update, index) => (
            <li key={`${order.id}-${update.createdAt}-${update.status}`} className={index === order.statusUpdates.length - 1 ? 'current' : 'complete'}>
              <span className="cust-shop-timeline-dot" aria-hidden="true">{index === order.statusUpdates.length - 1 ? '✦' : '✓'}</span>
              <div><strong>{update.status}</strong><p>{update.message}</p><time dateTime={update.createdAt}>{orderDate(update.createdAt)}</time></div>
            </li>
          ))}
        </ol>
      )}
      {order.deliveryLatitude != null && order.deliveryLongitude != null && (
        <a className="cust-shop-map-link" href={`https://www.google.com/maps/search/?api=1&query=${order.deliveryLatitude},${order.deliveryLongitude}`} target="_blank" rel="noreferrer">
          ⌖ View your shared delivery pin
        </a>
      )}
    </article>
  );
}
