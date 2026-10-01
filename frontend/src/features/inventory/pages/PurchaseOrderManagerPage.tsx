import { API_BASE_URL } from '../../../api/apiBaseUrl';
import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../../store/store';
import { getStoredToken } from '../authToken';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';

type POStatus = 'Draft' | 'InReview' | 'Placed' | 'InTransit' | 'PartiallyReceived' | 'Received' | 'Rejected' | 'Cancelled';

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
  photoUrls?: string[];
  items: Array<{
    purchaseOrderItemId: string;
    itemName?: string;
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
  unitCost?: number | null;
  branchId?: string | null;
  branchName?: string | null;
  supplierId?: string | null;
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
  Rejected: 'Rejected',
  Cancelled: 'Cancelled',
};

const statusTone: Record<POStatus, BadgeTone> = {
  Draft: 'slate',
  InReview: 'amber',
  Placed: 'violet',
  InTransit: 'blue',
  PartiallyReceived: 'amber',
  Received: 'green',
  Rejected: 'red',
  Cancelled: 'red',
};


const statusFilters = ['All statuses', ...lifecycleSteps.map((step) => statusLabels[step]), statusLabels.PartiallyReceived, statusLabels.Rejected, 'Cancelled'] as const;
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

async function apiUpload<T>(path: string, token: string | null, file: File): Promise<T> {
  const form = new FormData();
  form.append('file', file);
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
    body: form,
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
    return [body.message, validation].filter(Boolean).join(' ') || body.title || fallback;
  } catch {
    return fallback;
  }
}

