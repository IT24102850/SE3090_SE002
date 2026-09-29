import { API_BASE_URL } from '../../../api/apiBaseUrl';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';
import { getStoredToken } from '../authToken';
import { Badge } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';

type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  category?: string;
  unit?: string;
  branch?: string;
  branchId?: string | null;
  quantity: number;
  unitCost: number | null;
  sellingPrice: number | null;
};

type SalesReport = {
  salesCount: number;
  totalRevenue: number;
  averageSale: number;
  costOfGoodsSold: number | null;
  grossProfit: number | null;
  recentSales: RecentSale[];
};

type RecentSale = {
  id: string;
  reference: string;
  occurredAt: string;
  amount: number;
  quantity: number;
  items: string[];
  costOfGoodsSold: number | null;
  grossProfit: number | null;
};

type SaleReceipt = {
  reference: string;
  itemName: string;
  sku: string;
  branch: string;
  quantity: number;
  unit: string;
  unitPrice: number;
  amount: number;
  costOfGoodsSold: number;
  grossProfit: number;
  remainingQuantity: number;
  occurredAt: string;
};

type HistoricalSaleReceipt = Pick<RecentSale, 'reference' | 'occurredAt' | 'amount' | 'quantity' | 'items' | 'grossProfit'>;
type ReceiptView = SaleReceipt | HistoricalSaleReceipt;

type InventoryListResponse = { items?: InventoryItem[]; totalPages?: number };

const API_PAGE_SIZE = 100;

