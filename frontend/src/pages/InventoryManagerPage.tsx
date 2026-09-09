import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';
import { useAuth } from '../auth/AuthContext';

type StockStatus = 'In stock' | 'Low stock' | 'Out of stock';

type StockRow = {
  id?: string;
  sku: string;
  item: string;
  category: string;
  unit: string;
  price: number;
  qty: number;
  reorder: number;
  owner: string;
};

type StockForm = Omit<StockRow, 'sku'>;

const PAGE_SIZE = 5;

const initialStock: StockRow[] = [
  { sku: 'SKU-00128', item: 'Colombia Supremo Beans 1kg', category: 'Coffee & beverages', unit: 'bag', price: 4850, qty: 142, reorder: 40, owner: 'Kavindu' },
  { sku: 'SKU-00132', item: 'Premium Coffee Beans', category: 'Coffee & beverages', unit: 'kg', price: 6200, qty: 6, reorder: 40, owner: 'Kavindu' },
  { sku: 'SKU-00324', item: 'Vanilla Syrup 750ml', category: 'Coffee & beverages', unit: 'bottle', price: 1890, qty: 0, reorder: 25, owner: 'Kavindu' },
  { sku: 'SKU-00451', item: 'Butter Croissants (x12)', category: 'Bakery & desserts', unit: 'pack', price: 2450, qty: 96, reorder: 30, owner: 'Dinesh' },
  { sku: 'SKU-00598', item: 'Packaging Boxes — Medium', category: 'Packaging & supplies', unit: 'box', price: 580, qty: 11, reorder: 60, owner: 'Nadeesha' },
  { sku: 'SKU-00612', item: 'Craft Paper Cups 12oz (x50)', category: 'Packaging & supplies', unit: 'pack', price: 1150, qty: 74, reorder: 40, owner: 'Nadeesha' },
  { sku: 'SKU-00741', item: 'Whole Milk 1L', category: 'Dairy & chilled', unit: 'carton', price: 420, qty: 218, reorder: 80, owner: 'Nadeesha' },
  { sku: 'SKU-00811', item: 'Whole Milk 1L (Small)', category: 'Dairy & chilled', unit: 'carton', price: 380, qty: 18, reorder: 80, owner: 'Nadeesha' },
  { sku: 'SKU-00902', item: 'Brown Sugar 500g', category: 'Groceries', unit: 'bag', price: 640, qty: 65, reorder: 30, owner: 'Kavindu' },
  { sku: 'SKU-01033', item: 'Napkins — Kraft (x200)', category: 'Packaging & supplies', unit: 'pack', price: 950, qty: 43, reorder: 25, owner: 'Nadeesha' },
];

const suppliers = [
  { name: 'Ceylon Coffee Traders', category: 'Coffee & beverages', outstanding: 'LKR 184,500', rating: 4 },
  { name: 'MetroPack Ltd', category: 'Packaging & supplies', outstanding: 'LKR 96,200', rating: 5 },
  { name: 'Fresh Farms Dairy', category: 'Dairy & chilled', outstanding: 'LKR 72,850', rating: 4 },
  { name: 'Flour & Co Bakery Supply', category: 'Bakery & desserts', outstanding: 'LKR 61,400', rating: 3 },
];

const categoryOptions = ['Coffee & beverages', 'Packaging & supplies', 'Bakery & desserts', 'Dairy & chilled', 'Groceries'];
const categories = ['All categories', ...categoryOptions];
const statusFilters = ['All statuses', 'In stock', 'Low stock', 'Out of stock'] as const;
type StatusFilter = (typeof statusFilters)[number];

const statusTone: Record<StockStatus, BadgeTone> = {
  'In stock': 'green',
  'Low stock': 'amber',
  'Out of stock': 'red',
};

const emptyForm: StockForm = {
  item: '',
  category: categoryOptions[0],
  unit: '',
  price: 0,
  qty: 0,
  reorder: 10,
  owner: '',
};

