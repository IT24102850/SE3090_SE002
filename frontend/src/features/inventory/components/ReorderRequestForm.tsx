import { useEffect, useMemo, useState } from 'react';
import { errorMessage, formatLkr, reorderApi, reorderStatusLabel, type NamedOption, type ReorderWorkflow } from '../reorderApi';

/* Turns StockSense's replenishment recommendations into a reorder request.
 * The user picks the supplier and which lines to order (quantities start at
 * the recommendation and can be changed); the server prices it and runs the
 * safety gate, and this shows what it decided. One branch per order, because
 * a purchase order is delivered to one branch. */

export type RecommendationLine = {
  inventory_item_id: string;
  item_name: string;
  branch_id?: string;
  branch_name?: string;
  recommended_quantity: number;
  estimated_total_cost?: number | null;
};

type Props = { recommendations: RecommendationLine[]; analysisWorkflowId?: string };

export function ReorderRequestForm({ recommendations, analysisWorkflowId }: Props) {
  const branches = useMemo(() => {
    const seen = new Map<string, string>();
    recommendations.forEach((r) => r.branch_id && seen.set(r.branch_id, r.branch_name ?? 'Branch'));
    return [...seen].map(([id, name]) => ({ id, name }));
  }, [recommendations]);

  const [branchId, setBranchId] = useState(branches[0]?.id ?? '');
  const [suppliers, setSuppliers] = useState<NamedOption[]>([]);
  const [supplierId, setSupplierId] = useState('');
  const [quantities, setQuantities] = useState<Record<string, number>>(
    () => Object.fromEntries(recommendations.map((r) => [r.inventory_item_id, Math.ceil(r.recommended_quantity)])),
  );
  const [selected, setSelected] = useState<Record<string, boolean>>(
    () => Object.fromEntries(recommendations.map((r) => [r.inventory_item_id, true])),
  );
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<ReorderWorkflow | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    reorderApi.suppliers().then(setSuppliers).catch(() => setError('Suppliers could not be loaded.'));
  }, []);

  const lines = recommendations.filter((r) => r.branch_id === branchId);
  const chosen = lines.filter((r) => selected[r.inventory_item_id] && (quantities[r.inventory_item_id] ?? 0) > 0);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError('');
    setResult(null);
    if (!supplierId) return setError('Choose a supplier.');
    if (chosen.length === 0) return setError('Select at least one item with a quantity above zero.');
    setSubmitting(true);
    try {
      setResult(await reorderApi.request({
        branchId,
        supplierId,
        analysisWorkflowId,
        lines: chosen.map((r) => ({ inventoryItemId: r.inventory_item_id, quantity: quantities[r.inventory_item_id] })),
      }));
    } catch (e) {
      setError(errorMessage(e, 'The reorder request could not be sent.'));
    } finally {
      setSubmitting(false);
    }
  }

  if (branches.length === 0) return null;

  return (
    <form className="stocksense-reorder-form" onSubmit={submit} aria-label="Request a reorder" noValidate>
      <div className="stocksense-section-heading">
        <div><p className="eyebrow">NEXT STEP</p><h3>Request a reorder</h3></div>
      </div>
      <div className="toolbar toolbar-wrap">
        {branches.length > 1 && (
          <label>Branch{' '}
            <select className="filter-select" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </label>
        )}
        <label>Supplier{' '}
          <select className="filter-select" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} aria-label="Supplier">
            <option value="">Choose a supplier…</option>
            {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </label>
      </div>

      <table className="data-table">
        <thead><tr><th>Order</th><th>Item</th><th>Quantity</th><th>StockSense estimate</th></tr></thead>
        <tbody>
          {lines.map((r) => (
            <tr key={r.inventory_item_id}>
              <td>
                <input
                  type="checkbox"
                  aria-label={`Order ${r.item_name}`}
                  checked={selected[r.inventory_item_id] ?? false}
                  onChange={(e) => setSelected((s) => ({ ...s, [r.inventory_item_id]: e.target.checked }))}
                />
              </td>
              <td>{r.item_name}</td>
              <td>
                <input
                  type="number"
                  min={1}
                  aria-label={`Quantity of ${r.item_name}`}
                  value={quantities[r.inventory_item_id] ?? 0}
                  onChange={(e) => setQuantities((q) => ({ ...q, [r.inventory_item_id]: Number(e.target.value) }))}
                />
              </td>
              <td>{r.estimated_total_cost == null ? 'No unit cost' : formatLkr(r.estimated_total_cost)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <button className="btn btn-primary" type="submit" disabled={submitting}>
        {submitting ? 'Checking against the limits…' : 'Request reorder'}
      </button>
      <p className="cell-sub">Prices come from your inventory records. Orders over the limits wait for a manager&apos;s approval.</p>

      {error && <p className="page-notice" role="alert">{error}</p>}
      {result && (
        <div className="page-notice" role="status">
          <strong>{reorderStatusLabel[result.status]}.</strong> {result.finalOutcome}
          {result.status === 'Rejected' && result.error && <> {result.error}</>}
        </div>
      )}
    </form>
  );
}
