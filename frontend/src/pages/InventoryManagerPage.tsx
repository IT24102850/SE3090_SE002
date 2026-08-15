import { useMemo, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';

type StockRow = {
  sku: string;
  item: string;
  category: string;
  unit: string;
  price: string;
  qty: number;
  reorder: number;
  owner: string;
  status: 'In stock' | 'Low stock' | 'Out of stock';
};

const stock: StockRow[] = [
  { sku: 'SKU-00128', item: 'Colombia Supremo Beans 1kg', category: 'Coffee & beverages', unit: 'bag', price: 'LKR 4,850', qty: 142, reorder: 40, owner: 'Kavindu', status: 'In stock' },
  { sku: 'SKU-00132', item: 'Premium Coffee Beans', category: 'Coffee & beverages', unit: 'kg', price: 'LKR 6,200', qty: 6, reorder: 40, owner: 'Kavindu', status: 'Low stock' },
  { sku: 'SKU-00324', item: 'Vanilla Syrup 750ml', category: 'Coffee & beverages', unit: 'bottle', price: 'LKR 1,890', qty: 0, reorder: 25, owner: 'Kavindu', status: 'Out of stock' },
  { sku: 'SKU-00451', item: 'Butter Croissants (x12)', category: 'Bakery & desserts', unit: 'pack', price: 'LKR 2,450', qty: 96, reorder: 30, owner: 'Dinesh', status: 'In stock' },
  { sku: 'SKU-00598', item: 'Packaging Boxes — Medium', category: 'Packaging & supplies', unit: 'box', price: 'LKR 580', qty: 11, reorder: 60, owner: 'Nadeesha', status: 'Low stock' },
  { sku: 'SKU-00612', item: 'Craft Paper Cups 12oz (x50)', category: 'Packaging & supplies', unit: 'pack', price: 'LKR 1,150', qty: 74, reorder: 40, owner: 'Nadeesha', status: 'In stock' },
  { sku: 'SKU-00741', item: 'Whole Milk 1L', category: 'Dairy & chilled', unit: 'carton', price: 'LKR 420', qty: 218, reorder: 80, owner: 'Nadeesha', status: 'In stock' },
  { sku: 'SKU-00811', item: 'Whole Milk 1L (Small)', category: 'Dairy & chilled', unit: 'carton', price: 'LKR 380', qty: 18, reorder: 80, owner: 'Nadeesha', status: 'Low stock' },
  { sku: 'SKU-00902', item: 'Brown Sugar 500g', category: 'Groceries', unit: 'bag', price: 'LKR 640', qty: 65, reorder: 30, owner: 'Kavindu', status: 'In stock' },
  { sku: 'SKU-01033', item: 'Napkins — Kraft (x200)', category: 'Packaging & supplies', unit: 'pack', price: 'LKR 950', qty: 43, reorder: 25, owner: 'Nadeesha', status: 'In stock' },
];

const suppliers = [
  { name: 'Ceylon Coffee Traders', category: 'Coffee & beverages', outstanding: 'LKR 184,500', rating: 4 },
  { name: 'MetroPack Ltd', category: 'Packaging & supplies', outstanding: 'LKR 96,200', rating: 5 },
  { name: 'Fresh Farms Dairy', category: 'Dairy & chilled', outstanding: 'LKR 72,850', rating: 4 },
  { name: 'Flour & Co Bakery Supply', category: 'Bakery & desserts', outstanding: 'LKR 61,400', rating: 3 },
];

const categories = ['All categories', 'Coffee & beverages', 'Packaging & supplies', 'Bakery & desserts', 'Dairy & chilled', 'Groceries'];
const statusFilters = ['All statuses', 'In stock', 'Low stock', 'Out of stock'] as const;
type StatusFilter = (typeof statusFilters)[number];

const statusTone: Record<StockRow['status'], BadgeTone> = {
  'In stock': 'green',
  'Low stock': 'amber',
  'Out of stock': 'red',
};

function StockLevelBar({ qty, reorder }: { qty: number; reorder: number }) {
  const pct = Math.min(100, (qty / reorder) * 100);
  const tone = qty === 0 ? 'red' : pct < 45 ? 'amber' : 'green';
  return (
    <div className="stock-level stock-level-wide">
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

export function InventoryManagerPage() {
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState(categories[0]);
  const [status, setStatus] = useState<StatusFilter>(statusFilters[0]);

  const rows = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    return stock.filter((row) => {
      const matchesQuery =
        queryLower === '' ||
        row.item.toLowerCase().includes(queryLower) ||
        row.sku.toLowerCase().includes(queryLower) ||
        row.owner.toLowerCase().includes(queryLower);
      const matchesCategory = category === 'All categories' || row.category === category;
      const matchesStatus = status === 'All statuses' || row.status === status;
      return matchesQuery && matchesCategory && matchesStatus;
    });
  }, [category, query, status]);

  const stats = useMemo(() => {
    const total = stock.reduce((sum, row) => sum + row.qty, 0);
    const low = stock.filter((row) => row.status !== 'In stock').length;
    const value = stock.reduce((sum, row) => sum + row.qty * parseFloat(row.price.replace(/[^\d.]/g, '')), 0);
    return { items: stock.length, total, low, value };
  }, []);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / INVENTORY</p>
          <h1>Inventory manager</h1>
          <p className="page-sub">Search items, monitor stock levels, and keep suppliers in check.</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-secondary">Import</button>
          <button className="btn btn-primary">Add item</button>
        </div>
      </header>

      <section className="stat-strip" aria-label="Inventory summary">
        <div className="stat"><span className="stat-value">{stats.items}</span><span className="stat-label">Items tracked</span></div>
        <div className="stat"><span className="stat-value">{stats.total.toLocaleString()}</span><span className="stat-label">Units on hand</span></div>
        <div className="stat"><span className="stat-value">{stats.low}</span><span className="stat-label">Need attention</span></div>
        <div className="stat"><span className="stat-value">LKR {stats.value.toLocaleString()}</span><span className="stat-label">Stock value</span></div>
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
            <select className="filter-select" value={status} onChange={(event) => setStatus(event.target.value as (typeof statusFilters)[number])} aria-label="Filter by status">
              {statusFilters.map((option) => <option key={option}>{option}</option>)}
            </select>
          </div>

          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>Item</th><th>Category</th><th>On hand</th><th>Stock level</th><th>Unit price</th><th>Status</th></tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.sku}>
                    <td>
                      <p className="cell-title">{row.item}</p>
                      <p className="cell-sub">{row.sku} · {row.owner}</p>
                    </td>
                    <td><span className="category-pill">{row.category}</span></td>
                    <td><span className="qty">{row.qty}</span> <span className="cell-sub">{row.unit}s</span></td>
                    <td><StockLevelBar qty={row.qty} reorder={row.reorder} /></td>
                    <td className="amount">{row.price}</td>
                    <td><Badge tone={statusTone[row.status]}>{row.status}</Badge></td>
                  </tr>
                ))}
                {rows.length === 0 && (
                  <tr><td colSpan={6} className="empty-state">No items match your filters.</td></tr>
                )}
              </tbody>
            </table>
          </div>
          <p className="table-caption">Showing {rows.length} of {stock.length} items · Reorder levels and owners set by branch staff</p>
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
          <button className="btn btn-secondary supplier-action">View all suppliers</button>
        </aside>
      </div>
    </div>
  );
}
