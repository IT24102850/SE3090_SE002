import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import { useGetBranchesQuery } from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { Badge, type BadgeTone } from '../ui/Badge';
import { getStoredToken } from '../authToken';
import { useToast } from '../ui/ToastContext';

type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  category?: string;
  categoryId?: string;
  description?: string;
  unit?: string;
  branch?: string;
  branchId?: string;
  quantity: number;
  reorderLevel: number;
  unitCost?: number;
};
type BranchSummary = { id: string; name: string; items: number; value: number; attention: number; health: 'Healthy' | 'Needs attention' | 'Critical' };
type BranchCommerceSummary = {
  branchId: string;
  branchName: string;
  salesCount: number;
  salesRevenue: number;
  manualSalesCount: number;
  manualSalesRevenue: number;
  customerOrderSalesCount: number;
  customerOrderSalesRevenue: number;
  customerOrderCount: number;
  customerOrderValue: number;
  pendingOrders: number;
  confirmedOrders: number;
  preparingOrders: number;
  readyForPickupOrders: number;
  outForDeliveryOrders: number;
  completedOrders: number;
  cancelledOrders: number;
};
type BranchCommerceReport = {
  salesCount: number;
  salesRevenue: number;
  manualSalesCount: number;
  manualSalesRevenue: number;
  customerOrderSalesCount: number;
  customerOrderSalesRevenue: number;
  customerOrderCount: number;
  customerOrderValue: number;
  pendingOrders: number;
  confirmedOrders: number;
  preparingOrders: number;
  readyForPickupOrders: number;
  outForDeliveryOrders: number;
  completedOrders: number;
  cancelledOrders: number;
  branches: BranchCommerceSummary[];
};
type StockHealthFilter = 'All stock health' | 'In stock' | 'Low stock' | 'Out of stock';

const healthTone: Record<BranchSummary['health'], BadgeTone> = { Healthy: 'green', 'Needs attention': 'amber', Critical: 'red' };

function healthFor(items: InventoryItem[]): BranchSummary['health'] {
  if (items.some((item) => item.quantity <= 0)) return 'Critical';
  if (items.some((item) => item.quantity <= item.reorderLevel)) return 'Needs attention';
  return 'Healthy';
}

function money(value: number) {
  return `LKR ${value.toLocaleString('en-LK')}`;
}

function categoryNameFor(item: InventoryItem, categoryNames: Record<string, string>) {
  if (item.category?.trim()) return item.category.trim();
  if (item.categoryId) {
    const resolved = categoryNames[item.categoryId.toLowerCase()];
    if (resolved) return resolved;
  }
  const description = item.description?.trim().toLowerCase();
  if (description) {
    for (const name of Object.values(categoryNames)) {
      const normalized = name.toLowerCase();
      if (description === normalized || (description.startsWith(`${normalized} (`) && description.endsWith(')'))) {
        return name;
      }
    }
  }
  return 'Uncategorised';
}

function categoryPresentation(category?: string) {
  const label = category?.trim() || 'Uncategorised';
  const normalized = label.toLowerCase();
  if (normalized.includes('tech') || normalized.includes('computer') || normalized.includes('equipment')) return { label, icon: '◈', tone: 'tech' };
  if (normalized.includes('office') || normalized.includes('station') || normalized.includes('paper')) return { label, icon: '▤', tone: 'office' };
  if (normalized.includes('food') || normalized.includes('bever') || normalized.includes('ingredient') || normalized.includes('provision')) return { label, icon: '◌', tone: 'provisions' };
  if (normalized.includes('print') || normalized.includes('market') || normalized.includes('packaging')) return { label, icon: '✦', tone: 'creative' };
  return { label, icon: '◆', tone: 'other' };
}

