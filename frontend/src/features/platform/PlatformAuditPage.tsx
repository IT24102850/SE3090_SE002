import { useEffect, useState } from 'react';
import PlatformLayout from './PlatformLayout';
import { useAuditQuery } from './platformApi';

const n = (v: number) => v.toLocaleString();
const when = (iso: string) => new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'medium' });

const GROUPS: { label: string; prefix: string }[] = [
  { label: 'All events', prefix: '' },
  { label: 'Sign-ins', prefix: 'auth.login' },
  { label: 'MFA', prefix: 'auth.mfa' },
  { label: 'Sessions', prefix: 'auth.session' },
  { label: 'Passwords', prefix: 'auth.password' },
  { label: 'Tenant changes', prefix: 'tenant.' },
  { label: 'User changes', prefix: 'user.' },
  { label: 'Refused actions', prefix: 'action.' },
];

export default function PlatformAuditPage() {
  const [prefix, setPrefix] = useState('');
  const [outcome, setOutcome] = useState('');
  const [search, setSearch] = useState('');
  const [debounced, setDebounced] = useState('');
  const [page, setPage] = useState(1);
  useEffect(() => { const id = window.setTimeout(() => setDebounced(search), 300); return () => window.clearTimeout(id); }, [search]);
  useEffect(() => { setPage(1); }, [prefix, outcome, debounced]);

  const { data, isLoading, isFetching } = useAuditQuery({
    action: prefix || undefined,
    succeeded: outcome === '' ? undefined : outcome === 'ok',
    search: debounced || undefined,
    page,
    pageSize: 50,
  });

  const exportCsv = () => {
    if (!data) return;
    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const lines = [
      ['time', 'actor', 'action', 'target', 'detail', 'outcome', 'ip', 'userAgent'].join(','),
      ...data.items.map((a) => [a.createdAt, a.actorEmail, a.action, a.targetLabel, a.detail, a.succeeded ? 'ok' : 'failed', a.ipAddress, a.userAgent].map(esc).join(',')),
    ];
    const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `unify-platform-audit-page${data.page}.csv`; a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <PlatformLayout title="Audit log">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Append-only</div>
          <h1>Audit log</h1>
          <p>Every sign-in attempt, code check, session change and owner action - with the address it came from. Nothing here can be edited or deleted.</p>
        </div>
        <button type="button" className="pf-btn" onClick={exportCsv} disabled={!data || data.items.length === 0}>⇩ Export this page (CSV)</button>
      </div>

      <div className="pf-filters">
        <select className="pf-select" value={prefix} onChange={(e) => setPrefix(e.target.value)} aria-label="Event group">
          {GROUPS.map((g) => <option key={g.prefix} value={g.prefix}>{g.label}</option>)}
        </select>
        <select className="pf-select" value={outcome} onChange={(e) => setOutcome(e.target.value)} aria-label="Outcome">
          <option value="">Any outcome</option>
          <option value="ok">Succeeded</option>
          <option value="failed">Failed</option>
        </select>
        <input className="pf-input" placeholder="Search actor, target, detail or IP…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search audit log" />
        <span className="pf-filters-spacer" />
        <span className="pf-count">{data ? `${n(data.total)} event${data.total === 1 ? '' : 's'}` : ''}{isFetching && ' · updating…'}</span>
      </div>

      <div className="pf-table-wrap">
        <table className="pf-table">
          <thead><tr><th>When</th><th>Action</th><th>Actor</th><th>Target</th><th>Detail</th><th>From</th><th>Outcome</th></tr></thead>
          <tbody>
            {isLoading && <tr><td colSpan={7} className="pf-empty">Loading…</td></tr>}
            {!isLoading && (data?.items.length ?? 0) === 0 && <tr><td colSpan={7} className="pf-empty">No events match.</td></tr>}
            {data?.items.map((a) => (
              <tr key={a.id}>
                <td style={{ whiteSpace: 'nowrap' }}>{when(a.createdAt)}</td>
                <td className="pf-mono">{a.action}</td>
                <td>{a.actorEmail}</td>
                <td>{a.targetLabel ?? '—'}{a.targetType && <small>{a.targetType}</small>}</td>
                <td style={{ maxWidth: 320 }}>{a.detail ?? '—'}</td>
                <td className="pf-mono" title={a.userAgent}>{a.ipAddress}</td>
                <td><span className={`pf-pill ${a.succeeded ? 'pf-pill-good' : 'pf-pill-bad'}`}>{a.succeeded ? 'ok' : 'failed'}</span></td>
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
    </PlatformLayout>
  );
}
