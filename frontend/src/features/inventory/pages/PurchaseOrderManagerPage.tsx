import { API_BASE_URL } from '../../../api/apiBaseUrl';
import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import { getStoredToken } from '../authToken';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';

type POStatus = 'Draft' | 'InReview' | 'Placed' | 'InTransit' | 'PartiallyReceived' | 'Received' | 'Cancelled';

type TimelineEvent = {
  status: POStatus;
  at: string;
  by: string;
  note?: string;
};

type PurchaseOrderItem = {
  id: string;
  inventoryItemId?: string;
  itemName?: string;
  description?: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  receivedQuantity: number;
  damagedQuantity: number;
  shortageQuantity: number;
  receivingClosed: boolean;
};

type PurchaseOrder = {
  id: string;
  number: string;
  supplier: string;
  branchId: string;
  branch?: string;
  status: POStatus;
  amount: number;
  lineItems: number;
  createdAt: string;
  updatedAt: string;
  timeline: TimelineEvent[];
  items?: PurchaseOrderItem[];
  receipts?: PurchaseOrderReceiptResponse[];
};

type PurchaseOrderItemResponse = {
  id: string;
  inventoryItemId?: string;
  itemName?: string;
  description?: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  receivedQuantity: number;
  damagedQuantity: number;
  shortageQuantity: number;
  receivingClosed: boolean;
};

type PurchaseOrderResponse = {
  id: string;
  number: string;
  branchId: string;
  branch?: string;
  supplierId: string;
  supplier?: string;
  status: string;
  totalAmount: number;
  lineItems: number;
  createdAt: string;
  updatedAt: string;
  items?: PurchaseOrderItemResponse[];
  receipts?: PurchaseOrderReceiptResponse[];
};

type PurchaseOrderReceiptResponse = {
  id: string;
  receivedAt: string;
  receivedBy: string;
  items: Array<{
    purchaseOrderItemId: string;
    deliveredQuantity: number;
    acceptedQuantity: number;
    damagedQuantity: number;
    shortageQuantity: number;
    notes?: string;
  }>;
};

type PurchaseOrderOption = { id: string; name: string };
type PurchaseOrderItemOption = {
  id: string;
  name: string;
  sku: string;
  unitCost?: number;
  branchId?: string | null;
};

type PurchaseOrderOptionsResponse = {
  branches: PurchaseOrderOption[];
  suppliers: PurchaseOrderOption[];
  items?: PurchaseOrderItemOption[];
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
  PartiallyReceived: 'Partially received',
  Received: 'Received',
  Cancelled: 'Cancelled',
};

const statusTone: Record<POStatus, BadgeTone> = {
  Draft: 'slate',
  InReview: 'amber',
  Placed: 'violet',
  InTransit: 'blue',
  PartiallyReceived: 'amber',
  Received: 'green',
  Cancelled: 'red',
};


const statusFilters = ['All statuses', ...lifecycleSteps.map((step) => statusLabels[step]), statusLabels.PartiallyReceived, 'Cancelled'] as const;
type StatusFilter = (typeof statusFilters)[number];

const fallbackOrders: PurchaseOrder[] = [
  {
    id: 'po-2147',
    number: 'PO-2147',
    supplier: 'Ceylon Coffee Traders',
    branchId: 'demo-main',
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
    branchId: 'demo-main',
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
    branchId: 'demo-main',
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
    branchId: 'demo-main',
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
    branchId: 'demo-colombo',
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

// Kept as a development fixture only; runtime state is always loaded from PostgreSQL via the API.
void fallbackOrders;
void amountByNumber;

async function apiGet<T>(path: string, token: string | null): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!response.ok) throw new Error(await apiErrorMessage(response, path));
  return response.json() as Promise<T>;
}

async function apiPut<T>(path: string, token: string | null, body: unknown): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(await apiErrorMessage(response, path));
  return response.json() as Promise<T>;
}

async function apiPost<T>(path: string, token: string | null, body: unknown): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(await apiErrorMessage(response, path));
  return response.json() as Promise<T>;
}

async function apiErrorMessage(response: Response, path: string): Promise<string> {
  const fallback = `Request failed (${response.status}): ${path}`;
  try {
    const body = await response.json() as { message?: string; title?: string; errors?: Record<string, string[]> };
    const validation = body.errors
      ? Object.values(body.errors).flat().filter(Boolean).join(' ')
      : '';
    return body.message || body.title || validation || fallback;
  } catch {
    return fallback;
  }
}

function normalizeStatus(raw: string): POStatus {
  const cleaned = raw.replace(/\s|-/g, '');
  const match = (['Draft', 'InReview', 'Placed', 'InTransit', 'PartiallyReceived', 'Received', 'Cancelled'] as const)
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
  if (current === 'InTransit' || current === 'PartiallyReceived') return null;
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
    branchId: response.branchId,
    branch: response.branch,
    status,
    amount: Number(response.totalAmount ?? 0),
    lineItems: Number(response.lineItems ?? (response.items?.length ?? 0)),
    createdAt: response.createdAt,
    updatedAt: response.updatedAt,
    timeline: existing?.timeline ?? [{ status: 'Draft', at: response.createdAt, by: 'System' }, ...(status !== 'Draft' ? [{ status, at: response.updatedAt, by: 'System' }] : [])],
    items: response.items ?? existing?.items ?? [],
    receipts: response.receipts ?? existing?.receipts ?? [],
  };
}