function normalizeStatus(raw: string): POStatus {
  const cleaned = raw.replace(/\s|-/g, '');
  const match = (['Draft', 'InReview', 'Placed', 'InTransit', 'PartiallyReceived', 'Received', 'Rejected', 'Cancelled'] as const)
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
  if (current === 'Cancelled' || current === 'Rejected' || current === 'Received') return null;
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

function batchOrderBase(number: string) {
  return number.match(/^(.*)-(\d{2})$/)?.[1] ?? null;
}

function PurchaseOrderTimestamp({ value, dateOnly = false }: { value: string; dateOnly?: boolean }) {
  const label = dateOnly ? formatDate(value) : formatDateTime(value);
  return (
    <time className="purchase-order-timestamp" dateTime={value}>
      <span aria-hidden="true">{dateOnly ? '▦' : '◷'}</span>
      {label}
    </time>
  );
}

function LifecycleTracker({ status, compact = false }: { status: POStatus; compact?: boolean }) {
  if (status === 'Cancelled' || status === 'Rejected') {
    return <span className="lifecycle-cancelled">{statusLabels[status]}</span>;
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
  quantities: Record<string, number>;
  unitPrice: number;
};

function CreatePoModal({
  onClose,
  onCreate,
  canCreateMultiBranch,
  requiresReview,
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
  canCreateMultiBranch: boolean;
  requiresReview: boolean;
  onCreate: (draft: {
    branchOrders: Array<{
      branchId: string;
      items: Array<{ inventoryItemId?: string; description?: string; quantity: number; unitPrice: number }>;
    }>;
    supplierId: string;
    number: string;
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
  const initialBranchId = defaultBranchId && branches.some((branch) => branch.id === defaultBranchId)
    ? defaultBranchId
    : branches[0]?.id ?? '';
  const [selectedBranchIds, setSelectedBranchIds] = useState<string[]>(initialBranchId ? [initialBranchId] : []);
  const itemForReorder = inventoryItems.find((item) => item.id === initialInventoryItemId);
  const initialSupplierId = suppliers.some((supplier) => supplier.id === itemForReorder?.supplierId)
    ? itemForReorder!.supplierId!
    : suppliers[0]?.id ?? '';
  const [supplierId, setSupplierId] = useState(initialSupplierId);
  const [poNumber, setPoNumber] = useState(defaultNumber);
  const [error, setError] = useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);

  const supplierCatalogItems = inventoryItems.filter(
    (item) => item.supplierId === supplierId,
  );
  const initialItem = supplierCatalogItems.find((item) => item.id === initialInventoryItemId) ??
    supplierCatalogItems[0];
  const [items, setItems] = useState<PoItemDraft[]>([
    {
      inventoryItemId: initialItem?.id ?? '',
      description: initialItem?.name ?? '',
      quantities: Object.fromEntries(selectedBranchIds.map((id) => [
        id,
        initialQuantity && initialQuantity > 0 ? initialQuantity : 1,
      ])),
      unitPrice: initialItem?.unitCost ?? 0,
    },
  ]);

  function handleItemSelect(index: number, val: string) {
    setItems((prev) => {
      const copy = [...prev];
      if (val === 'custom') {
        copy[index] = { ...copy[index], inventoryItemId: '', description: copy[index].description || '' };
      } else {
        const found = supplierCatalogItems.find((inv) => inv.id === val);
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
    const nextItem = supplierCatalogItems[0];
    setItems((prev) => [
      ...prev,
      {
        inventoryItemId: nextItem?.id ?? '',
        description: nextItem?.name ?? '',
        quantities: Object.fromEntries(selectedBranchIds.map((id) => [id, 0])),
        unitPrice: nextItem?.unitCost ?? 0,
      },
    ]);
  }

  function changeBranches(branchId: string, checked: boolean) {
    setSelectedBranchIds((current) => checked
      ? current.includes(branchId) ? current : [...current, branchId]
      : current.filter((id) => id !== branchId));
  }

  function selectAllBranches() {
    setSelectedBranchIds(branches.map((branch) => branch.id));
    setItems((current) => current.map((item) => ({
      ...item,
      quantities: Object.fromEntries(branches.map((branch) => [
        branch.id,
        item.quantities[branch.id] || 1,
      ])),
    })));
  }

  function changeSupplier(nextSupplierId: string) {
    const nextSupplierItems = inventoryItems.filter(
      (item) => item.supplierId === nextSupplierId,
    );
    setSupplierId(nextSupplierId);
    setItems((current) => current.map((row) => {
      if (!row.inventoryItemId) return row;
      const replacement = nextSupplierItems[0];
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

  const grandTotal = items.reduce((sum, item) => {
    const quantity = selectedBranchIds.reduce((total, id) => total + (Number(item.quantities[id]) || 0), 0);
    return sum + quantity * (Number(item.unitPrice) || 0);
  }, 0);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    if (selectedBranchIds.length === 0) {
      setError('Select at least one destination branch.');
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
      if (item.inventoryItemId) {
        const catalogItem = supplierCatalogItems.find((candidate) => candidate.id === item.inventoryItemId);
        if (!catalogItem || catalogItem.unitCost == null) {
          setError(`Item #${i + 1} is not linked to this supplier or has no catalog unit cost.`);
          return;
        }
        if (Number(item.unitPrice) !== catalogItem.unitCost) {
          setError(`Item #${i + 1} price must match its catalog unit cost.`);
          return;
        }
      }
      for (const id of selectedBranchIds) {
        const quantity = Number(item.quantities[id]) || 0;
        if (quantity < 0) {
          setError(`Item #${i + 1} quantity cannot be negative.`);
          return;
        }
        if (!Number.isInteger(quantity)) {
          setError(`Item #${i + 1} quantity must be a whole number.`);
          return;
        }
      }
      if (Number(item.unitPrice) < 0) {
        setError(`Item #${i + 1} unit price cannot be negative.`);
        return;
      }
    }

    const branchOrders = selectedBranchIds.map((id) => ({
      branchId: id,
      items: items
        .filter((item) => (Number(item.quantities[id]) || 0) > 0)
        .map((item) => ({
          inventoryItemId: item.inventoryItemId || undefined,
          description: item.description.trim() || undefined,
          quantity: Number(item.quantities[id]),
          unitPrice: Number(item.unitPrice),
        })),
    }));
    const branchWithoutItems = branchOrders.find((order) => order.items.length === 0);
    if (branchWithoutItems) {
      const branchName = branches.find((branch) => branch.id === branchWithoutItems.branchId)?.name ?? 'Selected branch';
      setError(`Enter a quantity for at least one item for ${branchName}.`);
      return;
    }

    setConfirmOpen(true);
  }

  async function confirmCreate() {
    setConfirmOpen(false);
    await onCreate({
      branchOrders: selectedBranchIds.map((id) => ({
        branchId: id,
        items: items
          .filter((item) => (Number(item.quantities[id]) || 0) > 0)
          .map((item) => ({
            inventoryItemId: item.inventoryItemId || undefined,
            description: item.description.trim() || undefined,
            quantity: Number(item.quantities[id]),
            unitPrice: Number(item.unitPrice),
          })),
      })),
      supplierId,
      number: poNumber.trim(),
    });
  }

  return (
    <div className="modal-overlay" onClick={onClose} role="presentation">
      <div className="modal modal-lg po-create-modal" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="create-po-title">
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
            <div className="form-field form-field-wide">
              Destination branches
              <div className="po-branch-options" role="group" aria-label="Destination branches">
                {branches.map((branch) => (
                  <label key={branch.id} className={`po-branch-option${selectedBranchIds.includes(branch.id) ? ' is-selected' : ''}`}>
                    <input
                      type="checkbox"
                      checked={selectedBranchIds.includes(branch.id)}
                      onChange={(event) => changeBranches(branch.id, event.target.checked)}
                      aria-label={`Order for ${branch.name}`}
                      disabled={!canCreateMultiBranch}
                    />
                    <span>{branch.name}</span>
                  </label>
                ))}
              </div>
              <small className="po-branch-help">
                Any supplier catalog item can be ordered to the selected destinations. Each selected branch gets its own purchase order and stock receipt.
                {selectedBranchIds.length > 1 && ` Generated numbers: ${selectedBranchIds.map((_, index) => `${poNumber.trim() || 'PO'}-${String(index + 1).padStart(2, '0')}`).join(', ')}.`}
              </small>
              {canCreateMultiBranch && branches.length > 1 && (
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  onClick={selectAllBranches}
                  aria-label="Select all branches"
                >
                  Select all branches
                </button>
              )}
            </div>
            <label className="form-field form-field-wide">
              Supplier
              <select value={supplierId} onChange={(event) => changeSupplier(event.target.value)} required>
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

            <div className="po-items-table-wrap">
              <table className="po-items-table">
                <thead>
                  <tr>
                    <th>Item / Description</th>
                    {selectedBranchIds.map((id) => (
                      <th key={id}>{branches.find((branch) => branch.id === id)?.name ?? 'Branch'} qty</th>
                    ))}
                    <th>Unit Price (LKR)</th>
                    <th>Subtotal</th>
                    <th className="cell-action"></th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((row, idx) => {
                    const lineQuantity = selectedBranchIds.reduce((sum, id) => sum + (Number(row.quantities[id]) || 0), 0);
                    const lineSubtotal = lineQuantity * (Number(row.unitPrice) || 0);
                    const isCustom = !row.inventoryItemId;

                    return (
                      <tr key={idx}>
                        <td>
                          <select
                            value={row.inventoryItemId || 'custom'}
                            onChange={(e) => handleItemSelect(idx, e.target.value)}
                            aria-label={`Inventory item for line ${idx + 1}`}
                            style={{ marginBottom: isCustom ? '0.35rem' : '0' }}
                          >
                            <option value="custom">-- Custom Description --</option>
                            {supplierCatalogItems.map((inv) => (
                              <option key={inv.id} value={inv.id}>
                                {inv.name} ({inv.sku})
                                {inv.branchName ? ` · from ${inv.branchName}` : ''}
                                {inv.unitCost == null ? ' · cost not set' : ''}
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
                        {selectedBranchIds.map((id) => {
                          const branchName = branches.find((branch) => branch.id === id)?.name ?? 'branch';
                          return (
                            <td key={id}>
                              <input
                                type="number"
                                min="0"
                                step="1"
                                value={row.quantities[id] ?? 0}
                                onChange={(event) => {
                                  const value = event.target.value;
                                  if (value !== '' && !/^\d+$/.test(value)) return;
                                  const quantity = Number(value) || 0;
                                  setItems((prev) => prev.map((item, itemIndex) => itemIndex === idx
                                    ? { ...item, quantities: { ...item.quantities, [id]: quantity } }
                                    : item));
                                }}
                                aria-label={`Quantity for ${branchName}, line ${idx + 1}`}
                              />
                            </td>
                          );
                        })}
                        <td>
                          <input
                            type="number"
                            min={0}
                            step="0.01"
                            value={row.unitPrice}
                            onChange={(e) => handleFieldChange(idx, 'unitPrice', Number(e.target.value))}
                            readOnly={!isCustom}
                            aria-label={`Unit price for line ${idx + 1}${isCustom ? '' : ' (catalog locked)'}`}
                            title={isCustom ? 'Custom line price' : 'Catalog unit cost is locked'}
                            required
                          />
                        </td>
                        <td className="po-line-subtotal">LKR {lineSubtotal.toLocaleString()}</td>
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
            </div>

            <div className="po-total-row">
              <span>Total Order Value ({items.length} {items.length === 1 ? 'item' : 'items'}):</span>
              <span style={{ fontSize: '1.05rem', color: 'var(--color-primary)' }}>
                LKR {grandTotal.toLocaleString()}
              </span>
            </div>
            {confirmOpen && (
              <ConfirmDialog
                title={`Create ${selectedBranchIds.length} purchase order${selectedBranchIds.length === 1 ? '' : 's'}?`}
                message={requiresReview
                  ? `Submit ${poNumber.trim()} for ${formatPrice(grandTotal)} to Manager or Admin review?`
                  : `Create separate branch orders from ${poNumber.trim()} for ${formatPrice(grandTotal)} across ${selectedBranchIds.length} branch${selectedBranchIds.length === 1 ? '' : 'es'}? Each branch order will be saved as Draft.`}
                confirmLabel={requiresReview
                  ? `Submit ${selectedBranchIds.length} order${selectedBranchIds.length === 1 ? '' : 's'}`
                  : `Create ${selectedBranchIds.length} order${selectedBranchIds.length === 1 ? '' : 's'}`}
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
  acceptedQuantity: string;
  damagedQuantity: string;
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
    acceptedQuantity: number;
    damagedQuantity: number;
    closeRemainingAsShort: boolean;
    notes: string;
    inventoryItemId?: string;
  }>, photos: File[]) => Promise<void>;
}) {
  const [error, setError] = useState<string | null>(null);
  const [photos, setPhotos] = useState<File[]>([]);
  const branchInventoryItems = inventoryItems.filter((item) => item.branchId === order.branchId);
  const [lines, setLines] = useState<Record<string, ReceiptDraft>>(() =>
    Object.fromEntries((order.items ?? []).map((item) => [item.id, {
      acceptedQuantity: '',
      damagedQuantity: '',
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
      acceptedQuantity: Number(lines[item.id]?.acceptedQuantity || 0),
      damagedQuantity: Number(lines[item.id]?.damagedQuantity || 0),
      closeRemainingAsShort: false,
      notes: lines[item.id]?.notes.trim() ?? '',
      inventoryItemId: item.inventoryItemId ?? lines[item.id]?.inventoryItemId,
    }));
    const changed = payload.some((line) =>
      line.acceptedQuantity > 0 || line.damagedQuantity > 0,
    );
    if (!changed) {
      setError('Enter an accepted or damaged quantity, or confirm a remaining shortage for at least one item.');
      return;
    }
    if (payload.some((line) =>
      !Number.isInteger(line.acceptedQuantity) ||
      !Number.isInteger(line.damagedQuantity),
    )) {
      setError('Accepted and damaged quantities must be whole numbers.');
      return;
    }
    const invalid = payload.find((line) => {
      const item = order.items?.find((candidate) => candidate.id === line.purchaseOrderItemId);
      return line.acceptedQuantity < 0 ||
        line.damagedQuantity < 0 ||
        !item ||
        line.acceptedQuantity + line.damagedQuantity > remaining(item);
    });
    if (invalid) {
      setError('Accepted plus damaged units cannot exceed the remaining ordered quantity.');
      return;
    }
    const unlinkedAcceptedLine = payload.find((line) =>
      line.acceptedQuantity > 0 && !line.inventoryItemId,
    );
    if (unlinkedAcceptedLine) {
      setError('Choose a destination-branch inventory item for each accepted custom line.');
      return;
    }
    await onReceive(payload, photos);
  }

  return (
    <div className="modal-overlay" onClick={saving ? undefined : onClose} role="presentation">
      <div className="modal modal-lg" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="receive-po-title">
        <div className="modal-head">
          <div>
            <h2 id="receive-po-title">Receive {order.number}</h2>
            <p>Only accepted units are added to inventory. Any remaining units stay open for a later delivery.</p>
          </div>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close" disabled={saving}>×</button>
        </div>
        <form className="modal-body" onSubmit={(event) => void submit(event)}>
          {error && <p className="modal-error" role="alert">{error}</p>}
          <div className="po-items-section">
            <table className="po-items-table">
              <thead>
                <tr><th>Item</th><th>Ordered</th><th>Accepted so far</th><th>Still due after this delivery</th><th>Accepted now (good)</th><th>Damaged now</th></tr>
              </thead>
              <tbody>
                {(order.items ?? []).map((item) => {
                  const left = remaining(item);
                  const line = lines[item.id] ?? {
                    acceptedQuantity: '',
                    damagedQuantity: '',
                    notes: '',
                  };
                  const remainingAfterDelivery = Math.max(
                    0,
                    left -
                      (Number(line.acceptedQuantity) || 0) -
                      (Number(line.damagedQuantity) || 0),
                  );
                  return (
                    <tr key={item.id}>
                      <td>{item.itemName ?? item.description ?? 'Unnamed item'}</td>
                      <td>{item.quantity}</td>
                      <td>{item.receivedQuantity}</td>
                      <td className="po-receiving-remaining" aria-label={`Remaining after this delivery for ${item.itemName ?? item.description ?? 'item'}`}>
                        <strong>{remainingAfterDelivery}</strong>
                        <small>of {left} remaining before this delivery</small>
                      </td>
                      <td>
                        <input
                          aria-label={`Accepted now ${item.itemName ?? item.description ?? ''}`}
                          type="number"
                          min="0"
                          max={Math.max(0, left - Number(line.damagedQuantity || 0))}
                          step="1"
                          value={line.acceptedQuantity}
                          onChange={(event) => {
                            const value = event.target.value;
                            if (value === '' || /^\d+$/.test(value)) {
                              updateLine(item.id, { acceptedQuantity: value });
                            }
                          }}
                          disabled={saving || item.receivingClosed}
                        />
                      </td>
                      <td>
                        <input
                          aria-label={`Damaged now ${item.itemName ?? item.description ?? ''}`}
                          type="number"
                          min="0"
                          max={Math.max(0, left - Number(line.acceptedQuantity || 0))}
                          step="1"
                          value={line.damagedQuantity}
                          onChange={(event) => {
                            const value = event.target.value;
                            if (value === '' || /^\d+$/.test(value)) {
                              updateLine(item.id, { damagedQuantity: value });
                            }
                          }}
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
                        required={Number(line.acceptedQuantity) > 0}
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
                      maxLength={1000}
                      onChange={(event) => updateLine(item.id, { notes: event.target.value })}
                      placeholder="Optional condition / supplier notes"
                      disabled={saving}
                    />
                  </label>
                </div>
              );
            })}
            <label className="form-field form-field-wide">
              Optional delivery photos (up to 5, JPEG/PNG/WebP, 5 MB each)
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                multiple
                onChange={(event) => {
                  const selected = Array.from(event.target.files ?? []);
                  if (selected.length + photos.length > 5) {
                    setError('A receipt can have at most five photos.');
                    event.target.value = '';
                    return;
                  }
                  if (selected.some((file) => file.size > 5 * 1024 * 1024)) {
                    setError('Each receipt photo must be 5 MB or smaller.');
                    event.target.value = '';
                    return;
                  }
                  setError(null);
                  setPhotos((current) => [...current, ...selected]);
                  event.target.value = '';
                }}
                disabled={saving || photos.length >= 5}
              />
              {photos.length > 0 && (
                <span>{photos.map((photo) => photo.name).join(', ')}</span>
              )}
            </label>
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
  const canCreatePurchaseOrders = canManagePurchaseOrders || user?.role === 'Staff';
  const canCreateMultiBranchPurchaseOrders = user?.role === 'Admin';
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
      if (canCreatePurchaseOrders && reorderItemId && referenceData.items?.some((item) => item.id === reorderItemId)) setShowCreate(true);
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
  }, [canCreatePurchaseOrders, canManagePurchaseOrders, notify, reorderItemId, token]);

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
  const groupedOrdersById = useMemo(() => {
    const groups = new Map<string, PurchaseOrder[]>();
    for (const order of orders) {
      const base = batchOrderBase(order.number);
      if (!base) continue;
      const key = `${base}|${order.supplier}|${order.createdAt.slice(0, 10)}`;
      groups.set(key, [...(groups.get(key) ?? []), order]);
    }
    const grouped = new Map<string, PurchaseOrder[]>();
    for (const group of groups.values()) {
      if (group.length < 2) continue;
      const orderedGroup = [...group].sort((left, right) =>
        left.number.localeCompare(right.number, undefined, { numeric: true }));
      for (const order of orderedGroup) grouped.set(order.id, orderedGroup);
    }
    return grouped;
  }, [orders]);
  const selectedOrderGroup = selected ? groupedOrdersById.get(selected.id) ?? [] : [];

  const stats = useMemo(() => ({
    total: orders.length,
    open: orders.filter((order) => !['Received', 'Rejected', 'Cancelled'].includes(order.status)).length,
    inTransit: orders.filter((order) => order.status === 'InTransit' || order.status === 'PartiallyReceived').length,
    received: orders.filter((order) => order.status === 'Received').length,
    value: orders.filter((order) => !['Received', 'Rejected', 'Cancelled'].includes(order.status)).reduce((sum, order) => sum + order.amount, 0),
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
    if (!canManagePurchaseOrders || statusSavingId || order.status === 'Received' || order.status === 'Rejected' || order.status === 'Cancelled') return;
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

  async function rejectOrder(order: PurchaseOrder) {
    if (!canManagePurchaseOrders || statusSavingId || order.status !== 'InReview') return;
    setStatusSavingId(order.id);
    try {
      const updated = await apiPut<PurchaseOrderResponse>(
        `/purchase-orders/${order.id}/status`,
        token,
        { status: 'Rejected' },
      );
      setOrders((prev) => prev.map((candidate) =>
        candidate.id === order.id
          ? responseToOrder(updated, {
            ...candidate,
            timeline: [...candidate.timeline, {
              status: 'Rejected',
              at: updated.updatedAt,
              by: performer,
              note: 'Rejected by reviewer',
            }],
          })
          : candidate,
      ));
      notify(`${order.number} was rejected.`, 'success');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'The purchase order could not be rejected.';
      notify(message, 'error');
    } finally {
      setStatusSavingId(null);
    }
  }

  async function recordReceipt(order: PurchaseOrder, items: Array<{
    purchaseOrderItemId: string;
    acceptedQuantity: number;
    damagedQuantity: number;
    closeRemainingAsShort: boolean;
    notes: string;
    inventoryItemId?: string;
  }>, photos: File[]) {
    if (!canReceivePurchaseOrders) return;
    setStatusSavingId(order.id);
    let receiptSaved = false;
    try {
      const updated = await apiPost<PurchaseOrderResponse>(
        `/purchase-orders/${order.id}/receive`,
        token,
        { items },
      );
      receiptSaved = true;
      let updatedWithPhotos = updated;
      if (photos.length > 0) {
        const receiptId = updated.receipts?.[0]?.id;
        if (!receiptId) {
          throw new Error('The receipt was saved, but the API did not return a receipt ID for its photos.');
        }
        let photoUrls: string[] = [];
        for (const photo of photos) {
          const uploaded = await apiUpload<{ photoUrls: string[] }>(
            `/purchase-orders/${order.id}/receipts/${receiptId}/photos`,
            token,
            photo,
          );
          photoUrls = uploaded.photoUrls;
        }
        updatedWithPhotos = {
          ...updated,
          receipts: (updated.receipts ?? []).map((receipt) =>
            receipt.id === receiptId ? { ...receipt, photoUrls } : receipt,
          ),
        };
      }
      setOrders((current) => current.map((candidate) =>
        candidate.id === order.id ? responseToOrder(updatedWithPhotos, candidate) : candidate,
      ));
      setReceivingOrder(null);
      notify(`${order.number} receipt recorded. Accepted quantities were added to stock${photos.length === 0 ? '' : ` and ${photos.length} photos attached`}.`, 'success');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'The receipt could not be recorded.';
      notify(receiptSaved ? `Receipt saved, but photo evidence could not be attached. ${message}` : message, 'error');
    } finally {
      setStatusSavingId(null);
    }
  }

  const [creating, setCreating] = useState(false);

  async function createOrder(draft: {
    branchOrders: Array<{
      branchId: string;
      items: Array<{ inventoryItemId?: string; description?: string; quantity: number; unitPrice: number }>;
    }>;
    supplierId: string;
    number: string;
  }) {
    if (!canCreatePurchaseOrders || (!canCreateMultiBranchPurchaseOrders && draft.branchOrders.length !== 1)) return;
    const supplier = options.suppliers.find((option) => option.id === draft.supplierId);
    const selectedBranches = draft.branchOrders.map((order) =>
      options.branches.find((option) => option.id === order.branchId));
    if (!supplier || selectedBranches.some((branch) => !branch)) {
      notify('Select valid destination branches and a supplier before creating purchase orders.', 'error');
      return;
    }
    const now = new Date().toISOString();
    const fallbacks = draft.branchOrders.map((branchOrder, branchIndex): PurchaseOrder => {
      const branch = selectedBranches[branchIndex]!;
      const totalAmount = branchOrder.items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);
      return {
        id: '',
        number: draft.branchOrders.length === 1 ? draft.number : `${draft.number}-${String(branchIndex + 1).padStart(2, '0')}`,
        supplier: supplier.name,
        branchId: branch.id,
        branch: branch.name,
        status: canManagePurchaseOrders ? 'Draft' : 'InReview',
        amount: totalAmount,
        lineItems: branchOrder.items.length,
        createdAt: now,
        updatedAt: now,
        timeline: [{ status: canManagePurchaseOrders ? 'Draft' : 'InReview', at: now, by: performer }],
        items: branchOrder.items.map((item, itemIndex) => ({
          id: `temp-${branchIndex}-${itemIndex}`,
          inventoryItemId: item.inventoryItemId,
          itemName: options.items?.find((inventoryItem) => inventoryItem.id === item.inventoryItemId)?.name ?? item.description,
          description: item.description,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          lineTotal: item.quantity * item.unitPrice,
          receivedQuantity: 0,
          damagedQuantity: 0,
          shortageQuantity: 0,
          receivingClosed: false,
        })),
      };
    });
    setCreating(true);
    try {
      const responses = draft.branchOrders.length === 1
        ? [await apiPost<PurchaseOrderResponse>('/purchase-orders', token, {
          branchId: draft.branchOrders[0].branchId,
          supplierId: draft.supplierId,
          number: draft.number,
          status: 'Draft',
          items: draft.branchOrders[0].items,
        })]
        : await apiPost<PurchaseOrderResponse[]>('/purchase-orders/batch', token, {
          number: draft.number,
          supplierId: draft.supplierId,
          branchOrders: draft.branchOrders,
        });
      if (responses.length !== draft.branchOrders.length) {
        throw new Error('The server did not return an order for every selected branch.');
      }
      const liveOrders = responses.map((response, index) => responseToOrder(response, fallbacks[index]));
      setOrders((prev) => [...liveOrders, ...prev]);
      setSelectedId(liveOrders[0]?.id ?? null);
      setShowCreate(false);
      const totalAmount = liveOrders.reduce((sum, order) => sum + order.amount, 0);
      notify(
        user?.role === 'Staff'
          ? `${liveOrders[0].number} submitted for Manager or Admin review.`
          : `${liveOrders.length} purchase order${liveOrders.length === 1 ? '' : 's'} created successfully for ${selectedBranches.map((branch) => branch!.name).join(', ')} (Total: ${formatPrice(totalAmount)}).`,
        'success',
      );
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
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="purchase-orders-hero-copy">
          <p className="purchase-orders-eyebrow"><span aria-hidden="true">↗</span> INVENTORY / PROCUREMENT</p>
          <h1>Purchase orders</h1>
          <p>Coordinate suppliers, branches, and incoming stock from one order workspace.</p>
          <div className="purchase-orders-live"><span className={loading ? 'is-loading' : ''} aria-hidden="true" />{loading ? 'Syncing purchase orders…' : `${stats.open} open orders · ${stats.received} received`}</div>
        </div>
        <div className="purchase-orders-hero-art" aria-hidden="true"><span className="purchase-orders-art-ring" /><span className="purchase-orders-art-icon">▤</span><i /><i /><i /></div>
        <div className="purchase-orders-hero-actions">
          <button className="btn purchase-orders-refresh" type="button" onClick={() => { void loadOrders().then((ok) => { if (ok) notify('Purchase order data refreshed.', 'success'); }); }} disabled={loading}><span aria-hidden="true">↻</span>{loading ? 'Refreshing…' : 'Refresh data'}</button>
          {canCreatePurchaseOrders && <button className="btn purchase-orders-create" type="button" onClick={() => setShowCreate(true)} disabled={!options.branches.length || !options.suppliers.length}>＋ Create order</button>}
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

          <div className="table-wrap purchase-orders-register-wrap">
            <table className="data-table purchase-orders-register-table">
              <thead>
                <tr><th>PO</th><th>Supplier</th><th>Amount</th><th>Status</th><th>Lifecycle</th></tr>
              </thead>
              <tbody>
                {paged.map((order) => {
                  const group = groupedOrdersById.get(order.id) ?? [];
                  const groupBase = batchOrderBase(order.number);
                  return (
                  <tr
                    key={order.id}
                    className={`${order.id === selectedId ? 'row-selected ' : ''}${group.length > 1 ? 'purchase-order-grouped-row' : ''}`}
                    onClick={() => setSelectedId(order.id)}
                    onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); setSelectedId(order.id); } }}
                    tabIndex={0}
                    aria-selected={order.id === selectedId}
                  >
                    <td>
                      <p className="po-number">{order.number}</p>
                      <div className="purchase-order-register-meta">
                        {group.length > 1 && <span>Group {groupBase}</span>}
                        <PurchaseOrderTimestamp value={order.createdAt} dateOnly />
                      </div>
                    </td>
                    <td>
                      <p className="cell-title">{order.supplier}</p>
                      <p className="cell-sub">{order.branch ?? '—'}</p>
                    </td>
                    <td className="amount">{formatPrice(order.amount)}</td>
                    <td><Badge tone={statusTone[order.status]}>{statusLabels[order.status]}</Badge></td>
                    <td><LifecycleTracker status={order.status} compact /></td>
                  </tr>
                  );
                })}
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
                {selectedOrderGroup.length > 1 && (
                  <section
                    className="purchase-order-group-card"
                    aria-label={`Grouped purchase request ${batchOrderBase(selected.number)}`}
                  >
                    <div className="purchase-order-group-heading">
                      <div>
                        <span className="purchase-order-group-kicker">ONE REQUEST · BRANCH-SPECIFIC ORDERS</span>
                        <h3>{batchOrderBase(selected.number)}</h3>
                      </div>
                      <strong>{formatPrice(selectedOrderGroup.reduce((sum, order) => sum + order.amount, 0))}</strong>
                    </div>
                    <p>Each branch order has its own status and receipt, so record each delivery separately.</p>
                    <div className="purchase-order-group-branches" aria-label="Branch orders in this request">
                      {selectedOrderGroup.map((order, index) => (
                        <button
                          key={order.id}
                          type="button"
                          className={`purchase-order-group-branch${order.id === selected.id ? ' is-selected' : ''}`}
                          aria-pressed={order.id === selected.id}
                          onClick={() => setSelectedId(order.id)}
                        >
                          <span>{order.branch ?? `Branch ${index + 1}`}</span>
                          <strong>{statusLabels[order.status]}</strong>
                          <small>{formatPrice(order.amount)}</small>
                        </button>
                      ))}
                    </div>
                  </section>
                )}
                <LifecycleTracker status={selected.status} />

                <dl className="detail-grid">
                  <div><dt>Amount</dt><dd>{formatPrice(selected.amount)}</dd></div>
                  <div><dt>Branch</dt><dd>{selected.branch ?? '—'}</dd></div>
                  <div><dt>Created</dt><dd><PurchaseOrderTimestamp value={selected.createdAt} dateOnly /></dd></div>
                  <div><dt>Last updated</dt><dd><PurchaseOrderTimestamp value={selected.updatedAt} /></dd></div>
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
                  {canManagePurchaseOrders && selected.status === 'InReview' && (
                    <button type="button" className="btn btn-secondary" onClick={() => rejectOrder(selected)} disabled={statusSavingId !== null}>
                      {statusSavingId === selected.id ? 'Saving…' : 'Reject request'}
                    </button>
                  )}
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
                  {canManagePurchaseOrders && selected.status !== 'Received' && selected.status !== 'Rejected' && selected.status !== 'Cancelled' && (
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
                              <PurchaseOrderTimestamp value={receipt.receivedAt} />
                            </div>
                            <p className="timeline-user">Recorded by {receipt.receivedBy}</p>
                            <div className="receipt-line-summaries">
                              {receipt.items.map((item) => (
                                <div className="receipt-line-summary" key={`${receipt.id}-${item.purchaseOrderItemId}`}>
                                  <span>{item.itemName ?? 'Received item'}</span>
                                  <div className="receipt-line-quantities">
                                    <span><small>Delivered</small><strong>{item.deliveredQuantity}</strong></span>
                                    <span><small>Accepted</small><strong>{item.acceptedQuantity}</strong></span>
                                    <span><small>Damaged</small><strong>{item.damagedQuantity}</strong></span>
                                    <span><small>Short</small><strong>{item.shortageQuantity}</strong></span>
                                  </div>
                                  {item.notes && <p>{item.notes}</p>}
                                </div>
                              ))}
                            </div>
                            {!!receipt.photoUrls?.length && (
                              <div className="po-receipt-photos">
                                {receipt.photoUrls.map((url) => (
                                  <a
                                    key={url}
                                    href={url}
                                    target="_blank"
                                    rel="noreferrer"
                                    aria-label="Open receipt photo"
                                  >
                                    <img src={url} alt="Purchase order receipt evidence" loading="lazy" />
                                  </a>
                                ))}
                              </div>
                            )}
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
                            <PurchaseOrderTimestamp value={event.at} />
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
          canCreateMultiBranch={canCreateMultiBranchPurchaseOrders}
          requiresReview={user?.role === 'Staff'}
          branches={options.branches}
          suppliers={options.suppliers}
          inventoryItems={options.items ?? []}
          defaultNumber={nextPoNumber(orders)}
          defaultBranchId={user?.role === 'Staff' ? user.branchId : reorderBranchId ?? user?.branchId}
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
          onReceive={(items, photos) => recordReceipt(receivingOrder, items, photos)}
        />
      )}
    </div>
  );
}
