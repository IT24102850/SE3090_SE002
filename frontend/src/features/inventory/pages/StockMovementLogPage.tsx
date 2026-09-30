import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';
import { getStoredToken } from '../authToken';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';

type MovementType = string;

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
  performedBy?: string;
  supplierName?: string;
  isPhysicalCount?: boolean;
  countStatus?: string;
};

const PAGE_SIZE = 8;

const baseMovementTypes = ['Receive', 'Sale', 'Issue', 'Consumption', 'Waste', 'Adjustment'] as const;
type MovementTypeFilter = 'All types' | 'Outbound' | MovementType;

const typeTone: Record<MovementType, BadgeTone> = {
  Receive: 'green',
  Sale: 'red',
  Issue: 'red',
  Consumption: 'red',
  Waste: 'red',
  Adjustment: 'amber',
  'Physical count': 'violet',
};

function normalizeMovementType(value: unknown): MovementType {
  if (typeof value !== 'string' || value.trim() === '') return 'Unknown';
  const normalized = value.trim().toLowerCase();
  if (normalized === 'purchasereceived' || normalized === 'receive' || normalized === 'in') return 'Receive';
  if (normalized === 'sale') return 'Sale';
  if (normalized === 'issue' || normalized === 'out') return 'Issue';
  if (normalized === 'consumption') return 'Consumption';
  if (normalized === 'waste') return 'Waste';
  if (normalized === 'adjustment') return 'Adjustment';
  return value.trim();
}

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-LK', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function getDateBoundary(value: string, nextDay = false): number | null {
  if (!value) return null;
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day + (nextDay ? 1 : 0)).getTime();
}

function isOutboundMovement(movementType: MovementType) {
  return movementType === 'Sale' || movementType === 'Issue' || movementType === 'Consumption';
}

function formatCountStatus(status: string) {
  if (status === 'PendingApproval') return 'Pending approval';
  if (status === 'NeedsRecount') return 'Needs recount';
  return status;
}

async function fetchAllPages(
  endpoint: string,
  headers: HeadersInit,
  recordName: string,
  activeCheck?: () => boolean,
): Promise<unknown[]> {
  const records: unknown[] = [];
  let page = 1;
  let totalPages = 1;

  do {
    const response = await fetch(`${endpoint}?page=${page}&pageSize=100`, { headers });
    if (!response.ok) throw new Error(`${recordName} request failed (${response.status})`);
    const data: unknown = await response.json();
    if (Array.isArray(data)) {
      records.push(...data);
      totalPages = 1;
    } else if (data && typeof data === 'object' && 'items' in data && Array.isArray(data.items)) {
      const pageData = data as { items: unknown[]; totalPages: number };
      if (!Number.isInteger(pageData.totalPages) || pageData.totalPages < 0) {
        throw new Error(`${recordName} request returned invalid pagination details.`);
      }
      records.push(...pageData.items);
      totalPages = pageData.totalPages;
    } else {
      throw new Error(`${recordName} request returned an invalid response.`);
    }
    page += 1;
  } while (page <= totalPages && (!activeCheck || activeCheck()));

  return records;
}

