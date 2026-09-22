import { useState, type FormEvent } from 'react';
import PlatformLayout from './PlatformLayout';
import { errorMessage, useChangePasswordMutation, useMeQuery, useRevokeOtherSessionsMutation, useRevokeSessionMutation, useSessionsQuery } from './platformApi';

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—');

function shortAgent(ua: string) {
  if (!ua) return 'unknown';
  const browser = /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : 'Browser';
  const os = /Windows/.test(ua) ? 'Windows' : /Mac OS/.test(ua) ? 'macOS' : /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Linux/.test(ua) ? 'Linux' : '';
  return os ? `${browser} · ${os}` : browser;
}

const RULES = [
  ['Password', 'BCrypt work factor 12; at least 14 characters with upper, lower, a digit and a symbol.'],
  ['Second factor', 'TOTP (RFC 6238) from an authenticator app on every sign-in; each code is single-use.'],
  ['Secret at rest', 'The authenticator secret is AES-256-GCM encrypted with a key held in server configuration, not the database.'],
  ['Lockout', '5 wrong attempts lock the account for 15 minutes; sign-in is also limited to 5 tries a minute per address.'],
  ['Sessions', 'Every token is bound to a server-side session: 60 minutes hard, 15 minutes idle, revocable from this page.'],
  ['Step-up', 'Suspending a tenant, deactivating a user or resetting a password asks for a fresh code each time.'],
  ['Isolation', 'The owner account is invisible to the ordinary sign-in and carries no tenant permissions; this console is the only door.'],
  ['Audit', 'Every attempt and action is written to an append-only log with its IP address and browser.'],
] as const;

