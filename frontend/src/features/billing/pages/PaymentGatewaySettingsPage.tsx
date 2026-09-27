import { useState } from 'react';
import Modal from '../../../shared/components/Modal';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type PaymentGateway, type UpsertGatewayRequest } from '../billingApi';
import { date } from '../format';
import { useAsync } from '../useAsync';
import StatusBadge from '../components/StatusBadge';
import '../billing.css';

const PROVIDER_HELP: Record<string, { publicLabel: string; secretLabel: string; webhookLabel: string; hint: string }> = {
  Stripe: {
    publicLabel: 'Publishable key (pk_…)',
    secretLabel: 'Secret key (sk_…)',
    webhookLabel: 'Webhook signing secret (whsec_…)',
    hint: 'Stripe Dashboard → Developers → API keys. Add the webhook URL below under Developers → Webhooks with the payment_intent.succeeded and payment_intent.payment_failed events.',
  },
  PayPal: {
    publicLabel: 'Client ID',
    secretLabel: 'Client secret',
    webhookLabel: 'Webhook ID',
    hint: 'developer.paypal.com → Apps & Credentials. Create a webhook for the URL below with CHECKOUT.ORDER.APPROVED and PAYMENT.CAPTURE.* events, then paste its ID here.',
  },
};

export default function PaymentGatewaySettingsPage() {
  const toast = useToast();
  const { data, loading, error, reload } = useAsync(() => billingApi.listGateways(), []);
  const [editing, setEditing] = useState<PaymentGateway | 'new' | null>(null);
  const [testing, setTesting] = useState<string | null>(null);

  const test = async (g: PaymentGateway) => {
    setTesting(g.id);
    try {
      const r = await billingApi.testGateway(g.id);
      toast.show(r.message, r.ok ? 'success' : 'error');
    } catch (err) {
      toast.show(errorMessage(err, 'The test failed.'), 'error');
    } finally {
      setTesting(null);
    }
  };

  const remove = async (g: PaymentGateway) => {
    if (!window.confirm(`Remove ${g.name}? Customers will no longer be able to pay through it.`)) return;
    try {
      await billingApi.deleteGateway(g.id);
      reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The gateway could not be removed.'), 'error');
    }
  };

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Payment gateways</h1>
          <p className="page-subtitle">Connect Stripe or PayPal so customers can pay invoices online. Keys are encrypted and never shown again.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setEditing('new')}>+ Add gateway</button>
      </div>

      {error && <div className="bl-notice bl-notice-critical">{error}</div>}
      {data && data.length === 0 && (
        <div className="bl-notice">
          No gateway is configured, so online payments run in the <strong>sandbox</strong>: the full card and QR flow works, but no real money moves.
        </div>
      )}
      {loading && !data && <div className="loading-row"><span className="spinner spinner-dark" /></div>}

      <div className="bl-grid-2">
        {data?.map((g) => (
          <div key={g.id} className="card bl-stack" style={{ padding: 16 }}>
            <div className="bl-spread">
              <div>
                <div style={{ fontWeight: 700, fontSize: 16 }}>{g.name}</div>
                <div className="bl-small bl-muted">{g.provider} · {g.currency} · updated {date(g.updatedAt)}</div>
              </div>
              <div className="bl-row">
                <StatusBadge status={g.isActive ? 'Active' : 'Inactive'} />
                <span className={`bl-badge ${g.isTestMode ? 'bl-badge-warning' : 'bl-badge-good'}`}>{g.isTestMode ? 'Test mode' : 'Live'}</span>
              </div>
            </div>
            <dl className="bl-grid-2" style={{ margin: 0 }}>
              <div><dt className="bl-label">Public key</dt><dd className="bl-mono bl-small" style={{ margin: 0, overflowWrap: 'anywhere' }}>{g.publicKey ?? '—'}</dd></div>
              <div><dt className="bl-label">Secret key</dt><dd className="bl-mono bl-small" style={{ margin: 0 }}>{g.hasApiKey ? g.apiKeyHint : 'Not set'}</dd></div>
              <div><dt className="bl-label">Webhook secret</dt><dd className="bl-small" style={{ margin: 0 }}>{g.hasWebhookSecret ? 'Set' : 'Not set'}</dd></div>
            </dl>
            {g.webhookUrl && (
              <div className="bl-stack" style={{ gap: 4 }}>
                <span className="bl-label">Webhook URL</span>
                <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                  <code className="bl-code" style={{ flex: 1, padding: '6px 8px' }}>{g.webhookUrl}</code>
                  <button className="btn btn-ghost btn-sm" onClick={() => { void navigator.clipboard?.writeText(g.webhookUrl!); toast.show('Copied.', 'success'); }}>Copy</button>
                </div>
              </div>
            )}
            <div className="bl-row">
              <button className="btn btn-secondary btn-sm" onClick={() => setEditing(g)}>Edit</button>
              <button className="btn btn-secondary btn-sm" disabled={testing === g.id} onClick={() => test(g)}>{testing === g.id ? 'Testing…' : 'Test connection'}</button>
              <button className="btn btn-ghost btn-sm" onClick={() => remove(g)}>Remove</button>
            </div>
          </div>
        ))}
      </div>

      {editing && (
        <GatewayModal
          gateway={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); reload(); toast.show('Gateway saved.', 'success'); }}
        />
      )}
    </div>
  );
}

