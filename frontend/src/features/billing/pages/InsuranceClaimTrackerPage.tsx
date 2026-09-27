import { useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type ClaimStatus, type InsuranceClaim, type Invoice } from '../billingApi';
import { date, money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

const COLUMNS: { status: ClaimStatus; title: string }[] = [
  { status: 'Submitted', title: 'Submitted' },
  { status: 'UnderReview', title: 'Under review' },
  { status: 'Approved', title: 'Approved' },
  { status: 'Rejected', title: 'Rejected' },
];

/** Which moves the pipeline allows from each stage. */
const NEXT: Record<ClaimStatus, ClaimStatus[]> = {
  Submitted: ['UnderReview', 'Approved', 'Rejected'],
  UnderReview: ['Approved', 'Rejected'],
  Approved: [],
  Rejected: [],
};

export default function InsuranceClaimTrackerPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const isStaff = user?.role !== 'Customer';
  const toast = useToast();
  const { data, loading, error, reload } = useAsync(() => billingApi.listClaims(undefined, 100), []);
  const [dragging, setDragging] = useState<InsuranceClaim | null>(null);
  const [dropCol, setDropCol] = useState<ClaimStatus | null>(null);
  const [rejecting, setRejecting] = useState<InsuranceClaim | null>(null);
  const [creating, setCreating] = useState(false);
  const [viewing, setViewing] = useState<InsuranceClaim | null>(null);

  const claims = data?.items ?? [];

  const move = async (claim: InsuranceClaim, to: ClaimStatus, rejectionReason?: string) => {
    if (!NEXT[claim.status].includes(to)) {
      toast.show(`A ${claim.status === 'UnderReview' ? 'claim under review' : claim.status.toLowerCase() + ' claim'} cannot move to ${to}.`, 'warning');
      return;
    }
    if (to === 'Rejected' && !rejectionReason) {
      setRejecting(claim);
      return;
    }
    try {
      const result = await billingApi.updateClaimStatus(claim.id, { status: to, rejectionReason });
      toast.show(result.message, result.requiresApproval ? 'warning' : 'success');
      reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The claim could not be updated.'), 'error');
    }
  };

  const total = (status: ClaimStatus) => claims.filter((c) => c.status === status).reduce((s, c) => s + c.claimAmount, 0);

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Insurance claims</h1>
          <p className="page-subtitle">
            {isStaff ? 'Drag a claim to move it through review. Claims above 500 need an Admin to approve.' : 'Track the claims made against your bills.'}
          </p>
        </div>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>+ New claim</button>
      </div>

      {error && <div className="bl-notice bl-notice-critical">{error}</div>}
      {loading && !data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}

      <div className="bl-kanban">
        {COLUMNS.map((col) => (
          <section
            key={col.status}
            className={`bl-col${dropCol === col.status ? ' bl-drop' : ''}`}
            aria-label={`${col.title} claims`}
            onDragOver={(e) => { if (isStaff && dragging) { e.preventDefault(); setDropCol(col.status); } }}
            onDragLeave={() => setDropCol(null)}
            onDrop={(e) => {
              e.preventDefault();
              setDropCol(null);
              if (dragging && dragging.status !== col.status) void move(dragging, col.status);
              setDragging(null);
            }}
          >
            <div className="bl-col-head">
              <span>{col.title} <span className="bl-muted">({claims.filter((c) => c.status === col.status).length})</span></span>
              <span className="bl-small bl-muted">{money(total(col.status))}</span>
            </div>
            {claims.filter((c) => c.status === col.status).map((c) => (
              <article
                key={c.id}
                className="bl-claim"
                draggable={isStaff && NEXT[c.status].length > 0}
                onDragStart={() => setDragging(c)}
                onDragEnd={() => { setDragging(null); setDropCol(null); }}
              >
                <div className="bl-spread">
                  <span className="bl-claim-amount">{money(c.claimAmount, c.currency ?? 'LKR')}</span>
                  {c.requiresAdminApproval && c.status !== 'Approved' && c.status !== 'Rejected' && <span className="bl-badge bl-badge-warning">Admin</span>}
                </div>
                <div><strong>{c.provider}</strong> · <span className="bl-mono">{c.policyNumber}</span></div>
                <div className="bl-small bl-muted">{c.invoiceNumber} · submitted {date(c.submittedAt)}</div>
                {c.rejectionReason && <div className="bl-small" style={{ color: 'var(--color-critical)' }}>{c.rejectionReason}</div>}
                <div className="bl-row">
                  <button className="btn btn-ghost btn-sm" onClick={() => setViewing(c)}>Details{c.documents?.length ? ` · ${c.documents.length} docs` : ''}</button>
                  {isStaff && NEXT[c.status].map((to) => (
                    <button key={to} className="btn btn-ghost btn-sm" onClick={() => void move(c, to)} aria-label={`Move to ${to}`}>
                      {to === 'UnderReview' ? 'Review' : to === 'Approved' ? 'Approve' : 'Reject'}
                    </button>
                  ))}
                </div>
              </article>
            ))}
          </section>
        ))}
      </div>

      {rejecting && <RejectModal claim={rejecting} onClose={() => setRejecting(null)} onReject={(reason) => { const c = rejecting; setRejecting(null); void move(c, 'Rejected', reason); }} />}
      {creating && <NewClaimModal onClose={() => setCreating(false)} onCreated={() => { setCreating(false); reload(); toast.show('Claim submitted.', 'success'); }} />}
      {viewing && <ClaimDetailModal claim={viewing} onClose={() => setViewing(null)} onChanged={() => reload()} />}
    </div>
  );
}

