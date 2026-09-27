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

type Mode = 'business' | 'customer';

const MODES = [
  { id: 'business' as const, label: 'A business' },
  { id: 'customer' as const, label: 'A customer' },
];

const BUSINESS_TYPES = [
  { value: 'Tourism', label: 'Tourism & Trips' },
  { value: 'Clinic', label: 'Health & Clinic' },
  { value: 'Restaurant', label: 'Restaurant & Hospitality' },
  { value: 'Gym', label: 'Fitness & Gym' },
  { value: 'School', label: 'Education & Academy' },
  { value: 'RealEstate', label: 'Real Estate & Properties' },
  { value: 'General', label: 'General Commercial' },
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

/* ── Inline SVG Icons ────────────────────────────────────────────── */
const I = {
  user: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
  ),
  mail: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <polyline points="3 7 12 13 21 7" />
    </svg>
  ),
  lock: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  ),
  store: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  ),
  tag: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
      <line x1="7" y1="7" x2="7.01" y2="7" />
    </svg>
  ),
  pin: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
      <circle cx="12" cy="10" r="3" />
    </svg>
  ),
  phone: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z" />
    </svg>
  ),
  check: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12" />
    </svg>
  ),
  eye: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  ),
  eyeOff: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  ),
};

/* Modern Enclosed Field with Floating State Mark */
function FormField({
  icon,
  label,
  valid,
  children,
  trailing,
  className = '',
}: {
  icon: ReactNode;
  label: string;
  valid: boolean | null;
  children: ReactNode;
  trailing?: ReactNode;
  className?: string;
}) {
  const cls = [
    'su-field',
    valid === true ? 'is-valid' : '',
    valid === false ? 'is-invalid' : '',
    className,
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={cls}>
      <label>{label}</label>
      <div className="su-input-wrap">
        <span className="su-field-icon" aria-hidden="true">
          {icon}
        </span>
        {children}
        <span className="su-mark" aria-hidden="true">
          {trailing ?? (valid === true ? I.check : null)}
        </span>
      </div>
    </div>
  );
}

