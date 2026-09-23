import { useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { useSearchParams } from 'react-router-dom';
import type { RootState } from '../../../store/store';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type CustomerOption, type Invoice, type InvoiceTemplate, type SchedulePart } from '../billingApi';
import { addDays, date, isoDay, money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import InvoiceFormModal from '../components/InvoiceFormModal';
import InvoiceDetailModal from '../components/InvoiceDetailModal';
import '../billing.css';

const TABS = ['All', 'Issued', 'PartiallyPaid', 'Overdue', 'Paid', 'Cancelled'] as const;
const TAB_LABEL: Record<(typeof TABS)[number], string> = {
  All: 'All', Issued: 'Unpaid', PartiallyPaid: 'Part paid', Overdue: 'Overdue', Paid: 'Paid', Cancelled: 'Cancelled',
};

export default function InvoicesPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const toast = useToast();
  const [params, setParams] = useSearchParams();
  const status = (params.get('status') as (typeof TABS)[number]) ?? 'All';
  const [search, setSearch] = useState('');
  const [debounced, setDebounced] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [page, setPage] = useState(1);
  const [creating, setCreating] = useState(false);
  const [scheduling, setScheduling] = useState(false);
  const [selected, setSelected] = useState<Invoice | null>(null);
  const [customers, setCustomers] = useState<CustomerOption[]>([]);
  const [templates, setTemplates] = useState<InvoiceTemplate[]>([]);

  const canManage = user?.role !== 'Customer';
  const canCancel = user?.role === 'Admin' || user?.role === 'Manager';

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(1), [status, debounced, from, to]);

  useEffect(() => {
    billingApi.customers().then(setCustomers).catch(() => setCustomers([]));
    billingApi.listTemplates().then(setTemplates).catch(() => setTemplates([]));
  }, []);

  const { data, loading, error, reload } = useAsync(
    () => billingApi.listInvoices({ status: status === 'All' ? undefined : status, search: debounced, from, to, page, pageSize: 25 }),
    [status, debounced, from, to, page],
  );

  const replace = (next: Invoice) => {
    reload();
    setSelected(next);
  };

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Invoices</h1>
          <p className="page-subtitle">Per-visit bills, table bills, fees and deals - issue, collect, split, adjust and chase.</p>
        </div>
        <div className="bl-row">
          <button className="btn btn-secondary" onClick={() => setScheduling(true)}>Payment schedule</button>
          <button className="btn btn-primary" onClick={() => setCreating(true)}>+ New invoice</button>
        </div>
      </div>

      <div className="bl-tabs" role="tablist" aria-label="Invoice status">
        {TABS.map((t) => (
          <button key={t} role="tab" className="bl-tab" aria-selected={status === t}
            onClick={() => setParams(t === 'All' ? {} : { status: t })}>{TAB_LABEL[t]}</button>
        ))}
      </div>

      <div className="filter-bar bl-row">
        <input className="input" style={{ maxWidth: 240 }} placeholder="Search invoice number…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search invoices" />
        <label className="bl-row bl-small bl-muted">From <input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="bl-row bl-small bl-muted">To <input className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        {(from || to || search) && <button className="btn btn-ghost btn-sm" onClick={() => { setFrom(''); setTo(''); setSearch(''); }}>Clear</button>}
      </div>

      {error && <div className="bl-notice bl-notice-critical" role="alert">{error}</div>}

      <div className="bl-table-wrap">
        <table className="bl-table">
          <thead>
            <tr>
              <th>Invoice</th><th>Customer</th><th>Issued</th><th>Due</th><th>Status</th>
              <th className="bl-num">Total</th><th className="bl-num">Balance</th>
            </tr>
          </thead>
          <tbody>
            {loading && !data && <tr><td colSpan={7}><div className="loading-row"><span className="spinner spinner-dark" /></div></td></tr>}
            {data?.items.map((inv) => (
              <tr key={inv.id} className="bl-clickable" onClick={() => setSelected(inv)} tabIndex={0}
                onKeyDown={(e) => { if (e.key === 'Enter') setSelected(inv); }}>
                <td>
                  <strong>{inv.invoiceNumber}</strong>
                  {inv.scheduleLabel && <div className="bl-small bl-muted">{inv.scheduleLabel}</div>}
                </td>
                <td>{inv.customerName ?? '—'}</td>
                <td>{date(inv.createdAt)}</td>
                <td>{date(inv.dueDate)}</td>
                <td><StatusBadge status={inv.status} /></td>
                <td className="bl-num">{money(inv.finalAmount, inv.currency)}</td>
                <td className="bl-num">{money(inv.balanceDue, inv.currency)}</td>
              </tr>
            ))}
            {data && data.items.length === 0 && (
              <tr><td colSpan={7}><div className="bl-empty">No invoices match. Create one with “New invoice”.</div></td></tr>
            )}
          </tbody>
        </table>
      </div>

      {data && data.totalPages > 1 && (
        <div className="bl-spread">
          <span className="bl-muted bl-small">{data.totalCount} invoices</span>
          <div className="bl-row">
            <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
            <span className="bl-small">Page {page} of {data.totalPages}</span>
            <button className="btn btn-secondary btn-sm" disabled={page >= data.totalPages} onClick={() => setPage(page + 1)}>Next</button>
          </div>
        </div>
      )}

      {creating && (
        <InvoiceFormModal
          customers={customers}
          templates={templates}
          onClose={() => setCreating(false)}
          onCreated={(inv) => {
            setCreating(false);
            reload();
            const flagged = inv.validationIssues?.some((i) => i.severity === 'warning');
            toast.show(flagged ? `${inv.invoiceNumber} created and flagged for review by the billing agent.` : `${inv.invoiceNumber} created.`, flagged ? 'warning' : 'success');
            setSelected(inv);
          }}
        />
      )}

      {scheduling && (
        <ScheduleModal customers={customers} onClose={() => setScheduling(false)} onCreated={(count) => {
          setScheduling(false);
          reload();
          toast.show(`${count} scheduled invoices created.`, 'success');
        }} />
      )}

      {selected && (
        <InvoiceDetailModal
          key={selected.id}
          invoice={selected}
          canManage={canManage}
          canCancel={canCancel}
          onClose={() => setSelected(null)}
          onChanged={replace}
        />
      )}
    </div>
  );
}

