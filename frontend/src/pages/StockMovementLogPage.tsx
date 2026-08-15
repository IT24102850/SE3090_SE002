import { useEffect, useMemo, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';

type MovementType = 'Receive' | 'Issue' | 'Adjustment';

type MovementEntry = {
  id: string;
  occurredAt: string;
  item: string;
  sku: string;
  movementType: MovementType;
  quantity: number;
  reasonCode: string;
  reasonLabel: string;
  reference?: string;
  performedBy: string;
  notes?: string;
  purchaseOrder?: string;
};

const PAGE_SIZE = 8;

const reasonCodes = [
  { code: 'REC-001', label: 'Supplier delivery', type: 'Receive' as const },
  { code: 'REC-002', label: 'Transfer in', type: 'Receive' as const },
  { code: 'REC-003', label: 'PO receipt', type: 'Receive' as const },
  { code: 'ISS-001', label: 'Production use', type: 'Issue' as const },
  { code: 'ISS-002', label: 'Waste / spoilage', type: 'Issue' as const },
  { code: 'ISS-003', label: 'Transfer out', type: 'Issue' as const },
  { code: 'ADJ-001', label: 'Cycle count correction', type: 'Adjustment' as const },
  { code: 'ADJ-002', label: 'Damage write-off', type: 'Adjustment' as const },
  { code: 'ADJ-003', label: 'Opening balance', type: 'Adjustment' as const },
];

const movementTypes = ['All types', 'Receive', 'Issue', 'Adjustment'] as const;
type MovementTypeFilter = (typeof movementTypes)[number];

const reasonFilters = ['All reason codes', ...reasonCodes.map((reason) => reason.code)] as const;
type ReasonFilter = (typeof reasonFilters)[number];

const users = ['All users', 'Kavindu', 'Nadeesha', 'Dinesh', 'Hasaranga'] as const;
type UserFilter = (typeof users)[number];

const initialMovements: MovementEntry[] = [
  { id: 'mov-001', occurredAt: '2026-08-15T09:12:00Z', item: 'Colombia Supremo Beans 1kg', sku: 'SKU-00128', movementType: 'Issue', quantity: -12, reasonCode: 'ISS-001', reasonLabel: 'Production use', reference: 'BATCH-0815-A', performedBy: 'Kavindu', notes: 'Morning espresso roast' },
  { id: 'mov-002', occurredAt: '2026-08-15T08:40:00Z', item: 'Whole Milk 1L', sku: 'SKU-00741', movementType: 'Receive', quantity: 48, reasonCode: 'REC-001', reasonLabel: 'Supplier delivery', reference: 'GRN-4421', performedBy: 'Nadeesha', purchaseOrder: 'PO-2144' },
  { id: 'mov-003', occurredAt: '2026-08-14T16:55:00Z', item: 'Vanilla Syrup 750ml', sku: 'SKU-00324', movementType: 'Adjustment', quantity: -2, reasonCode: 'ADJ-002', reasonLabel: 'Damage write-off', reference: 'ADJ-881', performedBy: 'Kavindu', notes: 'Leaking bottle removed' },
  { id: 'mov-004', occurredAt: '2026-08-14T14:20:00Z', item: 'Craft Paper Cups 12oz (x50)', sku: 'SKU-00612', movementType: 'Issue', quantity: -6, reasonCode: 'ISS-001', reasonLabel: 'Production use', reference: 'SHIFT-PM', performedBy: 'Dinesh' },
  { id: 'mov-005', occurredAt: '2026-08-14T11:05:00Z', item: 'Premium Coffee Beans', sku: 'SKU-00132', movementType: 'Receive', quantity: 40, reasonCode: 'REC-003', reasonLabel: 'PO receipt', reference: 'GRN-4418', performedBy: 'Kavindu', purchaseOrder: 'PO-2147', notes: 'Partial delivery — balance expected Aug 16' },
  { id: 'mov-006', occurredAt: '2026-08-13T17:30:00Z', item: 'Packaging Boxes — Medium', sku: 'SKU-00598', movementType: 'Issue', quantity: -24, reasonCode: 'ISS-003', reasonLabel: 'Transfer out', reference: 'TRF-COL-03', performedBy: 'Nadeesha', notes: 'Sent to Colombo outlet' },
  { id: 'mov-007', occurredAt: '2026-08-13T10:15:00Z', item: 'Brown Sugar 500g', sku: 'SKU-00902', movementType: 'Adjustment', quantity: 3, reasonCode: 'ADJ-001', reasonLabel: 'Cycle count correction', reference: 'CC-0813', performedBy: 'Hasaranga' },
  { id: 'mov-008', occurredAt: '2026-08-12T15:48:00Z', item: 'Butter Croissants (x12)', sku: 'SKU-00451', movementType: 'Issue', quantity: -8, reasonCode: 'ISS-002', reasonLabel: 'Waste / spoilage', reference: 'WST-120', performedBy: 'Dinesh', notes: 'End-of-day unsold stock' },
  { id: 'mov-009', occurredAt: '2026-08-12T09:22:00Z', item: 'Napkins — Kraft (x200)', sku: 'SKU-01033', movementType: 'Receive', quantity: 20, reasonCode: 'REC-002', reasonLabel: 'Transfer in', reference: 'TRF-KDY-01', performedBy: 'Nadeesha' },
  { id: 'mov-010', occurredAt: '2026-08-11T13:00:00Z', item: 'Whole Milk 1L (Small)', sku: 'SKU-00811', movementType: 'Issue', quantity: -15, reasonCode: 'ISS-001', reasonLabel: 'Production use', performedBy: 'Nadeesha' },
  { id: 'mov-011', occurredAt: '2026-08-11T08:05:00Z', item: 'Colombia Supremo Beans 1kg', sku: 'SKU-00128', movementType: 'Receive', quantity: 60, reasonCode: 'REC-003', reasonLabel: 'PO receipt', reference: 'GRN-4402', performedBy: 'Kavindu', purchaseOrder: 'PO-2147' },
  { id: 'mov-012', occurredAt: '2026-08-10T18:40:00Z', item: 'Premium Coffee Beans', sku: 'SKU-00132', movementType: 'Adjustment', quantity: -1, reasonCode: 'ADJ-001', reasonLabel: 'Cycle count correction', reference: 'CC-0810', performedBy: 'Hasaranga', notes: 'Scale variance on shelf count' },
  { id: 'mov-013', occurredAt: '2026-08-10T11:18:00Z', item: 'Craft Paper Cups 12oz (x50)', sku: 'SKU-00612', movementType: 'Receive', quantity: 30, reasonCode: 'REC-001', reasonLabel: 'Supplier delivery', reference: 'GRN-4395', performedBy: 'Nadeesha', purchaseOrder: 'PO-2146' },
  { id: 'mov-014', occurredAt: '2026-08-09T16:02:00Z', item: 'Vanilla Syrup 750ml', sku: 'SKU-00324', movementType: 'Issue', quantity: -4, reasonCode: 'ISS-001', reasonLabel: 'Production use', performedBy: 'Kavindu' },
  { id: 'mov-015', occurredAt: '2026-08-09T09:50:00Z', item: 'Packaging Boxes — Medium', sku: 'SKU-00598', movementType: 'Receive', quantity: 50, reasonCode: 'REC-003', reasonLabel: 'PO receipt', reference: 'GRN-4388', performedBy: 'Nadeesha', purchaseOrder: 'PO-2146' },
];

const typeTone: Record<MovementType, BadgeTone> = {
  Receive: 'green',
  Issue: 'red',
  Adjustment: 'amber',
};

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-LK', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function UserChip({ name }: { name: string }) {
  return (
    <span className="user-chip">
      <span className="user-chip-avatar" aria-hidden="true">{name.charAt(0)}</span>
      {name}
    </span>
  );
}

