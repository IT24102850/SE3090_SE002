import { useEffect, useMemo, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';
import { getStoredToken } from '../authToken';

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

const users = ['All users', 'Kavindu', 'Nadeesha', 'Dinesh', 'Inventory Admin'] as const;
type UserFilter = (typeof users)[number];

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
  const token = getStoredToken();
  const [movements, setMovements] = useState<MovementEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState('');
  const [type, setType] = useState<MovementTypeFilter>(movementTypes[0]);
  const [reason, setReason] = useState<ReasonFilter>(reasonFilters[0]);
  const [user, setUser] = useState<UserFilter>(users[0]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(1);

  useEffect(() => {
    let active = true;
    async function loadMovements() {
      setLoading(true);
      setLoadError('');
      try {
        const response = await fetch('/api/inventory/movements?pageSize=100', {
          headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
        });
        if (!response.ok) throw new Error(`Movement request failed (${response.status})`);
        const data = await response.json();
        if (!active) return;
        setMovements((data ?? []).map((movement: any): MovementEntry => ({
          id: movement.id,
          occurredAt: movement.occurredAt,
          item: movement.item,
          sku: movement.sku,
          movementType: movement.movementType as MovementType,
          quantity: Number(movement.quantity),
          reasonCode: movement.movementType === 'Receive' ? 'REC-001' : movement.movementType === 'Adjustment' ? 'ADJ-001' : 'ISS-001',
          reasonLabel: movement.notes ?? movement.reference ?? movement.movementType,
          reference: movement.reference ?? undefined,
          performedBy: 'Inventory operator',
          notes: movement.notes ?? undefined,
        })));
      } catch (error) {
        console.error(error);
        if (active) {
          setMovements([]);
          setLoadError('Unable to load movement history from the database. Refresh and try again.');
        }
      } finally {
        if (active) setLoading(false);
      }
    }
    void loadMovements();
    return () => { active = false; };
  }, [token]);

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
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="panel p-6">Loading live movement history…</div>}

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
