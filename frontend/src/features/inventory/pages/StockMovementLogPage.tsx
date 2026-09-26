import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';
import { getStoredToken } from '../authToken';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';

type MovementType = 'Receive' | 'Issue' | 'Waste' | 'Adjustment';

type MovementEntry = {
  id: string;
  occurredAt: string;
  item: string;
  sku: string;
  movementType: MovementType;
  quantity: number;
  reasonLabel: string;
  reference?: string;
  notes?: string;
};

const PAGE_SIZE = 8;

const movementTypes = ['All types', 'Receive', 'Issue', 'Waste', 'Adjustment'] as const;
type MovementTypeFilter = (typeof movementTypes)[number];

const typeTone: Record<MovementType, BadgeTone> = {
  Receive: 'green',
  Issue: 'red',
  Waste: 'red',
  Adjustment: 'amber',
};

function normalizeMovementType(value: unknown): MovementType {
  if (value === 'Receive' || value === 'Issue' || value === 'Waste' || value === 'Adjustment') return value;
  return 'Adjustment';
}

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-LK', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function StockMovementLogPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const [movements, setMovements] = useState<MovementEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState('');
  const [type, setType] = useState<MovementTypeFilter>(movementTypes[0]);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(1);

  const loadMovements = useCallback(async (activeCheck?: () => boolean) => {
    setLoading(true);
    setLoadError('');
    try {
      const response = await fetch('/api/inventory/movements?pageSize=100', {
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) throw new Error(`Movement request failed (${response.status})`);
      const data = await response.json();
      if (activeCheck && !activeCheck()) return false;
      setMovements((Array.isArray(data) ? data : []).map((movement: any): MovementEntry => ({
        id: String(movement.id),
        occurredAt: movement.occurredAt,
        item: movement.item ?? 'Unknown item',
        sku: movement.sku ?? 'Unknown SKU',
        movementType: normalizeMovementType(movement.movementType),
        quantity: Number(movement.quantity ?? 0),
        reasonLabel: movement.notes ?? movement.reference ?? movement.movementType ?? 'Stock movement',
        reference: movement.reference ?? undefined,
        notes: movement.notes ?? undefined,
      })));
      return true;
    } catch (error) {
      console.error(error);
      if (!activeCheck || activeCheck()) {
        setMovements([]);
        setLoadError(error instanceof Error ? error.message : 'Unable to load movement history.');
      }
      return false;
    } finally {
      if (!activeCheck || activeCheck()) setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    let active = true;
    void loadMovements(() => active);
    return () => { active = false; };
  }, [loadMovements]);

  const contextFiltered = useMemo(() => {
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
        row.reasonLabel.toLowerCase().includes(queryLower) ||
        row.notes?.toLowerCase().includes(queryLower);
      const matchesFrom = fromMs === null || occurredMs >= fromMs;
      const matchesTo = toMs === null || occurredMs <= toMs;
      return matchesQuery && matchesFrom && matchesTo;
    });
  }, [dateFrom, dateTo, movements, query]);
  const filtered = useMemo(
    () => type === 'All types' ? contextFiltered : contextFiltered.filter((row) => row.movementType === type),
    [contextFiltered, type],
  );
  const movementTypeCounts = useMemo(() => ({
    all: contextFiltered.length,
    received: contextFiltered.filter((row) => row.movementType === 'Receive').length,
    issued: contextFiltered.filter((row) => row.movementType === 'Issue').length,
    wasted: contextFiltered.filter((row) => row.movementType === 'Waste').length,
    adjusted: contextFiltered.filter((row) => row.movementType === 'Adjustment').length,
  }), [contextFiltered]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);

  const paged = useMemo(() => {
    const start = (safePage - 1) * PAGE_SIZE;
    return filtered.slice(start, start + PAGE_SIZE);
  }, [filtered, safePage]);

  useEffect(() => {
    setPage(1);
  }, [query, type, dateFrom, dateTo]);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  const stats = useMemo(() => {
    const received = filtered.filter((row) => row.movementType === 'Receive' && row.quantity > 0).reduce((sum, row) => sum + row.quantity, 0);
    const issued = filtered.filter((row) => (row.movementType === 'Issue' || row.movementType === 'Waste') && row.quantity < 0).reduce((sum, row) => sum + Math.abs(row.quantity), 0);
    const net = filtered.reduce((sum, row) => sum + row.quantity, 0);
    return {
      count: filtered.length,
      received,
      issued,
      net,
      receives: filtered.filter((row) => row.movementType === 'Receive').length,
      issues: filtered.filter((row) => row.movementType === 'Issue').length,
      wastes: filtered.filter((row) => row.movementType === 'Waste').length,
      adjustments: filtered.filter((row) => row.movementType === 'Adjustment').length,
    };
  }, [filtered]);

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);
  const hasActiveFilters = query.trim() !== '' || type !== 'All types' || dateFrom !== '' || dateTo !== '';

  async function handleRefresh() {
    const refreshed = await loadMovements();
    if (refreshed) notify('Stock movement history refreshed.', 'success');
  }

  return (
    <div className="page stock-movement-page">
      <header className="movement-hero">
        <div className="movement-hero-copy">
          <p className="movement-eyebrow"><span aria-hidden="true">↗</span> OPERATIONS / STOCK ACTIVITY</p>
          <h1>Stock movements</h1>
          <p>Follow stock coming in, going out, and adjustments across your inventory.</p>
          <div className="movement-hero-meta"><span className={`movement-live-dot${loading ? ' is-loading' : ''}`} aria-hidden="true" />{loading ? 'Syncing recent activity…' : `${movements.length} latest records loaded`}<span className="movement-meta-separator">·</span>Latest first</div>
        </div>
        <div className="movement-hero-art" aria-hidden="true"><span className="movement-art-ring movement-art-ring-one" /><span className="movement-art-ring movement-art-ring-two" /><span className="movement-art-icon"><Icon name="movement" size={42} /></span><span className="movement-art-point movement-art-point-one" /><span className="movement-art-point movement-art-point-two" /></div>
        <div className="movement-hero-actions"><button className="btn movement-refresh" type="button" onClick={() => void handleRefresh()} disabled={loading}><span aria-hidden="true">↻</span>{loading ? 'Refreshing…' : 'Refresh history'}</button></div>
      </header>
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="panel p-6">Loading live movement history…</div>}

      <section className="stat-strip movement-stat-strip" aria-label="Movement summary">
        <article className="stat metric-card movement-stat movement-stat-activity">
          <div className="movement-stat-main"><span className="movement-stat-icon" aria-hidden="true"><Icon name="movement" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">ACTIVITY</span><strong className="movement-stat-value">{stats.count}</strong><span className="movement-stat-label">Matching movements</span></div><span className="movement-stat-index" aria-hidden="true">01</span></div>
          <div className="movement-stat-detail"><i className="movement-detail-receive" />{stats.receives} in <i className="movement-detail-out" />{stats.issues + stats.wastes} out <i className="movement-detail-adjust" />{stats.adjustments} adjusted</div>
        </article>
        <article className="stat metric-card movement-stat movement-stat-in">
          <div className="movement-stat-main"><span className="movement-stat-icon" aria-hidden="true"><span>↓</span></span><div className="metric-info"><span className="movement-stat-kicker">STOCK IN</span><strong className="movement-stat-value">+{stats.received.toLocaleString()}</strong><span className="movement-stat-label">Units received</span></div><span className="movement-stat-glyph" aria-hidden="true">IN</span></div>
          <div className="movement-stat-detail">Across {stats.receives} receive {stats.receives === 1 ? 'record' : 'records'}</div>
        </article>
        <article className="stat metric-card movement-stat movement-stat-out">
          <div className="movement-stat-main"><span className="movement-stat-icon" aria-hidden="true"><span>↑</span></span><div className="metric-info"><span className="movement-stat-kicker">STOCK OUT</span><strong className="movement-stat-value">{stats.issued > 0 ? `−${stats.issued.toLocaleString()}` : '0'}</strong><span className="movement-stat-label">Units issued / wasted</span></div><span className="movement-stat-glyph" aria-hidden="true">OUT</span></div>
          <div className="movement-stat-detail">Across {stats.issues + stats.wastes} outbound {stats.issues + stats.wastes === 1 ? 'record' : 'records'}</div>
        </article>
        <article className="stat metric-card movement-stat movement-stat-net">
          <div className="movement-stat-main"><span className="movement-stat-icon" aria-hidden="true"><Icon name="chart" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">NET MOVEMENT</span><strong className="movement-stat-value">{stats.net >= 0 ? `+${stats.net}` : stats.net.toLocaleString()}</strong><span className="movement-stat-label">Quantity change</span></div><span className="movement-stat-glyph" aria-hidden="true">Σ</span></div>
          <div className="movement-stat-detail">Includes {stats.adjustments} stock {stats.adjustments === 1 ? 'adjustment' : 'adjustments'}</div>
        </article>
      </section>

      <section className="panel movement-log-panel">
        <div className="movement-panel-head"><div><span className="movement-panel-icon" aria-hidden="true"><Icon name="inventory" size={19} /></span><div><h2>Activity log</h2><p>Filter records by item, movement type, or date.</p></div></div><span className="movement-count-pill">{filtered.length} shown</span></div>
        <div className="toolbar toolbar-wrap movement-toolbar">
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
          <label className="date-filter">
            <span>From</span>
            <input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} aria-label="From date" />
          </label>
          <label className="date-filter">
            <span>To</span>
            <input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} aria-label="To date" />
          </label>
          {hasActiveFilters && <button type="button" className="movement-clear-filters" onClick={() => { setQuery(''); setType('All types'); setDateFrom(''); setDateTo(''); }}>Clear filters</button>}
        </div>

        <div className="movement-type-summary" aria-label="Movement type counts">
          <button type="button" className={`movement-type-chip${type === 'All types' ? ' is-active' : ''}`} aria-pressed={type === 'All types'} onClick={() => setType('All types')}>All <strong>{movementTypeCounts.all}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-receive${type === 'Receive' ? ' is-active' : ''}`} aria-pressed={type === 'Receive'} onClick={() => setType(type === 'Receive' ? 'All types' : 'Receive')}><i /> Received <strong>{movementTypeCounts.received}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-issue${type === 'Issue' ? ' is-active' : ''}`} aria-pressed={type === 'Issue'} onClick={() => setType(type === 'Issue' ? 'All types' : 'Issue')}><i /> Issued <strong>{movementTypeCounts.issued}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-waste${type === 'Waste' ? ' is-active' : ''}`} aria-pressed={type === 'Waste'} onClick={() => setType(type === 'Waste' ? 'All types' : 'Waste')}><i /> Wasted <strong>{movementTypeCounts.wasted}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-adjust${type === 'Adjustment' ? ' is-active' : ''}`} aria-pressed={type === 'Adjustment'} onClick={() => setType(type === 'Adjustment' ? 'All types' : 'Adjustment')}><i /> Adjusted <strong>{movementTypeCounts.adjusted}</strong></button>
        </div>

        <div className="table-wrap">
          <table className="data-table movement-table">
            <thead><tr><th>When</th><th>Item</th><th>Type</th><th>Quantity</th><th>Details</th><th>Reference</th></tr></thead>
            <tbody>
              {paged.map((row) => (
                <tr key={row.id}>
                  <td className="movement-when">{formatDateTime(row.occurredAt)}</td>
                  <td>
                    <p className="cell-title">{row.item}</p>
                    <p className="cell-sub">{row.sku}</p>
                  </td>
                  <td className={`movement-type-cell movement-type-cell-${row.movementType.toLowerCase().replace(/\s+/g, '-')}`}><Badge tone={typeTone[row.movementType]}>{row.movementType}</Badge></td>
                  <td>
                    <span className={`movement-quantity${row.quantity > 0 ? ' is-in' : row.quantity < 0 ? ' is-out' : ''}`}>
                      {row.quantity > 0 ? `+${row.quantity}` : row.quantity}
                    </span>
                  </td>
                  <td>
                    <p className="movement-detail-text">{row.reasonLabel}</p>
                  </td>
                  <td className="movement-reference">{row.reference ?? '—'}</td>
                </tr>
              ))}
              {paged.length === 0 && (
                <tr><td colSpan={6} className="empty-state">{movements.length === 0 ? 'No stock movement records are available yet.' : 'No movements match these filters. Try clearing a filter or changing the date range.'}</td></tr>
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