function RejectModal({ claim, onClose, onReject }: { claim: InsuranceClaim; onClose: () => void; onReject: (reason: string) => void }) {
  const [reason, setReason] = useState('');
  return (
    <Modal title={`Reject ${claim.provider} claim`} onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-danger" disabled={!reason.trim()} onClick={() => onReject(reason.trim())}>Reject claim</button>
      </>
    }>
      <label className="bl-field"><span>Reason (shown to the patient)</span>
        <textarea className="input" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Treatment not covered under the policy" />
      </label>
    </Modal>
  );
}

function NewClaimModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const toast = useToast();
  const { data: invoices } = useAsync(() => billingApi.listInvoices({ pageSize: 100 }), []);
  const [invoiceId, setInvoiceId] = useState('');
  const [provider, setProvider] = useState('');
  const [policy, setPolicy] = useState('');
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const invoice: Invoice | undefined = invoices?.items.find((i) => i.id === invoiceId);
  const amountNum = Number(amount) || 0;
  const tooMuch = invoice && amountNum > invoice.finalAmount;
  const policyOk = /^[A-Za-z0-9][A-Za-z0-9/-]{3,39}$/.test(policy.trim());

  const save = async () => {
    setSaving(true);
    try {
      await billingApi.createClaim({ invoiceId, provider: provider.trim(), policyNumber: policy.trim(), claimAmount: amountNum, notes: notes || undefined });
      onCreated();
    } catch (err) {
      toast.show(errorMessage(err, 'The claim could not be submitted.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="New insurance claim" onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={saving || !invoiceId || !provider.trim() || !policyOk || amountNum <= 0 || !!tooMuch} onClick={save}>Submit claim</button>
      </>
    }>
      <div className="bl-form">
        <label className="bl-field"><span>Invoice</span>
          <select className="input" value={invoiceId} onChange={(e) => { setInvoiceId(e.target.value); const inv = invoices?.items.find((i) => i.id === e.target.value); if (inv && !amount) setAmount(String(inv.finalAmount)); }}>
            <option value="">Choose…</option>
            {invoices?.items.filter((i) => i.status !== 'Cancelled').map((i) => (
              <option key={i.id} value={i.id}>{i.invoiceNumber} · {i.customerName ?? ''} · {money(i.finalAmount, i.currency)}</option>
            ))}
          </select>
        </label>
        <div className="bl-grid-2">
          <label className="bl-field"><span>Insurer</span><input className="input" value={provider} maxLength={150} onChange={(e) => setProvider(e.target.value)} placeholder="Ceylinco, AIA, Allianz…" /></label>
          <label className="bl-field"><span>Policy number</span>
            <input className="input" value={policy} maxLength={100} aria-invalid={(policy !== '' && !policyOk) || undefined} onChange={(e) => setPolicy(e.target.value)} />
            {policy !== '' && !policyOk && <span className="bl-field-error">4-40 letters, digits, “/” or “-”.</span>}
          </label>
          <label className="bl-field"><span>Claim amount</span>
            <input className="input" type="number" min={0} step="0.01" value={amount} aria-invalid={tooMuch || undefined} onChange={(e) => setAmount(e.target.value)} />
            {tooMuch && <span className="bl-field-error">Cannot exceed the invoice ({money(invoice!.finalAmount, invoice!.currency)}).</span>}
          </label>
        </div>
        {amountNum > 500 && <div className="bl-notice bl-notice-warning bl-small">Claims above 500 are approved by an Admin.</div>}
        <label className="bl-field"><span>Notes</span><textarea className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></label>
      </div>
    </Modal>
  );
}

function ClaimDetailModal({ claim, onClose, onChanged }: { claim: InsuranceClaim; onClose: () => void; onChanged: () => void }) {
  const toast = useToast();
  const [current, setCurrent] = useState(claim);
  const [uploading, setUploading] = useState(false);
  const closed = current.status === 'Approved' || current.status === 'Rejected';

  const upload = async (file: File | undefined) => {
    if (!file) return;
    setUploading(true);
    try {
      setCurrent(await billingApi.uploadClaimDocument(current.id, file));
      onChanged();
      toast.show('Document attached.', 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'The document could not be uploaded.'), 'error');
    } finally {
      setUploading(false);
    }
  };

  return (
    <Modal title={`${current.provider} claim`} onClose={onClose}>
      <div className="bl-stack">
        <div className="bl-spread"><StatusBadge status={current.status} /><strong>{money(current.claimAmount, current.currency ?? 'LKR')}</strong></div>
        <dl className="bl-grid-2" style={{ margin: 0 }}>
          <div><dt className="bl-label">Policy</dt><dd className="bl-mono" style={{ margin: 0 }}>{current.policyNumber}</dd></div>
          <div><dt className="bl-label">Invoice</dt><dd style={{ margin: 0 }}>{current.invoiceNumber}</dd></div>
          <div><dt className="bl-label">Submitted</dt><dd style={{ margin: 0 }}>{date(current.submittedAt)}</dd></div>
          <div><dt className="bl-label">Review started</dt><dd style={{ margin: 0 }}>{date(current.reviewStartedAt)}</dd></div>
          <div><dt className="bl-label">Approved</dt><dd style={{ margin: 0 }}>{date(current.approvedAt)}</dd></div>
        </dl>
        {current.notes && <div className="bl-notice bl-small" style={{ whiteSpace: 'pre-wrap' }}>{current.notes}</div>}
        {current.rejectionReason && <div className="bl-notice bl-notice-critical bl-small">{current.rejectionReason}</div>}
        <div className="bl-stack">
          <span className="bl-label">Documents</span>
          {(current.documents ?? []).length === 0 && <span className="bl-muted bl-small">None yet.</span>}
          <ul className="bl-list">
            {(current.documents ?? []).map((d) => (
              <li key={d.url} className="bl-list-item">
                <a href={d.url} target="_blank" rel="noreferrer">{d.fileName}</a>
                <span className="bl-small bl-muted">{date(d.uploadedAt)}</span>
              </li>
            ))}
          </ul>
          {!closed && (
            <label className="btn btn-secondary btn-sm" style={{ width: 'fit-content' }}>
              {uploading ? 'Uploading…' : 'Attach photo or PDF'}
              <input type="file" accept="image/*,application/pdf" capture="environment" hidden onChange={(e) => void upload(e.target.files?.[0])} />
            </label>
          )}
        </div>
      </div>
    </Modal>
  );
}
