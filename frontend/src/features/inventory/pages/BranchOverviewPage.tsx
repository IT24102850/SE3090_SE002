import { useEffect, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { useGetBranchesQuery } from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { Badge, type BadgeTone } from '../ui/Badge';
import { getStoredToken } from '../authToken';

type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  category?: string;
  unit?: string;
  branch?: string;
  branchId?: string;
  quantity: number;
  reorderLevel: number;
  unitCost?: number;
};
type BranchSummary = { id: string; name: string; items: number; value: number; health: 'Healthy' | 'Needs attention' | 'Critical' };

const healthTone: Record<BranchSummary['health'], BadgeTone> = { Healthy: 'green', 'Needs attention': 'amber', Critical: 'red' };

function healthFor(items: InventoryItem[]): BranchSummary['health'] {
  if (items.some((item) => item.quantity <= 0)) return 'Critical';
  if (items.some((item) => item.quantity < item.reorderLevel)) return 'Needs attention';
  return 'Healthy';
}

function money(value: number) {
  return `LKR ${value.toLocaleString('en-LK')}`;
}

function categoryPresentation(category?: string, itemName?: string) {
  const label = category?.trim();
  const normalized = `${label ?? ''} ${itemName ?? ''}`.toLowerCase();
  if (normalized.includes('tech') || normalized.includes('information technology') || normalized.includes('laptop') || normalized.includes('usb') || normalized.includes('computer')) return { label: label || 'Technology', icon: '◈', tone: 'tech' };
  if (normalized.includes('office') || normalized.includes('station') || normalized.includes('furn') || normalized.includes('paper') || normalized.includes('cabinet') || normalized.includes('marker')) return { label: label || 'Office essentials', icon: '▤', tone: 'office' };
  if (normalized.includes('food') || normalized.includes('bever') || normalized.includes('provision') || normalized.includes('water') || normalized.includes('rice')) return { label: label || 'Provisions', icon: '◌', tone: 'provisions' };
  if (normalized.includes('print') || normalized.includes('market') || normalized.includes('card') || normalized.includes('toner')) return { label: label || 'Print & marketing', icon: '✦', tone: 'creative' };
  if (label) return { label, icon: '◆', tone: 'other' };
  return { label: 'Other items', icon: '◆', tone: 'other' };
}

export function BranchOverviewPage() {
  const token = getStoredToken();
  const tenantId = useSelector((state: RootState) => state.auth.user?.tenantId ?? '');
  const { data: databaseBranches = [] } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    async function load() {
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
        if (!cancelled) {
          setInventory(rows);
          setError('');
        }
      } catch {
        if (!cancelled) {
          setInventory([]);
          setError('Unable to load branch inventory from the database.');
        }
      }
    }
    void load();
    return () => { cancelled = true; };
  }, [token]);

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
        health: healthFor(unassigned),
      });
    }
    return summaries;
  }, [databaseBranches, inventory]);

  const categoryGroups = useMemo(() => {
    const grouped = new Map<string, InventoryItem[]>();
    inventory.forEach((item) => {
      const label = categoryPresentation(item.category, item.name).label;
      grouped.set(label, [...(grouped.get(label) ?? []), item]);
    });
    return [...grouped.entries()]
      .map(([label, items]) => ({ ...categoryPresentation(label), items, value: items.reduce((sum, item) => sum + Number(item.quantity ?? 0) * Number(item.unitCost ?? 0), 0) }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [inventory]);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / NETWORK</p>
          <h1>Multi-branch overview</h1>
          <p className="page-sub">See stock levels, item values, and replenishment needs across every branch.</p>
        </div>
      </header>
      {error && <p className="page-notice">{error}</p>}
      <section className="branch-summary-grid" aria-label="Branch stock summary">
        {branches.map((branch) => (
          <article className="branch-card" key={branch.id}>
            <div className="branch-card-head">
              <div><h2>{branch.name}</h2><p>{branch.items} items tracked</p></div>
              <Badge tone={healthTone[branch.health]}>{branch.health}</Badge>
            </div>
            <strong>{money(branch.value)}</strong>
            <span>Inventory value</span>
          </article>
        ))}
        {!branches.length && !error && <p className="cell-sub">No branches are recorded yet.</p>}
      </section>
      <section className="panel">
        <div className="panel-head comparison-heading">
          <div><p className="eyebrow">INVENTORY DIRECTORY</p><h2>Live stock comparison</h2><p>Browse every database item by its operational category and branch.</p></div>
          <span className="comparison-count">{inventory.length} items · {categoryGroups.length} categories</span>
        </div>
        {inventory.length ? (
          <div className="category-directory">
            {categoryGroups.map((group) => (
              <section className={`category-stock-card category-${group.tone}`} key={group.label}>
                <header className="category-stock-head">
                  <div className="category-title">
                    <span className="category-icon" aria-hidden="true">{group.icon}</span>
                    <div><h3>{group.label}</h3><p>{group.items.length} items across your branches</p></div>
                  </div>
                  <strong>{money(group.value)}</strong>
                </header>
                <div className="comparison-table-wrap">
                  <table className="data-table">
                    <thead><tr><th>Item</th><th>SKU</th><th>Branch</th><th>On hand</th><th>Reorder</th><th>Unit cost</th><th>Stock value</th></tr></thead>
                    <tbody>{group.items.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.name}</strong></td><td>{item.sku}</td><td>{item.branch ?? 'Unassigned'}</td>
                        <td>{item.quantity} {item.unit ?? 'units'}</td><td>{item.reorderLevel} {item.unit ?? 'units'}</td>
                        <td>{item.unitCost != null ? money(Number(item.unitCost)) : '—'}</td>
                        <td>{item.unitCost != null ? money(Number(item.quantity) * Number(item.unitCost)) : '—'}</td>
                      </tr>
                    ))}</tbody>
                  </table>
                </div>
              </section>
            ))}
          </div>
        ) : <p className="empty-state">No inventory items are recorded yet.</p>}
      </section>
    </div>
  );
}
