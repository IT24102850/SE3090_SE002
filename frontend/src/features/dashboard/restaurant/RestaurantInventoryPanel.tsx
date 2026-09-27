import { useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useLogInventoryWasteMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime } from '../../../shared/dateUtils';
import type { RestaurantInventory } from '../../booking/types';
import { formatMoney } from './restaurantReport';

/* Stock levels and the waste log.
 *
 * Left: every active ingredient against its reorder level, worst first,
 * with out-of-stock and low-stock flagged by word and colour. Right: the
 * waste log for the range and the form that adds to it. Waste is its own
 * movement type so it never blends into ordinary adjustments; the cost
 * on each entry is the item's unit cost at the time it was logged.
 *
 * "Consumed" is the recipe auto-decrement: a menu type with a recipe in
 * its config takes its ingredients off stock when an order starts prep. */

const REASONS = ['Spoiled', 'Over-prepped', 'Expired', 'Dropped / spilled', 'Returned by guest', 'Cooking error', 'Other'];

export default function RestaurantInventoryPanel({ data, loading, finance, canLog }: { data?: RestaurantInventory; loading: boolean; finance: boolean; canLog: boolean }) {
  const [filter, setFilter] = useState<'attention' | 'all'>('attention');
  const [logWaste, { isLoading: saving }] = useLogInventoryWasteMutation();
  const toast = useToast();
  const [itemId, setItemId] = useState('');
  const [qty, setQty] = useState('');
  const [reason, setReason] = useState(REASONS[0]);
  const [notes, setNotes] = useState('');

  const items = data?.items ?? [];
  const rows = useMemo(() => (filter === 'attention' ? items.filter((i) => i.status !== 'ok') : items), [items, filter]);
  const currency = data?.currency ?? 'LKR';
  const summary = data?.summary;

  async function submit(e: FormEvent) {
    e.preventDefault();
    const quantity = Number(qty);
    if (!itemId || !Number.isFinite(quantity) || quantity <= 0) {
      toast.show('Pick an item and a quantity above zero.', 'error');
      return;
    }
    try {
      await logWaste({ id: itemId, quantity, reason, notes: notes.trim() || undefined }).unwrap();
      toast.show('Waste logged and taken off stock.', 'success');
      setQty('');
      setNotes('');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not log the waste.'), 'error');
    }
  }

  return (
    <div>
      <div className="rest-stages">
        <Tile label="Low stock" value={summary ? summary.lowStock : undefined} sub={summary ? `${summary.outOfStock} out of stock · ${summary.items} items tracked` : ''} loading={loading} alert={(summary?.outOfStock ?? 0) > 0} />
        <Tile label="Waste in range" value={summary ? `${summary.wasteUnits.toLocaleString()} units` : undefined} sub={summary ? (finance ? `${formatMoney(summary.wasteCost, currency)} · ${summary.wasteEntries} entries` : `${summary.wasteEntries} entries`) : ''} loading={loading} />
        <Tile label="Auto-consumed" value={summary ? `${summary.consumptionUnits.toLocaleString()} units` : undefined} sub={summary ? `${summary.ordersConsumed} order${summary.ordersConsumed === 1 ? '' : 's'} with a recipe` : ''} loading={loading} />
        {finance && <Tile label="Stock value" value={summary ? formatMoney(summary.stockValue, currency) : undefined} sub="on hand at unit cost" loading={loading} />}
      </div>

      <div className="rest-inventory">
        <div>
          <div className="rest-subhead">
            <span>Stock levels</span>
            <div className="rest-queue-filter" role="tablist" aria-label="Stock view">
              <button type="button" role="tab" aria-selected={filter === 'attention'} className={filter === 'attention' ? 'active' : ''} onClick={() => setFilter('attention')}>Needs attention</button>
              <button type="button" role="tab" aria-selected={filter === 'all'} className={filter === 'all' ? 'active' : ''} onClick={() => setFilter('all')}>All</button>
            </div>
          </div>
          {loading && !data ? (
            <div className="loading-row"><span className="spinner spinner-dark" /> Loading stock…</div>
          ) : items.length === 0 ? (
            <div className="rest-empty">No stock items yet. Add ingredients under <Link to="/inventory">Inventory</Link>.</div>
          ) : rows.length === 0 ? (
            <div className="rest-empty">Everything is above its reorder level.</div>
          ) : (
            <div className="rest-stock-list">
              {rows.map((i) => (
                <div key={i.id} className={`rest-stock rest-stock-${i.status}`}>
                  <div className="rest-stock-main">
                    <strong>{i.name}</strong>
                    <span>{[i.sku, i.category].filter(Boolean).join(' · ')}{i.consumedInRange > 0 && ` · ${i.consumedInRange.toLocaleString()} auto-consumed`}{i.wastedInRange > 0 && ` · ${i.wastedInRange.toLocaleString()} wasted`}</span>
                  </div>
                  <div className="rest-stock-level">
                    <b>{i.quantity.toLocaleString()}</b><small>{i.unit ?? 'units'} · reorder at {i.reorderLevel.toLocaleString()}</small>
                  </div>
                  <span className={`badge badge-${i.status === 'out' ? 'critical' : i.status === 'low' ? 'warning' : 'good'}`}><span className="badge-dot" />{i.status === 'out' ? 'Out of stock' : i.status === 'low' ? 'Low' : 'OK'}</span>
                  <span className="rest-stock-track" aria-hidden="true"><span className="rest-stock-fill" style={{ width: `${Math.min(100, (i.levelPercent ?? 100) / 2)}%` }} /></span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div>
          <div className="rest-subhead"><span>Waste log</span><span style={{ textTransform: 'none', letterSpacing: 0 }}>{data?.from.slice(0, 10)} – {data?.to.slice(0, 10)}</span></div>
          {canLog && (
            <form className="rest-waste-form" onSubmit={submit}>
              <select className="input" value={itemId} onChange={(e) => setItemId(e.target.value)} aria-label="Item" required>
                <option value="">Item…</option>
                {items.map((i) => <option key={i.id} value={i.id}>{i.name} ({i.quantity.toLocaleString()} on hand)</option>)}
              </select>
              <input className="input" type="number" min="0.01" step="0.01" placeholder="Qty" value={qty} onChange={(e) => setQty(e.target.value)} aria-label="Quantity" required />
              <select className="input" value={reason} onChange={(e) => setReason(e.target.value)} aria-label="Reason">
                {REASONS.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
              <input className="input" placeholder="Note (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} aria-label="Note" />
              <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Logging…' : 'Log waste'}</button>
            </form>
          )}
          {loading && !data ? (
            <div className="loading-row"><span className="spinner spinner-dark" /></div>
          ) : !data || data.waste.log.length === 0 ? (
            <div className="rest-empty">No waste logged in this range.</div>
          ) : (
            <div className="rest-waste-list">
              {data.waste.log.map((w) => (
                <div key={w.id} className="rest-waste">
                  <div className="rest-waste-main">
                    <strong>{w.item}</strong>
                    <span>{w.reason}{detailOf(w.reason, w.notes)} · {formatDateTime(w.occurredAt)}</span>
                  </div>
                  <div className="rest-waste-side">
                    <b>{w.units.toLocaleString()}</b>
                    {finance && <small>{formatMoney(w.cost, currency)}</small>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** Waste notes are stored as "Reason: detail"; show only the detail. */
function detailOf(reason: string, notes?: string | null): string {
  if (!notes) return '';
  const idx = notes.indexOf(':');
  const detail = (idx >= 0 ? notes.slice(idx + 1) : notes === reason ? '' : notes).trim();
  return detail ? ` · ${detail}` : '';
}

function Tile({ label, value, sub, loading, alert }: { label: string; value: string | number | undefined; sub: string; loading: boolean; alert?: boolean }) {
  return (
    <div className={`rest-stage${alert ? ' rest-stage-alert' : ''}`}>
      <div className="rest-stage-label">{label}</div>
      <div className="rest-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="rest-stage-sub">{sub}</div>
    </div>
  );
}
