import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
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
  const tenantId = useSelector((state: RootState) => state.auth.user?.tenantId ?? '');
  const { data: databaseBranches = [] } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [categoryNames, setCategoryNames] = useState<Record<string, string>>({});
  const [categoryWarning, setCategoryWarning] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [itemQuery, setItemQuery] = useState('');
  const [itemBranch, setItemBranch] = useState('All branches');
  const [itemHealth, setItemHealth] = useState<StockHealthFilter>('All stock health');

  const loadInventory = useCallback(async (showMessage = false) => {
    setLoading(true);
    try {
      const rows: InventoryItem[] = [];
      let page = 1;
      let totalPages = 1;
      do {
        const response = await fetch(`/api/inventory?page=${page}&pageSize=100`, {
          headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        });
        if (!response.ok) throw new Error(`Inventory request failed (${response.status})`);
        const data = await response.json() as { items?: InventoryItem[]; totalPages?: number };
        rows.push(...(data.items ?? []));
        totalPages = Number(data.totalPages ?? 1);
        page += 1;
      } while (page <= totalPages);
      setInventory(rows);
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
  }, [notify, token]);

  useEffect(() => { void loadInventory(); }, [loadInventory]);

  const branches = useMemo<BranchSummary[]>(() => {
    const grouped = new Map<string, InventoryItem[]>();
    inventory.forEach((item) => {
      const key = item.branchId ?? 'unassigned';
      grouped.set(key, [...(grouped.get(key) ?? []), item]);
    });
    const summaries = databaseBranches.map((branch) => {
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
  }, [databaseBranches, inventory]);

  const summary = useMemo(() => ({
    branches: branches.length,
    attention: branches.reduce((sum, branch) => sum + branch.attention, 0),
    value: branches.reduce((sum, branch) => sum + branch.value, 0),
    healthy: branches.filter((branch) => branch.health === 'Healthy').length,
  }), [branches]);

  const comparisonItems = useMemo(() => {
    const term = itemQuery.trim().toLowerCase();
    return inventory.filter((item) => {
      const matchesBranch = itemBranch === 'All branches' || (item.branch ?? 'Unassigned') === itemBranch;
      const category = categoryPresentation(categoryNameFor(item, categoryNames)).label;
      const matchesText = !term || [item.name, item.sku, item.branch ?? 'Unassigned', category].some((field) => field.toLowerCase().includes(term));
      const health = item.quantity <= 0 ? 'Out of stock' : item.quantity <= item.reorderLevel ? 'Low stock' : 'In stock';
      const matchesHealth = itemHealth === 'All stock health' || itemHealth === health;
      return matchesBranch && matchesText && matchesHealth;
    });
  }, [categoryNames, inventory, itemBranch, itemHealth, itemQuery]);
  const comparisonBranches = ['All branches', ...Array.from(new Set(inventory.map((item) => item.branch ?? 'Unassigned'))).sort((a, b) => a.localeCompare(b))];
  const comparisonSummary = useMemo(() => ({
    units: comparisonItems.reduce((sum, item) => sum + Number(item.quantity ?? 0), 0),
    atRisk: comparisonItems.filter((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel).length,
    value: comparisonItems.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
  }), [comparisonItems]);
  const categoryGroups = useMemo(() => {
    const grouped = new Map<string, InventoryItem[]>();
    comparisonItems.forEach((item) => {
      const label = categoryPresentation(categoryNameFor(item, categoryNames)).label;
      grouped.set(label, [...(grouped.get(label) ?? []), item]);
    });
    return [...grouped.entries()]
      .map(([label, items]) => ({
        ...categoryPresentation(label),
        items,
        value: items.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0),
        atRisk: items.filter((item) => item.quantity <= 0 || item.quantity <= item.reorderLevel).length,
      }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [categoryNames, comparisonItems]);

  return (
    <div className="page branch-overview-page">
      <header className="branch-overview-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="branch-overview-hero-copy">
          <p className="branch-overview-eyebrow"><span aria-hidden="true">✣</span> INVENTORY / NETWORK</p>
          <h1>Branch overview</h1>
          <p>Compare stock health, inventory value, and replenishment needs across your locations.</p>
          <div className="branch-overview-live"><span className={loading ? 'is-loading' : error ? 'is-error' : ''} />{loading ? 'Syncing branch inventory…' : error ? 'Branch inventory sync needs attention' : `${summary.branches} locations · ${inventory.length} items tracked`}{lastUpdated && !loading && <small>Updated {lastUpdated.toLocaleTimeString('en-LK', { hour: '2-digit', minute: '2-digit' })}</small>}</div>
        </div>
        <div className="branch-overview-art" aria-hidden="true"><span className="branch-overview-orbit" /><span className="branch-overview-art-icon">⌖</span><i /><i /><i /></div>
        <button type="button" className="btn branch-overview-refresh" onClick={() => void loadInventory(true)} disabled={loading}><span aria-hidden="true">↻</span>{loading ? 'Refreshing…' : 'Refresh data'}</button>
      </header>
      {error && <p className="page-notice" role="alert">{error}</p>}
      <section className="branch-overview-metrics" aria-label="Network inventory summary">
        <article className="branch-overview-metric branch-overview-metric-locations"><span className="branch-overview-metric-icon">⌖</span><span className="branch-overview-metric-label">NETWORK</span><strong>{summary.branches}</strong><small>Locations in view</small></article>
        <article className="branch-overview-metric branch-overview-metric-items"><span className="branch-overview-metric-icon">▦</span><span className="branch-overview-metric-label">STOCK COVERAGE</span><strong>{inventory.length}</strong><small>Items across branches</small></article>
        <article className="branch-overview-metric branch-overview-metric-health"><span className="branch-overview-metric-icon">✓</span><span className="branch-overview-metric-label">HEALTHY LOCATIONS</span><strong>{summary.healthy}</strong><small>Meeting reorder levels</small></article>
        <article className="branch-overview-metric branch-overview-metric-value"><span className="branch-overview-metric-icon">LKR</span><span className="branch-overview-metric-label">INVENTORY VALUE</span><strong>{money(summary.value)}</strong><small>{summary.attention} items need review</small></article>
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
            <div className="branch-card-foot"><span>{branch.attention ? `${branch.attention} items need attention` : 'Stock levels look healthy'}</span><span className="branch-health-pulse" aria-hidden="true" /></div>
          </article>
        ))}
        {!branches.length && !error && !loading && <p className="cell-sub">No branches are recorded yet.</p>}
      </section>
      <section className="panel">
        <div className="panel-head comparison-heading">
          <div><p className="eyebrow">INVENTORY DIRECTORY</p><h2>Stock, organised by category</h2><p>Search and compare item availability, value, and reorder risk across branches.</p></div>
          <span className="comparison-count">{comparisonItems.length} of {inventory.length} items · {categoryGroups.length} categories</span>
        </div>
        <div className="toolbar toolbar-wrap branch-comparison-toolbar">
          <div className="search-field"><span className="search-icon" aria-hidden="true">⌕</span><input type="search" aria-label="Search branch inventory" placeholder="Search item, SKU, category or branch" value={itemQuery} onChange={(event) => setItemQuery(event.target.value)} /></div>
          <select className="filter-select" aria-label="Filter by branch" value={itemBranch} onChange={(event) => setItemBranch(event.target.value)}>{comparisonBranches.map((entry) => <option key={entry}>{entry}</option>)}</select>
          <select className="filter-select" aria-label="Filter by stock health" value={itemHealth} onChange={(event) => setItemHealth(event.target.value as StockHealthFilter)}>
            <option>All stock health</option><option>In stock</option><option>Low stock</option><option>Out of stock</option>
          </select>
          {(itemQuery || itemBranch !== 'All branches' || itemHealth !== 'All stock health') && <button type="button" className="btn btn-ghost inventory-clear-filters" onClick={() => { setItemQuery(''); setItemBranch('All branches'); setItemHealth('All stock health'); }}>Clear filters</button>}
        </div>
        {categoryWarning && <p className="branch-category-warning" role="status">{categoryWarning} Items without a saved category or matching legacy category text are grouped as “Uncategorised”.</p>}
        <div className="branch-directory-pulse" aria-label="Filtered inventory summary">
          <div><span className="branch-directory-pulse-icon">▦</span><span><small>ITEMS IN VIEW</small><strong>{comparisonItems.length}</strong></span></div>
          <div><span className="branch-directory-pulse-icon branch-directory-pulse-units">↕</span><span><small>UNITS ON HAND</small><strong>{comparisonSummary.units.toLocaleString('en-LK')}</strong></span></div>
          <div className={comparisonSummary.atRisk ? 'has-risk' : ''}><span className="branch-directory-pulse-icon branch-directory-pulse-risk">!</span><span><small>NEEDING ATTENTION</small><strong>{comparisonSummary.atRisk}</strong></span></div>
          <div><span className="branch-directory-pulse-icon branch-directory-pulse-value">LKR</span><span><small>FILTERED STOCK VALUE</small><strong>{money(comparisonSummary.value)}</strong></span></div>
        </div>
        {loading && !inventory.length ? <div className="branch-overview-loading"><span className="branch-loading-spinner" />Loading branch stock…</div> : comparisonItems.length ? (
          <div className="category-directory">
            {categoryGroups.map((group) => (
              <section className={`category-stock-card category-${group.tone}`} key={group.label}>
                <header className="category-stock-head">
                  <div className="category-title">
                    <span className="category-icon" aria-hidden="true">{group.icon}</span>
                    <div><h3>{group.label}</h3><p>{group.items.length} items · {group.atRisk} need attention</p></div>
                  </div>
                  <div className="category-stock-total"><small>ON-HAND VALUE</small><strong>{money(group.value)}</strong></div>
                </header>
                <div className="comparison-table-wrap">
                  <table className="data-table">
                    <thead><tr><th>Item</th><th>SKU</th><th>Branch</th><th>On hand</th><th>Reorder</th><th>Unit cost</th><th>Stock value</th><th>Stock health</th></tr></thead>
                    <tbody>{group.items.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.name}</strong><small className="branch-item-category">{categoryNameFor(item, categoryNames)}</small></td><td><code className="branch-item-sku">{item.sku}</code></td><td>{item.branch ?? 'Unassigned'}</td>
                        <td>{item.quantity} {item.unit ?? 'units'}</td><td>{item.reorderLevel} {item.unit ?? 'units'}</td>
                        <td>{item.unitCost != null ? money(Number(item.unitCost)) : '—'}</td>
                        <td>{item.unitCost != null ? money(Number(item.quantity) * Number(item.unitCost)) : '—'}</td>
                        <td><span className={`branch-stock-status ${item.quantity <= 0 ? 'is-out' : item.quantity <= item.reorderLevel ? 'is-low' : 'is-ok'}`}>{item.quantity <= 0 ? 'Out of stock' : item.quantity <= item.reorderLevel ? 'Low stock' : 'In stock'}</span></td>
                      </tr>
                    ))}</tbody>
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