function GatewayModal({ gateway, onClose, onSaved }: { gateway: PaymentGateway | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [form, setForm] = useState<UpsertGatewayRequest>({
    name: gateway?.name ?? 'Stripe',
    provider: gateway?.provider ?? 'Stripe',
    currency: gateway?.currency ?? 'LKR',
    isActive: gateway?.isActive ?? true,
    isTestMode: gateway?.isTestMode ?? true,
    publicKey: gateway?.publicKey ?? '',
    apiKey: '',
    webhookSecret: '',
  });
  const [saving, setSaving] = useState(false);
  const help = PROVIDER_HELP[form.provider];
  const liveKeyInTest = form.isTestMode && /^(sk|pk)_live_/.test(`${form.apiKey}${form.publicKey}`);

  const save = async () => {
    setSaving(true);
    try {
      // Blank secret fields on an edit mean "keep what is stored".
      const body = { ...form, apiKey: form.apiKey || (gateway ? null : ''), webhookSecret: form.webhookSecret || (gateway ? null : '') };
      if (gateway) await billingApi.updateGateway(gateway.id, body);
      else await billingApi.createGateway(body);
      onSaved();
    } catch (err) {
      toast.show(errorMessage(err, 'The gateway could not be saved.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={gateway ? `Edit ${gateway.name}` : 'Add payment gateway'} onClose={onClose} footer={
      <>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" disabled={saving || !form.name.trim()} onClick={save}>{saving ? 'Saving…' : 'Save'}</button>
      </>
    }>
      <div className="bl-form">
        <div className="bl-grid-3">
          <label className="bl-field"><span>Provider</span>
            <select className="input" value={form.provider} disabled={!!gateway} onChange={(e) => setForm({ ...form, provider: e.target.value, name: gateway ? form.name : e.target.value })}>
              <option value="Stripe">Stripe</option>
              <option value="PayPal">PayPal</option>
            </select>
          </label>
          <label className="bl-field"><span>Name</span><input className="input" value={form.name} maxLength={100} onChange={(e) => setForm({ ...form, name: e.target.value })} /></label>
          <label className="bl-field"><span>Currency</span><input className="input" value={form.currency} maxLength={3} onChange={(e) => setForm({ ...form, currency: e.target.value.toUpperCase() })} /></label>
        </div>
        {help && <div className="bl-notice bl-small">{help.hint}</div>}
        <label className="bl-field"><span>{help?.publicLabel ?? 'Public key'}</span>
          <input className="input bl-mono" value={form.publicKey ?? ''} autoComplete="off" onChange={(e) => setForm({ ...form, publicKey: e.target.value })} />
        </label>
        <label className="bl-field"><span>{help?.secretLabel ?? 'Secret key'}</span>
          <input className="input bl-mono" type="password" autoComplete="new-password" value={form.apiKey ?? ''}
            placeholder={gateway?.hasApiKey ? `Stored (${gateway.apiKeyHint}) - leave blank to keep` : ''}
            onChange={(e) => setForm({ ...form, apiKey: e.target.value })} />
        </label>
        <label className="bl-field"><span>{help?.webhookLabel ?? 'Webhook secret'}</span>
          <input className="input bl-mono" type="password" autoComplete="new-password" value={form.webhookSecret ?? ''}
            placeholder={gateway?.hasWebhookSecret ? 'Stored - leave blank to keep' : ''}
            onChange={(e) => setForm({ ...form, webhookSecret: e.target.value })} />
        </label>
        <div className="bl-row">
          <label className="bl-row"><input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} /> Active</label>
          <label className="bl-row"><input type="checkbox" checked={form.isTestMode} onChange={(e) => setForm({ ...form, isTestMode: e.target.checked })} /> Test / sandbox mode</label>
        </div>
        {liveKeyInTest && <div className="bl-notice bl-notice-warning bl-small">These look like live keys, but test mode is on.</div>}
      </div>
    </Modal>
  );
}