export default function PlatformSecurityPage() {
  const { data: me } = useMeQuery();
  const { data: sessions, isLoading } = useSessionsQuery(undefined, { pollingInterval: 30_000 });
  const [revoke, { isLoading: revoking }] = useRevokeSessionMutation();
  const [revokeOthers, { isLoading: revokingAll }] = useRevokeOtherSessionsMutation();
  const [changePassword, { isLoading: changing }] = useChangePasswordMutation();

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [code, setCode] = useState('');
  const [pwError, setPwError] = useState<string | null>(null);
  const [pwOk, setPwOk] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const strength = (() => {
    const checks = [next.length >= 14, /[A-Z]/.test(next) && /[a-z]/.test(next), /\d/.test(next), /[^A-Za-z0-9]/.test(next)];
    return checks.filter(Boolean).length;
  })();

  const submitPassword = async (e: FormEvent) => {
    e.preventDefault();
    setPwError(null); setPwOk(null);
    if (next !== again) { setPwError('The new passwords do not match.'); return; }
    if (strength < 4) { setPwError('Use at least 14 characters with upper and lower case, a digit and a symbol.'); return; }
    try {
      const r = await changePassword({ currentPassword: current, newPassword: next, code }).unwrap();
      setPwOk(r.message);
      setCurrent(''); setNext(''); setAgain(''); setCode('');
    } catch (err) {
      setPwError(errorMessage(err, 'Password change refused.'));
    }
  };

  const live = sessions?.filter((s) => s.isLive) ?? [];
  const past = sessions?.filter((s) => !s.isLive) ?? [];

  return (
    <PlatformLayout title="Security">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Owner account</div>
          <h1>Security</h1>
          <p>Your own sign-ins, the consoles currently open, and the password.</p>
        </div>
      </div>

      {notice && <div className="pf-alert pf-alert-good"><div><b>{notice}</b></div><button type="button" className="pf-btn pf-btn-sm" onClick={() => setNotice(null)}>Dismiss</button></div>}

      <div className="pf-grid pf-grid-3">
        <div className="pf-card pf-kpi"><div className="pf-kpi-label">Two-factor</div><div className="pf-kpi-value" style={{ fontSize: '1.2rem' }}>{me?.mfaEnabledAt ? 'Enrolled' : 'Not enrolled'}</div><div className="pf-kpi-sub">{me?.mfaEnabledAt ? `since ${when(me.mfaEnabledAt)}` : 'sign in again to enrol'}</div></div>
        <div className="pf-card pf-kpi"><div className="pf-kpi-label">Last sign-in</div><div className="pf-kpi-value" style={{ fontSize: '1.2rem' }}>{when(me?.lastLoginAt)}</div><div className="pf-kpi-sub">from {me?.lastLoginIp ?? '—'}</div></div>
        <div className="pf-card pf-kpi"><div className="pf-kpi-label">Password changed</div><div className="pf-kpi-value" style={{ fontSize: '1.2rem' }}>{when(me?.passwordChangedAt)}</div><div className="pf-kpi-sub">rotate every 90 days</div></div>
      </div>

      <div className="pf-grid pf-grid-21">
        <div className="pf-card">
          <div className="pf-card-head">
            <h2>Open consoles</h2>
            <button type="button" className="pf-btn pf-btn-sm pf-btn-danger" disabled={revokingAll || live.length <= 1} onClick={async () => { const r = await revokeOthers().unwrap(); setNotice(`${r.revoked} other session(s) signed out.`); }}>Sign out everywhere else</button>
          </div>
          <div className="pf-table-wrap" style={{ border: 0 }}>
            <table className="pf-table">
              <thead><tr><th>Where</th><th>Signed in</th><th>Last seen</th><th>Ends</th><th></th></tr></thead>
              <tbody>
                {isLoading && <tr><td colSpan={5} className="pf-empty">Loading…</td></tr>}
                {live.map((s) => (
                  <tr key={s.id}>
                    <td><strong>{s.ipAddress}</strong>{s.isCurrent && <span className="pf-pill pf-pill-accent" style={{ marginLeft: 8 }}>this one</span>}<small>{shortAgent(s.userAgent)}</small></td>
                    <td>{when(s.createdAt)}</td>
                    <td>{when(s.lastSeenAt)}</td>
                    <td>{when(s.expiresAt)}</td>
                    <td><div className="pf-actions">{!s.isCurrent && <button type="button" className="pf-btn pf-btn-sm pf-btn-danger" disabled={revoking} onClick={() => revoke(s.id)}>Revoke</button>}</div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {past.length > 0 && (
            <details style={{ marginTop: 12 }}>
              <summary style={{ cursor: 'pointer', fontSize: '.8rem', color: 'var(--color-text-secondary)' }}>Past sessions ({past.length})</summary>
              <div className="pf-table-wrap" style={{ border: 0, marginTop: 8 }}>
                <table className="pf-table">
                  <thead><tr><th>Where</th><th>Signed in</th><th>Ended</th><th>Why</th></tr></thead>
                  <tbody>
                    {past.map((s) => (
                      <tr key={s.id}>
                        <td>{s.ipAddress}<small>{shortAgent(s.userAgent)}</small></td>
                        <td>{when(s.createdAt)}</td>
                        <td>{when(s.revokedAt ?? s.expiresAt)}</td>
                        <td><span className="pf-pill pf-pill-neutral">{s.revokedReason ?? 'expired'}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          )}
        </div>

        <div className="pf-card">
          <div className="pf-card-head"><h2>Change password</h2><span>needs a code</span></div>
          <form className="pf-form" onSubmit={submitPassword}>
            {pwError && <div className="pf-error" role="alert">{pwError}</div>}
            {pwOk && <div className="pf-ok">{pwOk}</div>}
            <div className="pf-field"><label htmlFor="pf-pw-current">Current password</label><input id="pf-pw-current" className="pf-input" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} required /></div>
            <div className="pf-field">
              <label htmlFor="pf-pw-next">New password</label>
              <input id="pf-pw-next" className="pf-input" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} required minLength={14} />
              <div className="pf-login-steps" aria-hidden="true">{[1, 2, 3, 4].map((i) => <span key={i} className={strength >= i ? 'done' : ''} style={{ background: strength >= i ? 'var(--pf-accent)' : 'var(--color-surface-muted)' }} />)}</div>
              <span className="pf-count">14+ characters, upper and lower case, a digit, a symbol.</span>
            </div>
            <div className="pf-field"><label htmlFor="pf-pw-again">Repeat new password</label><input id="pf-pw-again" className="pf-input" type="password" autoComplete="new-password" value={again} onChange={(e) => setAgain(e.target.value)} required /></div>
            <div className="pf-field"><label htmlFor="pf-pw-code">Authenticator code</label><input id="pf-pw-code" className="pf-input pf-otp-input" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} required /></div>
            <button type="submit" className="pf-btn pf-btn-primary" disabled={changing || code.length !== 6}>{changing ? 'Changing…' : 'Change password'}</button>
            <span className="pf-count">Every other open console is signed out when the password changes.</span>
          </form>
        </div>
      </div>

      <div className="pf-card">
        <div className="pf-card-head"><h2>How this console is protected</h2></div>
        <dl className="pf-kv" style={{ gridTemplateColumns: '150px 1fr' }}>
          {RULES.map(([k, v]) => <><dt key={`${k}-k`}>{k}</dt><dd key={`${k}-v`}>{v}</dd></>)}
        </dl>
      </div>
    </PlatformLayout>
  );
}
