import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { getStoredToken } from '../authToken';
import { useToast } from '../ui/ToastContext';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';

type Supplier = {
  id: string;
  name: string;
  contactPerson: string | null;
  email: string;
  phone: string;
  address: string | null;
  paymentTerms: string | null;
  notes: string | null;
  leadTimeDays: number | null;
  createdAt: string;
  updatedAt: string;
  orderCount: number;
  activeOrderCount: number;
  totalOrderValue: number;
  lastOrderAt: string | null;
};
type SupplierFilter = 'all' | 'missing-contact' | 'missing-lead-time';
type SupplierOrder = {
  id: string;
  number: string;
  branch?: string | null;
  status: string;
  totalAmount: number;
  lineItems: number;
  createdAt: string;
};
type SupplierOrderListResponse = {
  items: SupplierOrder[];
  totalPages: number;
  totalCount: number;
};
type SupplierOrderHistory = {
  orders: SupplierOrder[];
  loading: boolean;
  error: string;
};

const supplierCurrency = new Intl.NumberFormat(undefined, {
  style: 'currency',
  currency: 'LKR',
  maximumFractionDigits: 2,
});

function formatSupplierCurrency(value: unknown): string {
  const amount = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : 0;
  return supplierCurrency.format(Number.isFinite(amount) ? amount : 0);
}

function supplierOrderValue(orders: SupplierOrder[]): number {
  return orders
    .filter((order) => order.status.toLowerCase() !== 'cancelled')
    .reduce((total, order) => {
      const amount = Number(order.totalAmount);
      return total + (Number.isFinite(amount) ? amount : 0);
    }, 0);
}

