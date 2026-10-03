import { useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type CommissionRule, type CommissionSplit } from '../billingApi';
import { money } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

type Draft = Omit<CommissionRule, 'id'>;
const emptyRule = (): Draft => ({
  name: '', role: 'Agent', ruleType: 'Percentage', rate: 3, fixedAmount: null, minAmount: null, maxAmount: null,
  description: null, isActive: true, effectiveFrom: null, effectiveTo: null,
});

export default function CommissionRulesPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const canEdit = user?.role === 'Admin' || user?.role === 'Manager';
  const toast = useToast();
  const { data: rules, reload } = useAsync(() => billingApi.listCommissionRules(), []);
  const [editing, setEditing] = useState<{ id: string | null; draft: Draft } | null>(null);
  const [deal, setDeal] = useState('');
  const [split, setSplit] = useState<CommissionSplit | null>(null);

  const calculate = async () => {
    try {
      setSplit(await billingApi.calculateCommission(Number(deal)));
    } catch (err) {
      toast.show(errorMessage(err, 'Could not calculate the split.'), 'error');
    }
  };

  const remove = async (r: CommissionRule) => {
    if (!window.confirm(`Delete the "${r.name}" rule?`)) return;
    try {
      await billingApi.deleteCommissionRule(r.id);
      reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not delete the rule.'), 'error');
    }
  };

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Commission rules</h1>
          <p className="page-subtitle">How a deal's commission splits between agents, brokers and referrers - for real estate and agency sales.</p>
        </div>
        {canEdit && <button className="btn btn-primary" onClick={() => setEditing({ id: null, draft: emptyRule() })}>+ New rule</button>}
      </div>

      <div className="bl-table-wrap">
        <table className="bl-table">
          <thead><tr><th>Rule</th><th>Role</th><th>Commission</th><th>Limits</th><th>Status</th>{canEdit && <th />}</tr></thead>
          <tbody>
            {(rules ?? []).map((r) => (
              <tr key={r.id}>
                <td>{r.name}{r.description && <div className="bl-small bl-muted">{r.description}</div>}</td>
                <td>{r.role ?? 'Any'}</td>
                <td>{r.ruleType === 'Percentage' ? `${r.rate}%` : money(r.fixedAmount ?? 0)}</td>
                <td className="bl-small">{r.minAmount != null ? `min ${money(r.minAmount)}` : ''}{r.minAmount != null && r.maxAmount != null ? ' · ' : ''}{r.maxAmount != null ? `max ${money(r.maxAmount)}` : ''}{r.minAmount == null && r.maxAmount == null ? '—' : ''}</td>
                <td><StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /></td>
                {canEdit && (
                  <td className="bl-row" style={{ flexWrap: 'nowrap' }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => setEditing({ id: r.id, draft: { ...r } })}>Edit</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => remove(r)}>Delete</button>
                  </td>
                )}
              </tr>
            ))}
            {rules && rules.length === 0 && <tr><td colSpan={6}><div className="bl-empty">No commission rules yet.</div></td></tr>}
          </tbody>
        </table>
      </div>

      <div className="card bl-stack" style={{ padding: 16 }}>
        <span className="bl-label">Split a deal</span>
        <div className="bl-row">
          <input className="input" style={{ maxWidth: 220 }} type="number" min={0} placeholder="Deal value" value={deal} onChange={(e) => setDeal(e.target.value)} aria-label="Deal value" />
          <button className="btn btn-secondary" disabled={!(Number(deal) > 0)} onClick={calculate}>Calculate</button>
        </div>
        {split && (
          <div className="bl-table-wrap">
            <table className="bl-table">
              <thead><tr><th>Rule</th><th>Role</th><th className="bl-num">Amount</th></tr></thead>
              <tbody>
                {split.lines.map((l) => (
                  <tr key={l.ruleId}><td>{l.ruleName}{l.clamped && <span className="bl-small bl-muted"> (limited)</span>}</td><td>{l.role ?? '—'}</td><td className="bl-num">{money(l.amount)}</td></tr>
                ))}
                <tr><td colSpan={2}><strong>Total commission</strong></td><td className="bl-num"><strong>{money(split.totalCommission)}</strong></td></tr>
                <tr><td colSpan={2}>To the business</td><td className="bl-num">{money(split.netToBusiness)}</td></tr>
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && (
        <RuleModal
          initial={editing.draft}
          id={editing.id}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); reload(); toast.show('Rule saved.', 'success'); }}
        />
      )}
    </div>
  );
}

function RuleModal({ initial, id, onClose, onSaved }: { initial: Draft; id: string | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [d, setD] = useState<Draft>(initial);
  const [saving, setSaving] = useState(false);
  const opt = (v: string) => (v.trim() === '' ? null : Number(v));

  const save = async () => {
    setSaving(true);
    try {
      await billingApi.saveCommissionRule(id, d);
      onSaved();
    } catch (err) {
      toast.show(errorMessage(err, 'The rule could not be saved.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={id ? 'Edit commission rule' : 'New commission rule'} onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={saving || !d.name.trim()} onClick={save}>Save</button>
      </>
    }>
      <div className="bl-form">
        <div className="bl-grid-2">
          <label className="bl-field"><span>Name</span><input className="input" value={d.name} onChange={(e) => setD({ ...d, name: e.target.value })} /></label>
          <label className="bl-field"><span>Role</span><input className="input" value={d.role ?? ''} placeholder="Agent, Broker, Referrer" onChange={(e) => setD({ ...d, role: e.target.value || null })} /></label>
          <label className="bl-field"><span>Type</span>
            <select className="input" value={d.ruleType} onChange={(e) => setD({ ...d, ruleType: e.target.value as Draft['ruleType'] })}>
              <option value="Percentage">Percentage of the deal</option>
              <option value="Fixed">Fixed amount</option>
            </select>
          </label>
          {d.ruleType === 'Percentage' ? (
            <label className="bl-field"><span>Rate (%)</span><input className="input" type="number" min={0} max={100} step="0.01" value={d.rate} onChange={(e) => setD({ ...d, rate: Number(e.target.value) })} /></label>
          ) : (
            <label className="bl-field"><span>Amount</span><input className="input" type="number" min={0} value={d.fixedAmount ?? ''} onChange={(e) => setD({ ...d, fixedAmount: opt(e.target.value) })} /></label>
          )}
          <label className="bl-field"><span>Minimum</span><input className="input" type="number" min={0} value={d.minAmount ?? ''} onChange={(e) => setD({ ...d, minAmount: opt(e.target.value) })} /></label>
          <label className="bl-field"><span>Maximum</span><input className="input" type="number" min={0} value={d.maxAmount ?? ''} onChange={(e) => setD({ ...d, maxAmount: opt(e.target.value) })} /></label>
        </div>
        <label className="bl-field"><span>Description</span><input className="input" value={d.description ?? ''} onChange={(e) => setD({ ...d, description: e.target.value || null })} /></label>
        <label className="bl-row"><input type="checkbox" checked={d.isActive} onChange={(e) => setD({ ...d, isActive: e.target.checked })} /> Active</label>
      </div>
    </Modal>
  );
}
