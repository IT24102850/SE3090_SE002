import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { useAuth } from '../auth/AuthContext';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';

type POStatus = 'Draft' | 'InReview' | 'Placed' | 'InTransit' | 'Received' | 'Cancelled';

type TimelineEvent = {
  status: POStatus;
  at: string;
  by: string;
  note?: string;
};

type PurchaseOrder = {
  id: string;
  number: string;
  supplier: string;
  branch?: string;
  status: POStatus;
  amount: number;
  lineItems: number;
  createdAt: string;
  updatedAt: string;
  timeline: TimelineEvent[];
};

type PurchaseOrderResponse = {
  id: string;
  number: string;
  branchId: string;
  branch?: string;
  supplierId: string;
  supplier?: string;
  status: string;
  createdAt: string;
  updatedAt: string;
};

type PurchaseOrderListResponse = {
  items: PurchaseOrderResponse[];
  page: number;
  pageSize: number;
  totalCount: number;
  totalPages: number;
};

const PAGE_SIZE = 6;

const lifecycleSteps: POStatus[] = ['Draft', 'InReview', 'Placed', 'InTransit', 'Received'];

const statusLabels: Record<POStatus, string> = {
  Draft: 'Draft',
  InReview: 'In review',
  Placed: 'Placed',
  InTransit: 'In transit',
  Received: 'Received',
  Cancelled: 'Cancelled',
};

const statusTone: Record<POStatus, BadgeTone> = {
  Draft: 'slate',
  InReview: 'amber',
  Placed: 'violet',
  InTransit: 'blue',
  Received: 'green',
  Cancelled: 'red',
};

const suppliers = [
  'Ceylon Coffee Traders',
  'MetroPack Ltd',
  'Fresh Farms Dairy',
  'Flour & Co Bakery Supply',
];

const statusFilters = ['All statuses', ...lifecycleSteps.map((step) => statusLabels[step]), 'Cancelled'] as const;
type StatusFilter = (typeof statusFilters)[number];

const fallbackOrders: PurchaseOrder[] = [
  {
    id: 'po-2147',
    number: 'PO-2147',
    supplier: 'Ceylon Coffee Traders',
    branch: 'Main branch',
    status: 'InTransit',
    amount: 184500,
    lineItems: 3,
    createdAt: '2026-08-08T10:00:00Z',
    updatedAt: '2026-08-12T14:30:00Z',
    timeline: [
      { status: 'Draft', at: '2026-08-08T10:00:00Z', by: 'Kavindu' },
      { status: 'InReview', at: '2026-08-08T11:20:00Z', by: 'Hasaranga', note: 'Approved supplier quote' },
      { status: 'Placed', at: '2026-08-09T09:15:00Z', by: 'Kavindu' },
      { status: 'InTransit', at: '2026-08-12T14:30:00Z', by: 'Nadeesha', note: 'Courier dispatched — ETA Aug 16' },
    ],
  },
  {
    id: 'po-2146',
    number: 'PO-2146',
    supplier: 'MetroPack Ltd',
    branch: 'Main branch',
    status: 'Received',
    amount: 96200,
    lineItems: 2,
    createdAt: '2026-08-06T08:30:00Z',
    updatedAt: '2026-08-10T16:00:00Z',
    timeline: [
      { status: 'Draft', at: '2026-08-06T08:30:00Z', by: 'Nadeesha' },
      { status: 'InReview', at: '2026-08-06T10:00:00Z', by: 'Hasaranga' },
      { status: 'Placed', at: '2026-08-07T09:00:00Z', by: 'Nadeesha' },
      { status: 'InTransit', at: '2026-08-09T11:45:00Z', by: 'MetroPack Ltd' },
      { status: 'Received', at: '2026-08-10T16:00:00Z', by: 'Nadeesha', note: 'GRN-4395 posted' },
    ],
  },
  {
    id: 'po-2144',
    number: 'PO-2144',
    supplier: 'Fresh Farms Dairy',
    branch: 'Main branch',
    status: 'Placed',
    amount: 72850,
    lineItems: 1,
    createdAt: '2026-08-05T07:45:00Z',
    updatedAt: '2026-08-08T08:20:00Z',
    timeline: [
      { status: 'Draft', at: '2026-08-05T07:45:00Z', by: 'Nadeesha' },
      { status: 'InReview', at: '2026-08-05T12:00:00Z', by: 'Hasaranga' },
      { status: 'Placed', at: '2026-08-08T08:20:00Z', by: 'Nadeesha' },
    ],
  },
  {
    id: 'po-2141',
    number: 'PO-2141',
    supplier: 'Flour & Co Bakery Supply',
    branch: 'Main branch',
    status: 'InReview',
    amount: 61400,
    lineItems: 4,
    createdAt: '2026-08-04T13:10:00Z',
    updatedAt: '2026-08-04T15:00:00Z',
    timeline: [
      { status: 'Draft', at: '2026-08-04T13:10:00Z', by: 'Dinesh' },
      { status: 'InReview', at: '2026-08-04T15:00:00Z', by: 'Hasaranga', note: 'Awaiting manager sign-off' },
    ],
  },
  {
    id: 'po-2138',
    number: 'PO-2138',
    supplier: 'Ceylon Coffee Traders',
    branch: 'Colombo outlet',
    status: 'Cancelled',
    amount: 42000,
    lineItems: 1,
    createdAt: '2026-08-01T09:00:00Z',
    updatedAt: '2026-08-02T11:30:00Z',
    timeline: [
      { status: 'Draft', at: '2026-08-01T09:00:00Z', by: 'Kavindu' },
      { status: 'Cancelled', at: '2026-08-02T11:30:00Z', by: 'Hasaranga', note: 'Duplicate order — merged into PO-2147' },
    ],
  },
];