export function SuppliersPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [query, setQuery] = useState('');
  const [directoryFilter, setDirectoryFilter] = useState<SupplierFilter>('all');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState('');
  const [contactPerson, setContactPerson] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [address, setAddress] = useState('');
  const [paymentTerms, setPaymentTerms] = useState('');
  const [notes, setNotes] = useState('');
  const [leadTimeDays, setLeadTimeDays] = useState('');
  const [editingSupplierId, setEditingSupplierId] = useState<string | null>(null);
  const [expandedSupplierId, setExpandedSupplierId] = useState<string | null>(null);
  const [supplierOrderHistories, setSupplierOrderHistories] = useState<Record<string, SupplierOrderHistory>>({});
  const [confirmDeleteSupplierId, setConfirmDeleteSupplierId] = useState<string | null>(null);
  const [deletingSupplierId, setDeletingSupplierId] = useState<string | null>(null);

  const loadSuppliers = useCallback(async () => {
    setLoading(true);
    setLoadError('');
    try {
      const response = await fetch('/api/suppliers', {
        headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' },
      });
      if (!response.ok) throw new Error(`Supplier request failed (${response.status})`);
      const result = await response.json();
      setSuppliers(Array.isArray(result.items) ? result.items : []);
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to load suppliers.';
      setLoadError(message);
      return false;
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => { void loadSuppliers(); }, [loadSuppliers]);
  useEffect(() => {
    if (!expandedSupplierId) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setExpandedSupplierId(null);
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [expandedSupplierId]);

  async function loadSupplierOrderHistory(supplier: Supplier) {
    const cached = supplierOrderHistories[supplier.id];
    if (cached && !cached.error) return;

    setSupplierOrderHistories((current) => ({
      ...current,
      [supplier.id]: { orders: cached?.orders ?? [], loading: true, error: '' },
    }));

    try {
      const firstPageResponse = await fetch(
        `/api/purchase-orders?supplierId=${encodeURIComponent(supplier.id)}&page=1&pageSize=100`,
        { headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' } },
      );
      if (!firstPageResponse.ok) {
        throw new Error(`Order history request failed (${firstPageResponse.status})`);
      }
      const firstPage = await firstPageResponse.json() as SupplierOrderListResponse;
      const remainingPages = await Promise.all(
        Array.from({ length: Math.max(0, firstPage.totalPages - 1) }, (_, index) =>
          fetch(
            `/api/purchase-orders?supplierId=${encodeURIComponent(supplier.id)}&page=${index + 2}&pageSize=100`,
            { headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' } },
          ).then(async (response) => {
            if (!response.ok) throw new Error(`Order history request failed (${response.status})`);
            return response.json() as Promise<SupplierOrderListResponse>;
          }),
        ),
      );
      setSupplierOrderHistories((current) => ({
        ...current,
        [supplier.id]: {
          orders: [firstPage, ...remainingPages].flatMap((page) => page.items),
          loading: false,
          error: '',
        },
      }));
    } catch (error) {
      setSupplierOrderHistories((current) => ({
        ...current,
        [supplier.id]: {
          orders: current[supplier.id]?.orders ?? [],
          loading: false,
          error: error instanceof Error ? error.message : 'Unable to load supplier order history.',
        },
      }));
    }
  }

  function toggleSupplierDetails(supplier: Supplier) {
    if (expandedSupplierId === supplier.id) {
      setExpandedSupplierId(null);
      return;
    }
    setExpandedSupplierId(supplier.id);
    void loadSupplierOrderHistory(supplier);
  }

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return suppliers.filter((supplier) => {
      const matchesQuery = !needle || [
        supplier.name, supplier.contactPerson ?? '', supplier.email, supplier.phone,
        supplier.address ?? '', supplier.paymentTerms ?? '', supplier.notes ?? '',
      ].some((field) => field.toLowerCase().includes(needle));
      const matchesFilter = directoryFilter === 'all' ||
        (directoryFilter === 'missing-contact' && !supplier.contactPerson && !supplier.email && !supplier.phone) ||
        (directoryFilter === 'missing-lead-time' && !supplier.leadTimeDays);
      return matchesQuery && matchesFilter;
    });
  }, [directoryFilter, query, suppliers]);

  async function createSupplier(event: FormEvent) {
    event.preventDefault();
    if (!name.trim()) return;
    const leadDays = leadTimeDays.trim() ? Number(leadTimeDays) : null;
    if (leadDays !== null && (!Number.isInteger(leadDays) || leadDays < 1 || leadDays > 90)) {
      notify('Lead time must be a whole number from 1 to 90 days.', 'error');
      return;
    }
    setSaving(true);
    try {
      const response = await fetch(editingSupplierId ? `/api/suppliers/${editingSupplierId}` : '/api/suppliers', {
        method: editingSupplierId ? 'PUT' : 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? `Bearer ${token}` : '' },
        body: JSON.stringify({
          name: name.trim(),
          contactPerson: contactPerson.trim(),
          email: email.trim(),
          phone: phone.trim(),
          address: address.trim(),
          paymentTerms: paymentTerms.trim(),
          notes: notes.trim(),
          leadTimeDays: leadDays,
        }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.message || body?.title || `Supplier could not be saved (${response.status})`);
      }
      const created = await response.json() as Supplier;
      setSuppliers((current) => {
        const previous = current.find((supplier) => supplier.id === created.id);
        const saved = editingSupplierId && previous
          ? {
            ...created,
            orderCount: previous.orderCount,
            activeOrderCount: previous.activeOrderCount,
            totalOrderValue: previous.totalOrderValue,
            lastOrderAt: previous.lastOrderAt,
          }
          : created;
        return [...current.filter((supplier) => supplier.id !== created.id), saved].sort((a, b) => a.name.localeCompare(b.name));
      });
      setName('');
      setContactPerson('');
      setEmail('');
      setPhone('');
      setAddress('');
      setPaymentTerms('');
      setNotes('');
      setLeadTimeDays('');
      setEditingSupplierId(null);
      setShowForm(false);
      notify(`${created.name} was ${editingSupplierId ? 'updated' : 'added'} to your suppliers.`, 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Supplier could not be saved.', 'error');
    } finally {
      setSaving(false);
    }
  }

  function editSupplier(supplier: Supplier) {
    setEditingSupplierId(supplier.id);
    setName(supplier.name);
    setContactPerson(supplier.contactPerson ?? '');
    setEmail(supplier.email);
    setPhone(supplier.phone);
    setAddress(supplier.address ?? '');
    setPaymentTerms(supplier.paymentTerms ?? '');
    setNotes(supplier.notes ?? '');
    setLeadTimeDays(supplier.leadTimeDays?.toString() ?? '');
    setShowForm(true);
  }

  function resetSupplierForm() {
    setEditingSupplierId(null);
    setName('');
    setContactPerson('');
    setEmail('');
    setPhone('');
    setAddress('');
    setPaymentTerms('');
    setNotes('');
    setLeadTimeDays('');
    setShowForm(false);
  }

  async function deleteSupplier(supplier: Supplier) {
    setDeletingSupplierId(supplier.id);
    try {
      const response = await fetch(`/api/suppliers/${supplier.id}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' },
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.message || body?.title || `Supplier could not be deleted (${response.status})`);
      }

      setSuppliers((current) => current.filter((item) => item.id !== supplier.id));
      setSupplierOrderHistories((current) => {
        const next = { ...current };
        delete next[supplier.id];
        return next;
      });
      setExpandedSupplierId(null);
      setConfirmDeleteSupplierId(null);
      notify(`${supplier.name} was deleted from your suppliers.`, 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Supplier could not be deleted.', 'error');
    } finally {
      setDeletingSupplierId(null);
    }
  }

  const contactCount = suppliers.filter((supplier) => supplier.contactPerson || supplier.email || supplier.phone).length;
  const missingContactCount = suppliers.length - contactCount;
  const contactCoveragePercent = suppliers.length === 0 ? 0 : Math.round((contactCount / suppliers.length) * 100);
  const missingLeadTimeCount = suppliers.filter((supplier) => !supplier.leadTimeDays).length;
  const leadTimeCount = suppliers.length - missingLeadTimeCount;
  const leadTimeCoveragePercent = suppliers.length === 0 ? 0 : Math.round((leadTimeCount / suppliers.length) * 100);
  const selectedSupplier = suppliers.find((supplier) => supplier.id === expandedSupplierId);
  const supplierPendingDeletion = suppliers.find((supplier) => supplier.id === confirmDeleteSupplierId);
  const selectedHistory = selectedSupplier ? supplierOrderHistories[selectedSupplier.id] : undefined;
  const selectedHistorySummary = selectedHistory && !selectedHistory.loading && !selectedHistory.error
    ? {
      orderCount: selectedHistory.orders.length,
      activeOrderCount: selectedHistory.orders.filter((order) => order.status.toLowerCase() !== 'cancelled').length,
      totalOrderValue: supplierOrderValue(selectedHistory.orders),
      lastOrderAt: selectedHistory.orders
        .map((order) => order.createdAt)
        .sort((left, right) => new Date(right).getTime() - new Date(left).getTime())[0] ?? null,
    }
    : null;

  return (
    <div className="page suppliers-page">
      <header className="suppliers-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="suppliers-hero-copy">
          <p className="suppliers-eyebrow"><span aria-hidden="true">◈</span> INVENTORY PARTNERS</p>
          <h1>Supplier directory</h1>
          <p>Keep supplier contacts together and make purchasing easier to coordinate.</p>
          <div className="suppliers-hero-meta"><span className={`suppliers-live-dot${loading ? ' is-loading' : ''}`} aria-hidden="true" />{loading ? 'Syncing supplier records…' : `${suppliers.length} supplier${suppliers.length === 1 ? '' : 's'} in your directory`}</div>
        </div>
        <div className="suppliers-hero-actions">
          <button type="button" className="btn suppliers-refresh" onClick={() => { void loadSuppliers().then((ok) => { if (ok) notify('Supplier list refreshed.', 'success'); }); }} disabled={loading}>
            <span aria-hidden="true">↻</span> {loading ? 'Refreshing…' : 'Refresh'}
          </button>
          <button type="button" className="btn suppliers-add" onClick={() => { if (showForm) resetSupplierForm(); else { resetSupplierForm(); setShowForm(true); } }}>{showForm ? 'Close form' : '＋ Add supplier'}</button>
        </div>
        <div className="suppliers-hero-mark" aria-hidden="true"><span>♧</span><i /><i /><i /></div>
      </header>

      {loadError && <div className="page-notice" role="alert">{loadError}</div>}

      <section className="suppliers-summary" aria-label="Supplier summary">
        <article className="suppliers-summary-card suppliers-summary-directory">
          <div className="suppliers-summary-main">
            <span className="suppliers-summary-icon suppliers-icon-teal" aria-hidden="true">♧</span>
            <div className="suppliers-summary-copy">
              <span className="suppliers-summary-kicker">PARTNER DIRECTORY</span>
              <strong>{suppliers.length}</strong>
              <span className="suppliers-summary-label">Suppliers registered</span>
            </div>
            <span className="suppliers-summary-index" aria-hidden="true">01</span>
          </div>
          <div className="suppliers-summary-detail">
            <span className="suppliers-summary-detail-mark" aria-hidden="true">✓</span>
            {contactCount} of {suppliers.length} {suppliers.length === 1 ? 'supplier has' : 'suppliers have'} contact details
          </div>
        </article>
        <article className="suppliers-summary-card suppliers-summary-contacts">
          <div className="suppliers-summary-main">
            <span className="suppliers-summary-icon suppliers-icon-blue" aria-hidden="true">✉</span>
            <div className="suppliers-summary-copy">
              <span className="suppliers-summary-kicker">CONTACT COVERAGE</span>
              <strong>{contactCount}</strong>
              <span className="suppliers-summary-label">Suppliers with contact details</span>
            </div>
            <span className="suppliers-summary-percent">{contactCoveragePercent}%</span>
          </div>
          <div className="suppliers-coverage-track" role="progressbar" aria-label="Supplier contact coverage" aria-valuemin={0} aria-valuemax={100} aria-valuenow={contactCoveragePercent}>
            <span style={{ width: `${contactCoveragePercent}%` }} />
          </div>
          <div className="suppliers-summary-detail">
            <span>{missingContactCount === 0 ? 'All suppliers have contact details' : `${missingContactCount} ${missingContactCount === 1 ? 'supplier is' : 'suppliers are'} missing details`}</span>
            <span className={`suppliers-coverage-status${missingContactCount === 0 && suppliers.length > 0 ? ' is-complete' : ''}`}>
              {suppliers.length === 0 ? 'No data yet' : missingContactCount === 0 ? 'Complete' : 'Needs attention'}
            </span>
          </div>
        </article>
        <article className="suppliers-summary-card suppliers-summary-lead-time">
          <div className="suppliers-summary-main">
            <span className="suppliers-summary-icon suppliers-icon-violet" aria-hidden="true">▤</span>
            <div className="suppliers-summary-copy">
              <span className="suppliers-summary-kicker">DELIVERY READINESS</span>
              <strong>{leadTimeCount}</strong>
              <span className="suppliers-summary-label">Suppliers with lead times</span>
            </div>
            <span className="suppliers-summary-percent">{leadTimeCoveragePercent}%</span>
          </div>
          <div className="suppliers-coverage-track" role="progressbar" aria-label="Supplier lead time coverage" aria-valuemin={0} aria-valuemax={100} aria-valuenow={leadTimeCoveragePercent}>
            <span style={{ width: `${leadTimeCoveragePercent}%` }} />
          </div>
          <div className="suppliers-summary-detail">
            <span>{missingLeadTimeCount === 0 ? 'Lead times ready for planning' : `${missingLeadTimeCount} ${missingLeadTimeCount === 1 ? 'supplier needs' : 'suppliers need'} a lead time`}</span>
            <span className={`suppliers-coverage-status${missingLeadTimeCount === 0 && suppliers.length > 0 ? ' is-complete' : ''}`}>
              {suppliers.length === 0 ? 'No data yet' : missingLeadTimeCount === 0 ? 'Ready' : 'Add lead times'}
            </span>
          </div>
        </article>
      </section>

      {showForm && (
        <form className="suppliers-create-card" onSubmit={(event) => void createSupplier(event)}>
          <div className="suppliers-create-heading"><div><span className="suppliers-create-kicker">{editingSupplierId ? 'EDIT PARTNER' : 'NEW PARTNER'}</span><h2>{editingSupplierId ? 'Update supplier' : 'Add a supplier'}</h2><p>Record the supplier's usual delivery lead time from your order history.</p></div><span className="suppliers-create-symbol" aria-hidden="true">＋</span></div>
          <div className="suppliers-form-grid">
            <label>Supplier name <input value={name} onChange={(event) => setName(event.target.value)} required maxLength={160} placeholder="e.g. Central Office Supplies" /></label>
            <label>Contact person <input value={contactPerson} onChange={(event) => setContactPerson(event.target.value)} maxLength={160} placeholder="Primary contact name" /></label>
            <label>Email address <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} maxLength={256} placeholder="orders@example.com" /></label>
            <label>Phone number <input type="tel" value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={64} placeholder="+94 …" /></label>
            <label>Usual lead time (days) <input type="number" min={1} max={90} step={1} value={leadTimeDays} onChange={(event) => setLeadTimeDays(event.target.value)} placeholder="Leave blank if unknown" /></label>
            <label>Payment terms <input value={paymentTerms} onChange={(event) => setPaymentTerms(event.target.value)} maxLength={160} placeholder="e.g. Net 30 or payment on delivery" /></label>
            <label>Business address <textarea value={address} onChange={(event) => setAddress(event.target.value)} maxLength={500} rows={2} placeholder="Supplier's billing or delivery address" /></label>
            <label>Supplier notes <textarea value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={1000} rows={2} placeholder="Useful purchasing or delivery notes" /></label>
          </div>
          <div className="suppliers-form-actions"><button className="btn btn-secondary" type="button" onClick={resetSupplierForm}>Cancel</button><button className="btn btn-primary" type="submit" disabled={saving || !name.trim()}>{saving ? 'Saving…' : editingSupplierId ? 'Save changes' : 'Save supplier'}</button></div>
        </form>
      )}

      <section className="panel suppliers-directory-panel">
        <div className="suppliers-directory-head"><div><span className="suppliers-section-mark" aria-hidden="true">▤</span><div><h2>All suppliers</h2><p>Contact, delivery, and purchasing details for your inventory workspace.</p></div></div><label className="suppliers-search"><span aria-hidden="true">⌕</span><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search supplier details" aria-label="Search suppliers" /></label></div>
        <div className="inventory-quick-filters" role="group" aria-label="Filter supplier directory">
          <button type="button" className={`inventory-chip${directoryFilter === 'all' ? ' is-active' : ''}`} aria-pressed={directoryFilter === 'all'} onClick={() => setDirectoryFilter('all')}>All suppliers <strong>({suppliers.length})</strong></button>
          <button type="button" className={`inventory-chip chip-amber${directoryFilter === 'missing-contact' ? ' is-active' : ''}`} aria-pressed={directoryFilter === 'missing-contact'} onClick={() => setDirectoryFilter('missing-contact')}>Missing contact <strong>({missingContactCount})</strong></button>
          <button type="button" className={`inventory-chip chip-red${directoryFilter === 'missing-lead-time' ? ' is-active' : ''}`} aria-pressed={directoryFilter === 'missing-lead-time'} onClick={() => setDirectoryFilter('missing-lead-time')}>Lead time not set <strong>({missingLeadTimeCount})</strong></button>
          {(query || directoryFilter !== 'all') && <button type="button" className="btn btn-ghost inventory-clear-filters" onClick={() => { setQuery(''); setDirectoryFilter('all'); }}>Clear filters</button>}
        </div>
        <div className="table-wrap">
          <table className="data-table suppliers-table">
            <thead><tr><th>Supplier</th><th>Email</th><th>Phone</th><th>Lead time</th><th>Payment terms</th><th>Added</th><th>Orders</th><th>Actions</th></tr></thead>
            <tbody>
              {filtered.map((supplier) => (
                <tr key={supplier.id}>
                  <td>
                    <div className="suppliers-table-name"><span className="suppliers-avatar">{supplier.name.trim().charAt(0).toUpperCase()}</span><div><strong>{supplier.name}</strong><small>{supplier.contactPerson ? `Contact: ${supplier.contactPerson}` : 'Contact person not set'}</small></div></div>
                  </td>
                  <td>{supplier.email ? <a href={`mailto:${supplier.email}`}>{supplier.email}</a> : <span className="suppliers-missing">No email saved</span>}</td>
                  <td>{supplier.phone ? <a href={`tel:${supplier.phone}`}>{supplier.phone}</a> : <span className="suppliers-missing">No phone saved</span>}</td>
                  <td>{supplier.leadTimeDays ? `${supplier.leadTimeDays} days` : <span className="suppliers-missing">Not set</span>}</td>
                  <td>{supplier.paymentTerms || <span className="suppliers-missing">Not set</span>}</td>
                  <td>{supplier.createdAt ? new Date(supplier.createdAt).toLocaleDateString() : '—'}</td>
                  <td>
                    <div className="supplier-order-summary">
                      <span className="supplier-order-summary-kicker">ORDERS</span>
                      <div className="supplier-order-summary-values">
                        <strong>{supplier.orderCount} <span>{supplier.orderCount === 1 ? 'order' : 'orders'}</span></strong>
                        <span>{formatSupplierCurrency(supplier.totalOrderValue)} PO value</span>
                      </div>
                      <button
                        type="button"
                        className="suppliers-history-button"
                        aria-expanded={expandedSupplierId === supplier.id}
                        aria-controls={`supplier-details-${supplier.id}`}
                        onClick={() => void toggleSupplierDetails(supplier)}
                      >
                          <span className="suppliers-order-history-icon" aria-hidden="true">▤</span> Order history &amp; details <span aria-hidden="true">→</span>
                      </button>
                    </div>
                  </td>
                  <td>
                    <div className="suppliers-row-actions">
                      <button type="button" className="btn btn-secondary" onClick={() => editSupplier(supplier)}>Edit</button>
                      <button
                        type="button"
                        className="btn btn-danger"
                        disabled={supplier.orderCount > 0 || deletingSupplierId === supplier.id}
                        title={supplier.orderCount > 0 ? 'Suppliers with purchase order history cannot be deleted.' : undefined}
                        onClick={() => setConfirmDeleteSupplierId(supplier.id)}
                      >{deletingSupplierId === supplier.id ? 'Deleting…' : 'Delete'}</button>
                    </div>
                  </td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={8} className="empty-state">{suppliers.length ? 'No suppliers match your search.' : 'No suppliers yet. Add a supplier to start building your directory.'}</td></tr>}
              {loading && suppliers.length === 0 && <tr><td colSpan={8} className="empty-state">Loading supplier directory…</td></tr>}
            </tbody>
          </table>
        </div>
        <div className="suppliers-directory-footer"><span>Showing {filtered.length} of {suppliers.length} suppliers</span><span>AI prefers the supplier assigned to an item, then falls back to its latest supplier-linked receipt.</span></div>
      </section>
      {selectedSupplier && (() => {
        const supplier = selectedSupplier;
        const history = supplierOrderHistories[supplier.id];
        const orders = history?.orders ?? [];
        const lastOrderAt = selectedHistorySummary?.lastOrderAt ?? supplier.lastOrderAt;
        return (
          <div
            className="modal-overlay suppliers-modal-overlay"
            role="presentation"
            onMouseDown={(event) => {
              if (event.target === event.currentTarget) setExpandedSupplierId(null);
            }}
          >
            <section
              className="modal suppliers-modal"
              id={`supplier-details-${supplier.id}`}
              role="dialog"
              aria-modal="true"
              aria-labelledby="supplier-details-title"
              onMouseDown={(event) => event.stopPropagation()}
            >
              <header className="modal-head">
                <div><span className="suppliers-create-kicker">SUPPLIER PROFILE</span><h2 id="supplier-details-title">{supplier.name}</h2></div>
                <button className="modal-close" type="button" aria-label="Close supplier details" onClick={() => setExpandedSupplierId(null)}>×</button>
              </header>
              <div className="modal-body suppliers-modal-body">
                <section className="suppliers-profile-metrics" aria-label={`${supplier.name} order summary`}>
                  <article className="supplier-metric-card supplier-metric-orders">
                    <span className="supplier-metric-icon" aria-hidden="true">▤</span>
                    <span className="supplier-metric-label">All orders</span>
                    <strong>{history?.loading ? '…' : selectedHistorySummary?.orderCount ?? supplier.orderCount}</strong>
                    <small>{lastOrderAt
                      ? `Last order ${new Date(lastOrderAt).toLocaleDateString()}`
                      : 'No order history yet'}</small>
                  </article>
                  <article className="supplier-metric-card supplier-metric-active">
                    <span className="supplier-metric-icon" aria-hidden="true">↗</span>
                    <span className="supplier-metric-label">Non-cancelled orders</span>
                    <strong>{history?.loading ? '…' : selectedHistorySummary?.activeOrderCount ?? supplier.activeOrderCount}</strong>
                    <small>Included in the PO value total</small>
                  </article>
                  <article className="supplier-metric-card supplier-metric-value">
                    <span className="supplier-metric-icon" aria-hidden="true">LKR</span>
                    <span className="supplier-metric-label">Total PO value</span>
                    <strong>{history?.loading ? '…' : formatSupplierCurrency(selectedHistorySummary?.totalOrderValue ?? supplier.totalOrderValue)}</strong>
                    <small>Not a confirmed amount paid</small>
                  </article>
                </section>
                <div className="suppliers-expanded-details">
                  <section className="suppliers-profile-details" aria-label={`${supplier.name} supplier details`}>
                    <h3>Supplier details</h3>
                    <dl>
                      <div><dt>Contact person</dt><dd>{supplier.contactPerson || 'Not provided'}</dd></div>
                      <div><dt>Email</dt><dd>{supplier.email || 'Not provided'}</dd></div>
                      <div><dt>Phone</dt><dd>{supplier.phone || 'Not provided'}</dd></div>
                      <div><dt>Business address</dt><dd>{supplier.address || 'Not provided'}</dd></div>
                      <div><dt>Payment terms</dt><dd>{supplier.paymentTerms || 'Not provided'}</dd></div>
                      <div><dt>Usual lead time</dt><dd>{supplier.leadTimeDays ? `${supplier.leadTimeDays} days` : 'Not set'}</dd></div>
                      <div><dt>Notes</dt><dd>{supplier.notes || 'No notes'}</dd></div>
                    </dl>
                  </section>
                  <section className="suppliers-order-history" aria-label={`${supplier.name} purchase order history`}>
                    <div className="suppliers-history-heading">
                      <div><h3>Purchase order history</h3><p>Cancelled orders are excluded from value; supplier payments are not tracked.</p></div>
                      <Link
                        className="suppliers-history-button"
                        to={`/purchase-orders?supplier=${encodeURIComponent(supplier.name)}`}
                      >Open purchase orders <span aria-hidden="true">↗</span></Link>
                    </div>
                    {history?.loading && (
                      <div className="suppliers-history-loading" role="status" aria-live="polite">
                        <span className="suppliers-history-spinner" aria-hidden="true" />
                        <span className="suppliers-history-loading-copy">
                          <strong>Loading purchase orders</strong>
                          <small>Gathering the latest supplier order history…</small>
                        </span>
                        <span className="suppliers-history-loading-bars" aria-hidden="true"><i /><i /><i /></span>
                      </div>
                    )}
                    {history?.error && (
                      <div className="page-notice" role="alert">
                        {history.error}
                        <button className="btn btn-secondary" type="button" onClick={() => {
                          setSupplierOrderHistories((current) => {
                            const next = { ...current };
                            delete next[supplier.id];
                            return next;
                          });
                          void loadSupplierOrderHistory(supplier);
                        }}>Retry</button>
                      </div>
                    )}
                    {!history?.loading && !history?.error && orders.length === 0 && (
                      <p>No purchase orders are recorded for this supplier yet.</p>
                    )}
                    {orders.length > 0 && (
                      <div className="table-wrap suppliers-history-table-wrap">
                        <table className="data-table suppliers-history-table">
                          <thead><tr><th>Order</th><th>Date</th><th>Branch</th><th>Status</th><th>Lines</th><th>Order value</th></tr></thead>
                          <tbody>
                            {orders.map((order) => (
                              <tr key={order.id}>
                                <td>{order.number}</td>
                                <td>{new Date(order.createdAt).toLocaleDateString()}</td>
                                <td>{order.branch || '—'}</td>
                                <td>{order.status}</td>
                                <td>{order.lineItems}</td>
                                <td>{formatSupplierCurrency(order.totalAmount)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </section>
                </div>
              </div>
            </section>
          </div>
        );
      })()}
      {supplierPendingDeletion && (
        <ConfirmDialog
          title={`Delete ${supplierPendingDeletion.name}?`}
          message="This permanently removes the supplier from your directory and clears its supplier references from inventory. This cannot be undone."
          confirmLabel={deletingSupplierId === supplierPendingDeletion.id ? 'Deleting…' : 'Delete supplier'}
          tone="danger"
          onConfirm={() => { void deleteSupplier(supplierPendingDeletion); }}
          onCancel={() => setConfirmDeleteSupplierId(null)}
        />
      )}
    </div>
  );
}
