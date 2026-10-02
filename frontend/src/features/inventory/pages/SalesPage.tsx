import { API_BASE_URL } from '../../../api/apiBaseUrl';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';
import { getStoredToken } from '../authToken';
import { Badge } from '../ui/Badge';
import { Icon } from '../ui/Icon';
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
  reorderLevel?: number;
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
  reorderLevel: number;
  occurredAt: string;
};

type HistoricalSaleReceipt = Pick<RecentSale, 'reference' | 'occurredAt' | 'amount' | 'quantity' | 'items' | 'grossProfit'>;
type ReceiptView = SaleReceipt | HistoricalSaleReceipt;

type InventoryListResponse = { items?: InventoryItem[]; totalPages?: number };
type BranchOption = { id: string; name: string };

const API_PAGE_SIZE = 100;
const BRANCH_LOADING_MIN_DURATION_MS = 5_000;

function isBranchOption(value: unknown): value is BranchOption {
  return Boolean(
    value && typeof value === 'object' &&
    'id' in value && typeof value.id === 'string' &&
    'name' in value && typeof value.name === 'string',
  );
}

function money(value: number | null | undefined) {
  return value == null ? 'Not available' : `LKR ${value.toLocaleString('en-LK', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function quantity(value: number) {
  return value.toLocaleString('en-LK', { maximumFractionDigits: 3 });
}

function receiptDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Date unavailable';
  const local = date.toLocaleString('en-GB', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  return local.replace(',', '');
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
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [selectedBranchId, setSelectedBranchId] = useState(user?.role === 'Admin' ? '' : user?.branchId ?? '');
  const [report, setReport] = useState<SalesReport | null>(null);
  const [selectedId, setSelectedId] = useState('');
  const [search, setSearch] = useState('');
  const itemSearchRef = useRef<HTMLInputElement>(null);
  const [itemPickerOpen, setItemPickerOpen] = useState(false);
  const [activeItemOption, setActiveItemOption] = useState(0);
  const [amount, setAmount] = useState('1');
  const [loading, setLoading] = useState(true);
  const loadRequestSequence = useRef(0);
  const pendingBranchChange = useRef(false);
  const [saving, setSaving] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [receipt, setReceipt] = useState<ReceiptView | null>(null);

  const isAdmin = user?.role === 'Admin';
  const assignedBranchMissing = !isAdmin && !user?.branchId;
  const selectedItem = items.find((item) => item.id === selectedId) ?? null;
  const selectedBranchName = branches.find((branch) => branch.id === selectedBranchId)?.name;
  const saleQuantity = Number(amount);
  const itemOptions = useMemo(() => {
    const query = search.trim().toLowerCase();
    return items.filter((item) => {
      if (!item.branchId || item.quantity <= 0) return false;
      if (selectedBranchId && item.branchId !== selectedBranchId) return false;
      if (!query) return true;
      return `${item.name} ${item.sku} ${item.category ?? ''} ${item.branch ?? ''}`.toLowerCase().includes(query);
    });
  }, [items, search, selectedBranchId]);
  const selectItem = (item: InventoryItem) => {
    setSelectedId(item.id);
    setSearch(`${item.name} · ${item.sku} · ${item.branch ?? 'No branch'}`);
    setItemPickerOpen(false);
  };

  const loadData = useCallback(async (showFeedback = false) => {
    const requestSequence = ++loadRequestSequence.current;
    const holdForBranchChange = pendingBranchChange.current;
    pendingBranchChange.current = false;
    const loadingStartedAt = Date.now();
    setLoading(true);
    try {
      if (!isAdmin && !user?.branchId) {
        setItems([]);
        setBranches([]);
        setSelectedId('');
        setReport(null);
        throw new Error('Your account has no assigned branch. Sales are unavailable until one is assigned.');
      }
      const effectiveBranchId = isAdmin ? selectedBranchId : user?.branchId ?? '';
      const branchResponse = await authorizedFetch('/inventory/branches', token);
      const branchData: unknown = await branchResponse.json();
      if (requestSequence !== loadRequestSequence.current) return;
      if (!Array.isArray(branchData) || !branchData.every(isBranchOption)) {
        throw new Error('Branch response did not contain a valid branch list.');
      }
      const scopedBranches = isAdmin
        ? branchData
        : branchData.filter((branch) => branch.id === user?.branchId);
      setBranches(scopedBranches);

      const inventory: InventoryItem[] = [];
      let page = 1;
      let totalPages = 1;
      while (page <= totalPages) {
        const inventoryParams = new URLSearchParams({ page: String(page), pageSize: String(API_PAGE_SIZE) });
        if (effectiveBranchId) inventoryParams.set('branchId', effectiveBranchId);
        const response = await authorizedFetch(`/inventory?${inventoryParams.toString()}`, token);
        const payload = await response.json() as InventoryListResponse;
        if (!Array.isArray(payload.items)) throw new Error('Inventory response did not contain an item list.');
        inventory.push(...payload.items);
        totalPages = Math.max(1, Number(payload.totalPages ?? 1));
        page++;
        if (requestSequence !== loadRequestSequence.current) return;
      }
      const range = dateWindow(7);
      const params = new URLSearchParams({ from: range.from, to: range.to, page: '1', pageSize: '10' });
      if (effectiveBranchId) params.set('branchId', effectiveBranchId);
      const reportResponse = await authorizedFetch(`/reports/sales-activity?${params}`, token);
      const nextReport = await reportResponse.json() as SalesReport;
      if (requestSequence !== loadRequestSequence.current) return;
      const scopedInventory = isAdmin
        ? inventory
        : inventory.filter((item) => item.branchId === effectiveBranchId);
      setItems(scopedInventory);
      setSelectedId((current) => scopedInventory.some((item) =>
        item.id === current && item.quantity > 0 &&
        (!effectiveBranchId || item.branchId === effectiveBranchId),
      ) ? current : '');
      setReport(nextReport);
      if (showFeedback) notify('Sales and inventory refreshed.', 'success');
    } catch (error) {
      if (requestSequence === loadRequestSequence.current) {
        notify(error instanceof Error ? error.message : 'Sales data could not be loaded.', 'error');
      }
    } finally {
      if (requestSequence === loadRequestSequence.current) {
        if (holdForBranchChange) {
          const remainingDuration = BRANCH_LOADING_MIN_DURATION_MS - (Date.now() - loadingStartedAt);
          if (remainingDuration > 0) {
            await new Promise((resolve) => setTimeout(resolve, remainingDuration));
          }
        }
        if (requestSequence === loadRequestSequence.current) setLoading(false);
      }
    }
  }, [isAdmin, notify, selectedBranchId, token, user?.branchId]);

  useEffect(() => { void loadData(); }, [loadData]);

  function changeBranch(branchId: string) {
    if (!isAdmin) return;
    pendingBranchChange.current = true;
    setSelectedBranchId(branchId);
    setSelectedId('');
    setSearch('');
    setAmount('1');
    setItemPickerOpen(false);
    setActiveItemOption(0);
  }

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
        reorderLevel: selectedItem.reorderLevel ?? 0,
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
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="workflow-hero-copy">
          <p className="eyebrow">OPERATIONS / INVENTORY</p>
          <h1>Sales</h1>
          <p>Record a sale against current catalog pricing and available branch stock.</p>
          <div className="sales-hero-status">
            <span className={loading ? 'is-loading' : 'is-ready'} aria-hidden="true" />
            <span>{loading ? 'Syncing sales and inventory' : `${items.filter((item) => item.quantity > 0).length} in-stock items available`}</span>
            <span className="sales-hero-status-divider" aria-hidden="true" />
            <span>{selectedBranchName ?? (selectedBranchId ? 'Selected branch' : isAdmin ? 'All branches' : 'Assigned branch')}</span>
          </div>
        </div>
        <aside className="sales-hero-activity" aria-label="Latest sales activity">
          <div className="sales-hero-activity-heading">
            <span className="sales-hero-activity-icon" aria-hidden="true"><Icon name="chart" size={17} /></span>
            <div><span>RECENT ACTIVITY</span><strong>Last 7 days</strong></div>
            <span className="sales-hero-activity-live" aria-hidden="true" />
          </div>
          {report?.recentSales.length ? (
            <ul>
              {report.recentSales.slice(0, 3).map((sale) => (
                <li key={sale.id}>
                  <span><strong>{sale.reference}</strong><small>{receiptDate(sale.occurredAt)}</small></span>
                  <b>{money(sale.amount)}</b>
                </li>
              ))}
            </ul>
          ) : (
            <p className="sales-hero-activity-empty">
              {loading ? 'Loading recent transactions…' : 'No sales recorded in this period yet.'}
            </p>
          )}
        </aside>
        <div className="page-actions">
          <button className="btn btn-secondary" type="button" onClick={() => void loadData(true)} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>
      </header>

      <section className="stat-strip sales-stat-strip" aria-label="Sales summary for the last seven days">
        <article className="panel sales-stat sales-stat-revenue" aria-label="7-day revenue">
          <div className="sales-stat-main">
            <span className="sales-stat-icon" aria-hidden="true"><Icon name="chart" size={20} /></span>
            <div><span className="sales-stat-kicker">SALES PERFORMANCE</span><strong>{money(report?.totalRevenue)}</strong></div>
            <span className="sales-stat-period">7 DAYS</span>
          </div>
          <div className="sales-stat-detail"><span className="sales-stat-detail-dot" />Sales total for the last seven days</div>
        </article>
        <article className="panel sales-stat sales-stat-profit" aria-label="Gross profit">
          <div className="sales-stat-main">
            <span className="sales-stat-icon" aria-hidden="true"><Icon name="workflow" size={20} /></span>
            <div><span className="sales-stat-kicker">PROFITABILITY</span><strong>{money(report?.grossProfit)}</strong></div>
            <span className="sales-stat-period">7 DAYS</span>
          </div>
          <div className="sales-stat-detail"><span className="sales-stat-detail-dot" />Revenue after recorded item costs</div>
        </article>
        <article className="panel sales-stat sales-stat-count" aria-label="Sales recorded">
          <div className="sales-stat-main">
            <span className="sales-stat-icon" aria-hidden="true"><Icon name="inventory" size={20} /></span>
            <div><span className="sales-stat-kicker">TRANSACTIONS</span><strong>{report?.salesCount ?? '—'}</strong></div>
            <span className="sales-stat-period">7 DAYS</span>
          </div>
          <div className="sales-stat-detail"><span className="sales-stat-detail-dot" />Completed sales in this period</div>
        </article>
        <article className="panel sales-stat sales-stat-average" aria-label="Average sale">
          <div className="sales-stat-main">
            <span className="sales-stat-icon" aria-hidden="true"><Icon name="predict" size={20} /></span>
            <div><span className="sales-stat-kicker">TYPICAL CHECK</span><strong>{money(report?.averageSale)}</strong></div>
            <span className="sales-stat-period">AVERAGE</span>
          </div>
          <div className="sales-stat-detail"><span className="sales-stat-detail-dot" />Average value per transaction</div>
        </article>
      </section>

      {user?.role === 'Staff' && (
        <aside className="sales-staff-tip" aria-labelledby="sales-staff-tip-title">
          <span className="sales-staff-tip-icon" aria-hidden="true"><Icon name="info" size={19} /></span>
          <div>
            <h2 id="sales-staff-tip-title">Quick pricing tip</h2>
            <p>
              Sale price and cost are filled in from the item catalog, so you
              don’t need to enter them. If a price looks off, let your manager
              know and they can update it for you.
            </p>
          </div>
        </aside>
      )}

      <section className="panel sales-record-panel">
        <div className="panel-head">
          <div><span className="sales-section-eyebrow">NEW TRANSACTION</span><h2>Record a sale</h2><p>Choose an in-stock item from the selected branch, review the total, and confirm. Catalog prices stay locked.</p></div>
          <Badge tone="blue">Live stock</Badge>
        </div>
        <div className="sales-form">
          {loading && (
            <div className="sales-branch-loading" role="status" aria-live="polite">
              <span className="sales-branch-loading-spinner" aria-hidden="true" />
              <span>Fetching {selectedBranchName ?? 'selected branch'} stock and sales data…</span>
              <span className="sales-branch-loading-track" aria-hidden="true"><i /></span>
            </div>
          )}
          <label className="form-field sales-branch-picker">
            Sale branch
            {isAdmin
              ? <select aria-label="Sale branch" value={selectedBranchId} onChange={(event) => changeBranch(event.target.value)} disabled={saving}>
                  <option value="">All branches</option>
                  {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
                </select>
              : <input aria-label="Sale branch" value={branches.find((branch) => branch.id === user?.branchId)?.name ?? (user?.branchId ? 'Assigned branch' : 'No assigned branch')} readOnly />}
            <small>{assignedBranchMissing
              ? 'Ask an administrator to assign your account to a branch before recording sales.'
              : loading
                ? 'Refreshing branch-specific stock and recent sales.'
                : isAdmin && !selectedBranchId
                  ? 'Administrator view includes all tenant branches.'
                  : 'Only stock held at your assigned branch can be selected.'}</small>
          </label>
          <div
            className="form-field sales-item-picker"
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setItemPickerOpen(false);
            }}
          >
            Search in-stock item
            <div className="sales-item-search-control">
              <input
                ref={itemSearchRef}
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
                placeholder={selectedBranchId ? 'Search this branch by name, SKU or category' : 'Search name, SKU, category or branch'}
                disabled={loading || saving}
                autoComplete="off"
              />
              {search && (
                <button
                  type="button"
                  className="sales-item-clear"
                  aria-label="Clear selected item"
                  title="Clear selected item"
                  disabled={loading || saving}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => {
                    setSearch('');
                    setSelectedId('');
                    setAmount('1');
                    setActiveItemOption(0);
                    setItemPickerOpen(true);
                    itemSearchRef.current?.focus();
                  }}
                >
                  <span aria-hidden="true">×</span>
                </button>
              )}
            </div>
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
                    {items.some((item) =>
                      item.quantity > 0 && item.branchId &&
                      (!selectedBranchId || item.branchId === selectedBranchId),
                    ) ? 'No in-stock item matches this search.' : selectedBranchId
                      ? 'No in-stock items are available at this branch.'
                      : 'No in-stock items with an assigned branch are available.'}
                  </p>
                )}
              </div>
            )}
            {selectedItem && <small>Selected · {quantity(selectedItem.quantity)} {selectedItem.unit ?? 'units'} available at {selectedItem.branch ?? 'assigned branch'}</small>}
          </div>
          <label className="form-field">
            Quantity
            <input type="number" aria-label="Quantity to sell" min="0" step="1" max={selectedItem?.quantity} value={amount} onChange={(event) => setAmount(event.target.value)} disabled={!selectedItem || saving} />
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

      <section className="panel sales-history-panel" aria-labelledby="sales-history-title">
        <div className="panel-head sales-history-head">
          <div className="sales-history-heading">
            <span className="sales-history-icon" aria-hidden="true"><Icon name="chart" size={19} /></span>
            <div>
              <span className="sales-section-eyebrow">TRANSACTION HISTORY</span>
              <h2 id="sales-history-title">Recent sales &amp; receipts</h2>
              <p>Review completed sales, compare totals, and open printable receipts.</p>
            </div>
          </div>
          <div className="sales-history-meta">
            <Badge tone="blue">Last 7 days</Badge>
            {report && <span className="sales-history-count">{report.recentSales.length} {report.recentSales.length === 1 ? 'sale' : 'sales'}</span>}
          </div>
        </div>
        {loading && !report ? (
          <div className="sales-history-state" role="status">
            <span className="sales-history-state-icon" aria-hidden="true"><Icon name="chart" size={20} /></span>
            <strong>Loading transactions</strong>
            <span>Fetching your latest sales and receipt details…</span>
          </div>
        ) : (
          <div className="table-wrap sales-history-table-wrap">
            <table className="data-table sales-history-table">
              <thead><tr><th>Sale reference</th><th>Items sold</th><th>Quantity</th><th>Date &amp; time</th><th>Sale total</th><th>Gross profit</th><th>Receipt</th></tr></thead>
              <tbody>
                {(report?.recentSales ?? []).map((sale) => (
                  <tr key={sale.id}>
                    <td>
                      <div className="sales-history-reference">
                        <span className="sales-history-reference-mark" aria-hidden="true"><Icon name="po" size={15} /></span>
                        <div><strong>{sale.reference}</strong><small>Completed sale</small></div>
                      </div>
                    </td>
                    <td>
                      <div className="sales-history-items">
                        <strong>{sale.items[0] || 'Inventory sale'}</strong>
                        {sale.items.length > 1 && <small>+{sale.items.length - 1} more {sale.items.length === 2 ? 'item' : 'items'}</small>}
                      </div>
                    </td>
                    <td><span className="sales-history-quantity">{quantity(sale.quantity)} <small>units</small></span></td>
                    <td>
                      <div className="sales-history-time">
                        <strong>{new Date(sale.occurredAt).toLocaleDateString('en-LK', { dateStyle: 'medium' })}</strong>
                        <small>{new Date(sale.occurredAt).toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}</small>
                      </div>
                    </td>
                    <td><strong className="sales-history-total">{money(sale.amount)}</strong></td>
                    <td><span className={`sales-history-profit${sale.grossProfit == null ? ' is-unavailable' : ''}`}>{money(sale.grossProfit)}</span></td>
                    <td><button type="button" className="sales-receipt-button" onClick={() => setReceipt(sale)}><Icon name="po" size={15} /> View receipt</button></td>
                  </tr>
                ))}
                {!report?.recentSales.length && <tr><td colSpan={7}>
                  <div className="sales-history-state sales-history-empty">
                    <span className="sales-history-state-icon" aria-hidden="true"><Icon name="chart" size={20} /></span>
                    <strong>No sales in this period</strong>
                    <span>Completed transactions from the last seven days will appear here.</span>
                  </div>
                </td></tr>}
              </tbody>
            </table>
          </div>
        )}
        <footer className="sales-history-footer">
          <span><i aria-hidden="true" /> Sales are recorded against current catalog prices and branch stock.</span>
          <span>Showing the last 7 days</span>
        </footer>
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
          <section className="sales-receipt-modal" role="dialog" aria-modal="true" aria-labelledby="sales-receipt-title">
            <div className="sales-receipt-toolbar">
              <span>Receipt preview</span>
              <div className="sales-receipt-actions">
                <button className="btn btn-primary" type="button" onClick={() => window.print()}>Print / Save PDF</button>
                <button className="btn btn-secondary" type="button" onClick={() => setReceipt(null)} aria-label="Close receipt">Close</button>
              </div>
            </div>
            <article className="sales-receipt-paper">
              <header className="sales-receipt-paper-header">
                <div>
                  <span className="sales-receipt-kicker">UNIFY · SALES RECEIPT</span>
                  <h2 id="sales-receipt-title">Sale recorded</h2>
                  <p>Official inventory sale record</p>
                </div>
                <span className="sales-receipt-status">SALE RECORDED</span>
              </header>
              <div className="sales-receipt-metadata">
                <div><span>REFERENCE</span><strong>{receipt.reference}</strong></div>
                <div><span>DATE &amp; TIME</span><strong>{receiptDate(receipt.occurredAt)}</strong></div>
                {'branch' in receipt && <div><span>BRANCH</span><strong>{receipt.branch}</strong></div>}
              </div>
              <div className={`sales-receipt-line-items${'itemName' in receipt ? ' has-unit-price' : ''}`}>
                <div className="sales-receipt-line-head">
                  <span>ITEM</span><span>QTY</span>{'itemName' in receipt && <span>UNIT PRICE</span>}<span>AMOUNT</span>
                </div>
                <div className="sales-receipt-line">
                  <div><strong>{'itemName' in receipt ? receipt.itemName : receipt.items.join(', ') || 'Inventory sale'}</strong>{'itemName' in receipt && <small>SKU {receipt.sku}</small>}</div>
                  <span>{'itemName' in receipt ? `${quantity(receipt.quantity)} ${receipt.unit}` : `Qty ${quantity(receipt.quantity)}`}</span>
                  {'itemName' in receipt && <span>{money(receipt.unitPrice)}</span>}
                  <strong>{money(receipt.amount)}</strong>
                </div>
              </div>
              <div className="sales-receipt-summary">
                <div className="sales-receipt-inventory">
                  <span>{'remainingQuantity' in receipt ? 'INVENTORY UPDATE' : 'SALE RECORD'}</span>
                  <strong>{'remainingQuantity' in receipt ? `Stock remaining: ${quantity(receipt.remainingQuantity)} ${receipt.unit}` : 'Saved sale transaction'}</strong>
                </div>
                <div className="sales-receipt-total"><span>TOTAL</span><strong>{money(receipt.amount)}</strong></div>
              </div>
              {'remainingQuantity' in receipt && receipt.remainingQuantity <= receipt.reorderLevel && (
                <p className="sales-receipt-low-stock">LOW STOCK | Remaining quantity is at or below the reorder level.</p>
              )}
              <footer className="sales-receipt-footer">
                <p>This receipt confirms that the inventory sale was recorded in Unify. Payment collection is not recorded by this receipt.</p>
                <span>Generated by Unify</span>
              </footer>
            </article>
          </section>
        </div>
      )}
    </div>
  );
}