function LifecycleTracker({ status, compact = false }: { status: POStatus; compact?: boolean }) {
  if (status === 'Cancelled') {
    return <span className="lifecycle-cancelled">Cancelled</span>;
  }

  const activeIndex = lifecycleSteps.indexOf(status === 'PartiallyReceived' ? 'InTransit' : status);

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

type PoItemDraft = {
  inventoryItemId: string;
  description: string;
  quantity: number;
  unitPrice: number;
};

function CreatePoModal({
  onClose,
  onCreate,
  branches,
  suppliers,
  inventoryItems,
  defaultNumber,
  defaultBranchId,
  initialInventoryItemId,
  initialQuantity,
  creating,
}: {
  onClose: () => void;
  onCreate: (draft: {
    branchId: string;
    supplierId: string;
    number: string;
    items: Array<{ inventoryItemId?: string; description?: string; quantity: number; unitPrice: number }>;
  }) => Promise<void>;
  branches: PurchaseOrderOption[];
  suppliers: PurchaseOrderOption[];
  inventoryItems: PurchaseOrderItemOption[];
  defaultNumber: string;
  defaultBranchId?: string;
  initialInventoryItemId?: string;
  initialQuantity?: number;
  creating: boolean;
}) {
  const [branchId, setBranchId] = useState(defaultBranchId && branches.some((branch) => branch.id === defaultBranchId)
    ? defaultBranchId
    : branches[0]?.id ?? '');
  const [supplierId, setSupplierId] = useState(suppliers[0]?.id ?? '');
  const [poNumber, setPoNumber] = useState(defaultNumber);
  const [error, setError] = useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const branchInventoryItems = inventoryItems.filter((item) => item.branchId === branchId);
  const initialItem = branchInventoryItems.find((item) => item.id === initialInventoryItemId) ?? branchInventoryItems[0];
  const [items, setItems] = useState<PoItemDraft[]>([
    {
      inventoryItemId: initialItem?.id ?? '',
      description: initialItem?.name ?? '',
      quantity: initialQuantity && initialQuantity > 0 ? initialQuantity : 1,
      unitPrice: initialItem?.unitCost ?? 0,
    },
  ]);

  function handleItemSelect(index: number, val: string) {
    setItems((prev) => {
      const copy = [...prev];
      if (val === 'custom') {
        copy[index] = { ...copy[index], inventoryItemId: '', description: copy[index].description || '' };
      } else {
        const found = branchInventoryItems.find((inv) => inv.id === val);
        copy[index] = {
          ...copy[index],
          inventoryItemId: val,
          description: found?.name ?? copy[index].description,
          unitPrice: found?.unitCost ?? copy[index].unitPrice,
        };
      }
      return copy;
    });
  }

  function handleFieldChange<K extends keyof PoItemDraft>(index: number, field: K, val: PoItemDraft[K]) {
    setItems((prev) => {
      const copy = [...prev];
      copy[index] = { ...copy[index], [field]: val };
      return copy;
    });
  }

  function addItem() {
    const nextItem = branchInventoryItems[0];
    setItems((prev) => [
      ...prev,
      {
        inventoryItemId: nextItem?.id ?? '',
        description: nextItem?.name ?? '',
        quantity: 1,
        unitPrice: nextItem?.unitCost ?? 0,
      },
    ]);
  }

  function changeBranch(nextBranchId: string) {
    const nextBranchItems = inventoryItems.filter((item) => item.branchId === nextBranchId);
    setBranchId(nextBranchId);
    setItems((current) => current.map((row) => {
      if (!row.inventoryItemId || inventoryItems.some((item) => item.id === row.inventoryItemId && item.branchId === nextBranchId)) {
        return row;
      }
      const replacement = nextBranchItems[0];
      return {
        ...row,
        inventoryItemId: replacement?.id ?? '',
        description: replacement?.name ?? '',
        unitPrice: replacement?.unitCost ?? 0,
      };
    }));
  }

  function removeItem(index: number) {
    if (items.length <= 1) return;
    setItems((prev) => prev.filter((_, i) => i !== index));
  }

  const grandTotal = items.reduce((sum, item) => sum + (Number(item.quantity) || 0) * (Number(item.unitPrice) || 0), 0);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    if (!branchId) {
      setError('Branch is required.');
      return;
    }
    if (!supplierId) {
      setError('Supplier is required.');
      return;
    }
    if (!poNumber.trim()) {
      setError('PO number is required.');
      return;
    }
    if (items.length === 0) {
      setError('At least one item is required.');
      return;
    }

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (!item.inventoryItemId && !item.description.trim()) {
        setError(`Item #${i + 1} requires an inventory item or custom description.`);
        return;
      }
      if (Number(item.quantity) <= 0) {
        setError(`Item #${i + 1} quantity must be greater than 0.`);
        return;
      }
      if (Number(item.unitPrice) < 0) {
        setError(`Item #${i + 1} unit price cannot be negative.`);
        return;
      }
    }

    setConfirmOpen(true);
  }

  async function confirmCreate() {
    setConfirmOpen(false);
    await onCreate({
      branchId,
      supplierId,
      number: poNumber.trim(),
      items: items.map((i) => ({
        inventoryItemId: i.inventoryItemId ? i.inventoryItemId : undefined,
        description: i.description.trim() || undefined,
        quantity: Number(i.quantity),
        unitPrice: Number(i.unitPrice),
      })),
    });
  }

  return (
    <div className="modal-overlay" onClick={onClose} role="presentation">
      <div className="modal modal-lg" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="create-po-title">
        <div className="modal-head">
          <h2 id="create-po-title">Create Purchase Order</h2>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="modal-body" onSubmit={handleSubmit}>
          {error && <p className="modal-error">{error}</p>}

          <div className="form-grid">
            <label className="form-field">
              PO Number
              <input
                value={poNumber}
                onChange={(event) => setPoNumber(event.target.value)}
                placeholder="e.g. PO-2148"
                required
              />
            </label>
            <label className="form-field">
              Destination Branch
              <select value={branchId} onChange={(event) => changeBranch(event.target.value)} required>
                {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </label>
            <label className="form-field form-field-wide">
              Supplier
              <select value={supplierId} onChange={(event) => setSupplierId(event.target.value)} required>
                {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </label>
          </div>

          <div className="po-items-section">
            <div className="po-items-header">
              <h3>Order Line Items</h3>
              <button type="button" className="btn btn-secondary btn-sm" onClick={addItem}>
                + Add item
              </button>
            </div>

            <table className="po-items-table">
              <thead>
                <tr>
                  <th style={{ width: '38%' }}>Item / Description</th>
                  <th style={{ width: '18%' }}>Quantity</th>
                  <th style={{ width: '22%' }}>Unit Price (LKR)</th>
                  <th style={{ width: '18%', textAlign: 'right' }}>Subtotal</th>
                  <th className="cell-action"></th>
                </tr>
              </thead>
              <tbody>
                {items.map((row, idx) => {
                  const lineSubtotal = (Number(row.quantity) || 0) * (Number(row.unitPrice) || 0);
                  const isCustom = !row.inventoryItemId;

                  return (
                    <tr key={idx}>
                      <td>
                        <select
                          value={row.inventoryItemId || 'custom'}
                          onChange={(e) => handleItemSelect(idx, e.target.value)}
                          style={{ marginBottom: isCustom ? '0.35rem' : '0' }}
                        >
                          <option value="custom">-- Custom Description --</option>
                          {branchInventoryItems.map((inv) => (
                            <option key={inv.id} value={inv.id}>
                              {inv.name} ({inv.sku})
                            </option>
                          ))}
                        </select>
                        {isCustom && (
                          <input
                            type="text"
                            placeholder="Enter custom item description"
                            value={row.description}
                            onChange={(e) => handleFieldChange(idx, 'description', e.target.value)}
                            required
                          />
                        )}
                      </td>
                      <td>
                        <input
                          type="number"
                          min={1}
                          step={1}
                          value={row.quantity}
                          onChange={(e) => handleFieldChange(idx, 'quantity', Number(e.target.value))}
                          required
                        />
                      </td>
                      <td>
                        <input
                          type="number"
                          min={0}
                          step={1}
                          value={row.unitPrice}
                          onChange={(e) => handleFieldChange(idx, 'unitPrice', Number(e.target.value))}
                          required
                        />
                      </td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>
                        LKR {lineSubtotal.toLocaleString()}
                      </td>
                      <td className="cell-action">
                        {items.length > 1 && (
                          <button
                            type="button"
                            className="po-item-delete-btn"
                            title="Remove item"
                            onClick={() => removeItem(idx)}
                          >
                            ×
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>

            <div className="po-total-row">
              <span>Total Order Value ({items.length} {items.length === 1 ? 'item' : 'items'}):</span>
              <span style={{ fontSize: '1.05rem', color: 'var(--color-primary)' }}>
                LKR {grandTotal.toLocaleString()}
              </span>
            </div>
            {confirmOpen && (
              <ConfirmDialog
                title={`Create ${poNumber.trim()}?`}
                message={`Create this purchase order for ${formatPrice(grandTotal)} with ${items.length} line item${items.length === 1 ? '' : 's'}? The order will be saved to the database as Draft.`}
                confirmLabel="Create purchase order"
                onConfirm={() => { void confirmCreate(); }}
                onCancel={() => setConfirmOpen(false)}
              />
            )}
          </div>

          <div className="modal-actions" style={{ marginTop: '1.25rem' }}>
            <button type="button" className="btn btn-secondary" onClick={onClose} disabled={creating}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={creating}>
              {creating ? 'Creating…' : 'Create purchase order'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

type ReceiptDraft = {
  deliveredQuantity: string;
  damagedQuantity: string;
  closeRemainingAsShort: boolean;
  notes: string;
  inventoryItemId?: string;
};

function ReceivePoModal({
  order,
  inventoryItems,
  saving,
  onClose,
  onReceive,
}: {
  order: PurchaseOrder;
  inventoryItems: PurchaseOrderItemOption[];
  saving: boolean;
  onClose: () => void;
  onReceive: (items: Array<{
    purchaseOrderItemId: string;
    deliveredQuantity: number;
    damagedQuantity: number;
    closeRemainingAsShort: boolean;
    notes: string;
    inventoryItemId?: string;
  }>) => Promise<void>;
}) {
  const [error, setError] = useState<string | null>(null);
  const branchInventoryItems = inventoryItems.filter((item) => item.branchId === order.branchId);
  const [lines, setLines] = useState<Record<string, ReceiptDraft>>(() =>
    Object.fromEntries((order.items ?? []).map((item) => [item.id, {
      deliveredQuantity: '',
      damagedQuantity: '',
      closeRemainingAsShort: false,
      notes: '',
      inventoryItemId: undefined,
    }])),
  );

  const remaining = (item: PurchaseOrderItem) => Math.max(
    0,
    item.quantity - item.receivedQuantity - item.damagedQuantity - item.shortageQuantity,
  );

  function updateLine(id: string, patch: Partial<ReceiptDraft>) {
    setLines((current) => ({ ...current, [id]: { ...current[id], ...patch } }));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (!order.items?.length) {
      setError('This purchase order has no item details to receive.');
      return;
    }
    const payload = order.items.map((item) => ({
      purchaseOrderItemId: item.id,
      deliveredQuantity: Number(lines[item.id]?.deliveredQuantity || 0),
      damagedQuantity: Number(lines[item.id]?.damagedQuantity || 0),
      closeRemainingAsShort: lines[item.id]?.closeRemainingAsShort ?? false,
      notes: lines[item.id]?.notes.trim() ?? '',
      inventoryItemId: item.inventoryItemId ?? lines[item.id]?.inventoryItemId,
    }));
    const changed = payload.some((line) =>
      line.deliveredQuantity > 0 || line.closeRemainingAsShort,
    );
    if (!changed) {
      setError('Enter a delivered quantity or confirm a remaining shortage for at least one item.');
      return;
    }
    const invalid = payload.find((line) =>
      line.deliveredQuantity < 0 ||
      line.damagedQuantity < 0 ||
      line.damagedQuantity > line.deliveredQuantity,
    );
    if (invalid) {
      setError('Quantities must be zero or greater, and damaged units cannot exceed delivered units.');
      return;
    }
    const unlinkedAcceptedLine = payload.find((line) =>
      line.deliveredQuantity > line.damagedQuantity && !line.inventoryItemId,
    );
    if (unlinkedAcceptedLine) {
      setError('Choose a destination-branch inventory item for each accepted custom line.');
      return;
    }
    const exceeds = order.items.find((item) =>
      payload.find((line) => line.purchaseOrderItemId === item.id)!.deliveredQuantity > remaining(item),
    );
    if (exceeds) {
      setError(`Delivered quantity for ${exceeds.itemName ?? exceeds.description ?? 'an item'} exceeds its ${remaining(exceeds)} remaining units.`);
      return;
    }
    await onReceive(payload);
  }

  return (
    <div className="modal-overlay" onClick={saving ? undefined : onClose} role="presentation">
      <div className="modal modal-lg" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="receive-po-title">
        <div className="modal-head">
          <div>
            <h2 id="receive-po-title">Receive {order.number}</h2>
            <p>Only accepted units are added to inventory. Record shortages to close a line when no more delivery is expected.</p>
          </div>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close" disabled={saving}>×</button>
        </div>
        <form className="modal-body" onSubmit={(event) => void submit(event)}>
          {error && <p className="modal-error" role="alert">{error}</p>}
          <div className="po-items-section">
            <table className="po-items-table">
              <thead>
                <tr><th>Item</th><th>Ordered</th><th>Accepted so far</th><th>Remaining</th><th>Delivered now</th><th>Damaged now</th></tr>
              </thead>
              <tbody>
                {(order.items ?? []).map((item) => {
                  const left = remaining(item);
                  const line = lines[item.id] ?? {
                    deliveredQuantity: '',
                    damagedQuantity: '',
                    closeRemainingAsShort: false,
                    notes: '',
                  };
                  return (
                    <tr key={item.id}>
                      <td>{item.itemName ?? item.description ?? 'Unnamed item'}</td>
                      <td>{item.quantity}</td>
                      <td>{item.receivedQuantity}</td>
                      <td>{left}</td>
                      <td>
                        <input
                          aria-label={`Delivered now ${item.itemName ?? item.description ?? ''}`}
                          type="number"
                          min="0"
                          max={left}
                          step="0.001"
                          value={line.deliveredQuantity}
                          onChange={(event) => updateLine(item.id, { deliveredQuantity: event.target.value })}
                          disabled={saving || item.receivingClosed}
                        />
                      </td>
                      <td>
                        <input
                          aria-label={`Damaged now ${item.itemName ?? item.description ?? ''}`}
                          type="number"
                          min="0"
                          step="0.001"
                          value={line.damagedQuantity}
                          onChange={(event) => updateLine(item.id, { damagedQuantity: event.target.value })}
                          disabled={saving || item.receivingClosed}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {(order.items ?? []).map((item) => {
              const line = lines[item.id];
              if (!line || item.receivingClosed) return null;
              return (
                <div className="form-grid" key={`${item.id}-receipt-details`}>
                  {!item.inventoryItemId && (
                    <label className="form-field form-field-wide">
                      Inventory item to add accepted units to
                      <select
                        value={line.inventoryItemId ?? ''}
                        onChange={(event) => updateLine(item.id, { inventoryItemId: event.target.value || undefined })}
                        disabled={saving}
                        required={Number(line.deliveredQuantity) > Number(line.damagedQuantity)}
                      >
                        <option value="">Select destination-branch item</option>
                        {branchInventoryItems.map((inventoryItem) => (
                          <option key={inventoryItem.id} value={inventoryItem.id}>
                            {inventoryItem.name} ({inventoryItem.sku})
                          </option>
                        ))}
                      </select>
                    </label>
                  )}
                  <label className="form-field form-field-wide">
                    Notes for {item.itemName ?? item.description ?? 'item'}
                    <input
                      value={line.notes}
                      onChange={(event) => updateLine(item.id, { notes: event.target.value })}
                      placeholder="Optional condition / supplier notes"
                      disabled={saving}
                    />
                  </label>
                  <label className="form-field form-field-wide">
                    <span>
                      <input
                        type="checkbox"
                        checked={line.closeRemainingAsShort}
                        onChange={(event) => updateLine(item.id, { closeRemainingAsShort: event.target.checked })}
                        disabled={saving}
                      />{' '}
                      No more delivery expected; record the remaining {Math.max(0, remaining(item) - Number(line.deliveredQuantity || 0))} units as short
                    </span>
                  </label>
                </div>
              );
            })}
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Recording receipt…' : 'Record receipt and update stock'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export function PurchaseOrderManagerPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const { user } = useSelector((state: RootState) => state.auth);
  const canManagePurchaseOrders = user?.role === 'Admin' || user?.role === 'Manager';
  const canReceivePurchaseOrders = canManagePurchaseOrders || user?.role === 'Staff';
  const [searchParams] = useSearchParams();
  const [orders, setOrders] = useState<PurchaseOrder[]>([]);
  const [options, setOptions] = useState<PurchaseOrderOptionsResponse>({ branches: [], suppliers: [] });
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>(statusFilters[0]);
  const [supplierFilter, setSupplierFilter] = useState(() => searchParams.get('supplier') ?? 'All suppliers');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [page, setPage] = useState(1);
  const [statusSavingId, setStatusSavingId] = useState<string | null>(null);
  const [receivingOrder, setReceivingOrder] = useState<PurchaseOrder | null>(null);
  const reorderItemId = searchParams.get('reorderItemId') ?? undefined;
  const reorderBranchId = searchParams.get('branchId') ?? undefined;
  const requestedQuantity = Number(searchParams.get('quantity'));
  const reorderQuantity = Number.isFinite(requestedQuantity) && requestedQuantity > 0 ? requestedQuantity : undefined;

  const performer = user?.fullName ?? 'Staff';

  const loadOrders = useCallback(async (isActive: () => boolean = () => true) => {
    setLoading(true);
    setLoadError(null);
    try {
      const firstPage = await apiGet<PurchaseOrderListResponse>('/purchase-orders?page=1&pageSize=100', token);
      const remainingPages = await Promise.all(
        Array.from({ length: Math.max(0, firstPage.totalPages - 1) }, (_, index) =>
          apiGet<PurchaseOrderListResponse>(`/purchase-orders?page=${index + 2}&pageSize=100`, token),
        ),
      );
      const referenceData = await apiGet<PurchaseOrderOptionsResponse>('/purchase-orders/options', token)
        .catch(() => ({ branches: [], suppliers: [], items: [] }));
      if (!isActive()) return false;
      const loadedOrders = [firstPage, ...remainingPages]
        .flatMap((response) => response.items ?? [])
        .map((item) => responseToOrder(item));
      setOrders(loadedOrders);
      setOptions(referenceData);
      setSelectedId((current) => current && loadedOrders.some((order) => order.id === current) ? current : loadedOrders[0]?.id ?? null);
      if (canManagePurchaseOrders && reorderItemId && referenceData.items?.some((item) => item.id === reorderItemId)) setShowCreate(true);
      if (!referenceData.branches.length || !referenceData.suppliers.length) {
        setLoadError('Orders loaded, but branches or suppliers are unavailable. Refresh the data or add the missing records before creating an order.');
      }
      return true;
    } catch (error) {
      if (!isActive()) return false;
      const message = error instanceof Error ? error.message : 'Purchase orders could not be loaded.';
      setLoadError(message);
      notify(message, 'error');
      return false;
    } finally {
      if (isActive()) setLoading(false);
    }
  }, [canManagePurchaseOrders, notify, reorderItemId, token]);

  useEffect(() => {
    let active = true;
    void loadOrders(() => active);
    return () => { active = false; };
  }, [loadOrders]);

  const filtered = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    const apiStatus = filterStatusToApi(statusFilter);
    return orders.filter((order) => {
      const matchesQuery =
        queryLower === '' ||
        order.number.toLowerCase().includes(queryLower) ||
        order.supplier.toLowerCase().includes(queryLower) ||
        order.branch?.toLowerCase().includes(queryLower);
      const matchesStatus = apiStatus === null || order.status === apiStatus;
      const matchesSupplier = supplierFilter === 'All suppliers' || order.supplier === supplierFilter;
      return matchesQuery && matchesStatus && matchesSupplier;
    });
  }, [orders, query, statusFilter, supplierFilter]);
  const hasActiveFilters = query.trim() !== '' || statusFilter !== 'All statuses' || supplierFilter !== 'All suppliers';

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
    inTransit: orders.filter((order) => order.status === 'InTransit' || order.status === 'PartiallyReceived').length,
    received: orders.filter((order) => order.status === 'Received').length,
    value: orders.filter((order) => order.status !== 'Received' && order.status !== 'Cancelled').reduce((sum, order) => sum + order.amount, 0),
  }), [orders]);

  async function advanceStatus(order: PurchaseOrder) {
    if (!canManagePurchaseOrders || statusSavingId) return;
    const next = nextStatus(order.status);
    if (!next) return;

    const now = new Date().toISOString();
    const timelineEvent: TimelineEvent = { status: next, at: now, by: performer };

    setOrders((prev) => prev.map((candidate) => (
      candidate.id === order.id
        ? { ...candidate, status: next, updatedAt: now, timeline: [...candidate.timeline, timelineEvent] }
        : candidate
    )));

    try {
      setStatusSavingId(order.id);
      const updated = await apiPut<PurchaseOrderResponse>(`/purchase-orders/${order.id}/status`, token, { status: next });
      setOrders((prev) => prev.map((candidate) => candidate.id === order.id ? responseToOrder(updated, candidate) : candidate));
    } catch {
      setOrders((prev) => prev.map((candidate) => candidate.id === order.id ? order : candidate));
      notify(`Could not sync ${order.number}; no change was saved.`, 'error');
      return;
    } finally {
      setStatusSavingId(null);
    }
    notify(`${order.number} moved to ${statusLabels[next]}.`, 'success');
  }

  async function cancelOrder(order: PurchaseOrder) {
    if (!canManagePurchaseOrders || statusSavingId || order.status === 'Received' || order.status === 'Cancelled') return;
    const now = new Date().toISOString();
    const timelineEvent: TimelineEvent = { status: 'Cancelled', at: now, by: performer, note: 'Cancelled by user' };
    setOrders((prev) => prev.map((candidate) => (
      candidate.id === order.id
        ? { ...candidate, status: 'Cancelled', updatedAt: now, timeline: [...candidate.timeline, timelineEvent] }
        : candidate
    )));
    try {
      setStatusSavingId(order.id);
      const updated = await apiPut<PurchaseOrderResponse>(`/purchase-orders/${order.id}/status`, token, { status: 'Cancelled' });
      setOrders((prev) => prev.map((candidate) => candidate.id === order.id ? responseToOrder(updated, candidate) : candidate));
    } catch {
      setOrders((prev) => prev.map((candidate) => candidate.id === order.id ? order : candidate));
      notify(`Could not cancel ${order.number}; no change was saved.`, 'error');
      return;
    } finally {
      setStatusSavingId(null);
    }
    notify(`${order.number} was cancelled.`, 'info');
  }

  async function recordReceipt(order: PurchaseOrder, items: Array<{
    purchaseOrderItemId: string;
    deliveredQuantity: number;
    damagedQuantity: number;
    closeRemainingAsShort: boolean;
    notes: string;
    inventoryItemId?: string;
  }>) {
    if (!canReceivePurchaseOrders) return;
    setStatusSavingId(order.id);
    try {
      const updated = await apiPost<PurchaseOrderResponse>(
        `/purchase-orders/${order.id}/receive`,
        token,
        { items },
      );
      setOrders((current) => current.map((candidate) =>
        candidate.id === order.id ? responseToOrder(updated, candidate) : candidate,
      ));
      setReceivingOrder(null);
      notify(`${order.number} receipt recorded. Accepted quantities were added to stock.`, 'success');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'The receipt could not be recorded.';
      notify(message, 'error');
    } finally {
      setStatusSavingId(null);
    }
  }

  const [creating, setCreating] = useState(false);

  async function createOrder(draft: {
    branchId: string;
    supplierId: string;
    number: string;
    items: Array<{ inventoryItemId?: string; description?: string; quantity: number; unitPrice: number }>;
  }) {
    if (!canManagePurchaseOrders) return;
    const supplier = options.suppliers.find((option) => option.id === draft.supplierId);
    const branch = options.branches.find((option) => option.id === draft.branchId);
    if (!supplier || !branch) {
      notify('Select a valid branch and supplier before creating a purchase order.', 'error');
      return;
    }
    const now = new Date().toISOString();
    const totalAmount = draft.items.reduce((sum, i) => sum + i.quantity * i.unitPrice, 0);
    const created: PurchaseOrder = {
      id: '',
      number: draft.number,
      supplier: supplier.name,
      branchId: branch.id,
      branch: branch.name,
      status: 'Draft',
      amount: totalAmount,
      lineItems: draft.items.length,
      createdAt: now,
      updatedAt: now,
      timeline: [{ status: 'Draft', at: now, by: performer }],
      items: draft.items.map((i, idx) => ({
        id: `temp-${idx}`,
        inventoryItemId: i.inventoryItemId,
        itemName: options.items?.find((inv) => inv.id === i.inventoryItemId)?.name ?? i.description,
        description: i.description,
        quantity: i.quantity,
        unitPrice: i.unitPrice,
        lineTotal: i.quantity * i.unitPrice,
        receivedQuantity: 0,
        damagedQuantity: 0,
        shortageQuantity: 0,
        receivingClosed: false,
      })),
    };
    setCreating(true);
    try {
      const response = await apiPost<PurchaseOrderResponse>('/purchase-orders', token, {
        branchId: draft.branchId,
        supplierId: draft.supplierId,
        number: draft.number,
        status: 'Draft',
        items: draft.items,
      });
      const liveOrder = responseToOrder(response, created);
      setOrders((prev) => [liveOrder, ...prev]);
      setSelectedId(liveOrder.id);
      setShowCreate(false);
      notify(`Purchase order ${draft.number} was created successfully with ${draft.items.length} line items (Total: ${formatPrice(totalAmount)}).`, 'success');
    } catch (err: any) {
      console.error(err);
      notify(`Could not create ${draft.number}: ${err?.message || 'Check connection'}`, 'error');
    } finally {
      setCreating(false);
    }
  }

  const rangeStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div className="page purchase-orders-page">
      <header className="purchase-orders-hero">
        <div className="purchase-orders-hero-copy">
          <p className="purchase-orders-eyebrow"><span aria-hidden="true">↗</span> INVENTORY / PROCUREMENT</p>
          <h1>Purchase orders</h1>
          <p>Coordinate suppliers, branches, and incoming stock from one order workspace.</p>
          <div className="purchase-orders-live"><span className={loading ? 'is-loading' : ''} aria-hidden="true" />{loading ? 'Syncing purchase orders…' : `${stats.open} open orders · ${stats.received} received`}</div>
        </div>
        <div className="purchase-orders-hero-art" aria-hidden="true"><span className="purchase-orders-art-ring" /><span className="purchase-orders-art-icon">▤</span><i /><i /><i /></div>
        <div className="purchase-orders-hero-actions">
          <button className="btn purchase-orders-refresh" type="button" onClick={() => { void loadOrders().then((ok) => { if (ok) notify('Purchase order data refreshed.', 'success'); }); }} disabled={loading}><span aria-hidden="true">↻</span>{loading ? 'Refreshing…' : 'Refresh data'}</button>
          {canManagePurchaseOrders && <button className="btn purchase-orders-create" type="button" onClick={() => setShowCreate(true)} disabled={!options.branches.length || !options.suppliers.length}>＋ Create order</button>}
        </div>
      </header>

      {loadError && !loading && (
        <p className="page-banner">{loadError}</p>
      )}

      <section className="stat-strip purchase-orders-stat-strip" aria-label="Purchase order summary">
        <article className="stat metric-card purchase-order-metric purchase-order-metric-total"><div className="purchase-order-metric-main"><span className="purchase-order-metric-icon" aria-hidden="true">▤</span><div><span className="purchase-order-kicker">ORDER BOOK</span><strong>{stats.total}</strong><small>Total purchase orders</small></div></div><div className="purchase-order-metric-detail">{stats.received} completed and received</div></article>
        <article className="stat metric-card purchase-order-metric purchase-order-metric-open"><div className="purchase-order-metric-main"><span className="purchase-order-metric-icon" aria-hidden="true">◷</span><div><span className="purchase-order-kicker">IN PROGRESS</span><strong>{stats.open}</strong><small>Open orders</small></div></div><div className="purchase-order-metric-detail">Draft through in transit</div></article>
        <article className="stat metric-card purchase-order-metric purchase-order-metric-transit"><div className="purchase-order-metric-main"><span className="purchase-order-metric-icon" aria-hidden="true">⇢</span><div><span className="purchase-order-kicker">ON THE WAY</span><strong>{stats.inTransit}</strong><small>In transit</small></div></div><div className="purchase-order-metric-detail">Awaiting branch receipt</div></article>
        <article className="stat metric-card purchase-order-metric purchase-order-metric-value"><div className="purchase-order-metric-main"><span className="purchase-order-metric-icon" aria-hidden="true">LKR</span><div><span className="purchase-order-kicker">OPEN COMMITMENT</span><strong className="purchase-order-value">{formatPrice(stats.value)}</strong><small>Open order value</small></div></div><div className="purchase-order-metric-detail">Excludes received and cancelled orders</div></article>
      </section>

      <div className="po-layout purchase-orders-layout">
        <section className="panel po-list-panel">
          <div className="purchase-orders-panel-head"><div><span className="purchase-orders-panel-icon" aria-hidden="true">▤</span><div><h2>Order register</h2><p>Search orders, filter status, and select one to see its details.</p></div></div><span className="purchase-orders-count">{filtered.length} shown</span></div>
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
              {options.suppliers.map((option) => <option key={option.id}>{option.name}</option>)}
            </select>
            {hasActiveFilters && <button className="btn purchase-orders-clear" type="button" onClick={() => { setQuery(''); setStatusFilter('All statuses'); setSupplierFilter('All suppliers'); }}>Clear filters</button>}
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
                    onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); setSelectedId(order.id); } }}
                    tabIndex={0}
                    aria-selected={order.id === selectedId}
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
                {loading && orders.length === 0 && <tr><td colSpan={5} className="empty-state">Loading purchase orders…</td></tr>}
                {paged.length === 0 && !loading && (
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
              <div className="po-print-heading">
                <div>
                  <span>UNIFY · PROCUREMENT</span>
                  <h1>Purchase order</h1>
                </div>
                <strong>{selected.number}</strong>
              </div>
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
                  {selected.status === 'InReview' && !canManagePurchaseOrders ? (
                    <p className="cell-sub" role="status">
                      Awaiting approval by a Manager or Admin.
                    </p>
                  ) : canManagePurchaseOrders && nextStatus(selected.status) ? (
                    <button type="button" className="btn btn-primary" onClick={() => advanceStatus(selected)} disabled={statusSavingId !== null}>
                      {statusSavingId === selected.id
                        ? 'Saving…'
                        : selected.status === 'InReview'
                          ? 'Approve & place order'
                          : `Advance to ${statusLabels[nextStatus(selected.status)!]}`}
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() => window.print()}
                    title="Print purchase order or save as PDF"
                  >
                    🖨️ Print PO
                  </button>
                  {canReceivePurchaseOrders && ['InTransit', 'PartiallyReceived'].includes(selected.status) && (
                    <button
                      type="button"
                      className="btn btn-primary"
                      onClick={() => setReceivingOrder(selected)}
                      disabled={statusSavingId !== null}
                    >
                      {statusSavingId === selected.id ? 'Saving…' : 'Receive items'}
                    </button>
                  )}
                  {canManagePurchaseOrders && selected.status !== 'Received' && selected.status !== 'Cancelled' && (
                    <button type="button" className="btn btn-secondary" onClick={() => cancelOrder(selected)} disabled={statusSavingId !== null}>{statusSavingId === selected.id ? 'Saving…' : 'Cancel PO'}</button>
                  )}
                </div>
                {selected.receipts && selected.receipts.length > 0 && (
                  <div className="timeline-section">
                    <h3>Receiving history</h3>
                    <ol className="status-timeline">
                      {selected.receipts.map((receipt) => (
                        <li key={receipt.id}>
                          <div className="timeline-marker" aria-hidden="true" />
                          <div className="timeline-content">
                            <div className="timeline-head">
                              <Badge tone="green">Receipt</Badge>
                              <span className="cell-sub">{formatDateTime(receipt.receivedAt)}</span>
                            </div>
                            <p className="timeline-user">Recorded by {receipt.receivedBy}</p>
                            {receipt.items.map((item) => (
                              <p className="timeline-note" key={`${receipt.id}-${item.purchaseOrderItemId}`}>
                                Delivered {item.deliveredQuantity}; accepted {item.acceptedQuantity}; damaged {item.damagedQuantity}; short {item.shortageQuantity}
                                {item.notes ? ` · ${item.notes}` : ''}
                              </p>
                            ))}
                          </div>
                        </li>
                      ))}
                    </ol>
                  </div>
                )}

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
                {selected.items && selected.items.length > 0 && (
                  <div className="po-detail-items">
                    <h3>Line items</h3>
                    <table className="po-detail-items-table">
                      <thead>
                        <tr><th>Item / Description</th><th className="num">Ordered</th><th className="num">Accepted</th><th className="num">Damaged</th><th className="num">Short</th><th className="num">Unit price</th><th className="num">Line total</th></tr>
                      </thead>
                      <tbody>
                        {selected.items.map((item) => (
                          <tr key={item.id}>
                            <td>{item.itemName || item.description || 'Unnamed item'}</td>
                            <td className="num">{item.quantity.toLocaleString()}</td>
                            <td className="num">{item.receivedQuantity.toLocaleString()}</td>
                            <td className="num">{item.damagedQuantity.toLocaleString()}</td>
                            <td className="num">{item.shortageQuantity.toLocaleString()}</td>
                            <td className="num">{formatPrice(item.unitPrice)}</td>
                            <td className="num">{formatPrice(item.lineTotal)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
                <div className="po-print-total"><span>Order total</span><strong>{formatPrice(selected.amount)}</strong></div>
                <div className="po-print-signatures" aria-hidden="true">
                  <span>Prepared by</span><span>Authorized by</span><span>Received by</span>
                </div>
                <p className="po-print-note">Generated from the Unify inventory workspace. Please verify quantities at delivery.</p>
              </div>
            </>
          ) : (
            <div className="po-detail-empty">
              <p>Select a purchase order to view its lifecycle tracker.</p>
            </div>
          )}
        </aside>
      </div>

      {showCreate && (
        <CreatePoModal
          onClose={() => setShowCreate(false)}
          onCreate={createOrder}
          branches={options.branches}
          suppliers={options.suppliers}
          inventoryItems={options.items ?? []}
          defaultNumber={nextPoNumber(orders)}
          defaultBranchId={reorderBranchId ?? user?.branchId}
          initialInventoryItemId={reorderItemId}
          initialQuantity={reorderQuantity}
          creating={creating}
        />
      )}
      {receivingOrder && (
        <ReceivePoModal
          order={receivingOrder}
          inventoryItems={options.items ?? []}
          saving={statusSavingId === receivingOrder.id}
          onClose={() => setReceivingOrder(null)}
          onReceive={(items) => recordReceipt(receivingOrder, items)}
        />
      )}
    </div>
  );
}