const amountByNumber: Record<string, number> = {
  'PO-2147': 184500,
  'PO-2146': 96200,
  'PO-2144': 72850,
  'PO-2141': 61400,
};

async function apiGet<T>(path: string, token: string | null): Promise<T> {
  const response = await fetch(path, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) throw new Error(`Request failed: ${path}`);
  return response.json() as Promise<T>;
}

async function apiPut<T>(path: string, token: string | null, body: unknown): Promise<T> {
  const response = await fetch(path, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`Request failed: ${path}`);
  return response.json() as Promise<T>;
}

function normalizeStatus(raw: string): POStatus {
  const cleaned = raw.replace(/\s|-/g, '');
  const match = (['Draft', 'InReview', 'Placed', 'InTransit', 'Received', 'Cancelled'] as const)
    .find((status) => status.toLowerCase() === cleaned.toLowerCase());
  return match ?? 'Draft';
}

function filterStatusToApi(status: StatusFilter): POStatus | null {
  if (status === 'All statuses') return null;
  if (status === 'Cancelled') return 'Cancelled';
  const entry = Object.entries(statusLabels).find(([, label]) => label === status);
  return entry ? (entry[0] as POStatus) : null;
}

function formatPrice(amount: number) {
  return `LKR ${amount.toLocaleString()}`;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-LK', { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-LK', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function nextPoNumber(orders: PurchaseOrder[]) {
  const max = orders.reduce((acc, order) => {
    const num = parseInt(order.number.replace(/\D/g, ''), 10);
    return Number.isFinite(num) ? Math.max(acc, num) : acc;
  }, 2140);
  return `PO-${max + 1}`;
}

function nextStatus(current: POStatus): POStatus | null {
  if (current === 'Cancelled' || current === 'Received') return null;
  const index = lifecycleSteps.indexOf(current);
  if (index === -1 || index >= lifecycleSteps.length - 1) return null;
  return lifecycleSteps[index + 1];
}

function responseToOrder(response: PurchaseOrderResponse, existing?: PurchaseOrder): PurchaseOrder {
  const status = normalizeStatus(response.status);
  return {
    id: response.id,
    number: response.number,
    supplier: response.supplier ?? 'Unknown supplier',
    branch: response.branch,
    status,
    amount: existing?.amount ?? amountByNumber[response.number] ?? 0,
    lineItems: existing?.lineItems ?? 1,
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
    timeline: existing?.timeline ?? [{ status: 'Draft', at: response.createdAt, by: 'System' }, ...(status !== 'Draft' ? [{ status, at: response.updatedAt, by: 'System' }] : [])],
  };
}

function LifecycleTracker({ status, compact = false }: { status: POStatus; compact?: boolean }) {
  if (status === 'Cancelled') {
    return <span className="lifecycle-cancelled">Cancelled</span>;
  }

  const activeIndex = lifecycleSteps.indexOf(status);

  return (
    <ol className={`lifecycle-tracker${compact ? ' lifecycle-tracker-compact' : ''}`} aria-label="Purchase order lifecycle">
      {lifecycleSteps.map((step, index) => {
        const done = index < activeIndex;
        const active = index === activeIndex;
        return (
          <li
            key={step}
            className={`lifecycle-step${done ? ' lifecycle-step-done' : ''}${active ? ' lifecycle-step-active' : ''}`}
            aria-current={active ? 'step' : undefined}
          >
            <span className="lifecycle-dot" aria-hidden="true" />
            {!compact && <span className="lifecycle-label">{statusLabels[step]}</span>}
          </li>
        );
      })}
    </ol>
  );
}

function CreatePoModal({
  onClose,
  onCreate,
}: {
  onClose: () => void;
  onCreate: (supplier: string) => void;
}) {
  const [supplier, setSupplier] = useState(suppliers[0]);

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    onCreate(supplier);
  }

  return (
    <div className="modal-overlay" onClick={onClose} role="presentation">
      <div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="create-po-title">
        <div className="modal-head">
          <h2 id="create-po-title">Create purchase order</h2>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="modal-body" onSubmit={handleSubmit}>
          <label className="form-field form-field-wide">
            Supplier
            <select value={supplier} onChange={(event) => setSupplier(event.target.value)}>
              {suppliers.map((option) => <option key={option}>{option}</option>)}
            </select>
          </label>
          <p className="modal-hint">A draft PO will be created and can be advanced through the lifecycle.</p>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary">Create draft</button>
          </div>
        </form>
      </div>
    </div>
  );
}

