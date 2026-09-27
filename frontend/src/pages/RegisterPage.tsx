import { API_BASE_URL } from '../api/apiBaseUrl';
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import axios from 'axios';
import { useDispatch } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { TOURISM_SUB_TYPES } from '../features/booking/types';
import SegmentedToggle from '../features/marketing/SegmentedToggle';
import { useToast } from '../shared/components/Toast';
import { initializeAuth } from '../store/authSlice';
import type { AppDispatch } from '../store/store';
import '../features/marketing/landing.css';
import './signup.css';

/* Sign-up: a form half and an art half in one card.
 *
 * Two genuinely different things behind one toggle, which is why the toggle
 * is here and not on the sign-in page: registering a business creates a
 * tenant, registering as a customer joins one that already exists. They hit
 * different endpoints, collect different fields, and cannot be merged.
 *
 *   Business  POST /api/tenant/onboard   creates the tenant + an Admin user
 *   Customer  POST /api/auth/register    creates one global customer account
 *
 * A customer account is not tied to a business: they join one automatically
 * the first time they open it in the Unify app (Services/
 * CustomerAccountService.cs on the backend), so the form asks for nothing
 * but who they are. Customers do their booking in the app, not here, which
 * is why a successful sign-up ends on a "you're all set" panel rather than
 * in the admin dashboard.
 *
 * Role is never client-supplied on either route - the customer endpoint
 * assigns Customer regardless of what is sent, which is what makes it safe to
 * expose this choice in the UI at all.
 *
 * Fields validate as they are typed: a green tick the moment a value is
 * acceptable, a checklist under the password. The password policy here
 * (8+, a number or symbol, mixed case) is stricter than the API's minimum of
 * 6 on purpose - this is the account that will own a business's data.
 */

type Mode = 'business' | 'customer';

const MODES = [
  { id: 'business' as const, label: 'A business' },
  { id: 'customer' as const, label: 'A customer' },
];

const BUSINESS_TYPES = [
  { value: 'Tourism', label: 'Tourism' },
  { value: 'Clinic', label: 'Clinic' },
  { value: 'Restaurant', label: 'Restaurant' },
  { value: 'Gym', label: 'Gym' },
  { value: 'School', label: 'School' },
  { value: 'RealEstate', label: 'Real Estate' },
  { value: 'General', label: 'General' },
];

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const validName = (v: string) => v.trim().length >= 2;
const validEmail = (v: string) => EMAIL_RE.test(v.trim());
const validPhone = (v: string) => v.replace(/\D/g, '').length >= 7;
const passwordRules = (v: string) => ({
  length: v.length >= 8,
  numberOrSymbol: /[0-9]|[^A-Za-z0-9]/.test(v),
  mixedCase: /[a-z]/.test(v) && /[A-Z]/.test(v),
});
const validPassword = (v: string) => Object.values(passwordRules(v)).every(Boolean);

/* ── Icons (inline, so the page needs no icon package) ────────────── */
const I = {
  user: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 3.6-7 8-7s8 3 8 7" /></svg>,
  mail: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" /></svg>,
  lock: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="4" y="11" width="16" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></svg>,
  building: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16" /><path d="M16 9h2a2 2 0 0 1 2 2v10" /><path d="M8 7h4M8 11h4M8 15h4M4 21h18" /></svg>,
  tag: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M20 13 13 20a2 2 0 0 1-2.8 0L3 12.8V4h8.8L20 12.2a2 2 0 0 1 0 .8Z" /><circle cx="7.5" cy="7.5" r="1.2" /></svg>,
  pin: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11Z" /><circle cx="12" cy="10" r="2.5" /></svg>,
  phone: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2Z" /></svg>,
  store: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9l1.5-5h15L21 9" /><path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0" /><path d="M5 12v9h14v-9M10 21v-6h4v6" /></svg>,
  check: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="m8.5 12.5 2.3 2.3 4.7-5" /></svg>,
  eye: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" /><circle cx="12" cy="12" r="3" /></svg>,
  eyeOff: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" /><circle cx="12" cy="12" r="3" /><path d="M3 3l18 18" /></svg>,
  key: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="8" cy="15" r="4" /><path d="m11 12 9-9M15 8l2 2M18 5l2 2" /></svg>,
};

