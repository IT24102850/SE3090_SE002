import api from '../../api/axiosConfig';

/* StockSense reorder workflow - api/inventory/agent/reorders
 * (backend Controllers/StockSenseReordersController.cs). The server reads
 * prices itself and runs the deterministic safety gate; the client only says
 * which items, how many and from whom. */

export type ReorderCheck = { rule: string; passed: boolean; detail: string };
export type ReorderLine = { inventoryItemId: string; name: string; quantity: number; unitCost: number | null };
export type ReorderStatus = 'AwaitingApproval' | 'Completed' | 'Rejected' | 'RevisionRequested';

export type ReorderWorkflow = {
  id: string;
  status: ReorderStatus;
  approvalStatus: string;
  branchId: string;
  supplierId: string;
  supplierName: string;
  lines: ReorderLine[];
  totalValue: number;
  totalUnits: number;
  checks: ReorderCheck[];
  finalOutcome: string | null;
  error: string | null;
  purchaseOrderId: string | null;
  purchaseOrderNumber: string | null;
  requestedBy: string | null;
  decidedBy: string | null;
  decidedAt: string | null;
  createdAt: string;
  completedAt: string | null;
};

export type ReorderRequest = {
  branchId: string;
  supplierId: string;
  lines: { inventoryItemId: string; quantity: number }[];
  analysisWorkflowId?: string;
  note?: string;
};

export type NamedOption = { id: string; name: string };

export const reorderApi = {
  list: (status?: ReorderStatus) =>
    api.get<ReorderWorkflow[]>('/inventory/agent/reorders', { params: status ? { status } : undefined }).then((r) => r.data),
  request: (body: ReorderRequest) =>
    api.post<ReorderWorkflow>('/inventory/agent/reorders', body).then((r) => r.data),
  approve: (id: string) =>
    api.post<ReorderWorkflow>(`/inventory/agent/reorders/${id}/approve`, {}).then((r) => r.data),
  reject: (id: string, reason: string) =>
    api.post<ReorderWorkflow>(`/inventory/agent/reorders/${id}/reject`, { reason }).then((r) => r.data),
  revise: (id: string, reason: string) =>
    api.post<ReorderWorkflow>(`/inventory/agent/reorders/${id}/revise`, { reason }).then((r) => r.data),
  suppliers: () =>
    api.get<{ suppliers: NamedOption[] }>('/purchase-orders/options').then((r) => r.data.suppliers ?? []),
};

export const reorderStatusLabel: Record<ReorderStatus, string> = {
  AwaitingApproval: 'Awaiting approval',
  Completed: 'Ordered',
  Rejected: 'Rejected',
  RevisionRequested: 'Revision requested',
};

export function formatLkr(value: number): string {
  return value.toLocaleString('en-LK', { style: 'currency', currency: 'LKR' });
}

export function errorMessage(error: unknown, fallback: string): string {
  const data = (error as { response?: { data?: { message?: string; title?: string; errors?: Record<string, string[]> } } })?.response?.data;
  const firstFieldError = data?.errors ? Object.values(data.errors).flat()[0] : undefined;
  return data?.message ?? firstFieldError ?? data?.title ?? fallback;
}