export default function RegisterPage() {
  const [mode, setMode] = useState<Mode>('business');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('unify-home-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

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

  useEffect(() => {
    if (error) show(error, 'error');
  }, [error, show]);

  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => {
      delete document.documentElement.dataset.unifyTheme;
    };
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
    setError('');
    setConfirm('');
  };

  const currentPassword = mode === 'business' ? form.adminPassword : customer.password;
  const rules = useMemo(() => passwordRules(currentPassword), [currentPassword]);
  const confirmValid: boolean | null = confirm ? confirm === currentPassword : null;
  const v = (ok: boolean, value: string): boolean | null => (value.trim() ? ok : null);

  const formValid =
    mode === 'business'
      ? validName(form.businessName) &&
        validName(form.adminFullName) &&
        validEmail(form.adminEmail) &&
        validPassword(form.adminPassword) &&
        confirm === form.adminPassword
      : validName(customer.fullName) &&
        validEmail(customer.email) &&
        validPassword(customer.password) &&
        confirm === customer.password;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formValid) {
      setError(
        confirm !== currentPassword
          ? 'The two passwords do not match.'
          : 'Please complete the highlighted fields before proceeding.',
      );
      return;
    }
    setLoading(true);
    setError('');

    try {
      if (mode === 'customer') {
        await axios.post(`${API_BASE_URL}/auth/register`, customer);
        setCustomerDone(customer.email.trim());
        show('Your customer account has been created!', 'success');
        return;
      }

      const { data } = await axios.post(`${API_BASE_URL}/tenant/onboard`, form);
      localStorage.setItem('token', data.accessToken);
      localStorage.setItem('user', JSON.stringify(data.user));
      dispatch(initializeAuth());
      show('Your business workspace is ready!', 'success');
      navigate('/dashboard');
    } catch (err: unknown) {
      const message = axios.isAxiosError(err) ? err.response?.data?.message : undefined;
      setError(message || 'Registration failed. Please check your network and details.');
    } finally {
      setLoading(false);
    }
  };

  const eyeButton = (
    <button
      type="button"
      className="su-eye"
      onClick={() => setShowPassword((s) => !s)}
      title={showPassword ? 'Hide password' : 'Show password'}
      aria-label={showPassword ? 'Hide password' : 'Show password'}
    >
      {showPassword ? I.eyeOff : I.eye}
    </button>
  );

  const passwordChecklist = (
    <ul className="su-rules" aria-label="Password requirements">
      <li className={rules.length ? 'ok' : ''}>
        <span>8+ characters</span>
      </li>
      <li className={rules.mixedCase ? 'ok' : ''}>
        <span>Mixed case (A-Z, a-z)</span>
      </li>
      <li className={rules.numberOrSymbol ? 'ok' : ''}>
        <span>Number or symbol</span>
      </li>
    </ul>
  );

  return (
    <main className="lp lp-home su">
      {/* Background Ambient Orbs */}
      <div className="lp-auth-mesh" aria-hidden="true">
        <div className="lp-auth-orb-1" />
        <div className="lp-auth-orb-2" />
      </div>

      {/* Top Header Navigation */}
      <div className="su-content-wrap">
      <header className="lp-auth-topbar">
        <Link className="lp-auth-brand" to="/" title="Back to Unify Home">
          <img src="/unify-logo.svg" alt="Unify" width={32} height={32} />
          <span className="lp-auth-brand-name">unify</span>
          <span className="lp-auth-brand-badge">ONBOARDING</span>
        </Link>

        <div className="lp-auth-top-actions">
          <Link className="lp-auth-home-btn" to="/">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
              <polyline points="9 22 9 12 15 12 15 22" />
            </svg>
            <span>Home</span>
          </Link>

          {/* Interactive Sun / Moon Theme Switcher */}
          <div className="lp-home-theme-toggle" role="radiogroup" aria-label="Theme mode selector">
            <button
              type="button"
              className={`lp-theme-btn ${theme === 'light' ? 'is-active' : ''}`}
              onClick={() => setTheme('light')}
              aria-checked={theme === 'light'}
              role="radio"
              title="Light theme"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="5" />
                <line x1="12" y1="1" x2="12" y2="3" />
                <line x1="12" y1="21" x2="12" y2="23" />
                <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                <line x1="1" y1="12" x2="3" y2="12" />
                <line x1="21" y1="12" x2="23" y2="12" />
                <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
              </svg>
              <span>Light</span>
            </button>
            <button
              type="button"
              className={`lp-theme-btn ${theme === 'dark' ? 'is-active' : ''}`}
              onClick={() => setTheme('dark')}
              aria-checked={theme === 'dark'}
              role="radio"
              title="Dark theme"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
              </svg>
              <span>Dark</span>
            </button>
          </div>
        </div>
      </header>

      {/* Main 2-Column Registration Card */}
      <div className="su-card">
        {/* ── Form Half ─────────────────────────────────────── */}
        <section className="su-form" aria-labelledby="signup-title">
          <div className="su-member">
            <span>Already have an account?</span>
            <Link to="/login">Sign in →</Link>
          </div>

          <div className="su-head">
            <p className="lp-kicker">GET STARTED FOR FREE</p>
            <h1 id="signup-title">
              Sign up, <em>simply.</em>
            </h1>
            <p>
              {mode === 'business'
                ? 'Create your business workspace on Unify. Set up in 2 minutes with no credit card required.'
                : 'One account to discover and book across any business on Unify.'}
            </p>
          </div>

          <SegmentedToggle
            options={MODES}
            value={mode}
            onChange={switchMode}
            label="What are you signing up as"
          />

          <p className="su-mode-note">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" width={16} height={16}>
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="16" x2="12" y2="12" />
              <line x1="12" y1="8" x2="12.01" y2="8" />
            </svg>
            <span>
              {mode === 'business'
                ? 'You will be the primary owner and admin. You can invite your staff once in.'
                : 'Personal booking account: automatically joins a business the first time you book.'}
            </span>
          </p>

          {error && (
            <div className="su-alert" role="alert">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width={18} height={18}>
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
              <span>{error}</span>
            </div>
          )}

          {customerDone ? (
            <div className="su-done" role="status">
              <span className="su-done-mark" aria-hidden="true">
                ✓
              </span>
              <h2>You're all set!</h2>
              <p>
                Your Unify account for <b>{customerDone}</b> is ready. Open the <b>Unify app</b>, sign in, pick any business and book — it syncs your account automatically.
              </p>
              <div className="su-done-actions">
                <Link className="su-submit" to="/login">
                  <span>Go to sign in</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" width={16} height={16}>
                    <line x1="5" y1="12" x2="19" y2="12" />
                    <polyline points="12 5 19 12 12 19" />
                  </svg>
                </Link>
                <button
                  type="button"
                  className="su-link-btn"
                  onClick={() => {
                    setCustomerDone(null);
                    setCustomer({ fullName: '', email: '', password: '', phone: '' });
                    setConfirm('');
                  }}
                >
                  Create another account
                </button>
              </div>
            </div>
          ) : (
            <form onSubmit={handleSubmit} noValidate>
              {mode === 'business' ? (
                <div className="su-grid">
                  <div className="su-section">
                    <span>1. Business Profile</span>
                  </div>

                  <FormField
                    className="su-full"
                    icon={I.store}
                    label="Business Name"
                    valid={v(validName(form.businessName), form.businessName)}
                  >
                    <input
                      name="businessName"
                      value={form.businessName}
                      onChange={handleChange}
                      placeholder="e.g. Apex Marine & Tours"
                      required
                    />
                  </FormField>

                  <FormField
                    className={form.businessType === 'Tourism' ? '' : 'su-full'}
                    icon={I.tag}
                    label="Industry Type"
                    valid={null}
                  >
                    <select
                      name="businessType"
                      value={form.businessType}
                      onChange={handleChange}
                      aria-label="Business industry type"
                    >
                      {BUSINESS_TYPES.map((t) => (
                        <option key={t.value} value={t.value}>
                          {t.label}
                        </option>
                      ))}
                    </select>
                  </FormField>

                  {form.businessType === 'Tourism' && (
                    <FormField
                      icon={I.tag}
                      label="Tourism Sub-Type"
                      valid={v(Boolean(form.subType), form.subType)}
                    >
                      <select
                        name="subType"
                        value={form.subType}
                        onChange={handleChange}
                        aria-label="Tourism sub-type"
                      >
                        <option value="">Select sub-type…</option>
                        {TOURISM_SUB_TYPES.map((t) => (
                          <option key={t} value={t}>
                            {t}
                          </option>
                        ))}
                      </select>
                    </FormField>
                  )}

                  <FormField
                    icon={I.pin}
                    label="Address"
                    valid={v(form.address.trim().length >= 3, form.address)}
                  >
                    <input
                      name="address"
                      value={form.address}
                      onChange={handleChange}
                      placeholder="Main Branch location"
                    />
                  </FormField>

                  <FormField
                    icon={I.phone}
                    label="Business Phone"
                    valid={v(validPhone(form.phone), form.phone)}
                  >
                    <input
                      name="phone"
                      type="tel"
                      value={form.phone}
                      onChange={handleChange}
                      placeholder="+94 77 123 4567"
                    />
                  </FormField>

                  <div className="su-section">
                    <span>2. Admin Account</span>
                  </div>

                  <FormField
                    className="su-full"
                    icon={I.user}
                    label="Admin Full Name"
                    valid={v(validName(form.adminFullName), form.adminFullName)}
                  >
                    <input
                      name="adminFullName"
                      autoComplete="name"
                      value={form.adminFullName}
                      onChange={handleChange}
                      placeholder="e.g. Kasun Silva"
                      required
                    />
                  </FormField>

                  <FormField
                    className="su-full"
                    icon={I.mail}
                    label="Work Email"
                    valid={v(validEmail(form.adminEmail), form.adminEmail)}
                  >
                    <input
                      name="adminEmail"
                      type="email"
                      autoComplete="email"
                      value={form.adminEmail}
                      onChange={handleChange}
                      placeholder="kasun@apexmarine.com"
                      required
                    />
                  </FormField>

                  <FormField
                    className="su-full"
                    icon={I.lock}
                    label="Admin Password"
                    valid={v(validPassword(form.adminPassword), form.adminPassword)}
                    trailing={eyeButton}
                  >
                    <input
                      name="adminPassword"
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="new-password"
                      value={form.adminPassword}
                      onChange={handleChange}
                      placeholder="Create a secure password"
                      required
                    />
                  </FormField>

                  {form.adminPassword && passwordChecklist}

                  <FormField
                    icon={I.lock}
                    label="Confirm Password"
                    valid={confirmValid}
                  >
                    <input
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="new-password"
                      value={confirm}
                      onChange={(e) => setConfirm(e.target.value)}
                      placeholder="Re-type password"
                      required
                    />
                  </FormField>

                  <FormField
                    icon={I.phone}
                    label="Mobile Phone"
                    valid={v(validPhone(form.adminPhone), form.adminPhone)}
                  >
                    <input
                      name="adminPhone"
                      type="tel"
                      autoComplete="tel"
                      value={form.adminPhone}
                      onChange={handleChange}
                      placeholder="+94 71 987 6543"
                    />
                  </FormField>
                </div>
              ) : (
                <div className="su-grid">
                  <div className="su-section">
                    <span>Your Details</span>
                  </div>

                  <FormField
                    className="su-full"
                    icon={I.user}
                    label="Full Name"
                    valid={v(validName(customer.fullName), customer.fullName)}
                  >
                    <input
                      name="fullName"
                      autoComplete="name"
                      value={customer.fullName}
                      onChange={handleCustomerChange}
                      placeholder="e.g. Priya Jayasuriya"
                      required
                    />
                  </FormField>

                  <FormField
                    className="su-full"
                    icon={I.mail}
                    label="Email Address"
                    valid={v(validEmail(customer.email), customer.email)}
                  >
                    <input
                      name="email"
                      type="email"
                      autoComplete="email"
                      value={customer.email}
                      onChange={handleCustomerChange}
                      placeholder="priya@gmail.com"
                      required
                    />
                  </FormField>

                  <FormField
                    className="su-full"
                    icon={I.lock}
                    label="Password"
                    valid={v(validPassword(customer.password), customer.password)}
                    trailing={eyeButton}
                  >
                    <input
                      name="password"
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="new-password"
                      value={customer.password}
                      onChange={handleCustomerChange}
                      placeholder="Create a secure password"
                      required
                    />
                  </FormField>

                  {customer.password && passwordChecklist}

                  <FormField
                    icon={I.lock}
                    label="Confirm Password"
                    valid={confirmValid}
                  >
                    <input
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="new-password"
                      value={confirm}
                      onChange={(e) => setConfirm(e.target.value)}
                      placeholder="Re-type password"
                      required
                    />
                  </FormField>

                  <FormField
                    icon={I.phone}
                    label="Mobile Phone"
                    valid={v(validPhone(customer.phone), customer.phone)}
                  >
                    <input
                      name="phone"
                      type="tel"
                      autoComplete="tel"
                      value={customer.phone}
                      onChange={handleCustomerChange}
                      placeholder="+94 77 000 0000"
                    />
                  </FormField>
                </div>
              )}

              <div className="su-actions">
                <button type="submit" className="su-submit" disabled={loading}>
                  {loading ? (
                    <>
                      <span className="lp-spinner" />
                      <span>Creating workspace…</span>
                    </>
                  ) : (
                    <>
                      <span>{mode === 'business' ? 'Launch Workspace Free' : 'Create Account'}</span>
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                        <line x1="5" y1="12" x2="19" y2="12" />
                        <polyline points="12 5 19 12 12 19" />
                      </svg>
                    </>
                  )}
                </button>

                <div className="su-secure">
                  <span>✓</span>
                  <span>14-day free trial · No card required</span>
                </div>
              </div>
            </form>
          )}
        </section>

        {/* ── Art / Showcase Half ─────────────────────────── */}
        <aside className="su-art" aria-label="Unify Platform Features">
          <div className="su-art-photo-frame">
            <img
              src="/landing/services.jpg"
              alt="Modern team collaborating on scheduling and operations"
            />
            <div className="su-art-photo-overlay">
              <span className="su-art-chip">
                <i /> CLOUD BUSINESS OS
              </span>
              <strong className="lp-auth-photo-caption">
                All branches connected. Zero friction.
              </strong>
            </div>
          </div>

          <div className="su-art-copy">
            <span className="lp-auth-eyebrow">BUILT FOR REAL OPERATIONS</span>
            <h2>
              Make the busy<br />
              <em>feel beautiful.</em>
            </h2>
            <p>
              Run online appointments, staff roster shifts, automated inventory telemetry, and customer invoices from one clean dashboard.
            </p>

            <ul className="su-art-proof-list">
              <li>
                <span>✓</span>
                <span>Pre-configured blueprints for clinics, stays, dive hubs &amp; shops</span>
              </li>
              <li>
                <span>✓</span>
                <span>Automatic low-stock reorder triggers &amp; purchase orders</span>
              </li>
              <li>
                <span>✓</span>
                <span>Instant QR-code check-ins for customers &amp; staff</span>
              </li>
            </ul>
          </div>

          <div className="su-art-trust-bar">
            <div className="su-art-avatars">
              <span title="Diving Center">D</span>
              <span title="Boutique Stay">B</span>
              <span title="Artisan Retail">A</span>
              <span title="Wellness Hub">W</span>
            </div>
            <p>Trusted by 450+ growing businesses daily.</p>
          </div>
        </aside>
      </div>
      </div>
    </main>
  );
}