function money(value: number | null | undefined) {
  return value == null ? 'Not available' : `LKR ${value.toLocaleString('en-LK', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function quantity(value: number) {
  return value.toLocaleString('en-LK', { maximumFractionDigits: 3 });
}

function hasSupportedQuantityPrecision(value: number) {
  return Math.abs(value * 1000 - Math.round(value * 1000)) < 1e-8;
}

function dateWindow(days: number) {
  const to = new Date();
  const from = new Date(to);
  from.setDate(from.getDate() - days + 1);
  from.setHours(0, 0, 0, 0);
  return { from: from.toISOString(), to: to.toISOString() };
}

async function readError(response: Response) {
  try {
    const body = await response.json() as { message?: string; title?: string; errors?: Record<string, string[]> };
    const validation = body.errors ? Object.values(body.errors).flat()[0] : undefined;
    return body.message ?? validation ?? body.title ?? `Request failed (${response.status}).`;
  } catch {
    return `Request failed (${response.status}).`;
  }
}

async function authorizedFetch(path: string, token: string | null, init?: RequestInit) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: {
      Accept: 'application/json',
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });
  if (!response.ok) throw new Error(await readError(response));
  return response;
}

export function SalesPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const { user } = useSelector((state: RootState) => state.auth);
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [report, setReport] = useState<SalesReport | null>(null);
  const [selectedId, setSelectedId] = useState('');
  const [search, setSearch] = useState('');
  const [itemPickerOpen, setItemPickerOpen] = useState(false);
  const [activeItemOption, setActiveItemOption] = useState(0);
  const [amount, setAmount] = useState('1');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [receipt, setReceipt] = useState<ReceiptView | null>(null);

  const selectedItem = items.find((item) => item.id === selectedId) ?? null;
  const saleQuantity = Number(amount);
  const itemOptions = useMemo(() => {
    const query = search.trim().toLowerCase();
    return items.filter((item) => {
      if (!item.branchId || item.quantity <= 0) return false;
      if (!query) return true;
      return `${item.name} ${item.sku} ${item.category ?? ''} ${item.branch ?? ''}`.toLowerCase().includes(query);
    });
  }, [items, search]);
  const selectItem = (item: InventoryItem) => {
    setSelectedId(item.id);
    setSearch(`${item.name} · ${item.sku} · ${item.branch ?? 'No branch'}`);
    setItemPickerOpen(false);
  };

  const loadData = useCallback(async (showFeedback = false) => {
    setLoading(true);
    try {
      const inventory: InventoryItem[] = [];
      let page = 1;
      let totalPages = 1;
      while (page <= totalPages) {
        const response = await authorizedFetch(`/inventory?page=${page}&pageSize=${API_PAGE_SIZE}`, token);
        const payload = await response.json() as InventoryListResponse;
        if (!Array.isArray(payload.items)) throw new Error('Inventory response did not contain an item list.');
        inventory.push(...payload.items);
        totalPages = Math.max(1, Number(payload.totalPages ?? 1));
        page++;
      }
      const range = dateWindow(7);
      const params = new URLSearchParams({ from: range.from, to: range.to, page: '1', pageSize: '10' });
      const reportResponse = await authorizedFetch(`/reports/sales-activity?${params}`, token);
      const nextReport = await reportResponse.json() as SalesReport;
      setItems(inventory);
      setSelectedId((current) => inventory.some((item) => item.id === current && item.quantity > 0) ? current : '');
      setReport(nextReport);
      if (showFeedback) notify('Sales and inventory refreshed.', 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Sales data could not be loaded.', 'error');
    } finally {
      setLoading(false);
    }
  }, [notify, token]);

  useEffect(() => { void loadData(); }, [loadData]);

  const canRecord = Boolean(
    selectedItem &&
    saleQuantity > 0 &&
    Number.isFinite(saleQuantity) &&
    hasSupportedQuantityPrecision(saleQuantity) &&
    saleQuantity <= selectedItem.quantity &&
    selectedItem.unitCost != null &&
    selectedItem.sellingPrice != null &&
    selectedItem.sellingPrice > selectedItem.unitCost,
  );

  async function recordSale() {
    if (!selectedItem || !canRecord || saving) return;
    setSaving(true);
    setConfirming(false);
    const reference = `SALE-WEB-${crypto.randomUUID()}`;
    try {
      const response = await authorizedFetch(`/inventory/${selectedItem.id}/sell`, token, {
        method: 'POST',
        body: JSON.stringify({
          quantity: saleQuantity,
          expectedSellingPrice: selectedItem.sellingPrice,
          expectedUnitCost: selectedItem.unitCost,
          reference,
        }),
      });
      const result = await response.json() as {
        reference: string;
        itemName: string;
        quantity: number;
        unitPrice: number;
        amount: number;
        costOfGoodsSold: number;
        grossProfit: number;
        remainingQuantity: number;
        occurredAt: string;
      };
      setReceipt({
        reference: result.reference,
        itemName: result.itemName,
        sku: selectedItem.sku,
        branch: selectedItem.branch ?? 'Assigned branch',
        quantity: result.quantity,
        unit: selectedItem.unit ?? 'units',
        unitPrice: result.unitPrice,
        amount: result.amount,
        costOfGoodsSold: result.costOfGoodsSold,
        grossProfit: result.grossProfit,
        remainingQuantity: result.remainingQuantity,
        occurredAt: result.occurredAt,
      });
      setAmount('1');
      await loadData();
      notify('Sale recorded and stock updated.', 'success');
    } catch (error) {
      notify(error instanceof Error ? error.message : 'Sale could not be recorded.', 'error');
      await loadData();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page sales-page">
      <header className="workflow-hero sales-hero">
        <div className="workflow-hero-copy">
          <p className="eyebrow">OPERATIONS / INVENTORY</p>
          <h1>Sales</h1>
          <p>Record a sale against current catalog pricing and available branch stock.</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-secondary" type="button" onClick={() => void loadData(true)} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>
      </header>

      <section className="stat-strip sales-stat-strip" aria-label="Sales summary for the last seven days">
        <article className="panel sales-stat"><span>7-day revenue</span><strong>{money(report?.totalRevenue)}</strong></article>
        <article className="panel sales-stat"><span>Gross profit</span><strong>{money(report?.grossProfit)}</strong></article>
        <article className="panel sales-stat"><span>Sales recorded</span><strong>{report?.salesCount ?? '—'}</strong></article>
        <article className="panel sales-stat"><span>Average sale</span><strong>{money(report?.averageSale)}</strong></article>
      </section>

      {user?.role !== 'Admin' && user?.role !== 'Manager' && (
        <p className="page-banner">Sale price and cost are taken from the item catalog. Ask a manager to update catalog prices if they are incorrect.</p>
      )}

      <section className="panel sales-record-panel">
        <div className="panel-head">
          <div><h2>Record a sale</h2><p>Prices are locked to the catalog; stock and pricing are rechecked when saved.</p></div>
          <Badge tone="blue">Live stock</Badge>
        </div>
        <div className="sales-form">
          <div
            className="form-field sales-item-picker"
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setItemPickerOpen(false);
            }}
          >
            Search in-stock item
            <input
              role="combobox"
              aria-label="Search in-stock item"
              aria-autocomplete="list"
              aria-expanded={itemPickerOpen && !loading && !saving}
              aria-controls="sales-in-stock-item-options"
              aria-activedescendant={itemPickerOpen && itemOptions[activeItemOption] ? `sales-item-option-${itemOptions[activeItemOption].id}` : undefined}
              value={search}
              onFocus={() => setItemPickerOpen(true)}
              onChange={(event) => {
                setSearch(event.target.value);
                setSelectedId('');
                setActiveItemOption(0);
                setItemPickerOpen(true);
              }}
              onKeyDown={(event) => {
                if (event.key === 'Escape') {
                  setItemPickerOpen(false);
                  return;
                }
                if (!itemPickerOpen || itemOptions.length === 0) return;
                if (event.key === 'ArrowDown') {
                  event.preventDefault();
                  setActiveItemOption((current) => (current + 1) % itemOptions.length);
                } else if (event.key === 'ArrowUp') {
                  event.preventDefault();
                  setActiveItemOption((current) => (current - 1 + itemOptions.length) % itemOptions.length);
                } else if (event.key === 'Enter') {
                  event.preventDefault();
                  selectItem(itemOptions[activeItemOption]);
                }
              }}
              placeholder="Search name, SKU, category or branch"
              disabled={loading || saving}
              autoComplete="off"
            />
            {itemPickerOpen && !loading && !saving && (
              <div id="sales-in-stock-item-options" className="sales-item-options" role="listbox" aria-label="Matching in-stock items">
                {itemOptions.length > 0 ? itemOptions.map((item, index) => (
                  <button
                    id={`sales-item-option-${item.id}`}
                    key={item.id}
                    type="button"
                    role="option"
                    aria-selected={item.id === selectedId || index === activeItemOption}
                    className={index === activeItemOption ? 'is-active' : ''}
                    onMouseEnter={() => setActiveItemOption(index)}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => selectItem(item)}
                  >
                    <span><strong>{item.name}</strong><small>{item.sku} · {item.category ?? 'Uncategorized'} · {item.branch ?? 'No branch'}</small></span>
                    <span className="sales-item-stock">{quantity(item.quantity)} {item.unit ?? 'units'}</span>
                  </button>
                )) : (
                  <p className="sales-item-empty">
                    {items.some((item) => item.quantity > 0 && item.branchId) ? 'No in-stock item matches this search.' : 'No in-stock items with an assigned branch are available.'}
                  </p>
                )}
              </div>
            )}
            {selectedItem && <small>Selected · {quantity(selectedItem.quantity)} {selectedItem.unit ?? 'units'} available at {selectedItem.branch ?? 'assigned branch'}</small>}
          </div>
          <label className="form-field">
            Quantity
            <input type="number" aria-label="Quantity to sell" min="0.001" step="0.001" max={selectedItem?.quantity} value={amount} onChange={(event) => setAmount(event.target.value)} disabled={!selectedItem || saving} />
            {selectedItem && <small>Available: {quantity(selectedItem.quantity)} {selectedItem.unit ?? 'units'}</small>}
          </label>
          <label className="form-field">
            Unit selling price
            <input value={selectedItem ? money(selectedItem.sellingPrice) : 'Select an item'} readOnly />
          </label>
          <label className="form-field">
            Unit cost
            <input value={selectedItem ? money(selectedItem.unitCost) : 'Select an item'} readOnly />
          </label>
          <div className="sales-total">
            <span>Sale total</span>
            <strong>{selectedItem?.sellingPrice == null || !Number.isFinite(saleQuantity) ? '—' : money(saleQuantity * selectedItem.sellingPrice)}</strong>
            <small>{selectedItem?.unitCost != null && selectedItem.sellingPrice != null ? `Estimated gross profit ${money(saleQuantity * (selectedItem.sellingPrice - selectedItem.unitCost))}` : 'Catalog cost and selling price are required.'}</small>
          </div>
          <button type="button" className="btn btn-primary sales-submit" disabled={!canRecord || saving} onClick={() => setConfirming(true)}>
            {saving ? 'Recording sale…' : 'Review sale'}
          </button>
          {selectedItem && selectedItem.sellingPrice != null && selectedItem.unitCost != null && selectedItem.sellingPrice <= selectedItem.unitCost && (
            <p className="form-error" role="alert">Selling price must be greater than unit cost to record a profitable sale.</p>
          )}
          {selectedItem && saleQuantity > selectedItem.quantity && <p className="form-error" role="alert">Sale quantity exceeds available stock.</p>}
          {selectedItem && amount !== '' && Number.isFinite(saleQuantity) && !hasSupportedQuantityPrecision(saleQuantity) && <p className="form-error" role="alert">Sale quantity can have no more than three decimal places.</p>}
        </div>
      </section>

      <section className="panel sales-history-panel">
        <div className="panel-head"><div><h2>Recent sales &amp; receipts</h2><p>Latest recorded sales in the last seven days.</p></div></div>
        {loading && !report ? <p className="empty-state">Loading sales…</p> : (
          <div className="table-wrap">
            <table className="data-table">
              <thead><tr><th>Reference</th><th>Items</th><th>Quantity</th><th>Time</th><th>Sale total</th><th>Gross profit</th><th>Receipt</th></tr></thead>
              <tbody>
                {(report?.recentSales ?? []).map((sale) => (
                  <tr key={sale.id}>
                    <td><strong>{sale.reference}</strong></td>
                    <td>{sale.items.join(', ') || 'Inventory sale'}</td>
                    <td>{quantity(sale.quantity)}</td>
                    <td>{new Date(sale.occurredAt).toLocaleString('en-LK', { dateStyle: 'medium', timeStyle: 'short' })}</td>
                    <td className="amount">{money(sale.amount)}</td>
                    <td>{money(sale.grossProfit)}</td>
                    <td><button type="button" className="link-button" onClick={() => setReceipt(sale)}>View receipt</button></td>
                  </tr>
                ))}
                {!report?.recentSales.length && <tr><td colSpan={7} className="empty-state">No sales recorded in the last seven days.</td></tr>}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {confirming && selectedItem && (
        <ConfirmDialog
          title="Confirm this sale?"
          message={`${quantity(saleQuantity)} ${selectedItem.unit ?? 'units'} of ${selectedItem.name} at ${money(selectedItem.sellingPrice)} each. Total: ${money(saleQuantity * (selectedItem.sellingPrice ?? 0))}. Remaining stock: ${quantity(selectedItem.quantity - saleQuantity)}. The server will recheck price and stock before applying.`}
          confirmLabel="Record sale"
          onConfirm={() => { void recordSale(); }}
          onCancel={() => setConfirming(false)}
        />
      )}

      {receipt && (
        <div className="modal-overlay sales-receipt-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setReceipt(null); }}>
          <section className="modal sales-receipt-modal" role="dialog" aria-modal="true" aria-labelledby="sales-receipt-title">
            <div className="modal-header sales-receipt-actions">
              <h2 id="sales-receipt-title">Sale receipt</h2>
              <div><button className="btn btn-secondary" type="button" onClick={() => window.print()}>Print / Save PDF</button><button className="btn btn-secondary" type="button" onClick={() => setReceipt(null)}>Close</button></div>
            </div>
            <div className="modal-body sales-receipt-body">
              <p><strong>Reference</strong><span>{receipt.reference}</span></p>
              <p><strong>Date</strong><span>{new Date(receipt.occurredAt).toLocaleString('en-LK')}</span></p>
              {'itemName' in receipt ? (
                <>
                  <p><strong>Item</strong><span>{receipt.itemName} · {receipt.sku}</span></p>
                  <p><strong>Branch</strong><span>{receipt.branch}</span></p>
                  <p><strong>Quantity</strong><span>{quantity(receipt.quantity)} {receipt.unit}</span></p>
                  <p><strong>Unit price</strong><span>{money(receipt.unitPrice)}</span></p>
                  <p><strong>Total</strong><span>{money(receipt.amount)}</span></p>
                  <p><strong>Cost of goods</strong><span>{money(receipt.costOfGoodsSold)}</span></p>
                  <p><strong>Gross profit</strong><span>{money(receipt.grossProfit)}</span></p>
                  <p><strong>Stock remaining</strong><span>{quantity(receipt.remainingQuantity)} {receipt.unit}</span></p>
                </>
              ) : (
                <>
                  <p><strong>Items</strong><span>{receipt.items.join(', ') || 'Inventory sale'}</span></p>
                  <p><strong>Quantity</strong><span>{quantity(receipt.quantity)} total units</span></p>
                  <p><strong>Sale total</strong><span>{money(receipt.amount)}</span></p>
                  <p><strong>Gross profit</strong><span>{money(receipt.grossProfit)}</span></p>
                </>
              )}
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
