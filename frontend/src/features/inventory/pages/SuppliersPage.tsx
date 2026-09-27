import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { getStoredToken } from '../authToken';
import { useToast } from '../ui/ToastContext';

type Supplier = {
  id: string;
  name: string;
  email: string;
  phone: string;
  createdAt: string;
  updatedAt: string;
};

export function SuppliersPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');

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

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return suppliers;
    return suppliers.filter((supplier) =>
      [supplier.name, supplier.email, supplier.phone].some((field) => field.toLowerCase().includes(needle)));
  }, [query, suppliers]);

  async function createSupplier(event: FormEvent) {
    event.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    try {
      const response = await fetch('/api/suppliers', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? `Bearer ${token}` : '' },
        body: JSON.stringify({ name: name.trim(), email: email.trim(), phone: phone.trim() }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.message || body?.title || `Supplier could not be saved (${response.status})`);
      }
      const created = await response.json() as Supplier;
      setSuppliers((current) => [...current, created].sort((a, b) => a.name.localeCompare(b.name)));
      setName('');
      setEmail('');
      setPhone('');
      setShowForm(false);
      notify(`${created.name} was added to your suppliers.`, 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Supplier could not be saved.', 'error');
    } finally {
      setSaving(false);
    }
  }

  const contactCount = suppliers.filter((supplier) => supplier.email || supplier.phone).length;

  return (
    <div className="page suppliers-page">
      <header className="suppliers-hero">
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
          <button type="button" className="btn suppliers-add" onClick={() => setShowForm((open) => !open)}>{showForm ? 'Close form' : '＋ Add supplier'}</button>
        </div>
        <div className="suppliers-hero-mark" aria-hidden="true"><span>♧</span><i /><i /><i /></div>
      </header>

      {loadError && <div className="page-notice" role="alert">{loadError}</div>}

      <section className="suppliers-summary" aria-label="Supplier summary">
        <article className="suppliers-summary-card suppliers-summary-directory">
          <div className="suppliers-summary-main"><span className="suppliers-summary-icon suppliers-icon-teal" aria-hidden="true">♧</span><div className="suppliers-summary-copy"><span className="suppliers-summary-kicker">PARTNER DIRECTORY</span><strong>{suppliers.length}</strong><span className="suppliers-summary-label">Suppliers registered</span></div><span className="suppliers-summary-index" aria-hidden="true">01</span></div>
          <div className="suppliers-summary-detail">{contactCount} {contactCount === 1 ? 'supplier has' : 'suppliers have'} contact information</div>
        </article>
        <article className="suppliers-summary-card suppliers-summary-contacts">
          <div className="suppliers-summary-main"><span className="suppliers-summary-icon suppliers-icon-blue" aria-hidden="true">✉</span><div className="suppliers-summary-copy"><span className="suppliers-summary-kicker">CONTACT COVERAGE</span><strong>{contactCount}</strong><span className="suppliers-summary-label">With contact details</span></div><span className="suppliers-summary-index" aria-hidden="true">02</span></div>
          <div className="suppliers-summary-detail">{suppliers.length - contactCount} {suppliers.length - contactCount === 1 ? 'supplier is' : 'suppliers are'} missing contact information</div>
        </article>
        <article className="suppliers-summary-card suppliers-summary-link">
          <div className="suppliers-summary-main"><span className="suppliers-summary-icon suppliers-icon-violet" aria-hidden="true">▤</span><div className="suppliers-summary-copy"><span className="suppliers-summary-kicker">PURCHASING TOOLS</span><strong>Purchase orders</strong><span className="suppliers-summary-label">Supplier-linked ordering</span></div><span className="suppliers-summary-index" aria-hidden="true">03</span></div>
          <div className="suppliers-summary-detail"><Link to="/purchase-orders">Open purchase orders <span aria-hidden="true">→</span></Link></div>
        </article>
      </section>

      {showForm && (
        <form className="suppliers-create-card" onSubmit={(event) => void createSupplier(event)}>
          <div className="suppliers-create-heading"><div><span className="suppliers-create-kicker">NEW PARTNER</span><h2>Add a supplier</h2><p>Save a supplier contact for future purchase orders.</p></div><span className="suppliers-create-symbol" aria-hidden="true">＋</span></div>
          <div className="suppliers-form-grid">
            <label>Supplier name <input value={name} onChange={(event) => setName(event.target.value)} required maxLength={160} placeholder="e.g. Central Office Supplies" /></label>
            <label>Email address <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} maxLength={256} placeholder="orders@example.com" /></label>
            <label>Phone number <input type="tel" value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={64} placeholder="+94 …" /></label>
          </div>
          <div className="suppliers-form-actions"><button className="btn btn-secondary" type="button" onClick={() => setShowForm(false)}>Cancel</button><button className="btn btn-primary" type="submit" disabled={saving || !name.trim()}>{saving ? 'Saving…' : 'Save supplier'}</button></div>
        </form>
      )}

      <section className="panel suppliers-directory-panel">
        <div className="suppliers-directory-head"><div><span className="suppliers-section-mark" aria-hidden="true">▤</span><div><h2>All suppliers</h2><p>Contact details available to your inventory workspace.</p></div></div><label className="suppliers-search"><span aria-hidden="true">⌕</span><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search name or contact" aria-label="Search suppliers" /></label></div>
        <div className="table-wrap">
          <table className="data-table suppliers-table">
            <thead><tr><th>Supplier</th><th>Email</th><th>Phone</th><th>Added</th><th>Orders</th></tr></thead>
            <tbody>
              {filtered.map((supplier) => (
                <tr key={supplier.id}>
                  <td><div className="suppliers-table-name"><span className="suppliers-avatar">{supplier.name.trim().charAt(0).toUpperCase()}</span><div><strong>{supplier.name}</strong><small>Supplier partner</small></div></div></td>
                  <td>{supplier.email ? <a href={`mailto:${supplier.email}`}>{supplier.email}</a> : <span className="suppliers-missing">No email saved</span>}</td>
                  <td>{supplier.phone ? <a href={`tel:${supplier.phone}`}>{supplier.phone}</a> : <span className="suppliers-missing">No phone saved</span>}</td>
                  <td>{supplier.createdAt ? new Date(supplier.createdAt).toLocaleDateString() : '—'}</td>
                  <td><Link className="suppliers-order-link" to="/purchase-orders">View orders <span aria-hidden="true">↗</span></Link></td>
                </tr>
              ))}
              {!loading && filtered.length === 0 && <tr><td colSpan={5} className="empty-state">{suppliers.length ? 'No suppliers match your search.' : 'No suppliers yet. Add a supplier to start building your directory.'}</td></tr>}
              {loading && suppliers.length === 0 && <tr><td colSpan={5} className="empty-state">Loading supplier directory…</td></tr>}
            </tbody>
          </table>
        </div>
        <div className="suppliers-directory-footer"><span>Showing {filtered.length} of {suppliers.length} suppliers</span><span>Supplier information is shared with purchase orders.</span></div>
      </section>
    </div>
  );
}