export function PurchaseOrderManagerPage() {
  const { notify } = useToast();
  const { token, user } = useAuth();
  const [orders, setOrders] = useState<PurchaseOrder[]>(fallbackOrders);
  const [usedFallback, setUsedFallback] = useState(true);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>(statusFilters[0]);
  const [supplierFilter, setSupplierFilter] = useState('All suppliers');
  const [selectedId, setSelectedId] = useState<string | null>(fallbackOrders[0]?.id ?? null);
  const [showCreate, setShowCreate] = useState(false);
  const [page, setPage] = useState(1);

  const performer = user?.id === 'demo-user' ? 'Hasaranga' : 'Staff';

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      try {
        const response = await apiGet<PurchaseOrderListResponse>('/api/purchase-orders?pageSize=50', token);
        if (cancelled) return;
        if (response.items.length > 0) {
          setOrders((prev) => {
            const byNumber = new Map(prev.map((order) => [order.number, order]));
            return response.items.map((item) => responseToOrder(item, byNumber.get(item.number)));
          });
          setUsedFallback(false);
        }
      } catch {
        if (!cancelled) setUsedFallback(true);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, [token]);

  const filtered = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    const apiStatus = filterStatusToApi(statusFilter);
    return orders.filter((order) => {
      const matchesQuery =
        queryLower === '' ||
        order.number.toLowerCase().includes(queryLower) ||
        order.supplier.toLowerCase().includes(queryLower);
      const matchesStatus = apiStatus === null || order.status === apiStatus;
      const matchesSupplier = supplierFilter === 'All suppliers' || order.supplier === supplierFilter;
      return matchesQuery && matchesStatus && matchesSupplier;
    });
  }, [orders, query, statusFilter, supplierFilter]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);

  const paged = useMemo(() => {
    const start = (safePage - 1) * PAGE_SIZE;
    return filtered.slice(start, start + PAGE_SIZE);
  }, [filtered, safePage]);

  useEffect(() => {
    setPage(1);
  }, [query, statusFilter, supplierFilter]);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  useEffect(() => {
    if (selectedId && !filtered.some((order) => order.id === selectedId)) {
      setSelectedId(filtered[0]?.id ?? null);
    }
  }, [filtered, selectedId]);

  const selected = orders.find((order) => order.id === selectedId) ?? null;

  const stats = useMemo(() => ({
    total: orders.length,
    open: orders.filter((order) => order.status !== 'Received' && order.status !== 'Cancelled').length,
    inTransit: orders.filter((order) => order.status === 'InTransit').length,
    value: orders.filter((order) => order.status !== 'Cancelled').reduce((sum, order) => sum + order.amount, 0),
  }), [orders]);

  async function advanceStatus(order: PurchaseOrder) {
    const next = nextStatus(order.status);
    if (!next) return;

    const now = new Date().toISOString();
    const timelineEvent: TimelineEvent = { status: next, at: now, by: performer };

    setOrders((prev) => prev.map((candidate) => (
      candidate.id === order.id
        ? { ...candidate, status: next, updatedAt: now, timeline: [...candidate.timeline, timelineEvent] }
        : candidate
    )));

    if (!usedFallback) {
      try {
        await apiPut<PurchaseOrderResponse>(`/api/purchase-orders/${order.id}/status`, token, { status: next });
      } catch {
        notify(`Could not sync ${order.number}; the status is only saved locally.`, 'error');
        return;
      }
    }
    notify(`${order.number} moved to ${statusLabels[next]}.`);
  }

  function cancelOrder(order: PurchaseOrder) {
    if (order.status === 'Received' || order.status === 'Cancelled') return;
    const now = new Date().toISOString();
    const timelineEvent: TimelineEvent = { status: 'Cancelled', at: now, by: performer, note: 'Cancelled by user' };
    setOrders((prev) => prev.map((candidate) => (
      candidate.id === order.id
        ? { ...candidate, status: 'Cancelled', updatedAt: now, timeline: [...candidate.timeline, timelineEvent] }
        : candidate
    )));
    notify(`${order.number} was cancelled.`, 'info');
  }

  function createOrder(supplier: string) {
    const now = new Date().toISOString();
    const number = nextPoNumber(orders);
    const created: PurchaseOrder = {
      id: `local-${number}`,
      number,
      supplier,
      branch: 'Main branch',
      status: 'Draft',
      amount: 0,
      lineItems: 0,
      createdAt: now,
      updatedAt: now,
      timeline: [{ status: 'Draft', at: now, by: performer }],
    };
    setOrders((prev) => [created, ...prev]);
    setSelectedId(created.id);
    setShowCreate(false);
    notify(`${number} draft was created.`);
  }

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div className="page">
      <header className="page-head">
        <div>
          <p className="eyebrow">OPERATIONS / PROCUREMENT</p>
          <h1>Purchase order manager</h1>
          <p className="page-sub">Track PO lifecycle from draft through receipt, with status history and user attribution.</p>
        </div>
        <div className="page-actions">
          <button className="btn btn-primary" type="button" onClick={() => setShowCreate(true)}>Create PO</button>
        </div>
      </header>

      {usedFallback && !loading && (
        <p className="page-banner">Showing demo data — connect to the API to sync live purchase orders.</p>
      )}

      <section className="stat-strip" aria-label="Purchase order summary">
        <div className="stat"><span className="stat-value">{stats.total}</span><span className="stat-label">Total POs</span></div>
        <div className="stat"><span className="stat-value">{stats.open}</span><span className="stat-label">Open orders</span></div>
        <div className="stat"><span className="stat-value">{stats.inTransit}</span><span className="stat-label">In transit</span></div>
        <div className="stat"><span className="stat-value">{formatPrice(stats.value)}</span><span className="stat-label">Pipeline value</span></div>
      </section>

      <div className="po-layout">
        <section className="panel po-list-panel">
          <div className="toolbar toolbar-wrap">
            <div className="search-field">
              <span className="search-icon" aria-hidden="true">⌕</span>
              <input
                type="search"
                placeholder="Search PO number or supplier…"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                aria-label="Search purchase orders"
              />
            </div>
            <select className="filter-select" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as StatusFilter)} aria-label="Filter by status">
              {statusFilters.map((option) => <option key={option}>{option}</option>)}
            </select>
            <select className="filter-select" value={supplierFilter} onChange={(event) => setSupplierFilter(event.target.value)} aria-label="Filter by supplier">
              <option>All suppliers</option>
              {suppliers.map((option) => <option key={option}>{option}</option>)}
            </select>
          </div>

          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>PO</th><th>Supplier</th><th>Amount</th><th>Status</th><th>Lifecycle</th></tr>
              </thead>
              <tbody>
                {paged.map((order) => (
                  <tr
                    key={order.id}
                    className={order.id === selectedId ? 'row-selected' : undefined}
                    onClick={() => setSelectedId(order.id)}
                  >
                    <td>
                      <p className="po-number">{order.number}</p>
                      <p className="cell-sub">{formatDate(order.createdAt)}</p>
                    </td>
                    <td>
                      <p className="cell-title">{order.supplier}</p>
                      <p className="cell-sub">{order.branch ?? '—'}</p>
                    </td>
                    <td className="amount">{formatPrice(order.amount)}</td>
                    <td><Badge tone={statusTone[order.status]}>{statusLabels[order.status]}</Badge></td>
                    <td><LifecycleTracker status={order.status} compact /></td>
                  </tr>
                ))}
                {paged.length === 0 && (
                  <tr><td colSpan={5} className="empty-state">No purchase orders match your filters.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="table-footer">
            <p className="table-caption">
              {filtered.length === 0
                ? `No orders · ${orders.length} total`
                : `Showing ${rangeStart}–${rangeEnd} of ${filtered.length} orders · ${orders.length} total`}
            </p>
            {filtered.length > PAGE_SIZE && (
              <nav className="pagination" aria-label="Purchase order pagination">
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

        <aside className="panel po-detail-panel">
          {selected ? (
            <>
              <div className="panel-head">
                <div>
                  <h2>{selected.number}</h2>
                  <p>{selected.supplier} · {selected.lineItems} line items</p>
                </div>
                <Badge tone={statusTone[selected.status]}>{statusLabels[selected.status]}</Badge>
              </div>

              <div className="po-detail-body">
                <LifecycleTracker status={selected.status} />

                <dl className="detail-grid">
                  <div><dt>Amount</dt><dd>{formatPrice(selected.amount)}</dd></div>
                  <div><dt>Branch</dt><dd>{selected.branch ?? '—'}</dd></div>
                  <div><dt>Created</dt><dd>{formatDate(selected.createdAt)}</dd></div>
                  <div><dt>Last updated</dt><dd>{formatDateTime(selected.updatedAt)}</dd></div>
                </dl>

                <div className="po-actions">
                  {nextStatus(selected.status) && (
                    <button type="button" className="btn btn-primary" onClick={() => advanceStatus(selected)}>
                      Advance to {statusLabels[nextStatus(selected.status)!]}
                    </button>
                  )}
                  {selected.status !== 'Received' && selected.status !== 'Cancelled' && (
                    <button type="button" className="btn btn-secondary" onClick={() => cancelOrder(selected)}>Cancel PO</button>
                  )}
                </div>

                <div className="timeline-section">
                  <h3>Status history</h3>
                  <ol className="status-timeline">
                    {selected.timeline.map((event, index) => (
                      <li key={`${event.status}-${event.at}-${index}`}>
                        <div className="timeline-marker" aria-hidden="true" />
                        <div className="timeline-content">
                          <div className="timeline-head">
                            <Badge tone={statusTone[event.status]}>{statusLabels[event.status]}</Badge>
                            <span className="cell-sub">{formatDateTime(event.at)}</span>
                          </div>
                          <p className="timeline-user">By {event.by}</p>
                          {event.note && <p className="timeline-note">{event.note}</p>}
                        </div>
                      </li>
                    ))}
                  </ol>
                </div>
              </div>
            </>
          ) : (
            <div className="po-detail-empty">
              <p>Select a purchase order to view its lifecycle tracker.</p>
            </div>
          )}
        </aside>
      </div>

      {showCreate && <CreatePoModal onClose={() => setShowCreate(false)} onCreate={createOrder} />}
    </div>
  );
}