export function StockMovementLogPage() {
  const token = getStoredToken();
  const { notify } = useToast();
  const [activities, setActivities] = useState<MovementEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState('');
  const [type, setType] = useState<MovementTypeFilter>('All types');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(1);

  const loadMovements = useCallback(async (activeCheck?: () => boolean) => {
    setLoading(true);
    setLoadError('');
    try {
      const headers = { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' };
      const [movementRecords, countRecords] = await Promise.all([
        fetchAllPages('/api/inventory/movements', headers, 'Movement', activeCheck),
        fetchAllPages('/api/inventory/physical-counts', headers, 'Physical count', activeCheck),
      ]);
      if (activeCheck && !activeCheck()) return false;

      const movementEntries = movementRecords.map((value): MovementEntry => {
        if (!value || typeof value !== 'object') throw new Error('Movement request returned an invalid record.');
        const movement = value as Record<string, unknown>;
        const occurredAt = typeof movement.occurredAt === 'string' ? movement.occurredAt : '';
        const quantity = movement.quantity;
        if (!movement.id || !Number.isFinite(Date.parse(occurredAt)) || typeof quantity !== 'number' || !Number.isFinite(quantity)) {
          throw new Error('Movement request returned a record with invalid date or quantity.');
        }
        const movementType = normalizeMovementType(movement.movementType);
        const notes = typeof movement.notes === 'string' ? movement.notes : undefined;
        const reference = typeof movement.reference === 'string' ? movement.reference : undefined;
        return {
          id: String(movement.id),
          occurredAt,
          item: typeof movement.item === 'string' ? movement.item : 'Unknown item',
          sku: typeof movement.sku === 'string' ? movement.sku : 'Unknown SKU',
          movementType,
          quantity,
          reasonLabel: notes ?? reference ?? movementType,
          reference,
          notes,
          performedBy: typeof movement.performedBy === 'string' ? movement.performedBy : undefined,
          supplierName: typeof movement.supplierName === 'string' ? movement.supplierName : undefined,
        };
      });
      const physicalCounts = countRecords.map((value): MovementEntry => {
        if (!value || typeof value !== 'object') throw new Error('Physical count request returned an invalid record.');
        const count = value as Record<string, unknown>;
        const occurredAt = typeof count.countedAt === 'string' ? count.countedAt : '';
        const quantity = count.variance;
        if (!count.id || !Number.isFinite(Date.parse(occurredAt)) ||
            typeof quantity !== 'number' || !Number.isFinite(quantity) ||
            typeof count.status !== 'string' || typeof count.reason !== 'string') {
          throw new Error('Physical count request returned a record with invalid details.');
        }
        const notes = [
          typeof count.reasonNotes === 'string' ? count.reasonNotes : '',
          typeof count.reviewNotes === 'string' ? count.reviewNotes : '',
        ].filter(Boolean).join(' · ') || undefined;
        const reasonLabel = [
          `${formatCountStatus(count.status)} physical count`,
          count.reason.replace(/([a-z])([A-Z])/g, '$1 $2'),
          notes,
          `system ${String(count.systemQuantityAtCount)}; counted ${String(count.countedQuantity)}`,
        ].filter(Boolean).join(' · ');
        return {
          id: `physical-count-${String(count.id)}`,
          occurredAt,
          item: typeof count.itemName === 'string' ? count.itemName : 'Unknown item',
          sku: typeof count.sku === 'string' ? count.sku : 'Unknown SKU',
          movementType: 'Physical count',
          quantity,
          reasonLabel,
          reference: typeof count.reference === 'string' ? count.reference : undefined,
          notes,
          performedBy: typeof count.countedBy === 'string' ? count.countedBy : undefined,
          isPhysicalCount: true,
          countStatus: count.status,
        };
      });
      const appliedCountReferences = new Set(
        physicalCounts
          .filter((count) => count.countStatus === 'Applied' && count.reference)
          .map((count) => count.reference),
      );
      const distinctMovements = movementEntries.filter((movement) =>
        movement.movementType !== 'Adjustment' ||
        !movement.reference ||
        !appliedCountReferences.has(movement.reference),
      );
      const allActivities = [...distinctMovements, ...physicalCounts]
        .sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));

      if (activeCheck && !activeCheck()) return false;
      setActivities(allActivities);
      return true;
    } catch (error) {
      console.error(error);
      if (!activeCheck || activeCheck()) {
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
    const fromMs = getDateBoundary(dateFrom);
    const toMs = getDateBoundary(dateTo, true);

    return activities.filter((row) => {
      const occurredMs = new Date(row.occurredAt).getTime();
      const matchesQuery =
        queryLower === '' ||
        row.item.toLowerCase().includes(queryLower) ||
        row.sku.toLowerCase().includes(queryLower) ||
        row.reference?.toLowerCase().includes(queryLower) ||
        row.reasonLabel.toLowerCase().includes(queryLower) ||
        row.notes?.toLowerCase().includes(queryLower) ||
        row.movementType.toLowerCase().includes(queryLower) ||
        row.performedBy?.toLowerCase().includes(queryLower) ||
        row.supplierName?.toLowerCase().includes(queryLower);
      const matchesFrom = fromMs === null || occurredMs >= fromMs;
      const matchesTo = toMs === null || occurredMs < toMs;
      return matchesQuery && matchesFrom && matchesTo;
    });
  }, [activities, dateFrom, dateTo, query]);
  const filtered = useMemo(
    () => type === 'All types'
      ? contextFiltered
      : type === 'Outbound'
        ? contextFiltered.filter((row) => isOutboundMovement(row.movementType))
        : type === 'Adjustment'
          ? contextFiltered.filter((row) =>
            row.movementType === 'Adjustment' ||
            (row.isPhysicalCount && row.countStatus === 'Applied' && row.quantity !== 0),
          )
          : contextFiltered.filter((row) => row.movementType === type),
    [contextFiltered, type],
  );
  const availableTypes = useMemo(
    () => [...new Set([...baseMovementTypes, ...activities.map((row) => row.movementType)])],
    [activities],
  );
  const movementTypeCounts = useMemo(() => ({
    all: contextFiltered.length,
    received: contextFiltered.filter((row) => row.movementType === 'Receive').length,
    issued: contextFiltered.filter((row) => isOutboundMovement(row.movementType)).length,
    wasted: contextFiltered.filter((row) => row.movementType === 'Waste').length,
    adjusted: contextFiltered.filter((row) =>
      row.movementType === 'Adjustment' ||
      (row.isPhysicalCount && row.countStatus === 'Applied' && row.quantity !== 0),
    ).length,
    physicalCounts: contextFiltered.filter((row) => row.isPhysicalCount).length,
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
    const received = filtered.filter((row) => row.movementType === 'Receive').reduce((sum, row) => sum + Math.abs(row.quantity), 0);
    const issued = filtered.filter((row) => isOutboundMovement(row.movementType) || row.movementType === 'Waste').reduce((sum, row) => sum + Math.abs(row.quantity), 0);
    const net = filtered.reduce((sum, row) =>
      sum + (row.isPhysicalCount && row.countStatus !== 'Applied' ? 0 : row.quantity), 0);
    return {
      count: filtered.length,
      received,
      issued,
      net,
      receives: filtered.filter((row) => row.movementType === 'Receive').length,
      issues: filtered.filter((row) => isOutboundMovement(row.movementType)).length,
      wastes: filtered.filter((row) => row.movementType === 'Waste').length,
      adjustments: filtered.filter((row) =>
        row.movementType === 'Adjustment' ||
        (row.isPhysicalCount && row.countStatus === 'Applied' && row.quantity !== 0),
      ).length,
    };
  }, [filtered]);

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);
  const physicalCountTotal = activities.filter((row) => row.isPhysicalCount).length;
  const hasActiveFilters = query.trim() !== '' || type !== 'All types' || dateFrom !== '' || dateTo !== '';

  async function handleRefresh() {
    const refreshed = await loadMovements();
    if (refreshed) notify('Stock movement history refreshed.', 'success');
  }

  return (
    <div className="page stock-movement-page">
      <header className="movement-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="movement-hero-copy">
          <p className="movement-eyebrow"><span aria-hidden="true">↗</span> OPERATIONS / STOCK ACTIVITY</p>
          <h1>Stock activity</h1>
          <p>Follow physical counts, receipts, issues, and adjustments across your inventory.</p>
          <div className="movement-hero-meta"><span className={`movement-live-dot${loading ? ' is-loading' : ''}`} aria-hidden="true" />{loading ? 'Syncing recent activity…' : `${activities.length} records loaded`}<span className="movement-meta-separator">·</span>Newest first</div>
        </div>
        <div className="movement-hero-art" aria-hidden="true"><span className="movement-art-ring movement-art-ring-one" /><span className="movement-art-ring movement-art-ring-two" /><span className="movement-art-icon"><Icon name="movement" size={42} /></span><span className="movement-art-point movement-art-point-one" /><span className="movement-art-point movement-art-point-two" /></div>
        <div className="movement-hero-actions"><button className="btn movement-refresh" type="button" onClick={() => void handleRefresh()} disabled={loading}><span aria-hidden="true">↻</span>{loading ? 'Refreshing…' : 'Refresh history'}</button></div>
      </header>
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="panel p-6">Loading live movement history…</div>}

      <section className="stat-strip movement-stat-strip" aria-label="Stock activity summary">
        <article className="stat metric-card movement-stat movement-stat-activity">
          <div className="movement-stat-main"><span className="movement-stat-icon" aria-hidden="true"><Icon name="movement" size={20} /></span><div className="metric-info"><span className="movement-stat-kicker">ACTIVITY</span><strong className="movement-stat-value">{stats.count}</strong><span className="movement-stat-label">Matching activities</span></div><span className="movement-stat-index" aria-hidden="true">01</span></div>
          <div className="movement-stat-detail"><i className="movement-detail-receive" />{stats.receives} in <i className="movement-detail-out" />{stats.issues + stats.wastes} out <i className="movement-detail-adjust" />{stats.adjustments} adjusted · {physicalCountTotal} physical counts</div>
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
          <div className="movement-stat-detail">Net includes applied counts; unapplied counts do not change stock totals.</div>
        </article>
      </section>

      <section className="panel movement-log-panel">
        <div className="movement-panel-head"><div><span className="movement-panel-icon" aria-hidden="true"><Icon name="inventory" size={19} /></span><div><h2>Activity log</h2>        <p>Filter records by item, activity type, or date.</p></div></div><span className="movement-count-pill">{filtered.length} shown</span></div>
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
          <select className="filter-select" value={type} onChange={(event) => setType(event.target.value as MovementTypeFilter)} aria-label="Filter by activity type">
            <option>All types</option>
            <option value="Outbound">Outbound</option>
            {[...new Set([...availableTypes, 'Physical count'])].map((option) => <option key={option} value={option}>{option}</option>)}
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

        <div className="movement-type-summary" aria-label="Activity type counts">
          <button type="button" className={`movement-type-chip${type === 'All types' ? ' is-active' : ''}`} aria-pressed={type === 'All types'} onClick={() => setType('All types')}>All <strong>{movementTypeCounts.all}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-receive${type === 'Receive' ? ' is-active' : ''}`} aria-pressed={type === 'Receive'} onClick={() => setType(type === 'Receive' ? 'All types' : 'Receive')}><i /> Received <strong>{movementTypeCounts.received}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-issue${type === 'Outbound' ? ' is-active' : ''}`} aria-pressed={type === 'Outbound'} onClick={() => setType(type === 'Outbound' ? 'All types' : 'Outbound')}><i /> Issued / consumed <strong>{movementTypeCounts.issued}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-waste${type === 'Waste' ? ' is-active' : ''}`} aria-pressed={type === 'Waste'} onClick={() => setType(type === 'Waste' ? 'All types' : 'Waste')}><i /> Wasted <strong>{movementTypeCounts.wasted}</strong></button>
          <button type="button" className={`movement-type-chip movement-chip-adjust${type === 'Adjustment' ? ' is-active' : ''}`} aria-pressed={type === 'Adjustment'} onClick={() => setType(type === 'Adjustment' ? 'All types' : 'Adjustment')}><i /> Adjusted <strong>{movementTypeCounts.adjusted}</strong></button>
          <button type="button" className={`movement-type-chip${type === 'Physical count' ? ' is-active' : ''}`} aria-pressed={type === 'Physical count'} onClick={() => setType(type === 'Physical count' ? 'All types' : 'Physical count')}>Physical counts <strong>{movementTypeCounts.physicalCounts}</strong></button>
        </div>

        <div className="table-wrap">
          <table className="data-table movement-table">
          <thead><tr><th>When</th><th>Item</th><th>Type</th><th>Quantity / variance</th><th>Details</th><th>Reference</th><th>Recorded by</th></tr></thead>
            <tbody>
              {paged.map((row) => (
                <tr key={row.id}>
                  <td className="movement-when">{formatDateTime(row.occurredAt)}</td>
                  <td>
                    <p className="cell-title">{row.item}</p>
                    <p className="cell-sub">{row.sku}</p>
                  </td>
                  <td className={`movement-type-cell movement-type-cell-${row.movementType.toLowerCase().replace(/\s+/g, '-')}`}><Badge tone={typeTone[row.movementType] ?? 'neutral'}>{row.movementType}</Badge></td>
                  <td>
                    <span className={`movement-quantity${row.quantity > 0 ? ' is-in' : row.quantity < 0 ? ' is-out' : ''}`}>
                      {row.isPhysicalCount &&
                      row.countStatus !== 'Applied' &&
                      row.countStatus !== 'Matched'
                        ? `Variance ${row.quantity > 0 ? '+' : ''}${row.quantity}`
                        : row.quantity > 0 ? `+${row.quantity}` : row.quantity}
                    </span>
                  </td>
                  <td>
                    <p className="movement-detail-text">{row.reasonLabel}</p>
                  </td>
                  <td className="movement-reference">{row.reference ?? '—'}</td>
                  <td>{row.performedBy ?? 'Not recorded'}</td>
                </tr>
              ))}
              {paged.length === 0 && (
                <tr><td colSpan={7} className="empty-state">{loading ? 'Loading activity history…' : loadError ? 'Activity history could not be loaded. Refresh to retry.' : activities.length === 0 ? 'No stock activity records are available yet.' : 'No activity matches these filters. Try clearing a filter or changing the date range.'}</td></tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="table-footer">
          <p className="table-caption">
            {filtered.length === 0
              ? `No activity · ${activities.length} total recorded`
              : `Showing ${rangeStart}–${rangeEnd} of ${filtered.length} activities · ${activities.length} total recorded`}
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
