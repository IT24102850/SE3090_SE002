import { useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { useGetTenantQuery, useUpdateTenantMutation } from '../../api/bookingApi';
import { TOURISM_SUB_TYPES } from '../booking/types';

// FR-AS4/FR-AS11: business details + the reschedule/cancellation cutoff
// policy (previously hardcoded in BookingsController, now per-tenant).
export default function BusinessSettingsPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: tenant, isLoading } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const [updateTenant, { isLoading: saving }] = useUpdateTenantMutation();

  const [name, setName] = useState('');
  const [logoUrl, setLogoUrl] = useState('');
  const [subType, setSubType] = useState('');
  const [rescheduleCutoffHours, setRescheduleCutoffHours] = useState(2);
  const [cancellationCutoffHours, setCancellationCutoffHours] = useState(1);

  useEffect(() => {
    if (!tenant) return;
    setName(tenant.name);
    setLogoUrl(tenant.logoUrl ?? '');
    setSubType(tenant.subType ?? '');
    setRescheduleCutoffHours(tenant.rescheduleCutoffHours);
    setCancellationCutoffHours(tenant.cancellationCutoffHours);
  }, [tenant]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await updateTenant({
        name,
        logoUrl: logoUrl || undefined,
        rescheduleCutoffHours,
        cancellationCutoffHours,
        ...(tenant?.businessType === 'Tourism' ? { subType: subType || undefined } : {}),
      }).unwrap();
      show('Business settings saved.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not save settings.'), 'error');
    }
  };

  if (isLoading) {
    return <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading…</div></div>;
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Business Settings</h1>
          <p className="page-subtitle">Business details and the reschedule/cancellation policy for your business.</p>
        </div>
      </div>

      <div className="card" style={{ padding: 20, maxWidth: 640 }}>
        <form onSubmit={handleSubmit} className="form-grid">
          <div className="field field-full">
            <label>Business name</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="field field-full">
            <label>Logo URL</label>
            <input className="input" value={logoUrl} onChange={(e) => setLogoUrl(e.target.value)} placeholder="https://…" />
          </div>
          {tenant?.businessType === 'Tourism' && (
            <div className="field field-full">
              <label>Tourism sub-type</label>
              <select className="input" value={subType} onChange={(e) => setSubType(e.target.value)}>
                <option value="">Not set</option>
                {TOURISM_SUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
          )}
          <div className="field">
            <label>Reschedule cutoff (hours before appointment)</label>
            <input
              className="input" type="number" min={0} max={168}
              value={rescheduleCutoffHours}
              onChange={(e) => setRescheduleCutoffHours(Number(e.target.value))}
            />
          </div>
          <div className="field">
            <label>Cancellation cutoff (hours before appointment)</label>
            <input
              className="input" type="number" min={0} max={168}
              value={cancellationCutoffHours}
              onChange={(e) => setCancellationCutoffHours(Number(e.target.value))}
            />
          </div>
          <div className="field field-full">
            <button className="btn btn-primary" type="submit" disabled={saving}>
              {saving ? <span className="spinner" /> : 'Save settings'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
