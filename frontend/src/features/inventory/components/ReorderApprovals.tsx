import { useCallback, useEffect, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';
import {
  errorMessage,
  formatLkr,
  reorderApi,
  reorderStatusLabel,
  type ReorderStatus,
  type ReorderWorkflow,
} from '../reorderApi';

/* StockSense reorders with the evidence a manager decides on: every line at
 * the database price, the totals, and each check the safety gate ran - the
 * ones that failed are why it paused. Managers and Admins can approve (which
 * places the purchase order), reject, or send it back for revision with a
 * reason; the requester is notified either way. Everyone else sees status. */

const tone: Record<ReorderStatus, BadgeTone> = {
  AwaitingApproval: 'amber',
  Completed: 'green',
  Rejected: 'red',
  RevisionRequested: 'violet',
};

type Props = { canDecide: boolean; refreshMs?: number };

export function ReorderApprovals({ canDecide, refreshMs = 15_000 }: Props) {
  const [reorders, setReorders] = useState<ReorderWorkflow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState('');

  const load = useCallback(async () => {
    try {
      setReorders(await reorderApi.list());
      setError('');
    } catch (e) {
      setError(errorMessage(e, 'StockSense reorders could not be loaded.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(), refreshMs);
    return () => window.clearInterval(timer);
  }, [load, refreshMs]);

  async function decide(reorder: ReorderWorkflow, action: 'approve' | 'reject' | 'revise') {
    const reason = (reasons[reorder.id] ?? '').trim();
    if (action !== 'approve' && reason.length < 3) {
      setMessage('Give a reason of at least 3 characters - the requester will see it.');
      return;
    }
    setBusyId(reorder.id);
    setMessage('');
    try {
      const updated = action === 'approve'
        ? await reorderApi.approve(reorder.id)
        : action === 'reject'
          ? await reorderApi.reject(reorder.id, reason)
          : await reorderApi.revise(reorder.id, reason);
      setReorders((current) => current.map((r) => (r.id === updated.id ? updated : r)));
      setMessage(updated.purchaseOrderNumber
        ? `Approved - purchase order ${updated.purchaseOrderNumber} placed.`
        : updated.finalOutcome ?? 'Decision recorded.');
    } catch (e) {
      setMessage(errorMessage(e, 'The decision could not be recorded.'));
    } finally {
      setBusyId(null);
    }
  }

  const pending = reorders.filter((r) => r.status === 'AwaitingApproval').length;

  return (
    <section className="panel stocksense-reorders" aria-labelledby="stocksense-reorders-title">
      <div className="panel-head">
        <div>
          <p className="eyebrow">STOCKSENSE REORDERS</p>
          <h2 id="stocksense-reorders-title">Reorder requests</h2>
          <p className="hint">
            Orders within the limits are placed automatically. Anything over the value or unit limit, from a new supplier or
            without a unit cost waits here for a manager.
          </p>
        </div>
        <Badge tone={pending ? 'amber' : 'slate'}>{pending} awaiting approval</Badge>
      </div>

      {message && <p className="page-notice" role="status">{message}</p>}
      {error && <p className="page-notice" role="alert">{error}</p>}
      {loading && <p className="empty-state">Loading reorder requests…</p>}
      {!loading && !error && reorders.length === 0 && (
        <p className="empty-state">No reorder requests yet. Run StockSense and request a reorder from its recommendations.</p>
      )}

      <div className="stocksense-reorder-list">
        {reorders.map((reorder) => (
          <article key={reorder.id} className="stocksense-reorder-card" aria-label={`Reorder from ${reorder.supplierName}`}>
            <header className="stocksense-reorder-head">
              <div>
                <h3>{reorder.supplierName}</h3>
                <p className="cell-sub">
                  {reorder.lines.length} item(s) · {reorder.totalUnits} units · {formatLkr(reorder.totalValue)} ·{' '}
                  {new Date(reorder.createdAt).toLocaleString('en-LK')}
                </p>
              </div>
              <Badge tone={tone[reorder.status]}>{reorderStatusLabel[reorder.status]}</Badge>
            </header>

            <table className="data-table">
              <thead><tr><th>Item</th><th>Quantity</th><th>Unit cost</th><th>Line total</th></tr></thead>
              <tbody>
                {reorder.lines.map((line) => (
                  <tr key={line.inventoryItemId}>
                    <td>{line.name}</td>
                    <td>{line.quantity}</td>
                    <td>{line.unitCost == null ? 'Not set' : formatLkr(line.unitCost)}</td>
                    <td>{line.unitCost == null ? '—' : formatLkr(line.unitCost * line.quantity)}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            <ul className="stocksense-gate-checks" aria-label="Safety gate checks">
              {reorder.checks.map((check) => (
                <li key={check.rule} className={check.passed ? 'is-pass' : 'is-fail'}>
                  <span aria-hidden="true">{check.passed ? '✓' : '!'}</span> {check.detail}
                </li>
              ))}
            </ul>

            {reorder.finalOutcome && <p className="cell-sub">{reorder.finalOutcome}</p>}
            {reorder.purchaseOrderNumber && <p><strong>Purchase order {reorder.purchaseOrderNumber}</strong></p>}

            {canDecide && reorder.status === 'AwaitingApproval' && (
              <div className="stocksense-reorder-actions">
                <label className="sr-only" htmlFor={`reason-${reorder.id}`}>Reason for rejecting or revising</label>
                <input
                  id={`reason-${reorder.id}`}
                  type="text"
                  placeholder="Reason (needed to reject or ask for a revision)"
                  value={reasons[reorder.id] ?? ''}
                  onChange={(e) => setReasons((r) => ({ ...r, [reorder.id]: e.target.value }))}
                  maxLength={500}
                />
                <button className="btn btn-primary" type="button" disabled={busyId === reorder.id} onClick={() => void decide(reorder, 'approve')}>
                  Approve and order
                </button>
                <button className="btn btn-secondary" type="button" disabled={busyId === reorder.id} onClick={() => void decide(reorder, 'revise')}>
                  Request revision
                </button>
                <button className="btn btn-danger" type="button" disabled={busyId === reorder.id} onClick={() => void decide(reorder, 'reject')}>
                  Reject
                </button>
              </div>
            )}
          </article>
        ))}
      </div>
    </section>
  );
}