function deriveStatus(qty: number, reorder: number): StockStatus {
  if (qty === 0) return 'Out of stock';
  if (reorder > 0 && qty / reorder < 0.45) return 'Low stock';
  return 'In stock';
}

function formatPrice(amount: number) {
  return `LKR ${amount.toLocaleString()}`;
}

function nextSku(items: StockRow[]) {
  const max = items.reduce((acc, row) => {
    const num = parseInt(row.sku.replace(/\D/g, ''), 10);
    return Number.isFinite(num) ? Math.max(acc, num) : acc;
  }, 0);
  return `SKU-${String(max + 1).padStart(5, '0')}`;
}

function StockLevelBar({ qty, reorder }: { qty: number; reorder: number }) {
  const pct = reorder > 0 ? Math.min(100, (qty / reorder) * 100) : qty > 0 ? 100 : 0;
  const tone = qty === 0 ? 'red' : pct < 45 ? 'amber' : 'green';
  return (
    <div className="stock-level stock-level-wide" title={`${Math.round(pct)}% of reorder level`}>
      <div className={`stock-level-fill stock-level-${tone}`} style={{ width: `${Math.max(4, pct)}%` }} />
    </div>
  );
}

function Stars({ rating }: { rating: number }) {
  return (
    <span className="stars" aria-label={`${rating} out of 5`}>
      {[1, 2, 3, 4, 5].map((star) => (
        <span key={star} className={star <= rating ? 'star-on' : 'star-off'}>★</span>
      ))}
    </span>
  );
}

function ItemModal({
  title,
  initial,
  onClose,
  onSave,
  saving,
}: {
  title: string;
  initial: StockForm;
  onClose: () => void;
  onSave: (form: StockForm) => void;
  saving: boolean;
}) {
  const [form, setForm] = useState(initial);
  const [error, setError] = useState('');

  function update<K extends keyof StockForm>(key: K, value: StockForm[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!form.item.trim()) {
      setError('Item name is required.');
      return;
    }
    if (!form.unit.trim()) {
      setError('Unit is required.');
      return;
    }
    if (!form.owner.trim()) {
      setError('Owner is required.');
      return;
    }
    if (form.price < 0 || form.qty < 0 || form.reorder < 0) {
      setError('Price, quantity, and reorder level must be zero or greater.');
      return;
    }
    onSave(form);
  }

  return (
    <div className="modal-overlay" onClick={onClose} role="presentation">
      <div className="modal" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="item-modal-title">
        <div className="modal-head">
          <h2 id="item-modal-title">{title}</h2>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="modal-body" onSubmit={handleSubmit}>
          {error && <p className="modal-error">{error}</p>}
          <div className="form-grid">
            <label className="form-field form-field-wide">
              Item name
              <input value={form.item} onChange={(event) => update('item', event.target.value)} placeholder="e.g. Premium Coffee Beans" />
            </label>
            <label className="form-field">
              Category
              <select value={form.category} onChange={(event) => update('category', event.target.value)}>
                {categoryOptions.map((option) => <option key={option}>{option}</option>)}
              </select>
            </label>
            <label className="form-field">
              Unit
              <input value={form.unit} onChange={(event) => update('unit', event.target.value)} placeholder="e.g. kg, bag, pack" />
            </label>
            <label className="form-field">
              Unit price (LKR)
              <input type="number" min={0} step={1} value={form.price || ''} onChange={(event) => update('price', Number(event.target.value))} />
            </label>
            <label className="form-field">
              Quantity on hand
              <input type="number" min={0} step={1} value={form.qty || ''} onChange={(event) => update('qty', Number(event.target.value))} />
            </label>
            <label className="form-field">
              Reorder level
              <input type="number" min={0} step={1} value={form.reorder || ''} onChange={(event) => update('reorder', Number(event.target.value))} />
            </label>
            <label className="form-field form-field-wide">
              Owner
              <input value={form.owner} onChange={(event) => update('owner', event.target.value)} placeholder="Staff member responsible" />
            </label>
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Save item'}</button>
          </div>
        </form>
      </div>
    </div>
  );
}

