import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReorderWorkflow } from '../reorderApi';
import { ReorderApprovals } from './ReorderApprovals';
import { ReorderRequestForm } from './ReorderRequestForm';

/* The StockSense reorder UI: the evidence a manager decides on, who may
 * decide, reasons being required, and what the request form sends. The API
 * module is mocked; the server's gate is covered by the backend tests. */

vi.mock('../reorderApi', async () => {
  const actual = await vi.importActual<typeof import('../reorderApi')>('../reorderApi');
  return {
    ...actual,
    reorderApi: {
      list: vi.fn(),
      request: vi.fn(),
      approve: vi.fn(),
      reject: vi.fn(),
      revise: vi.fn(),
      suppliers: vi.fn(),
    },
  };
});

const { reorderApi } = await import('../reorderApi');
const api = vi.mocked(reorderApi);

const pending: ReorderWorkflow = {
  id: 'r1',
  status: 'AwaitingApproval',
  approvalStatus: 'Pending',
  branchId: 'b1',
  supplierId: 's1',
  supplierName: 'MediSupply',
  lines: [{ inventoryItemId: 'i1', name: 'Latex gloves', quantity: 200, unitCost: 800 }],
  totalValue: 160000,
  totalUnits: 200,
  checks: [
    { rule: 'supplier_active', passed: true, detail: 'MediSupply is an active supplier.' },
    { rule: 'value_within_auto_limit', passed: false, detail: 'Order value 160,000.00 exceeds the 150,000 auto-approval limit.' },
  ],
  finalOutcome: 'Paused for approval.',
  error: null,
  purchaseOrderId: null,
  purchaseOrderNumber: null,
  requestedBy: 'u-staff',
  decidedBy: null,
  decidedAt: null,
  createdAt: '2026-10-01T08:00:00Z',
  completedAt: null,
};

describe('ReorderApprovals', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.list.mockResolvedValue([pending]);
  });

  it('shows the lines, totals and the gate check that caused the pause', async () => {
    render(<ReorderApprovals canDecide />);

    const card = await screen.findByRole('article', { name: 'Reorder from MediSupply' });
    expect(within(card).getByText('Latex gloves')).toBeInTheDocument();
    expect(within(card).getByText('Awaiting approval')).toBeInTheDocument();
    const checks = within(card).getByRole('list', { name: 'Safety gate checks' });
    expect(within(checks).getByText(/exceeds the 150,000 auto-approval limit/)).toBeInTheDocument();
  });

  it('lets a manager approve, and reports the purchase order that was placed', async () => {
    api.approve.mockResolvedValue({ ...pending, status: 'Completed', approvalStatus: 'Approved', purchaseOrderNumber: 'SS-20261001-1234' });
    render(<ReorderApprovals canDecide />);

    fireEvent.click(await screen.findByRole('button', { name: 'Approve and order' }));

    expect(await screen.findByText('Approved - purchase order SS-20261001-1234 placed.')).toBeInTheDocument();
    expect(api.approve).toHaveBeenCalledWith('r1');
    expect(screen.queryByRole('button', { name: 'Approve and order' })).not.toBeInTheDocument();
  });

  it('requires a reason before rejecting', async () => {
    render(<ReorderApprovals canDecide />);

    fireEvent.click(await screen.findByRole('button', { name: 'Reject' }));

    expect(await screen.findByText(/Give a reason of at least 3 characters/)).toBeInTheDocument();
    expect(api.reject).not.toHaveBeenCalled();
  });

  it('sends the reason with a revision request', async () => {
    api.revise.mockResolvedValue({ ...pending, status: 'RevisionRequested', finalOutcome: 'Reorder needs changes: Split it' });
    render(<ReorderApprovals canDecide />);

    fireEvent.change(await screen.findByLabelText('Reason for rejecting or revising'), { target: { value: 'Split it' } });
    fireEvent.click(screen.getByRole('button', { name: 'Request revision' }));

    await waitFor(() => expect(api.revise).toHaveBeenCalledWith('r1', 'Split it'));
    expect(await screen.findByText('Revision requested')).toBeInTheDocument();
  });

  it('shows staff the status but no decision buttons', async () => {
    render(<ReorderApprovals canDecide={false} />);

    await screen.findByRole('article', { name: 'Reorder from MediSupply' });
    expect(screen.queryByRole('button', { name: 'Approve and order' })).not.toBeInTheDocument();
  });

  it('shows an error state when the list cannot load', async () => {
    api.list.mockRejectedValue({ response: { data: { message: 'Forbidden for this branch' } } });
    render(<ReorderApprovals canDecide />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Forbidden for this branch');
  });

  it('shows an empty state when there are no reorders', async () => {
    api.list.mockResolvedValue([]);
    render(<ReorderApprovals canDecide />);

    expect(await screen.findByText(/No reorder requests yet/)).toBeInTheDocument();
  });
});

describe('ReorderRequestForm', () => {
  const recommendations = [
    { inventory_item_id: 'i1', item_name: 'Latex gloves', branch_id: 'b1', branch_name: 'Weligama', recommended_quantity: 99.2, estimated_total_cost: 80000 },
    { inventory_item_id: 'i2', item_name: 'Face masks', branch_id: 'b1', branch_name: 'Weligama', recommended_quantity: 40, estimated_total_cost: null },
  ];

  beforeEach(() => {
    vi.clearAllMocks();
    api.suppliers.mockResolvedValue([{ id: 's1', name: 'MediSupply' }]);
  });

  it('needs a supplier before sending', async () => {
    render(<ReorderRequestForm recommendations={recommendations} />);

    fireEvent.click(screen.getByRole('button', { name: 'Request reorder' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Choose a supplier.');
    expect(api.request).not.toHaveBeenCalled();
  });

  it('sends only the selected lines, with the chosen quantities and the analysis it came from', async () => {
    api.request.mockResolvedValue({ ...pending, finalOutcome: 'Paused for approval: over the limit.' });
    render(<ReorderRequestForm recommendations={recommendations} analysisWorkflowId="a1" />);

    await screen.findByRole('option', { name: 'MediSupply' });
    fireEvent.change(screen.getByLabelText('Supplier'), { target: { value: 's1' } });
    fireEvent.click(screen.getByLabelText('Order Face masks'));
    fireEvent.change(screen.getByLabelText('Quantity of Latex gloves'), { target: { value: '120' } });
    fireEvent.click(screen.getByRole('button', { name: 'Request reorder' }));

    await waitFor(() => expect(api.request).toHaveBeenCalledWith({
      branchId: 'b1',
      supplierId: 's1',
      analysisWorkflowId: 'a1',
      lines: [{ inventoryItemId: 'i1', quantity: 120 }],
    }));
    expect(await screen.findByRole('status')).toHaveTextContent('Awaiting approval. Paused for approval: over the limit.');
  });

  it('rounds a fractional recommendation up to a whole unit', () => {
    render(<ReorderRequestForm recommendations={recommendations} />);

    expect(screen.getByLabelText('Quantity of Latex gloves')).toHaveValue(100);
  });
});
