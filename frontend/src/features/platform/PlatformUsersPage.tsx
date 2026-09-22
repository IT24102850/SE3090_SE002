import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import PlatformLayout from './PlatformLayout';
import OtpPrompt from './OtpPrompt';
import { errorMessage, useResetUserPasswordMutation, useSetUserActiveMutation, useUsersQuery, type PlatformUserRow } from './platformApi';

const n = (v: number) => v.toLocaleString();
const day = (iso: string) => new Date(iso).toLocaleDateString([], { dateStyle: 'medium' });

type Pending = { kind: 'deactivate' | 'activate' | 'reset'; user: PlatformUserRow };

export default function PlatformUsersPage() {
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [debounced, setDebounced] = useState('');
  useEffect(() => { const id = window.setTimeout(() => setDebounced(search), 300); return () => window.clearTimeout(id); }, [search]);
  useEffect(() => { setPage(1); }, [debounced, role, status]);

  const { data, isLoading, isFetching } = useUsersQuery({ search: debounced || undefined, role: role || undefined, status: status || undefined, page, pageSize: 25 });
  const [setActive, { isLoading: savingActive }] = useSetUserActiveMutation();
  const [resetPassword, { isLoading: savingReset }] = useResetUserPasswordMutation();
  const [pending, setPending] = useState<Pending | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ text: string; secret?: string } | null>(null);

  const confirm = async (code: string, reason: string) => {
    if (!pending) return;
    setError(null);
    try {
      if (pending.kind === 'reset') {
        const r = await resetPassword({ id: pending.user.id, reason, otp: code }).unwrap();
        setNotice({ text: `Temporary password for ${pending.user.email}. It is shown once - copy it now.`, secret: r.temporaryPassword });
      } else {
        const r = await setActive({ id: pending.user.id, active: pending.kind === 'activate', reason, otp: code }).unwrap();
        setNotice({ text: `${pending.user.email}: ${r.message}` });
      }
      setPending(null);
    } catch (err) {
      setError(errorMessage(err, 'The change was refused.'));
    }
  };

  const copy = (text: string) => { void navigator.clipboard?.writeText(text); };

  return (
    <PlatformLayout title="Users">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Everyone on the platform</div>
          <h1>Users</h1>
          <p>Admins, managers, staff and customers across every tenant. Deactivating someone blocks their sign-in immediately; a password reset issues a one-time temporary password.</p>
        </div>
      </div>

      {notice && (
        <div className="pf-alert pf-alert-good">
          <div style={{ flex: 1 }}>
            <b>{notice.text}</b>
            {notice.secret && (
              <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 6 }}>
                <code className="pf-secret pf-mono" style={{ padding: '6px 10px', fontSize: '1rem' }}>{notice.secret}</code>
                <button type="button" className="pf-btn pf-btn-sm" onClick={() => copy(notice.secret!)}>Copy</button>
              </div>
            )}
          </div>
          <button type="button" className="pf-btn pf-btn-sm" onClick={() => setNotice(null)}>Dismiss</button>
        </div>
      )}

      <div className="pf-filters">
        <input className="pf-input" placeholder="Search by name or email…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search users" />
        <select className="pf-select" value={role} onChange={(e) => setRole(e.target.value)} aria-label="Role">
          <option value="">All roles</option>
          {['Admin', 'Manager', 'Staff', 'Customer'].map((r) => <option key={r} value={r}>{r}</option>)}
        </select>
        <select className="pf-select" value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Status">
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Deactivated</option>
        </select>
        <span className="pf-filters-spacer" />
        <span className="pf-count">{data ? `${n(data.total)} user${data.total === 1 ? '' : 's'}` : ''}{isFetching && ' · updating…'}</span>
      </div>

      <div className="pf-table-wrap">
        <table className="pf-table">
          <thead>
            <tr><th>Person</th><th>Role</th><th>Tenant</th><th>Joined</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            {isLoading && <tr><td colSpan={6} className="pf-empty">Loading users…</td></tr>}
            {!isLoading && (data?.items.length ?? 0) === 0 && <tr><td colSpan={6} className="pf-empty">No users match.</td></tr>}
            {data?.items.map((u) => (
              <tr key={u.id}>
                <td><strong>{u.fullName || '(no name)'}</strong><small>{u.email}{u.phone && ` · ${u.phone}`}</small></td>
                <td><span className={`pf-pill ${u.role === 'Admin' ? 'pf-pill-accent' : 'pf-pill-neutral'}`}>{u.role}</span></td>
                <td>
                  {u.isGlobalCustomer ? (
                    <>
                      <span style={{ fontWeight: 600 }}>Global customer</span>
                      <small>{u.membershipCount === 0 ? 'no businesses joined yet' : `${u.membershipCount} business${u.membershipCount === 1 ? '' : 'es'} joined`}</small>
                    </>
                  ) : (
                    <>
                      <Link to={`/platform/tenants?open=${u.tenantId}`} style={{ color: 'inherit', fontWeight: 600 }}>{u.tenantName}</Link>
                      <small>{u.tenantBusinessType}{!u.tenantActive && ' · tenant suspended'}</small>
                    </>
                  )}
                </td>
                <td>{day(u.createdAt)}</td>
                <td>
                  <span className={`pf-pill ${u.isActive ? 'pf-pill-good' : 'pf-pill-bad'}`}>{u.isActive ? 'Active' : 'Deactivated'}</span>
                  {!u.isApproved && <span className="pf-pill pf-pill-warn" style={{ marginLeft: 6 }}>Pending approval</span>}
                </td>
                <td>
                  <div className="pf-actions">
                    <button type="button" className="pf-btn pf-btn-sm" onClick={() => setPending({ kind: 'reset', user: u })}>Reset password</button>
                    {u.isActive
                      ? <button type="button" className="pf-btn pf-btn-sm pf-btn-danger" onClick={() => setPending({ kind: 'deactivate', user: u })}>Deactivate</button>
                      : <button type="button" className="pf-btn pf-btn-sm" onClick={() => setPending({ kind: 'activate', user: u })}>Reactivate</button>}
                  </div>
                </td>
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

      {pending && (
        <OtpPrompt
          title={
            pending.kind === 'reset' ? `Reset the password for ${pending.user.email}?`
              : pending.kind === 'deactivate' ? `Deactivate ${pending.user.email}?`
                : `Reactivate ${pending.user.email}?`
          }
          description={
            pending.kind === 'reset' ? 'Their current password stops working. You will be shown a temporary one exactly once, to pass on out-of-band.'
              : pending.kind === 'deactivate' ? 'They can no longer sign in to the web app or the mobile app. Nothing is deleted.'
                : 'They can sign in again straight away.'
          }
          confirmLabel={pending.kind === 'reset' ? 'Issue temporary password' : pending.kind === 'deactivate' ? 'Deactivate' : 'Reactivate'}
          danger={pending.kind !== 'activate'}
          busy={savingActive || savingReset}
          error={error}
          onConfirm={confirm}
          onCancel={() => { setPending(null); setError(null); }}
        />
      )}
    </PlatformLayout>
  );
}