const SCHEDULE_PRESETS: Record<string, { label: string; build: (start: Date) => SchedulePart[] }> = {
  deposit: {
    label: 'Deposit + balance (tourism)',
    build: (s) => [
      { label: 'Deposit', percent: 30, dueDate: isoDay(s) },
      { label: 'Balance', percent: 70, dueDate: isoDay(addDays(s, 30)) },
    ],
  },
  installments: {
    label: '3 monthly installments (tuition)',
    build: (s) => [1, 2, 3].map((n) => ({ label: `Installment ${n} of 3`, percent: n === 3 ? 33.34 : 33.33, dueDate: isoDay(addDays(s, (n - 1) * 30)) })),
  },
  milestones: {
    label: 'Milestones (real estate)',
    build: (s) => [
      { label: 'Reservation', percent: 10, dueDate: isoDay(s) },
      { label: 'Agreement signed', percent: 40, dueDate: isoDay(addDays(s, 30)) },
      { label: 'Handover', percent: 50, dueDate: isoDay(addDays(s, 90)) },
    ],
  },
};

function ScheduleModal({ customers, onClose, onCreated }: { customers: CustomerOption[]; onClose: () => void; onCreated: (count: number) => void }) {
  const toast = useToast();
  const [customerId, setCustomerId] = useState('');
  const [description, setDescription] = useState('');
  const [total, setTotal] = useState('');
  const [currency, setCurrency] = useState('LKR');
  const [parts, setParts] = useState<SchedulePart[]>(SCHEDULE_PRESETS.deposit.build(new Date()));
  const [saving, setSaving] = useState(false);

  const totalNum = Number(total) || 0;
  const percentSum = parts.reduce((s, p) => s + (Number(p.percent) || 0), 0);
  const valid = customerId && description.trim() && totalNum > 0 && Math.abs(percentSum - 100) < 0.05 && parts.every((p) => p.label.trim() && p.dueDate);

  const save = async () => {
    setSaving(true);
    try {
      const result = await billingApi.createSchedule({
        customerId,
        description: description.trim(),
        totalAmount: totalNum,
        currency,
        parts: parts.map((p) => ({ ...p, dueDate: new Date(`${p.dueDate}T12:00:00`).toISOString() })),
      });
      onCreated(result.invoices.length);
    } catch (err) {
      toast.show(errorMessage(err, 'The schedule could not be created.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="Payment schedule" onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={!valid || saving} onClick={save}>{saving ? 'Creating…' : `Create ${parts.length} invoices`}</button>
      </>
    }>
      <div className="bl-form">
        <div className="bl-row">
          {Object.entries(SCHEDULE_PRESETS).map(([key, p]) => (
            <button key={key} className="btn btn-ghost btn-sm" onClick={() => setParts(p.build(new Date()))}>{p.label}</button>
          ))}
        </div>
        <div className="bl-grid-2">
          <label className="bl-field"><span>Customer</span>
            <select className="input" value={customerId} onChange={(e) => setCustomerId(e.target.value)}>
              <option value="">Choose…</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.fullName}</option>)}
            </select>
          </label>
          <label className="bl-field"><span>What is being paid for</span>
            <input className="input" value={description} maxLength={500} onChange={(e) => setDescription(e.target.value)} placeholder="Yala safari - 3 nights" />
          </label>
          <label className="bl-field"><span>Total</span>
            <input className="input" type="number" min={0} step="0.01" value={total} onChange={(e) => setTotal(e.target.value)} />
          </label>
          <label className="bl-field"><span>Currency</span>
            <input className="input" value={currency} maxLength={3} onChange={(e) => setCurrency(e.target.value.toUpperCase())} />
          </label>
        </div>
        <div className="bl-stack">
          {parts.map((p, i) => (
            <div key={i} className="bl-grid-3">
              <input className="input" aria-label={`Part ${i + 1} label`} value={p.label} onChange={(e) => setParts(parts.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))} />
              <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                <input className="input" type="number" min={0} max={100} step="0.01" aria-label={`Part ${i + 1} percent`} value={p.percent ?? ''}
                  onChange={(e) => setParts(parts.map((x, j) => (j === i ? { ...x, percent: Number(e.target.value) } : x)))} />
                <span className="bl-muted">% · {money((totalNum * (Number(p.percent) || 0)) / 100, currency)}</span>
              </div>
              <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                <input className="input" type="date" aria-label={`Part ${i + 1} due date`} value={p.dueDate} onChange={(e) => setParts(parts.map((x, j) => (j === i ? { ...x, dueDate: e.target.value } : x)))} />
                <button className="btn btn-ghost btn-sm" aria-label={`Remove part ${i + 1}`} disabled={parts.length === 1} onClick={() => setParts(parts.filter((_, j) => j !== i))}>✕</button>
              </div>
            </div>
          ))}
          <div className="bl-spread">
            <button className="btn btn-ghost btn-sm" onClick={() => setParts([...parts, { label: `Part ${parts.length + 1}`, percent: 0, dueDate: isoDay(addDays(new Date(), 30 * parts.length)) }])}>+ Add part</button>
            <span className={Math.abs(percentSum - 100) < 0.05 ? 'bl-muted' : 'bl-field-error'}>{percentSum.toFixed(2)}% of 100%</span>
          </div>
        </div>
      </div>
    </Modal>
  );
}
