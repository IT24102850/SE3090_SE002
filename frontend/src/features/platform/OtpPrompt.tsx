import { useState, type FormEvent } from 'react';

/* Step-up confirmation for anything that changes someone's access:
 * suspend a tenant, lock a user, hand out a temporary password. The code is
 * sent in the X-Platform-Otp header on that one request and burned
 * server-side, so it cannot be reused. */

export interface OtpPromptProps {
  title: string;
  description: string;
  confirmLabel?: string;
  danger?: boolean;
  withReason?: boolean;
  busy?: boolean;
  error?: string | null;
  onConfirm: (code: string, reason: string) => void;
  onCancel: () => void;
}

export default function OtpPrompt({ title, description, confirmLabel = 'Confirm', danger, withReason = true, busy, error, onConfirm, onCancel }: OtpPromptProps) {
  const [code, setCode] = useState('');
  const [reason, setReason] = useState('');

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (code.length === 6) onConfirm(code, reason.trim());
  };

  return (
    <div className="pf-modal-backdrop" role="presentation" onMouseDown={onCancel}>
      <form className="pf-modal" role="dialog" aria-modal="true" aria-labelledby="pf-otp-title" onMouseDown={(e) => e.stopPropagation()} onSubmit={submit}>
        <span className="pf-eyebrow">Confirm with your authenticator</span>
        <h2 id="pf-otp-title">{title}</h2>
        <p>{description}</p>
        {error && <div className="pf-error" role="alert">{error}</div>}
        {withReason && (
          <div className="pf-field">
            <label htmlFor="pf-otp-reason">Reason (kept in the audit log)</label>
            <input id="pf-otp-reason" className="pf-input" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Optional" />
          </div>
        )}
        <div className="pf-field">
          <label htmlFor="pf-otp-code">6-digit code</label>
          <input id="pf-otp-code" className="pf-input pf-otp-input" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} autoFocus required />
        </div>
        <div className="pf-modal-actions">
          <button type="button" className="pf-btn" onClick={onCancel} disabled={busy}>Cancel</button>
          <button type="submit" className={`pf-btn ${danger ? 'pf-btn-danger' : 'pf-btn-primary'}`} disabled={busy || code.length !== 6}>{busy ? 'Working…' : confirmLabel}</button>
        </div>
      </form>
    </div>
  );
}