/* An underline field: icon, control, and a tick once the value is valid. */
function Field({ icon, label, valid, filled, children, trailing }: {
  icon: ReactNode; label: string; valid: boolean | null; filled?: boolean; children: ReactNode; trailing?: ReactNode;
}) {
  // valid is null while the field is empty, so it doubles as "has a value"
  // unless the caller says otherwise (a select always has one).
  const hasValue = filled ?? valid !== null;
  const cls = ['su-field', hasValue ? 'has-value' : '', valid === true ? 'is-valid' : '', valid === false ? 'is-invalid' : ''].filter(Boolean).join(' ');
  return (
    <div className={cls}>
      <span className="su-field-icon" aria-hidden="true">{icon}</span>
      {children}
      <span className="su-mark" aria-hidden="true">{trailing ?? (valid ? I.check : null)}</span>
      <label aria-hidden="true">{label}</label>
    </div>
  );
}

const RegisterPage = () => {
  const [mode, setMode] = useState<Mode>('business');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [theme, setTheme] = useState<'light' | 'dark'>(() =>
    localStorage.getItem('unify-home-theme') === 'dark' ? 'dark' : 'light',
  );
  const navigate = useNavigate();
  const dispatch = useDispatch<AppDispatch>();
  const { show } = useToast();

  const [form, setForm] = useState({
    businessName: '',
    businessType: 'Tourism',
    subType: '',
    address: '',
    phone: '',
    adminEmail: '',
    adminPassword: '',
    adminFullName: '',
    adminPhone: '',
  });

  const [customer, setCustomer] = useState({
    fullName: '',
    email: '',
    password: '',
    phone: '',
  });
  const [customerDone, setCustomerDone] = useState<string | null>(null);

  useEffect(() => { if (error) show(error, 'error'); }, [error, show]);
  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => { delete document.documentElement.dataset.unifyTheme; };
  }, [theme]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setForm((prev) => ({
      ...prev,
      [name]: value,
      ...(name === 'businessType' && value !== 'Tourism' ? { subType: '' } : {}),
    }));
  };

  const handleCustomerChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setCustomer((prev) => ({ ...prev, [name]: value }));
  };

  const switchMode = (next: Mode) => {
    setMode(next);
    // The two forms fail for different reasons; carrying one's error into the
    // other tells the visitor their new form is broken before they touch it.
    setError('');
    setConfirm('');
  };

  const password = mode === 'business' ? form.adminPassword : customer.password;
  const rules = useMemo(() => passwordRules(password), [password]);
  const confirmValid: boolean | null = confirm ? confirm === password : null;
  const v = (ok: boolean, value: string): boolean | null => (value ? ok : null);

  const formValid = mode === 'business'
    ? validName(form.businessName) && validName(form.adminFullName) && validEmail(form.adminEmail) && validPassword(form.adminPassword) && confirm === form.adminPassword
    : validName(customer.fullName) && validEmail(customer.email) && validPassword(customer.password) && confirm === customer.password;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formValid) {
      setError(confirm !== password ? 'The two passwords do not match.' : 'Please complete the highlighted fields.');
      return;
    }
    setLoading(true);
    setError('');

    try {
      if (mode === 'customer') {
        // No token is kept: the admin web app has nothing for a customer
        // to do, and a stale customer session here would only confuse the
        // next business sign-in on this browser.
        await axios.post(`${API_BASE_URL}/auth/register`, customer);
        setCustomerDone(customer.email.trim());
        show('Your account has been created!', 'success');
        return;
      }

      const { data } = await axios.post(`${API_BASE_URL}/tenant/onboard`, form);
      localStorage.setItem('token', data.accessToken);
      localStorage.setItem('user', JSON.stringify(data.user));
      dispatch(initializeAuth());
      show('Your business workspace is ready!', 'success');
      navigate('/dashboard');
    } catch (err: unknown) {
      const message = axios.isAxiosError(err)
        ? err.response?.data?.message
        : undefined;
      setError(message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  const eye = (
    <button type="button" className="su-eye" onClick={() => setShowPassword((s) => !s)}
      aria-label={showPassword ? 'Hide password' : 'Show password'} aria-pressed={showPassword}>
      {showPassword ? I.eyeOff : I.eye}
    </button>
  );

  const passwordChecklist = (
    <ul className="su-rules" aria-label="Password requirements">
      <li className={rules.length ? 'ok' : ''}>At least 8 characters</li>
      <li className={rules.numberOrSymbol ? 'ok' : ''}>At least one number (0–9) or a symbol</li>
      <li className={rules.mixedCase ? 'ok' : ''}>Lowercase (a–z) and uppercase (A–Z)</li>
    </ul>
  );

  return (
    <main className="lp lp-auth-page su">
      <div className="lp-auth-backdrop" aria-hidden="true" />
      <div className="su-card">
        {/* ── Form half ─────────────────────────────────────── */}
        <section className="su-form" aria-labelledby="signup-title">
          <div className="lp-auth-theme" aria-label="Choose colour theme"><button type="button" className={theme === 'light' ? 'is-active' : ''} onClick={() => setTheme('light')} aria-pressed={theme === 'light'}>Light</button><button type="button" className={theme === 'dark' ? 'is-active' : ''} onClick={() => setTheme('dark')} aria-pressed={theme === 'dark'}>Dark</button></div>
          <span className="su-member">
            Already a member? <Link to="/login">Sign in</Link>
            <Link className="lp-auth-home" to="/"><span aria-hidden="true">⌂</span> Home</Link>
          </span>

          <div className="su-head">
            <p className="lp-kicker"><span /> GET STARTED</p>
            <h1 id="signup-title">Sign up, <em>simply.</em></h1>
            <p>{mode === 'business' ? 'Set up your business workspace on Unify.' : 'One account for every business on Unify - book anywhere, keep it all in one place.'}</p>
            <svg className="su-flourish" viewBox="0 0 40 40" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
              <path d="M6 30c10 2 20-6 22-18" /><path d="M23 14l5-3 1 6" />
            </svg>
          </div>

          <SegmentedToggle options={MODES} value={mode} onChange={switchMode} label="What are you signing up as" />
          <p className="su-mode-note">
            {mode === 'business'
              ? 'You will be the admin. Invite your team once you are in.'
              : 'No business to pick: you join one automatically the first time you book with it.'}
          </p>

          {error && <div className="su-alert" role="alert">{error}</div>}

          {customerDone ? (
            <div className="su-done" role="status">
              <span className="su-done-mark" aria-hidden="true">✓</span>
              <h2>You're all set</h2>
              <p>Your Unify account for <b>{customerDone}</b> is ready. Open the <b>Unify app</b>, sign in, pick any business and book - it joins you to that business automatically.</p>
              <div className="su-done-actions">
                <Link className="su-submit" to="/login">Go to sign in <span aria-hidden="true">→</span></Link>
                <button type="button" className="su-link-btn" onClick={() => { setCustomerDone(null); setCustomer({ fullName: '', email: '', password: '', phone: '' }); setConfirm(''); }}>Create another account</button>
              </div>
            </div>
          ) : (
          <form onSubmit={handleSubmit} noValidate>
            {mode === 'business' ? (
              <div className="su-grid">
                <div className="su-section">Business</div>
                <div className="su-full">
                  <Field icon={I.store} label="Business name" valid={v(validName(form.businessName), form.businessName)}>
                    <input name="businessName" value={form.businessName} onChange={handleChange} placeholder="Business name" required />
                  </Field>
                </div>
                <div className={form.businessType === 'Tourism' ? '' : 'su-full'}>
                  <Field icon={I.tag} label="Type" valid={null} filled>
                    <select name="businessType" value={form.businessType} onChange={handleChange} aria-label="Business type">
                      {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                    </select>
                  </Field>
                </div>
                {form.businessType === 'Tourism' && (
                  <div>
                    <Field icon={I.tag} label="What kind" valid={v(true, form.subType)}>
                      <select name="subType" value={form.subType} onChange={handleChange} aria-label="Tourism sub-type">
                        <option value="">What kind of tourism…</option>
                        {TOURISM_SUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                      </select>
                    </Field>
                  </div>
                )}
                <div>
                  <Field icon={I.pin} label="Address" valid={v(form.address.trim().length >= 3, form.address)}>
                    <input name="address" value={form.address} onChange={handleChange} placeholder="Address" />
                  </Field>
                </div>
                <div>
                  <Field icon={I.phone} label="Business phone" valid={v(validPhone(form.phone), form.phone)}>
                    <input name="phone" type="tel" value={form.phone} onChange={handleChange} placeholder="Business phone" />
                  </Field>
                </div>

                <div className="su-section">Your admin account</div>
                <div className="su-full">
                  <Field icon={I.user} label="Full name" valid={v(validName(form.adminFullName), form.adminFullName)}>
                    <input name="adminFullName" autoComplete="name" value={form.adminFullName} onChange={handleChange} placeholder="Full name" required />
                  </Field>
                </div>
                <div className="su-full">
                  <Field icon={I.mail} label="Email address" valid={v(validEmail(form.adminEmail), form.adminEmail)}>
                    <input name="adminEmail" type="email" autoComplete="email" value={form.adminEmail} onChange={handleChange} placeholder="Email address" required />
                  </Field>
                </div>
                <div className="su-full">
                  <Field icon={I.lock} label="Password" valid={v(validPassword(form.adminPassword), form.adminPassword)} trailing={eye}>
                    <input name="adminPassword" type={showPassword ? 'text' : 'password'} autoComplete="new-password"
                      value={form.adminPassword} onChange={handleChange} placeholder="Password" required />
                  </Field>
                </div>
                {form.adminPassword && passwordChecklist}
                <div>
                  <Field icon={I.lock} label="Re-type password" valid={confirmValid}>
                    <input type={showPassword ? 'text' : 'password'} autoComplete="new-password" value={confirm}
                      onChange={(e) => setConfirm(e.target.value)} placeholder="Re-type password" required />
                  </Field>
                </div>
                <div>
                  <Field icon={I.phone} label="Your phone" valid={v(validPhone(form.adminPhone), form.adminPhone)}>
                    <input name="adminPhone" type="tel" autoComplete="tel" value={form.adminPhone} onChange={handleChange} placeholder="Your phone" />
                  </Field>
                </div>
              </div>
            ) : (
              <div className="su-grid">
                <div className="su-section">Your details</div>
                <div className="su-full">
                  <Field icon={I.user} label="Full name" valid={v(validName(customer.fullName), customer.fullName)}>
                    <input name="fullName" autoComplete="name" value={customer.fullName} onChange={handleCustomerChange} placeholder="Full name" required />
                  </Field>
                </div>
                <div className="su-full">
                  <Field icon={I.mail} label="Email address" valid={v(validEmail(customer.email), customer.email)}>
                    <input name="email" type="email" autoComplete="email" value={customer.email} onChange={handleCustomerChange} placeholder="Email address" required />
                  </Field>
                </div>
                <div className="su-full">
                  <Field icon={I.lock} label="Password" valid={v(validPassword(customer.password), customer.password)} trailing={eye}>
                    <input name="password" type={showPassword ? 'text' : 'password'} autoComplete="new-password"
                      value={customer.password} onChange={handleCustomerChange} placeholder="Password" required />
                  </Field>
                </div>
                {customer.password && passwordChecklist}
                <div>
                  <Field icon={I.lock} label="Re-type password" valid={confirmValid}>
                    <input type={showPassword ? 'text' : 'password'} autoComplete="new-password" value={confirm}
                      onChange={(e) => setConfirm(e.target.value)} placeholder="Re-type password" required />
                  </Field>
                </div>
                <div>
                  <Field icon={I.phone} label="Phone" valid={v(validPhone(customer.phone), customer.phone)}>
                    <input name="phone" type="tel" autoComplete="tel" value={customer.phone} onChange={handleCustomerChange} placeholder="Phone" />
                  </Field>
                </div>
              </div>
            )}

            <div className="su-actions">
              <button type="submit" className="su-submit" disabled={loading}>
                {loading ? <><span className="lp-spinner" style={{ marginLeft: 6 }} /> Creating…</> : <>Sign Up <span aria-hidden="true">→</span></>}
              </button>
              <span className="su-secure"><span>✓</span>Private and secure · no credit card</span>
            </div>
          </form>
          )}
        </section>

        {/* ── Art half: the landing page's world ───────────── */}
        <aside className="su-art" aria-hidden="true">
          <div className="su-shape su-shape--a" />
          <div className="su-shape su-shape--c" />
          <div className="su-shape su-shape--b" />
          <div className="su-orb su-orb--1" />
          <div className="su-orb su-orb--2" />

          <div className="su-art-kicker">One place for the whole day</div>
          <h2 className="su-art-title">Make the busy<br />feel <em>beautiful.</em></h2>

          <div className="su-float su-dash">
            <div className="su-dash-top">
              <span className="su-dash-brand"><img src="/unify-logo.svg" alt="" />Today</span>
              <span className="su-dash-cta">+ New booking</span>
            </div>
            <div className="su-dash-greet">GOOD MORNING</div>
            <h3>Your day, at a glance.</h3>
            <div className="su-dash-stats">
              <div className="su-dash-stat"><small>Today's bookings</small><strong>24 <i>+12%</i></strong></div>
              <div className="su-dash-stat"><small>Available slots</small><strong>08 <i>On track</i></strong></div>
              <div className="su-dash-stat"><small>Team on duty</small><strong>12 <i>All in</i></strong></div>
            </div>
            <div className="su-dash-row"><span>09:30</span><i style={{ background: '#4bbfae' }} /><b>Client appointment</b></div>
            <div className="su-dash-row"><span>11:00</span><i style={{ background: '#ff7558' }} /><b>Team check-in</b></div>
            <div className="su-dash-row"><span>14:15</span><i style={{ background: '#8b8ef5' }} /><b>Service session</b></div>
          </div>

          <div className="su-float su-stat">
            <div className="su-stat-label">This week</div>
            <div className="su-stat-value">176</div>
            <svg viewBox="0 0 120 34" fill="none" strokeWidth="3" strokeLinecap="round">
              <path d="M4 26c10-20 18-20 28 0" stroke="#ff7558" />
              <path d="M38 20c10 20 18 20 28 0" stroke="#006e68" />
              <path d="M72 26c10-20 18-20 28 0" stroke="#ff7558" />
            </svg>
          </div>

          <div className="su-float su-note">
            <div className="su-note-key">{I.key}</div>
            <div>
              <h4>Your data, your rules</h4>
              <p>Bookings, stock and customers stay yours. Role-based access keeps the right people on the right screens.</p>
            </div>
          </div>

          <div className="su-avatars">
            <span style={{ background: '#ffb28a' }}>R</span><span style={{ background: '#4bbfae' }}>S</span><span style={{ background: '#8b8ef5' }}>A</span><span style={{ background: '#112024' }}>+</span>
            Made for people who run the real work.
          </div>
        </aside>
      </div>
    </main>
  );
};

export default RegisterPage;