export function InventoryManagerPage() {
  const { notify } = useToast();
  const { token } = useAuth();
  const [items, setItems] = useState<StockRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState(categories[0]);
  const [status, setStatus] = useState<StatusFilter>(statusFilters[0]);
  const [page, setPage] = useState(1);
  const [modal, setModal] = useState<{ mode: 'add' } | { mode: 'edit'; sku: string } | null>(null);
  const [deleteSku, setDeleteSku] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    return items.filter((row) => {
      const rowStatus = deriveStatus(row.qty, row.reorder);
      const matchesQuery =
        queryLower === '' ||
        row.item.toLowerCase().includes(queryLower) ||
        row.sku.toLowerCase().includes(queryLower) ||
        row.owner.toLowerCase().includes(queryLower);
      const matchesCategory = category === 'All categories' || row.category === category;
      const matchesStatus = status === 'All statuses' || rowStatus === status;
      return matchesQuery && matchesCategory && matchesStatus;
    });
  }, [category, items, query, status]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);

  const paged = useMemo(() => {
    const start = (safePage - 1) * PAGE_SIZE;
    return filtered.slice(start, start + PAGE_SIZE);
  }, [filtered, safePage]);

  useEffect(() => {
    setPage(1);
  }, [query, category, status]);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  const stats = useMemo(() => {
    const total = items.reduce((sum, row) => sum + row.qty, 0);
    const low = items.filter((row) => deriveStatus(row.qty, row.reorder) !== 'In stock').length;
    const value = items.reduce((sum, row) => sum + row.qty * row.price, 0);
    return { items: items.length, total, low, value };
  }, [items]);

  const editingItem = modal?.mode === 'edit' ? items.find((row) => row.sku === modal.sku) : undefined;

  async function loadInventory() {
    setLoading(true);
    setLoadError('');
    try {
      const response = await fetch('/api/inventory?page=1&pageSize=100', {
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) throw new Error(`Inventory request failed (${response.status})`);
      const data = await response.json();
      setItems((data.items ?? []).map((item: any): StockRow => ({
        id: item.id,
        sku: item.sku,
        item: item.name,
        category: item.category ?? 'Uncategorized',
        unit: item.unit ?? 'unit',
        price: Number(item.unitCost ?? 0),
        qty: Number(item.quantity ?? 0),
        reorder: Number(item.reorderLevel ?? 0),
        owner: item.branch ?? 'Inventory Admin',
      })));
    } catch (error) {
      console.error(error);
      setItems([]);
      setLoadError('Unable to load inventory from the database. Refresh and try again.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadInventory();
  }, [token]);

  async function handleSave(form: StockForm) {
    setSaving(true);
    try {
      const existing = modal?.mode === 'edit' ? items.find((row) => row.sku === modal.sku) : undefined;
      const path = existing?.id ? `/api/inventory/${existing.id}` : '/api/inventory';
      const method = existing?.id ? 'PUT' : 'POST';
      const response = await fetch(path, {
        method,
        headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? 'Bearer ' + token : '' },
        body: JSON.stringify({
          name: form.item,
          sku: existing?.sku ?? nextSku(items),
          description: null,
          categoryId: null,
          unitId: null,
          branchId: null,
          quantity: form.qty,
          reorderLevel: form.reorder,
          unitCost: form.price,
        }),
      });
      if (!response.ok) throw new Error(`Save failed (${response.status})`);
      await loadInventory();
      setModal(null);
      notify(`${form.item} was ${existing ? 'updated' : 'added'} in inventory.`);
    } catch (error) {
      console.error(error);
      notify('Inventory could not be saved. Check your connection and permissions.', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function confirmDelete() {
    if (!deleteSku) return;
    const item = items.find((row) => row.sku === deleteSku);
    if (!item?.id) {
      setDeleteSku(null);
      notify('This fallback row is not connected to the live inventory.', 'warning');
      return;
    }
    try {
      const response = await fetch(`/api/inventory/${item.id}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) throw new Error(`Delete failed (${response.status})`);
      await loadInventory();
      setDeleteSku(null);
      notify(`${item.item} was deleted.`, 'info');
    } catch (error) {
      console.error(error);
      notify('Inventory item could not be deleted.', 'error');
    }
  }

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / INVENTORY</p>
          <h1>Inventory manager</h1>
          <p className="page-sub">Search items, monitor stock levels, and keep suppliers in check.</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-secondary" type="button" onClick={() => void loadInventory()} disabled={loading}>Refresh</button>
          <button className="btn btn-secondary" type="button" onClick={() => notify('Import is ready for a CSV file. File selection will be available next.', 'warning')}>Import</button>
          <button className="btn btn-primary" type="button" onClick={() => setModal({ mode: 'add' })}>Add item</button>
        </div>
      </header>
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="panel p-6">Loading live inventory…</div>}

      <section className="stat-strip" aria-label="Inventory summary">
        <div className="stat metric-card">
          <div className="metric-icon-bubble metric-purple" aria-hidden="true"><Icon name="inventory" size={20} /></div>
          <div className="metric-info"><span className="stat-value metric-value">{stats.items}</span><span className="stat-label metric-label">Items tracked</span></div>
        </div>
        <div className="stat metric-card">
          <div className="metric-icon-bubble metric-cyan" aria-hidden="true"><Icon name="box" size={20} /></div>
          <div className="metric-info"><span className="stat-value metric-value">{stats.total.toLocaleString()}</span><span className="stat-label metric-label">Units on hand</span></div>
        </div>
        <div className="stat metric-card">
          <div className="metric-icon-bubble metric-amber" aria-hidden="true"><Icon name="alert" size={20} /></div>
          <div className="metric-info"><span className="stat-value metric-value">{stats.low}</span><span className="stat-label metric-label">Need attention</span></div>
        </div>
        <div className="stat metric-card">
          <div className="metric-icon-bubble metric-emerald" aria-hidden="true"><Icon name="chart" size={20} /></div>
          <div className="metric-info"><span className="stat-value metric-value">LKR {stats.value.toLocaleString()}</span><span className="stat-label metric-label">Stock value</span></div>
        </div>
      </section>

      <div className="inventory-layout">
        <section className="panel inventory-panel">
          <div className="toolbar">
            <div className="search-field">
              <span className="search-icon" aria-hidden="true">⌕</span>
              <input
                type="search"
                placeholder="Search items, SKUs, owners…"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                aria-label="Search stock"
              />
            </div>
            <select className="filter-select" value={category} onChange={(event) => setCategory(event.target.value)} aria-label="Filter by category">
              {categories.map((option) => <option key={option}>{option}</option>)}
            </select>
            <select className="filter-select" value={status} onChange={(event) => setStatus(event.target.value as StatusFilter)} aria-label="Filter by status">
              {statusFilters.map((option) => <option key={option}>{option}</option>)}
            </select>
          </div>

          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>Item</th><th>Category</th><th>On hand</th><th>Stock level</th><th>Unit price</th><th>Status</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {paged.map((row) => {
                  const rowStatus = deriveStatus(row.qty, row.reorder);
                  return (
                    <tr key={row.sku}>
                      <td>
                        <p className="cell-title">{row.item}</p>
                        <p className="cell-sub">{row.sku} · {row.owner}</p>
                      </td>
                      <td><span className="category-pill">{row.category}</span></td>
                      <td><span className="qty">{row.qty}</span> <span className="cell-sub">{row.unit}s</span></td>
                      <td><StockLevelBar qty={row.qty} reorder={row.reorder} /></td>
                      <td className="amount">{formatPrice(row.price)}</td>
                      <td><Badge tone={statusTone[rowStatus]}>{rowStatus}</Badge></td>
                      <td>
                        <div className="row-actions">
                          <button type="button" className="row-action" aria-label={`Edit ${row.item}`} onClick={() => setModal({ mode: 'edit', sku: row.sku })}>✎</button>
                          <button type="button" className="row-action row-action-danger" aria-label={`Delete ${row.item}`} onClick={() => setDeleteSku(row.sku)}>🗑</button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {paged.length === 0 && (
                  <tr><td colSpan={7} className="empty-state">No items match your filters.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="table-footer">
            <p className="table-caption">
              {filtered.length === 0
                ? `No items · ${items.length} total in inventory`
                : `Showing ${rangeStart}–${rangeEnd} of ${filtered.length} items · ${items.length} total in inventory`}
            </p>
            {filtered.length > PAGE_SIZE && (
              <nav className="pagination" aria-label="Inventory pagination">
                <button
                  type="button"
                  className="pagination-btn"
                  disabled={safePage <= 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Previous
                </button>
                {Array.from({ length: totalPages }, (_, index) => index + 1).map((pageNum) => (
                  <button
                    key={pageNum}
                    type="button"
                    className={`pagination-btn${pageNum === safePage ? ' pagination-btn-active' : ''}`}
                    aria-current={pageNum === safePage ? 'page' : undefined}
                    onClick={() => setPage(pageNum)}
                  >
                    {pageNum}
                  </button>
                ))}
                <button
                  type="button"
                  className="pagination-btn"
                  disabled={safePage >= totalPages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </button>
              </nav>
            )}
          </div>
        </section>

        <aside className="suppliers-panel">
          <div className="panel-head">
            <div>
              <h2>Suppliers</h2>
              <p>Active partners</p>
            </div>
          </div>
          <ul className="supplier-list">
            {suppliers.map((supplier) => (
              <li className="supplier" key={supplier.name}>
                <div className="supplier-avatar">{supplier.name.charAt(0)}</div>
                <div className="supplier-body">
                  <p className="supplier-name">{supplier.name}</p>
                  <p className="supplier-category">{supplier.category}</p>
                  <div className="supplier-meta">
                    <Stars rating={supplier.rating} />
                    <span className="supplier-outstanding">{supplier.outstanding} outstanding</span>
                  </div>
                </div>
              </li>
            ))}
          </ul>
          <button className="btn btn-secondary supplier-action" type="button" onClick={() => notify('Showing the four suppliers with the highest outstanding balances.', 'info')}>View all suppliers</button>
        </aside>
      </div>

      {modal && (
        <ItemModal
          title={modal.mode === 'add' ? 'Add inventory item' : 'Edit inventory item'}
          initial={modal.mode === 'edit' && editingItem
            ? { item: editingItem.item, category: editingItem.category, unit: editingItem.unit, price: editingItem.price, qty: editingItem.qty, reorder: editingItem.reorder, owner: editingItem.owner }
            : emptyForm}
          onClose={() => setModal(null)}
          onSave={handleSave}
          saving={saving}
        />
      )}

      {deleteSku && (
        <div className="modal-overlay" onClick={() => setDeleteSku(null)} role="presentation">
          <div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="alertdialog" aria-modal="true" aria-labelledby="delete-title">
            <div className="modal-head">
              <h2 id="delete-title">Delete item?</h2>
              <button type="button" className="modal-close" onClick={() => setDeleteSku(null)} aria-label="Close">×</button>
            </div>
            <div className="modal-body">
              <p className="delete-copy">
                Remove <strong>{items.find((row) => row.sku === deleteSku)?.item}</strong> ({deleteSku}) from inventory? This cannot be undone.
              </p>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setDeleteSku(null)}>Cancel</button>
                <button type="button" className="btn btn-danger" onClick={confirmDelete}>Delete</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
