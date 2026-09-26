import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { QRCodeSVG } from 'qrcode.react';
import { RootState } from '../../../store/store';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';
import { getStoredToken } from '../authToken';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';

type StockStatus = 'In stock' | 'Low stock' | 'Out of stock';

type StockRow = {
  id?: string;
  categoryId?: string;
  unitId?: string;
  branchId?: string;
  supplierId?: string;
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
type SupplierOption = { id: string; name: string; leadTimeDays: number | null };

const PAGE_SIZE = 5;

const categoryOptions = ['Office essentials', 'Technology', 'Provisions', 'Print & marketing', 'Other items'];
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
  supplierId: undefined,
};

function deriveStatus(qty: number, reorder: number): StockStatus {
  if (qty === 0) return 'Out of stock';
  if (reorder > 0 && qty / reorder < 0.45) return 'Low stock';
  return 'In stock';
}

function formatPrice(amount: number) {
  return `LKR ${amount.toLocaleString()}`;
}

function displayCategory(category: string | null | undefined, itemName: string) {
  if (category?.trim()) return category.trim();
  const normalized = itemName.toLowerCase();
  if (/(laptop|computer|usb|printer|electronic|tech)/.test(normalized)) return 'Technology';
  if (/(paper|cabinet|marker|stationery|office|desk|chair)/.test(normalized)) return 'Office essentials';
  if (/(water|rice|food|beverage|coffee|sugar|milk|provision)/.test(normalized)) return 'Provisions';
  if (/(toner|card|print|marketing|brochure)/.test(normalized)) return 'Print & marketing';
  return 'Other items';
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

void Stars;

function ItemModal({
  title,
  initial,
  onClose,
  onSave,
  saving,
  suppliers,
}: {
  title: string;
  initial: StockForm;
  onClose: () => void;
  onSave: (form: StockForm) => void;
  saving: boolean;
  suppliers: SupplierOption[];
}) {
  const [form, setForm] = useState(initial);
  const [error, setError] = useState('');
  const [confirmOpen, setConfirmOpen] = useState(false);

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
    setConfirmOpen(true);
  }

  function confirmSave() {
    setConfirmOpen(false);
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
            <label className="form-field form-field-wide">
              Preferred supplier for AI planning
              <select value={form.supplierId ?? ''} onChange={(event) => update('supplierId', event.target.value || undefined)}>
                <option value="">No supplier assigned</option>
                {suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}{supplier.leadTimeDays ? ` (${supplier.leadTimeDays} days)` : ' (lead time not set)'}</option>)}
              </select>
            </label>
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Save item'}</button>
          </div>
        </form>
      </div>
      {confirmOpen && (
        <ConfirmDialog
          title={title.startsWith('Add') ? 'Add this item to inventory?' : 'Save inventory changes?'}
          message={title.startsWith('Add')
            ? `Create "${form.item}" with ${form.qty} ${form.unit} in the database?`
            : `Update "${form.item}" and save the changes to the database?`}
          confirmLabel={title.startsWith('Add') ? 'Add item' : 'Save changes'}
          onConfirm={confirmSave}
          onCancel={() => setConfirmOpen(false)}
        />
      )}
    </div>
  );
}