export function BranchOverviewPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const user = useSelector((state: RootState) => state.auth.user);
  const tenantId = user?.tenantId ?? '';
  const isAdmin = user?.role === 'Admin';
  const assignedBranchId = isAdmin ? undefined : user?.branchId;
  const { data: databaseBranches = [] } = useGetBranchesQuery(
    { tenantId },
    { skip: !tenantId || !isAdmin },
  );
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [assignedBranch, setAssignedBranch] = useState<{ id: string; name: string } | null>(null);
  const [categoryNames, setCategoryNames] = useState<Record<string, string>>({});
  const [categoryWarning, setCategoryWarning] = useState('');
  const [commerce, setCommerce] = useState<BranchCommerceReport | null>(null);
  const [commerceError, setCommerceError] = useState('');
  const [commerceLoading, setCommerceLoading] = useState(true);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [itemQuery, setItemQuery] = useState('');
  const [itemBranch, setItemBranch] = useState(isAdmin ? 'All branches' : assignedBranchId ?? '');
  const [itemHealth, setItemHealth] = useState<StockHealthFilter>('All stock health');

  const loadInventory = useCallback(async (showMessage = false) => {
    setLoading(true);
    try {
      if (!isAdmin && !assignedBranchId) {
        throw new Error('Your account has no assigned branch. Inventory is unavailable until one is assigned.');
      }
      let branchScope = '';
      if (!isAdmin && assignedBranchId) {
        const branchResponse = await fetch('/api/inventory/branches', {
          headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        });
        if (!branchResponse.ok) throw new Error(`Branch request failed (${branchResponse.status})`);
        const branchData = await branchResponse.json() as Array<{ id?: string; name?: string }>;
        const branch = branchData.find((entry) => entry.id === assignedBranchId);
        if (!branch) throw new Error('Your assigned branch could not be loaded.');
        branchScope = branch.name ?? 'Assigned branch';
        setAssignedBranch({ id: assignedBranchId, name: branchScope });
        setItemBranch(branchScope);
      }
      const rows: InventoryItem[] = [];
      let page = 1;
      let totalPages = 1;
      do {
        const params = new URLSearchParams({ page: String(page), pageSize: '100' });
        if (assignedBranchId) params.set('branchId', assignedBranchId);
        const response = await fetch(`/api/inventory?${params}`, {
          headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        });
        if (!response.ok) throw new Error(`Inventory request failed (${response.status})`);
        const data = await response.json() as { items?: InventoryItem[]; totalPages?: number };
        rows.push(...(data.items ?? []));
        totalPages = Number(data.totalPages ?? 1);
        page += 1;
      } while (page <= totalPages);
      setInventory(isAdmin
        ? rows
        : rows.filter((item) => item.branchId === assignedBranchId));
      try {
        const categoryResponse = await fetch('/api/inventory/categories', {
          headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        });
        if (!categoryResponse.ok) throw new Error(`Category request failed (${categoryResponse.status})`);
        const categoryData = await categoryResponse.json() as Array<{ id?: string; name?: string }>;
        setCategoryNames(Object.fromEntries(
          categoryData
            .filter((category) => typeof category.id === 'string' && typeof category.name === 'string' && category.name.trim())
            .map((category) => [category.id!.toLowerCase(), category.name!.trim()]),
        ));
        setCategoryWarning('');
      } catch (categoryError) {
        const message = categoryError instanceof Error ? categoryError.message : 'Unable to load inventory categories.';
        setCategoryWarning(`Category names could not be resolved (${message}).`);
      }
      setError('');
      setLastUpdated(new Date());
      if (showMessage) notify('Branch inventory refreshed.', 'success');
      return true;
    } catch (loadError) {
      const message = loadError instanceof Error ? loadError.message : 'Unable to load branch inventory from the database.';
      setError(message);
      if (showMessage) notify(message, 'error');
      return false;
    } finally {
      setLoading(false);
    }
  }, [assignedBranchId, isAdmin, notify, token]);

  const loadCommerce = useCallback(async () => {
    if (!isAdmin && !assignedBranchId) {
      setCommerceLoading(false);
      return false;
    }
    setCommerceLoading(true);
    try {
      const to = new Date();
      const from = new Date();
      from.setDate(from.getDate() - 29);
      const params = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
      if (assignedBranchId) params.set('branchId', assignedBranchId);
      const response = await fetch(`/api/reports/branch-commerce?${params}`, {
        headers: token ? { Authorization: ['Bearer', token].join(' ') } : undefined,
      });
      if (!response.ok) throw new Error(`Sales and order summary request failed (${response.status}).`);
      const report = await response.json() as BranchCommerceReport;
      setCommerce(report);
      setCommerceError('');
      return true;
    } catch (loadError) {
      const message = loadError instanceof Error
        ? loadError.message
        : 'Unable to load branch sales and customer-order activity.';
      setCommerceError(message);
      return false;
    } finally {
      setCommerceLoading(false);
    }
  }, [assignedBranchId, isAdmin, token]);

  useEffect(() => { void loadInventory(); }, [loadInventory]);
  useEffect(() => { void loadCommerce(); }, [loadCommerce]);
  useEffect(() => {
    const timer = window.setInterval(() => { void loadCommerce(); }, 30000);
    return () => window.clearInterval(timer);
  }, [loadCommerce]);

  const branches = useMemo<BranchSummary[]>(() => {
    const grouped = new Map<string, InventoryItem[]>();
    inventory.forEach((item) => {
      const key = item.branchId ?? 'unassigned';
      grouped.set(key, [...(grouped.get(key) ?? []), item]);
    });
    const sourceBranches = isAdmin
      ? databaseBranches
      : assignedBranch ? [assignedBranch] : [];
    const summaries = sourceBranches.map((branch) => {
      const items = grouped.get(branch.id) ?? [];
      return {
        id: branch.id,
        name: branch.name,
        items: items.length,
        value: items.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
        attention: items.filter((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel).length,
        health: items.length ? healthFor(items) : 'Healthy',
      };
    });
    const unassigned = grouped.get('unassigned') ?? [];
    if (unassigned.length) {
      summaries.push({
        id: 'unassigned',
        name: 'Unassigned stock',
        items: unassigned.length,
        value: unassigned.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
        attention: unassigned.filter((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel).length,
        health: healthFor(unassigned),
      });
    }
    return summaries;
  }, [assignedBranch, databaseBranches, inventory, isAdmin]);

  const summary = useMemo(() => ({
    branches: branches.length,
    attention: branches.reduce((sum, branch) => sum + branch.attention, 0),
    value: branches.reduce((sum, branch) => sum + branch.value, 0),
    healthy: branches.filter((branch) => branch.health === 'Healthy').length,
  }), [branches]);
  const productCount = useMemo(
    () => new Set(inventory.map((item) => item.sku.trim().toLowerCase() || item.name.trim().toLowerCase())).size,
    [inventory],
  );
  const commerceByBranch = useMemo(
    () => new Map((commerce?.branches ?? []).map((branch) => [branch.branchId, branch])),
    [commerce],
  );
  const activeOrderCount = commerce
    ? commerce.pendingOrders + commerce.confirmedOrders + commerce.preparingOrders +
      commerce.readyForPickupOrders + commerce.outForDeliveryOrders
    : 0;

  const comparisonItems = useMemo(() => {
    const term = itemQuery.trim().toLowerCase();
    return inventory.filter((item) => {
      const matchesBranch = isAdmin
        ? itemBranch === 'All branches' || (item.branch ?? 'Unassigned') === itemBranch
        : Boolean(assignedBranchId) && item.branchId === assignedBranchId;
      const category = categoryPresentation(categoryNameFor(item, categoryNames)).label;
      const matchesText = !term || [item.name, item.sku, item.branch ?? 'Unassigned', category].some((field) => field.toLowerCase().includes(term));
      const health = item.quantity <= 0 ? 'Out of stock' : item.quantity <= item.reorderLevel ? 'Low stock' : 'In stock';
      const matchesHealth = itemHealth === 'All stock health' || itemHealth === health;
      return matchesBranch && matchesText && matchesHealth;
    });
  }, [assignedBranchId, categoryNames, inventory, isAdmin, itemBranch, itemHealth, itemQuery]);
  const comparisonBranches = isAdmin
    ? ['All branches', ...Array.from(new Set(inventory.map((item) => item.branch ?? 'Unassigned'))).sort((a, b) => a.localeCompare(b))]
    : [assignedBranch?.name ?? 'Assigned branch'];
  const comparisonSummary = useMemo(() => ({
    units: comparisonItems.reduce((sum, item) => sum + Number(item.quantity ?? 0), 0),
    atRisk: new Set(
      comparisonItems
        .filter((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel)
        .map((item) => item.sku.trim().toLowerCase() || item.name.trim().toLowerCase()),
    ).size,
    value: comparisonItems.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
  }), [comparisonItems]);
  const categoryGroups = useMemo(() => {
    const products = new Map<string, InventoryItem[]>();
    comparisonItems.forEach((item) => {
      const productKey = item.sku.trim().toLowerCase() || item.name.trim().toLowerCase();
      products.set(productKey, [...(products.get(productKey) ?? []), item]);
    });
    const categories = new Map<string, InventoryItem[][]>();
    products.forEach((branches) => {
      const label = categoryPresentation(categoryNameFor(branches[0], categoryNames)).label;
      const categoryProducts = categories.get(label) ?? [];
      categoryProducts.push(branches.sort((first, second) =>
        (first.branch ?? 'Unassigned').localeCompare(second.branch ?? 'Unassigned'),
      ));
      categories.set(label, categoryProducts);
    });
    return [...categories.entries()]
      .map(([label, items]) => ({
        ...categoryPresentation(label),
        items,
        value: items.flat().reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
        atRisk: items.filter((branches) =>
          branches.some((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel),
        ).length,
      }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [categoryNames, comparisonItems]);

  return (
    <div className="page branch-overview-page">
      <header className="branch-overview-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="branch-overview-hero-copy">
          <p className="branch-overview-eyebrow"><span aria-hidden="true">◈</span> INVENTORY / NETWORK</p>
          <h1>Branch overview</h1>
          <p>Compare stock health, inventory value, and replenishment needs across your locations.</p>
          <div className="branch-overview-live"><span className={loading ? 'is-loading' : error ? 'is-error' : ''} />{loading ? 'Syncing branch inventory…' : error ? 'Branch inventory sync needs attention' : `${summary.branches} locations · ${productCount} products tracked`}{lastUpdated && !loading && <small>Updated {lastUpdated.toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}</small>}</div>
        </div>
        <div className="branch-overview-art" aria-hidden="true"><span className="branch-overview-orbit" /><span className="branch-overview-art-icon">⌖</span><i /><i /><i /></div>
        <button type="button" className="btn branch-overview-refresh" onClick={() => { void loadInventory(true); void loadCommerce(); }} disabled={loading || commerceLoading}><span aria-hidden="true">↻</span>{loading || commerceLoading ? 'Refreshing…' : 'Refresh data'}</button>
      </header>
      {error && <p className="page-notice" role="alert">{error}</p>}
      <section className="branch-overview-metrics" aria-label="Network inventory summary">
        <article className="branch-overview-metric branch-overview-metric-locations"><span className="branch-overview-metric-icon">⌖</span><span className="branch-overview-metric-label">NETWORK</span><strong>{summary.branches}</strong><small>Locations in view</small></article>
        <article className="branch-overview-metric branch-overview-metric-items"><span className="branch-overview-metric-icon">▦</span><span className="branch-overview-metric-label">STOCK COVERAGE</span><strong>{productCount}</strong><small>Products across branches</small></article>
        <article className="branch-overview-metric branch-overview-metric-health"><span className="branch-overview-metric-icon">◉</span><span className="branch-overview-metric-label">HEALTHY LOCATIONS</span><strong>{summary.healthy}</strong><small>Meeting reorder levels</small></article>
        <article className="branch-overview-metric branch-overview-metric-value"><span className="branch-overview-metric-icon">LKR</span><span className="branch-overview-metric-label">INVENTORY VALUE</span><strong>{money(summary.value)}</strong><small>{summary.attention} items need review</small></article>
      </section>
      <section className="branch-commerce-overview" aria-label="Sales and customer orders for the last 30 days">
        <div className="branch-commerce-heading">
          <div><p className="eyebrow">LAST 30 DAYS</p><h2>Sales &amp; customer orders</h2><p>Completed customer orders are included in sales. Stock is reserved when each order is placed.</p></div>
          <div className="branch-commerce-links"><Link to="/inventory-analytics">View analytics</Link><Link to="/customer-orders">Manage orders</Link></div>
        </div>
        {commerceError && <p className="branch-commerce-error" role="alert">{commerceError}</p>}
        <div className="branch-commerce-metrics">
          <article><span>Total sales</span><strong>{commerceLoading && !commerce ? '…' : money(commerce?.salesRevenue ?? 0)}</strong><small>{commerce?.salesCount ?? 0} recorded sales</small></article>
          <article><span>Manual sales</span><strong>{commerceLoading && !commerce ? '…' : money(commerce?.manualSalesRevenue ?? 0)}</strong><small>{commerce?.manualSalesCount ?? 0} manually recorded</small></article>
          <article><span>Customer-order sales</span><strong>{commerceLoading && !commerce ? '…' : money(commerce?.customerOrderSalesRevenue ?? 0)}</strong><small>{commerce?.customerOrderSalesCount ?? 0} completed orders · included in total sales</small></article>
          <article><span>Customer orders</span><strong>{commerceLoading && !commerce ? '…' : commerce?.customerOrderCount ?? 0}</strong><small>{money(commerce?.customerOrderValue ?? 0)} order value · excludes cancelled</small></article>
          <article><span>Open orders</span><strong>{commerceLoading && !commerce ? '…' : activeOrderCount}</strong><small>{commerce?.pendingOrders ?? 0} awaiting confirmation</small></article>
          <article><span>Completed orders</span><strong>{commerceLoading && !commerce ? '…' : commerce?.completedOrders ?? 0}</strong><small>Recorded once as customer-order sales</small></article>
        </div>
      </section>
      <section className="branch-summary-grid" aria-label="Branch stock summary">
        {branches.map((branch) => (
          <article className={`branch-card branch-card-${branch.health.toLowerCase().replace(' ', '-')}`} key={branch.id}>
            <div className="branch-card-head">
              <span className="branch-card-icon" aria-hidden="true">⌖</span>
              <div className="branch-card-name"><h2>{branch.name}</h2><p>{branch.items} items tracked</p></div>
              <Badge tone={healthTone[branch.health]}>{branch.health}</Badge>
            </div>
            <div className="branch-card-value"><strong>{money(branch.value)}</strong><span>Inventory value</span></div>
            <div className="branch-card-commerce" aria-label={`${branch.name} sales and order activity`}>
              <div><span>Total sales</span><strong>{money(commerceByBranch.get(branch.id)?.salesRevenue ?? 0)}</strong><small>{commerceByBranch.get(branch.id)?.salesCount ?? 0} recorded</small></div>
              <div><span>Manual sales</span><strong>{money(commerceByBranch.get(branch.id)?.manualSalesRevenue ?? 0)}</strong><small>{commerceByBranch.get(branch.id)?.manualSalesCount ?? 0} recorded</small></div>
              <div><span>Customer-order sales</span><strong>{money(commerceByBranch.get(branch.id)?.customerOrderSalesRevenue ?? 0)}</strong><small>{commerceByBranch.get(branch.id)?.customerOrderSalesCount ?? 0} completed</small></div>
              <div><span>Customer orders</span><strong>{commerceByBranch.get(branch.id)?.customerOrderCount ?? 0}</strong><small>{money(commerceByBranch.get(branch.id)?.customerOrderValue ?? 0)} value · excl. cancelled</small></div>
              <small>
                {commerceByBranch.get(branch.id)?.pendingOrders ?? 0} pending ·{' '}
                {commerceByBranch.get(branch.id)?.preparingOrders ?? 0} preparing ·{' '}
                {commerceByBranch.get(branch.id)?.readyForPickupOrders ?? 0} ready ·{' '}
                {commerceByBranch.get(branch.id)?.outForDeliveryOrders ?? 0} delivering
              </small>
            </div>
            <div className="branch-card-foot"><span>{branch.attention ? `${branch.attention} items need attention` : 'Stock levels look healthy'}</span><span className="branch-health-pulse" aria-hidden="true" /></div>
          </article>
        ))}
        {!branches.length && !error && !loading && <p className="cell-sub">No branches are recorded yet.</p>}
      </section>
      <section className="panel branch-directory-panel">
        <div className="panel-head comparison-heading">
          <div><p className="eyebrow">INVENTORY DIRECTORY</p><h2>Stock, organised by category</h2><p>Search and compare item availability, value, and reorder risk across branches.</p></div>
          <span className="comparison-count">{categoryGroups.reduce((sum, group) => sum + group.items.length, 0)} of {productCount} products · {comparisonItems.length} branch stocks · {categoryGroups.length} categories</span>
        </div>
        <div className="toolbar toolbar-wrap branch-comparison-toolbar">
          <div className="search-field"><span className="search-icon" aria-hidden="true">⌕</span><input type="search" aria-label="Search branch inventory" placeholder="Search item, SKU, category or branch" value={itemQuery} onChange={(event) => setItemQuery(event.target.value)} /></div>
          {isAdmin
            ? <select className="filter-select" aria-label="Filter by branch" value={itemBranch} onChange={(event) => setItemBranch(event.target.value)}>{comparisonBranches.map((entry) => <option key={entry}>{entry}</option>)}</select>
            : <span className="filter-select" aria-label="Assigned branch">{comparisonBranches[0]}</span>}
          <select className="filter-select" aria-label="Filter by stock health" value={itemHealth} onChange={(event) => setItemHealth(event.target.value as StockHealthFilter)}>
            <option>All stock health</option><option>In stock</option><option>Low stock</option><option>Out of stock</option>
          </select>
          {(itemQuery || (isAdmin && itemBranch !== 'All branches') || itemHealth !== 'All stock health') && <button type="button" className="btn btn-ghost inventory-clear-filters" onClick={() => { setItemQuery(''); setItemBranch(isAdmin ? 'All branches' : assignedBranch?.name ?? ''); setItemHealth('All stock health'); }}>Clear filters</button>}
        </div>
        {categoryWarning && <p className="branch-category-warning" role="status">{categoryWarning} Items without a saved category or matching legacy category text are grouped as “Uncategorised”.</p>}
        <div className="branch-directory-pulse" aria-label="Filtered inventory summary">
          <div><span className="branch-directory-pulse-icon">▦</span><span><small>PRODUCTS IN VIEW</small><strong>{categoryGroups.reduce((sum, group) => sum + group.items.length, 0)}</strong></span></div>
          <div><span className="branch-directory-pulse-icon branch-directory-pulse-units">◧</span><span><small>UNITS ON HAND</small><strong>{comparisonSummary.units.toLocaleString('en-LK')}</strong></span></div>
          <div className={comparisonSummary.atRisk ? 'has-risk' : ''}><span className="branch-directory-pulse-icon branch-directory-pulse-risk">⚠</span><span><small>NEEDING ATTENTION</small><strong>{comparisonSummary.atRisk}</strong></span></div>
          <div><span className="branch-directory-pulse-icon branch-directory-pulse-value">LKR</span><span><small>FILTERED STOCK VALUE</small><strong>{money(comparisonSummary.value)}</strong></span></div>
        </div>
        {loading && !inventory.length ? <div className="branch-overview-loading"><span className="branch-loading-spinner" />Loading branch stock…</div> : comparisonItems.length ? (
          <div className="category-directory">
            {categoryGroups.map((group) => (
              <section className={`category-stock-card category-${group.tone}`} key={group.label}>
                <header className="category-stock-head">
                  <div className="category-title">
                    <span className="category-icon" aria-hidden="true">{group.icon}</span>
                    <div><h3>{group.label}</h3><p>{group.items.length} products · {group.atRisk} need attention</p></div>
                  </div>
                  <div className="category-stock-total"><small>ON-HAND VALUE</small><strong>{money(group.value)}</strong></div>
                </header>
                <div className="comparison-table-wrap">
                  <table className="data-table">
                    <thead><tr><th>Item</th><th>SKU</th><th>Branch stock</th><th>Total on hand</th><th>Total stock value</th></tr></thead>
                    <tbody>{group.items.map((productItems) => {
                      const first = productItems[0];
                      const totalQuantity = productItems.reduce((sum, item) => sum + Number(item.quantity ?? 0), 0);
                      const totalValue = productItems.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0);
                      return (
                      <tr key={first.sku.trim().toLowerCase() || first.name.trim().toLowerCase()}>
                        <td><strong>{first.name}</strong><small className="branch-item-category">{categoryNameFor(first, categoryNames)}</small></td>
                        <td>
                          <span className="branch-item-sku-card">
                            <span className="branch-item-sku-mark" aria-hidden="true">SKU</span>
                            <code className="branch-item-sku">{first.sku}</code>
                          </span>
                        </td>
                        <td className="branch-stock-cell">
                          <div className="branch-stock-allocations">
                            {productItems.map((item) => {
                              const stockHealth = item.quantity <= 0 ? 'Out of stock' : item.quantity <= item.reorderLevel ? 'Low stock' : 'In stock';
                              return (
                                <div className="branch-stock-allocation" key={item.id}>
                                  <span className="branch-stock-allocation-name">{item.branch ?? 'Unassigned'}</span>
                                  <span className="branch-stock-allocation-quantity">{item.quantity} {item.unit ?? 'units'}</span>
                                  <span className={`branch-stock-status ${item.quantity <= 0 ? 'is-out' : item.quantity <= item.reorderLevel ? 'is-low' : 'is-ok'}`}>{stockHealth}</span>
                                </div>
                              );
                            })}
                          </div>
                        </td>
                        <td>{totalQuantity} {first.unit ?? 'units'}</td>
                        <td>{productItems.some((item) => item.unitCost != null) ? money(totalValue) : '—'}</td>
                      </tr>
                    );})}</tbody>
                  </table>
                </div>
              </section>
            ))}
          </div>
        ) : <p className="empty-state">{inventory.length ? 'No stock items match these filters. Clear filters or choose another branch.' : 'No inventory items are recorded yet.'}</p>}
      </section>
    </div>
  );
}
