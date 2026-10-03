import { useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { errorMessage, useEnrolMfaMutation, useLoginMutation, type PlatformLoginResult } from './platformApi';
import { clearPlatformSession, isPlatformSessionLive, storePlatformSession } from './platformSession';
import { useToast } from '../../shared/components/Toast';
import './platform.css';

/* Sign-in for the platform console. Three screens in one card:
 *   1. email + password
 *   2. the 6-digit code (every sign-in after enrolment)
 *   2'. first-time enrolment: scan the QR, confirm one code
 * A session only ever comes back from the server after step 2 or 2'. */

type Step = 'credentials' | 'code' | 'enrol';

export default function PlatformLoginPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [step, setStep] = useState<Step>('credentials');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [setup, setSetup] = useState<{ setupToken: string; secret: string; otpauthUri: string } | null>(null);
  const [error, setError] = useState<string | null>(
    params.get('reason') === 'expired' ? 'Your session ended. Sign in again to continue.' : null,
  );
  const [login, { isLoading: loggingIn }] = useLoginMutation();
  const [enrol, { isLoading: enrolling }] = useEnrolMfaMutation();
  const { show } = useToast();

  useEffect(() => {
    document.documentElement.dataset.theme = 'dark';
    if (isPlatformSessionLive()) navigate('/platform', { replace: true });
    return () => { document.documentElement.dataset.theme = localStorage.getItem('unify-theme') || 'light'; };
  }, [navigate]);

  const finish = (result: PlatformLoginResult) => {
    if (result.status === 'ok' && result.accessToken && result.expiresAt) {
      storePlatformSession(result.accessToken, result.expiresAt, result.idleTimeoutMinutes ?? 15);
      const name = result.user?.fullName?.trim() || result.user?.email?.split('@')[0] || 'there';
      show(`Welcome back, ${name}!`, 'success');
      navigate('/platform', { replace: true });
      return true;
    }
    return false;
  };

  const submitCredentials = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      const result = await login({ email: email.trim(), password, code: code || undefined }).unwrap();
      if (finish(result)) return;
      if (result.status === 'mfaRequired') { setStep('code'); setCode(''); return; }
      if (result.status === 'mfaSetupRequired' && result.setupToken && result.secret && result.otpauthUri) {
        setSetup({ setupToken: result.setupToken, secret: result.secret, otpauthUri: result.otpauthUri });
        setStep('enrol');
        setCode('');
        return;
      }
      setError(result.message || 'Unexpected response.');
    } catch (err) {
      setError(errorMessage(err, 'Sign-in failed.'));
    }
  };

  const submitEnrol = async (e: FormEvent) => {
    e.preventDefault();
    if (!setup) return;
    setError(null);
    try {
      const result = await enrol({ setupToken: setup.setupToken, code }).unwrap();
      if (!finish(result)) setError(result.message || 'Enrolment failed.');
    } catch (err) {
      setError(errorMessage(err, 'Enrolment failed.'));
    }
  };

  const restart = () => {
    clearPlatformSession();
    setStep('credentials');
    setCode('');
    setSetup(null);
    setError(null);
  };

  const busy = loggingIn || enrolling;

  return (
    <main className="pf-login">
      <section className="pf-login-card" aria-labelledby="pf-login-title">
        <div className="pf-brand">
          <span className="pf-brand-mark" aria-hidden="true">🛡️</span>
          <span><strong>Unify</strong><small>Platform console</small></span>
        </div>
        <div className="pf-login-steps" aria-hidden="true">
          <span className="done" />
          <span className={step !== 'credentials' ? 'done' : ''} />
        </div>

        {step === 'credentials' && (
          <form className="pf-form" onSubmit={submitCredentials}>
            <div>
              <h1 id="pf-login-title">Owner sign-in</h1>
              <p>This console is restricted to the platform owner. Every attempt is recorded.</p>
            </div>
            {error && <div className="pf-error" role="alert">{error}</div>}
            <div className="pf-field">
              <label htmlFor="pf-email">Email</label>
              <input id="pf-email" className="pf-input" type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
            </div>
            <div className="pf-field">
              <label htmlFor="pf-password">Password</label>
              <input id="pf-password" className="pf-input" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </div>
            <button className="pf-btn pf-btn-primary" type="submit" disabled={busy}>{busy ? 'Checking…' : 'Continue →'}</button>
          </form>
        )}

        {step === 'code' && (
          <form className="pf-form" onSubmit={submitCredentials}>
            <div>
              <h1 id="pf-login-title">Authenticator code</h1>
              <p>Open your authenticator app and enter the 6-digit code for <b>{email}</b>.</p>
            </div>
            {error && <div className="pf-error" role="alert">{error}</div>}
            <div className="pf-field">
              <label htmlFor="pf-code">6-digit code</label>
              <input id="pf-code" className="pf-input pf-otp-input" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9 ]*" maxLength={7} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} required autoFocus />
            </div>
            <button className="pf-btn pf-btn-primary" type="submit" disabled={busy || code.length !== 6}>{busy ? 'Verifying…' : 'Sign in'}</button>
            <button className="pf-btn" type="button" onClick={restart}>Start over</button>
          </form>
        )}

        {step === 'enrol' && setup && (
          <form className="pf-form" onSubmit={submitEnrol}>
            <div>
              <h1 id="pf-login-title">Set up two-factor sign-in</h1>
              <p>First sign-in: scan this with Google Authenticator, Authy, 1Password or any TOTP app, then enter the code it shows. From now on the console needs it every time.</p>
            </div>
            {error && <div className="pf-error" role="alert">{error}</div>}
            <div className="pf-qr"><QRCodeSVG value={setup.otpauthUri} size={180} level="M" /></div>
            <details>
              <summary style={{ cursor: 'pointer', fontSize: '.78rem', color: 'rgba(238,243,250,.7)' }}>Can't scan? Enter the key manually</summary>
              <div className="pf-secret pf-mono" style={{ marginTop: 8 }}>{setup.secret.replace(/(.{4})/g, '$1 ').trim()}</div>
            </details>
            <div className="pf-field">
              <label htmlFor="pf-enrol-code">Code from the app</label>
              <input id="pf-enrol-code" className="pf-input pf-otp-input" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} required autoFocus />
            </div>
            <button className="pf-btn pf-btn-primary" type="submit" disabled={busy || code.length !== 6}>{busy ? 'Confirming…' : 'Confirm and sign in'}</button>
            <button className="pf-btn" type="button" onClick={restart}>Cancel</button>
          </form>
        )}

        <div className="pf-login-foot">
          Not the owner? <Link to="/login">Go to the workspace sign-in</Link>
        </div>
      </section>
    </main>
  );
}