export function StockMovementLogPage() {
  const [movements] = useState(initialMovements);
  const [query, setQuery] = useState('');
  const [type, setType] = useState<MovementTypeFilter>(movementTypes[0]);
  const [reason, setReason] = useState<ReasonFilter>(reasonFilters[0]);
  const [user, setUser] = useState<UserFilter>(users[0]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(1);

  const filtered = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    const fromMs = dateFrom ? new Date(`${dateFrom}T00:00:00`).getTime() : null;
    const toMs = dateTo ? new Date(`${dateTo}T23:59:59`).getTime() : null;

    return movements.filter((row) => {
      const occurredMs = new Date(row.occurredAt).getTime();
      const matchesQuery =
        queryLower === '' ||
        row.item.toLowerCase().includes(queryLower) ||
        row.sku.toLowerCase().includes(queryLower) ||
        row.reference?.toLowerCase().includes(queryLower) ||
        row.purchaseOrder?.toLowerCase().includes(queryLower) ||
        row.reasonCode.toLowerCase().includes(queryLower);
      const matchesType = type === 'All types' || row.movementType === type;
      const matchesReason = reason === 'All reason codes' || row.reasonCode === reason;
      const matchesUser = user === 'All users' || row.performedBy === user;
      const matchesFrom = fromMs === null || occurredMs >= fromMs;
      const matchesTo = toMs === null || occurredMs <= toMs;
      return matchesQuery && matchesType && matchesReason && matchesUser && matchesFrom && matchesTo;
    });
  }, [dateFrom, dateTo, movements, query, reason, type, user]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);

  const paged = useMemo(() => {
    const start = (safePage - 1) * PAGE_SIZE;
    return filtered.slice(start, start + PAGE_SIZE);
  }, [filtered, safePage]);

  useEffect(() => {
    setPage(1);
  }, [query, type, reason, user, dateFrom, dateTo]);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  const stats = useMemo(() => {
    const received = filtered.filter((row) => row.quantity > 0).reduce((sum, row) => sum + row.quantity, 0);
    const issued = filtered.filter((row) => row.quantity < 0).reduce((sum, row) => sum + Math.abs(row.quantity), 0);
    return { count: filtered.length, received, issued, net: received - issued };
  }, [filtered]);

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / STOCK</p>
          <h1>Stock movement log</h1>
          <p className="page-sub">Filterable history of receives, issues, and adjustments with reason codes and user attribution.</p>
        </div>
      </header>

      <section className="stat-strip" aria-label="Movement summary">
        <div className="stat"><span className="stat-value">{stats.count}</span><span className="stat-label">Movements</span></div>
        <div className="stat"><span className="stat-value stat-value-in">+{stats.received}</span><span className="stat-label">Units in</span></div>
        <div className="stat"><span className="stat-value stat-value-out">−{stats.issued}</span><span className="stat-label">Units out</span></div>
        <div className="stat"><span className="stat-value">{stats.net >= 0 ? `+${stats.net}` : stats.net}</span><span className="stat-label">Net change</span></div>
      </section>

      <section className="panel">
        <div className="toolbar toolbar-wrap">
          <div className="search-field">
            <span className="search-icon" aria-hidden="true">⌕</span>
            <input
              type="search"
              placeholder="Search items, SKUs, references, POs…"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              aria-label="Search movements"
            />
          </div>
          <select className="filter-select" value={type} onChange={(event) => setType(event.target.value as MovementTypeFilter)} aria-label="Filter by movement type">
            {movementTypes.map((option) => <option key={option}>{option}</option>)}
          </select>
          <select className="filter-select" value={reason} onChange={(event) => setReason(event.target.value as ReasonFilter)} aria-label="Filter by reason code">
            {reasonFilters.map((option) => <option key={option}>{option}</option>)}
          </select>
          <select className="filter-select" value={user} onChange={(event) => setUser(event.target.value as UserFilter)} aria-label="Filter by user">
            {users.map((option) => <option key={option}>{option}</option>)}
          </select>
          <label className="date-filter">
            <span>From</span>
            <input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} aria-label="From date" />
          </label>
          <label className="date-filter">
            <span>To</span>
            <input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} aria-label="To date" />
          </label>
        </div>

        <div className="reason-legend" aria-label="Reason code legend">
          {reasonCodes.map((entry) => (
            <span key={entry.code} className="reason-legend-item">
              <code>{entry.code}</code> {entry.label}
            </span>
          ))}
        </div>

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>When</th>
                <th>Item</th>
                <th>Type</th>
                <th>Qty</th>
                <th>Reason</th>
                <th>Reference</th>
                <th>Performed by</th>
              </tr>
            </thead>
            <tbody>
              {paged.map((row) => (
                <tr key={row.id}>
                  <td className="cell-sub">{formatDateTime(row.occurredAt)}</td>
                  <td>
                    <p className="cell-title">{row.item}</p>
                    <p className="cell-sub">{row.sku}{row.purchaseOrder ? ` · ${row.purchaseOrder}` : ''}</p>
                  </td>
                  <td><Badge tone={typeTone[row.movementType]}>{row.movementType}</Badge></td>
                  <td>
                    <span className={row.quantity > 0 ? 'qty qty-in' : row.quantity < 0 ? 'qty qty-out' : 'qty'}>
                      {row.quantity > 0 ? `+${row.quantity}` : row.quantity}
                    </span>
                  </td>
                  <td>
                    <span className="reason-code">{row.reasonCode}</span>
                    <p className="cell-sub">{row.reasonLabel}</p>
                  </td>
                  <td className="cell-sub">{row.reference ?? '—'}{row.notes ? <p className="cell-note">{row.notes}</p> : null}</td>
                  <td><UserChip name={row.performedBy} /></td>
                </tr>
              ))}
              {paged.length === 0 && (
                <tr><td colSpan={7} className="empty-state">No movements match your filters.</td></tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="table-footer">
          <p className="table-caption">
            {filtered.length === 0
              ? `No movements · ${movements.length} total recorded`
              : `Showing ${rangeStart}–${rangeEnd} of ${filtered.length} movements · ${movements.length} total recorded`}
          </p>
          {filtered.length > PAGE_SIZE && (
            <nav className="pagination" aria-label="Movement log pagination">
              <button type="button" className="pagination-btn" disabled={safePage <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
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
              <button type="button" className="pagination-btn" disabled={safePage >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</button>
            </nav>
          )}
        </div>
      </section>
    </div>
  );
}
