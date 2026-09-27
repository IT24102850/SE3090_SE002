import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import PlatformLayout from './PlatformLayout';
import OtpPrompt from './OtpPrompt';
import { errorMessage, useSetTenantActiveMutation, useTenantQuery, useTenantsQuery, type PlatformTenantRow } from './platformApi';

const n = (v: number) => v.toLocaleString();
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString([], { dateStyle: 'medium' }) : '—');
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—');

function useDebounced<T>(value: T, ms = 300) {
  const [v, setV] = useState(value);
  useEffect(() => { const id = window.setTimeout(() => setV(value), ms); return () => window.clearTimeout(id); }, [value, ms]);
  return v;
}

function TenantDrawer({ id, onClose }: { id: string; onClose: () => void }) {
  const { data: t, isLoading } = useTenantQuery(id);
  const [setActive, { isLoading: saving }] = useSetTenantActiveMutation();
  const [prompt, setPrompt] = useState<null | 'suspend' | 'reactivate'>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const confirm = async (code: string, reason: string) => {
    if (!t || !prompt) return;
    setError(null);
    try {
      const r = await setActive({ id: t.id, active: prompt === 'reactivate', reason, otp: code }).unwrap();
      setNotice(r.message);
      setPrompt(null);
    } catch (err) {
      setError(errorMessage(err, 'The change was refused.'));
    }
  };

  return (
    <>
      <div className="pf-drawer-backdrop" onMouseDown={onClose} />
      <aside className="pf-drawer" role="dialog" aria-modal="true" aria-labelledby="pf-tenant-title">
        <div className="pf-drawer-head">
          <div>
            <div className="pf-eyebrow">Tenant</div>
            <h2 id="pf-tenant-title">{t?.name ?? 'Loading…'}</h2>
          </div>
          <button type="button" className="pf-drawer-close" aria-label="Close" onClick={onClose}>×</button>
        </div>
        {isLoading && <div className="pf-empty">Loading tenant…</div>}
        {notice && <div className="pf-ok">{notice}</div>}
        {t && (
          <>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <span className={`pf-pill ${t.isActive ? 'pf-pill-good' : 'pf-pill-bad'}`}>{t.isActive ? 'Active' : 'Suspended'}</span>
              <span className="pf-pill pf-pill-neutral">{t.businessType}{t.subType ? ` · ${t.subType}` : ''}</span>
            </div>
            <dl className="pf-kv">
              <dt>Created</dt><dd>{when(t.createdAt)}</dd>
              <dt>Contact</dt><dd>{t.contactEmail ?? '—'}{t.contactPhone ? ` · ${t.contactPhone}` : ''}</dd>
              <dt>Website</dt><dd>{t.website ? <a href={t.website} target="_blank" rel="noreferrer">{t.website}</a> : '—'}</dd>
              <dt>Tagline</dt><dd>{t.shortTagline ?? '—'}</dd>
              <dt>Footprint</dt><dd>{t.branches.length} branch(es) · {t.resources} resources · {t.bookingTypes} booking types</dd>
              <dt>Bookings (30 d)</dt><dd>{n(t.bookings30d)}</dd>
              <dt>ID</dt><dd className="pf-mono">{t.id}</dd>
            </dl>

            <div className="pf-card" style={{ padding: 14 }}>
              <div className="pf-card-head"><h2>Bookings by status</h2></div>
              {t.bookingsByStatus.length === 0 ? <div className="pf-count">No bookings.</div> : (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {t.bookingsByStatus.map((s) => <span key={s.status} className="pf-pill pf-pill-neutral">{s.status} · {n(s.count)}</span>)}
                </div>
              )}
            </div>

            <div className="pf-card" style={{ padding: 14 }}>
              <div className="pf-card-head"><h2>People</h2><span>{t.users.length}</span></div>
              <div className="pf-table-wrap" style={{ border: 0 }}>
                <table className="pf-table">
                  <thead><tr><th>Name</th><th>Role</th><th>Status</th></tr></thead>
                  <tbody>
                    {t.users.map((u) => (
                      <tr key={u.id}>
                        <td>{u.fullName}<small>{u.email}</small></td>
                        <td>{u.role}</td>
                        <td><span className={`pf-pill ${u.isActive ? 'pf-pill-good' : 'pf-pill-bad'}`}>{u.isActive ? 'Active' : 'Inactive'}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            {t.audit.length > 0 && (
              <div className="pf-card" style={{ padding: 14 }}>
                <div className="pf-card-head"><h2>Owner actions on this tenant</h2></div>
                {t.audit.map((a) => (
                  <div key={a.id} className={`pf-audit-row${a.succeeded ? '' : ' failed'}`}>
                    <i aria-hidden="true" /><span><span className="pf-mono">{a.action}</span><small>{a.actorEmail}{a.detail && <> · {a.detail}</>}</small></span><time>{when(a.createdAt)}</time>
                  </div>
                ))}
              </div>
            )}

            <div className="pf-modal-actions">
              {t.isActive
                ? <button type="button" className="pf-btn pf-btn-danger" onClick={() => setPrompt('suspend')}>Suspend tenant</button>
                : <button type="button" className="pf-btn pf-btn-primary" onClick={() => setPrompt('reactivate')}>Reactivate tenant</button>}
            </div>
          </>
        )}
      </aside>
      {prompt && t && (
        <OtpPrompt
          title={prompt === 'suspend' ? `Suspend ${t.name}?` : `Reactivate ${t.name}?`}
          description={prompt === 'suspend'
            ? 'Every user of this business is signed out of new logins immediately. Their data is kept; nothing is deleted.'
            : 'Its users can sign in again straight away.'}
          confirmLabel={prompt === 'suspend' ? 'Suspend' : 'Reactivate'}
          danger={prompt === 'suspend'}
          busy={saving}
          error={error}
          onConfirm={confirm}
          onCancel={() => { setPrompt(null); setError(null); }}
        />
      )}
    </>
  );
}

export default function PlatformTenantsPage() {
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [businessType, setBusinessType] = useState('');
  const [page, setPage] = useState(1);
  const debounced = useDebounced(search);
  const { data, isLoading, isFetching } = useTenantsQuery({ search: debounced || undefined, status: status || undefined, businessType: businessType || undefined, page, pageSize: 20 });
  const open = params.get('open');

  useEffect(() => { setPage(1); }, [debounced, status, businessType]);

  const setOpen = (id: string | null) => {
    const next = new URLSearchParams(params);
    if (id) next.set('open', id); else next.delete('open');
    setParams(next, { replace: true });
  };

  const rows: PlatformTenantRow[] = data?.items ?? [];

  return (
    <PlatformLayout title="Tenants">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Businesses on the platform</div>
          <h1>Tenants</h1>
          <p>Every business registered on Unify. Open one for its people, footprint and the suspend switch.</p>
        </div>
      </div>

      <div className="pf-filters">
        <input className="pf-input" placeholder="Search by name or contact email…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search tenants" />
        <select className="pf-select" value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Status">
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="suspended">Suspended</option>
        </select>
        <select className="pf-select" value={businessType} onChange={(e) => setBusinessType(e.target.value)} aria-label="Business type">
          <option value="">All business types</option>
          {(data?.businessTypes ?? []).map((b) => <option key={b} value={b}>{b}</option>)}
        </select>
        <span className="pf-filters-spacer" />
        <span className="pf-count">{data ? `${n(data.total)} tenant${data.total === 1 ? '' : 's'}` : ''}{isFetching && ' · updating…'}</span>
      </div>

      <div className="pf-table-wrap">
        <table className="pf-table">
          <thead>
            <tr>
              <th>Business</th><th>Type</th><th>Admin</th><th className="num">Users</th><th className="num">Branches</th><th className="num">Bookings</th><th className="num">30 d</th><th>Last booking</th><th>Joined</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {isLoading && <tr><td colSpan={10} className="pf-empty">Loading tenants…</td></tr>}
            {!isLoading && rows.length === 0 && <tr><td colSpan={10} className="pf-empty">No tenants match.</td></tr>}
            {rows.map((t) => (
              <tr key={t.id} style={{ cursor: 'pointer' }} onClick={() => setOpen(t.id)}>
                <td><strong>{t.name}</strong><small>{t.contactEmail ?? t.id.slice(0, 8)}</small></td>
                <td>{t.businessType}{t.subType && <small>{t.subType}</small>}</td>
                <td>{t.adminEmail ?? <span className="pf-count">none</span>}</td>
                <td className="num">{n(t.userCount)}</td>
                <td className="num">{n(t.branchCount)}</td>
                <td className="num">{n(t.bookingCount)}</td>
                <td className="num">{n(t.bookings30d)}</td>
                <td>{day(t.lastBookingAt)}</td>
                <td>{day(t.createdAt)}</td>
                <td><span className={`pf-pill ${t.isActive ? 'pf-pill-good' : 'pf-pill-bad'}`}>{t.isActive ? 'Active' : 'Suspended'}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {data && data.totalPages > 1 && (
        <div className="pf-pager">
          <button type="button" className="pf-btn pf-btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>← Prev</button>
          <span>Page {data.page} of {data.totalPages}</span>
          <button type="button" className="pf-btn pf-btn-sm" disabled={page >= data.totalPages} onClick={() => setPage((p) => p + 1)}>Next →</button>
        </div>
      )}

      {open && <TenantDrawer id={open} onClose={() => setOpen(null)} />}
    </PlatformLayout>
  );
}