export function InventoryManagerPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const { user } = useSelector((state: RootState) => state.auth);
  const [searchParams] = useSearchParams();
  const [items, setItems] = useState<StockRow[]>([]);
  const [suppliers, setSuppliers] = useState<SupplierOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState(() => searchParams.get('search') ?? '');
  const [category, setCategory] = useState(categories[0]);
  const [status, setStatus] = useState<StatusFilter>(statusFilters[0]);
  const [page, setPage] = useState(1);
  const [modal, setModal] = useState<{ mode: 'add' } | { mode: 'edit'; sku: string } | null>(null);
  const [qrItem, setQrItem] = useState<StockRow | null>(null);
  const [deleteSku, setDeleteSku] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

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
    const low = items.filter((row) => deriveStatus(row.qty, row.reorder) === 'Low stock').length;
    const out = items.filter((row) => deriveStatus(row.qty, row.reorder) === 'Out of stock').length;
    const value = items.reduce((sum, row) => sum + row.qty * row.price, 0);
    const categories = new Set(items.map((row) => row.category).filter(Boolean)).size;
    return { items: items.length, total, low, out, value, categories };
  }, [items]);

  const editingItem = modal?.mode === 'edit' ? items.find((row) => row.sku === modal.sku) : undefined;

  async function loadInventory(): Promise<boolean> {
    setLoading(true);
    setLoadError('');
    try {
      const response = await fetch('/api/inventory?page=1&pageSize=100', {
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) {
        const errorBody = await response.json().catch(() => null);
        throw new Error(errorBody?.message || errorBody?.title || `Inventory request failed (${response.status})`);
      }
      const data = await response.json();
      setItems((data.items ?? []).map((item: any): StockRow => ({
        id: item.id,
        sku: item.sku,
        item: item.name,
        category: displayCategory(item.category, item.name),
        unit: item.unit ?? 'unit',
        categoryId: item.categoryId ?? undefined,
        unitId: item.unitId ?? undefined,
        branchId: item.branchId ?? undefined,
        supplierId: item.supplierId ?? undefined,
        price: Number(item.unitCost ?? 0),
        qty: Number(item.quantity ?? 0),
        reorder: Number(item.reorderLevel ?? 0),
        owner: item.branch ?? 'Inventory Admin',
      })));
    } catch (error) {
      console.error(error);
      setItems([]);
      const message = error instanceof Error ? error.message : 'Unable to load inventory from the database.';
      setLoadError(`${message} Refresh and try again.`);
      notify(message, 'error');
      return false;
    } finally {
      setLoading(false);
    }
    return true;
  }

  function exportInventoryCsv() {
    if (!items.length) {
      notify('No inventory items to export.', 'warning');
      return;
    }
    const header = 'Item,SKU,Category,On Hand,Unit,Reorder Level,Unit Price (LKR),Owner';
    const lines = items.map(r =>
      [r.item, r.sku, r.category, r.qty, r.unit, r.reorder, r.price, r.owner]
        .map(v => `"${String(v).replace(/"/g, '""')}"`)
        .join(',')
    );
    const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `inventory-catalog-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    notify(`Exported ${items.length} inventory items to CSV.`, 'success');
  }

  async function handleCsvImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImporting(true);
    try {
      const text = await file.text();
      const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
      if (lines.length < 2) {
        throw new Error('CSV file is empty or missing headers.');
      }
      // Simple parse: skip header
      let createdCount = 0;
      for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',').map(c => c.replace(/^"|"$/g, '').trim());
        if (!cols[0]) continue;
        const name = cols[0];
        const category = cols[2] || categoryOptions[0];
        const qty = Number(cols[3]) || 0;
        const unit = cols[4] || 'unit';
        const reorder = Number(cols[5]) || 10;
        const price = Number(cols[6]) || 0;
        const res = await fetch('/api/inventory', {
          method: 'POST',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? 'Bearer ' + token : '' },
          body: JSON.stringify({
            name,
            sku: nextSku(items),
            description: `${category} (${unit})`,
            quantity: qty,
            reorderLevel: reorder,
            unitCost: price,
            branchId: user?.branchId ?? null,
          }),
        });
        if (res.ok) createdCount++;
      }
      await loadInventory();
      notify(`Successfully imported ${createdCount} items from CSV.`, 'success');
    } catch (err: any) {
      notify(err?.message || 'Failed to import CSV.', 'error');
    } finally {
      setImporting(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  }

  useEffect(() => {
    void loadInventory();
  }, [token]);

  useEffect(() => {
    let active = true;
    void fetch('/api/suppliers', { headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' } })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Supplier request failed (${response.status})`);
        return response.json();
      })
      .then((result) => { if (active) setSuppliers(Array.isArray(result.items) ? result.items : []); })
      .catch((error) => { console.error(error); });
    return () => { active = false; };
  }, [token]);

  async function handleRefresh() {
    if (await loadInventory()) {
      notify('Inventory refreshed.', 'success');
    }
  }

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
          categoryId: existing?.categoryId ?? null,
          unitId: existing?.unitId ?? null,
          branchId: existing?.branchId ?? user?.branchId ?? null,
          ...(existing ? {} : { quantity: form.qty }),
          reorderLevel: form.reorder,
          unitCost: form.price,
          supplierId: form.supplierId ?? null,
          ...(existing ? { clearSupplier: !form.supplierId } : {}),
        }),
      });
      if (!response.ok) {
        const errJson = await response.json().catch(() => null);
        const errDetail = errJson?.message || errJson?.title || `Save failed (${response.status})`;
        throw new Error(errDetail);
      }
      if (existing && form.qty !== existing.qty) {
        const adjustment = await fetch(`/api/inventory/${existing.id}/adjust`, {
          method: 'POST',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? 'Bearer ' + token : '' },
          body: JSON.stringify({ quantity: form.qty - existing.qty, reference: 'Inventory manager edit' }),
        });
        if (!adjustment.ok) {
          const adjJson = await adjustment.json().catch(() => null);
          const adjDetail = adjJson?.message || `Quantity adjustment failed (${adjustment.status})`;
          throw new Error(adjDetail);
        }
      }
      await loadInventory();
      setModal(null);
      notify(`${form.item} was successfully ${existing ? 'updated' : 'added'} in inventory.`, 'success');
    } catch (error: any) {
      console.error(error);
      notify(error?.message || 'Inventory could not be saved. Check your connection and permissions.', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function confirmDelete() {
    if (!deleteSku) return;
    const item = items.find((row) => row.sku === deleteSku);
    if (!item?.id) {
      setDeleteSku(null);
      notify('This inventory item is missing its database ID. Refresh and try again.', 'warning');
      return;
    }
    try {
      const response = await fetch(`/api/inventory/${item.id}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) {
        const errJson = await response.json().catch(() => null);
        throw new Error(errJson?.message || `Delete failed (${response.status})`);
      }
      await loadInventory();
      setDeleteSku(null);
      notify(`${item.item} was successfully deleted from inventory.`, 'success');
    } catch (error: any) {
      console.error(error);
      notify(error?.message || 'Inventory item could not be deleted.', 'error');
    }
  }

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div className="page inventory-manager-page">
      <header className="inventory-manager-hero">
        <div className="inventory-manager-hero-copy">
          <p className="inventory-manager-eyebrow"><span aria-hidden="true">◆</span> INVENTORY CONTROL CENTER</p>
          <h1>Inventory manager</h1>
          <p>One clear view of your stock, item health, and inventory value.</p>
          <div className="inventory-manager-health" aria-live="polite">
            <span className={`inventory-manager-health-dot${loading ? ' is-loading' : ''}`} aria-hidden="true" />
            {loading ? 'Updating live inventory…' : `${stats.items} items tracked`}
            <span className="inventory-manager-health-separator">·</span>
            {stats.low + stats.out === 0 ? 'All stock levels look healthy' : `${stats.low + stats.out} items need attention`}
          </div>
        </div>
        <div className="inventory-manager-hero-art" aria-hidden="true">
          <span className="inventory-manager-orbit inventory-manager-orbit-one" />
          <span className="inventory-manager-orbit inventory-manager-orbit-two" />
          <span className="inventory-manager-cube">▦</span>
          <span className="inventory-manager-art-label">STOCK<br />VISIBILITY</span>
        </div>
        <div className="page-actions">
          <input
            type="file"
            ref={fileInputRef}
            accept=".csv"
            style={{ display: 'none' }}
            onChange={handleCsvImport}
          />
          <button className="btn btn-secondary inventory-manager-refresh" type="button" onClick={() => void handleRefresh()} disabled={loading}><span aria-hidden="true">↻</span> {loading ? 'Refreshing…' : 'Refresh data'}</button>
          <button className="btn btn-secondary" type="button" onClick={() => fileInputRef.current?.click()} disabled={importing || loading} title="Import items from CSV file"><span aria-hidden="true">⇧</span> {importing ? 'Importing…' : 'Import CSV'}</button>
          <button className="btn btn-secondary" type="button" onClick={exportInventoryCsv} title="Export inventory catalogue as CSV"><span aria-hidden="true">⇩</span> Export CSV</button>
          <Link className="btn btn-secondary inventory-manager-suppliers-link" to="/suppliers"><span aria-hidden="true">♧</span> Suppliers</Link>
          <button className="btn btn-primary inventory-manager-add" type="button" onClick={() => setModal({ mode: 'add' })}><span aria-hidden="true">＋</span> Add item</button>
        </div>
      </header>
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="panel p-6">Loading live inventory…</div>}

      <section className="stat-strip" aria-label="Inventory summary">
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-items"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="inventory" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">CATALOGUE</span><strong className="inventory-manager-metric-value">{stats.items}</strong><span className="inventory-manager-metric-label">Items tracked</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">01</span></div><div className="inventory-manager-metric-detail">Organized across {stats.categories} {stats.categories === 1 ? 'category' : 'categories'}</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-units"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="box" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">AVAILABLE STOCK</span><strong className="inventory-manager-metric-value">{stats.total.toLocaleString()}</strong><span className="inventory-manager-metric-label">Units on hand</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">02</span></div><div className="inventory-manager-metric-detail">Current recorded quantity across items</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-attention"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="alert" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">STOCK HEALTH</span><strong className="inventory-manager-metric-value">{stats.low + stats.out}</strong><span className="inventory-manager-metric-label">Need attention</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">03</span></div><div className="inventory-manager-metric-detail">{stats.out} out of stock · {stats.low} running low</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-valuation"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="chart" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">VALUATION</span><strong className="inventory-manager-metric-value-number">LKR {stats.value.toLocaleString()}</strong><span className="inventory-manager-metric-label">Stock value</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">04</span></div><div className="inventory-manager-metric-detail">Calculated using recorded unit costs</div></article>
      </section>

      <div className="inventory-layout inventory-manager-layout">
        <section className="panel inventory-panel inventory-manager-table-panel">
          <div className="inventory-manager-panel-heading">
            <div className="inventory-manager-panel-icon" aria-hidden="true"><Icon name="inventory" size={19} /></div>
            <div><h2>Stock catalogue</h2><p>Search, review, and manage individual inventory items.</p></div>
            <span className="inventory-manager-total-pill">{items.length} {items.length === 1 ? 'item' : 'items'}</span>
          </div>
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
          <div className="inventory-quick-filters" role="group" aria-label="Quick stock status filters">
            <button
              type="button"
              className={`inventory-chip${status === 'All statuses' ? ' is-active' : ''}`}
              onClick={() => setStatus('All statuses')}
            >
              All Items <strong>({stats.items})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-green${status === 'In stock' ? ' is-active' : ''}`}
              onClick={() => setStatus('In stock')}
            >
              In Stock <strong>({Math.max(0, stats.items - stats.low - stats.out)})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-amber${status === 'Low stock' ? ' is-active' : ''}`}
              onClick={() => setStatus('Low stock')}
            >
              Low Stock <strong>({stats.low})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-red${status === 'Out of stock' ? ' is-active' : ''}`}
              onClick={() => setStatus('Out of stock')}
            >
              Out of Stock <strong>({stats.out})</strong>
            </button>
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
                          <button type="button" className="row-action" aria-label={`Show QR for ${row.item}`} title="Show item QR" onClick={() => setQrItem(row)}><QRCodeSVG value={row.sku} size={18} level="M" bgColor="#fff" fgColor="#111" /></button>
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

      </div>

      {modal && (
        <ItemModal
          title={modal.mode === 'add' ? 'Add inventory item' : 'Edit inventory item'}
          initial={modal.mode === 'edit' && editingItem
            ? { item: editingItem.item, category: editingItem.category, unit: editingItem.unit, price: editingItem.price, qty: editingItem.qty, reorder: editingItem.reorder, owner: editingItem.owner, supplierId: editingItem.supplierId }
            : emptyForm}
          onClose={() => setModal(null)}
          onSave={handleSave}
          saving={saving}
          suppliers={suppliers}
        />
      )}

      {qrItem && (
        <div className="modal-overlay" onClick={() => setQrItem(null)} role="presentation">
          <div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="inventory-qr-title">
            <div className="modal-head">
              <h2 id="inventory-qr-title">Item QR label</h2>
              <button type="button" className="modal-close" onClick={() => setQrItem(null)} aria-label="Close">×</button>
            </div>
            <div className="modal-body" style={{ textAlign: 'center' }}>
              <p className="cell-title">{qrItem.item}</p>
              <div style={{ display: 'inline-block', padding: 16, background: '#fff', borderRadius: 12 }}>
                <QRCodeSVG value={qrItem.sku} size={240} level="M" title={`QR code for SKU ${qrItem.sku}`} />
              </div>
              <p className="cell-title" style={{ marginTop: 12 }}><code>{qrItem.sku}</code></p>
              <p className="modal-hint">This QR encodes only the item SKU. Scan it from Stock Movements or Physical Stock Count.</p>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setQrItem(null)}>Close</button>
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={() => {
                    if (!navigator.clipboard) {
                      notify('Clipboard access is not available in this browser.', 'warning');
                      return;
                    }
                    void navigator.clipboard.writeText(qrItem.sku)
                      .then(() => notify('SKU copied.', 'success'))
                      .catch(() => notify('Could not copy the SKU in this browser.', 'warning'));
                  }}
                >Copy SKU</button>
              </div>
            </div>
          </div>
        </div>
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
