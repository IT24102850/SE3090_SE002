import { useEffect, useState } from 'react';
import axios from 'axios';
import { useDispatch } from 'react-redux';
import { Link, useNavigate } from 'react-router-dom';
import { TOURISM_SUB_TYPES } from '../features/booking/types';
import SegmentedToggle from '../features/marketing/SegmentedToggle';
import { useToast } from '../shared/components/Toast';
import { initializeAuth } from '../store/authSlice';
import type { AppDispatch } from '../store/store';
import '../features/marketing/landing.css';

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:5298/api';

/* Sign-up, as a split frame: photograph on the left, the form on the right.
 *
 * Two genuinely different things behind one toggle, which is why the toggle
 * is here and not on the sign-in page: registering a business creates a
 * tenant, registering as a customer joins one that already exists. They hit
 * different endpoints, collect different fields, and cannot be merged.
 *
 *   Business  POST /api/tenant/onboard   creates the tenant + an Admin user
 *   Customer  POST /api/auth/register    creates a Customer of one tenant
 *
 * Role is never client-supplied on either route - the customer endpoint
 * assigns Customer regardless of what is sent, which is what makes it safe to
 * expose this choice in the UI at all.
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

interface PublicTenant {
  id: string;
  name: string;
  businessType: string;
  subType: string | null;
}

/* Eye / eye-off, inline so the toggle needs no icon dependency. */
const EyeIcon = ({ off }: { off: boolean }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
    strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" />
    <circle cx="12" cy="12" r="3" />
    {off && <path d="M3 3l18 18" />}
  </svg>
);

const RegisterPage = () => {
  const [mode, setMode] = useState<Mode>('business');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showPassword, setShowPassword] = useState(false);
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
    tenantId: '',
    fullName: '',
    email: '',
    password: '',
    phone: '',
  });

  /* The businesses a customer can join.
   *
   * Fetched on mount, not when the customer side is opened. Deferring it
   * looks like the thriftier choice - most visitors here are registering a
   * business and never see the list - but this endpoint measures 2-4s warm
   * and 18s cold against the hosted database, so deferring means clicking
   * "A customer" and watching a disabled select say "Loading businesses" for
   * several seconds. Starting early usually means it has already arrived.
   * The response is a few hundred bytes; the latency is the cost, not the
   * payload. */
  const [tenants, setTenants] = useState<PublicTenant[] | null>(null);
  const [tenantsError, setTenantsError] = useState('');

  useEffect(() => { if (error) show(error, 'error'); }, [error, show]);
  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => { delete document.documentElement.dataset.unifyTheme; };
  }, [theme]);

  useEffect(() => {
    let cancelled = false;
    axios
      .get<PublicTenant[]>(`${API_BASE_URL}/tenant/public`)
      .then((r) => { if (!cancelled) setTenants(r.data); })
      .catch(() => {
        if (cancelled) return;
        setTenants([]);
        setTenantsError('Could not load the list of businesses. Try again in a moment.');
      });
    return () => { cancelled = true; };
  }, []);

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
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const { data } =
        mode === 'business'
          ? await axios.post(`${API_BASE_URL}/tenant/onboard`, form)
          : await axios.post(`${API_BASE_URL}/auth/register`, customer);

      localStorage.setItem('token', data.accessToken);
      localStorage.setItem('user', JSON.stringify(data.user));
      dispatch(initializeAuth());
      show(mode === 'business' ? 'Your business workspace is ready!' : 'Your account has been created!', 'success');
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

  const passwordToggle = (
    <button type="button" className="lp-signup-eye" onClick={() => setShowPassword((v) => !v)}
      aria-label={showPassword ? 'Hide password' : 'Show password'} aria-pressed={showPassword}>
      <EyeIcon off={!showPassword} />
    </button>
  );

  return (
    <main className="lp lp-auth-page lp-signup-page">
      <div className="lp-auth-backdrop" aria-hidden="true" />
      <div className="lp-signup-wrap">
        <div className="lp-signup-frame">
          <aside className="lp-signup-visual" aria-hidden="true">
            <img src="/landing/team-screen.jpg" alt="" />
          </aside>

          <section className="lp-signup-panel" aria-labelledby="signup-title">
            <div className="lp-auth-theme" aria-label="Choose colour theme"><button type="button" className={theme === 'light' ? 'is-active' : ''} onClick={() => setTheme('light')} aria-pressed={theme === 'light'}>Light</button><button type="button" className={theme === 'dark' ? 'is-active' : ''} onClick={() => setTheme('dark')} aria-pressed={theme === 'dark'}>Dark</button></div>
            <Link className="lp-auth-home" to="/"><span aria-hidden="true">⌂</span> Home</Link>

            <Link className="lp-signup-logo" to="/" aria-label="Unify home">
              <img src="/unify-logo.svg" alt="" width={48} height={48} />
            </Link>
            <h1 id="signup-title">Create an account</h1>

            <SegmentedToggle
              options={MODES}
              value={mode}
              onChange={switchMode}
              label="What are you signing up as"
            />

            {error && <div className="lp-alert" role="alert"><span>!</span>{error}</div>}

            <form onSubmit={handleSubmit}>
              {mode === 'business' ? (
                <div className="lp-form-grid">
                  <div className="lp-field lp-field-full">
                    <label htmlFor="businessName">Business Name</label>
                    <input id="businessName" name="businessName" className="lp-input" placeholder="Enter your business name"
                      value={form.businessName} onChange={handleChange} required />
                  </div>

                  <div className={form.businessType === 'Tourism' ? 'lp-field' : 'lp-field lp-field-full'}>
                    <label htmlFor="businessType">Business Type</label>
                    <select id="businessType" name="businessType" className="lp-input"
                      value={form.businessType} onChange={handleChange}>
                      {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                    </select>
                  </div>

                  {form.businessType === 'Tourism' && (
                    <div className="lp-field">
                      <label htmlFor="subType">What Kind</label>
                      <select id="subType" name="subType" className="lp-input"
                        value={form.subType} onChange={handleChange}>
                        <option value="">Select…</option>
                        {TOURISM_SUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                      </select>
                    </div>
                  )}

                  {form.businessType === 'Tourism' && (
                    <p className="lp-field-full lp-field-hint">
                      This decides your dashboard, your terminology and the fields your booking form
                      collects. You can change it later in settings.
                    </p>
                  )}

                  <div className="lp-field">
                    <label htmlFor="address">Address</label>
                    <input id="address" name="address" className="lp-input" placeholder="Enter your address"
                      value={form.address} onChange={handleChange} />
                  </div>

                  <div className="lp-field">
                    <label htmlFor="phone">Business Phone</label>
                    <input id="phone" name="phone" className="lp-input" placeholder="+94 77 000 0000"
                      value={form.phone} onChange={handleChange} />
                  </div>

                  <div className="lp-field lp-field-full">
                    <label htmlFor="adminEmail">Email Address</label>
                    <input id="adminEmail" name="adminEmail" type="email" className="lp-input" autoComplete="email"
                      placeholder="Enter your email address" value={form.adminEmail} onChange={handleChange} required />
                  </div>

                  <div className="lp-field lp-field-full">
                    <label htmlFor="adminFullName">Full Name</label>
                    <input id="adminFullName" name="adminFullName" className="lp-input" autoComplete="name"
                      placeholder="Enter your full name" value={form.adminFullName} onChange={handleChange} required />
                  </div>

                  <div className="lp-field">
                    <label htmlFor="adminPassword">Password</label>
                    <div className="lp-signup-pw">
                      <input id="adminPassword" name="adminPassword" type={showPassword ? 'text' : 'password'}
                        className="lp-input" autoComplete="new-password" placeholder="Create your password"
                        value={form.adminPassword} onChange={handleChange} required />
                      {passwordToggle}
                    </div>
                  </div>

                  <div className="lp-field">
                    <label htmlFor="adminPhone">Phone</label>
                    <input id="adminPhone" name="adminPhone" className="lp-input" autoComplete="tel"
                      placeholder="+94 77 000 0000" value={form.adminPhone} onChange={handleChange} />
                  </div>
                </div>
              ) : (
                <div className="lp-form-grid">
                  <div className="lp-field lp-field-full">
                    <label htmlFor="tenantId">Business</label>
                    <select id="tenantId" name="tenantId" className="lp-input"
                      value={customer.tenantId} onChange={handleCustomerChange}
                      disabled={tenants === null} required>
                      <option value="">
                        {tenants === null ? 'Loading businesses…' : 'Select the business you are joining'}
                      </option>
                      {(tenants ?? []).map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name} — {t.subType || t.businessType}
                        </option>
                      ))}
                    </select>
                  </div>

                  <p className="lp-field-full lp-field-hint">
                    {tenantsError
                      ? tenantsError
                      : 'A customer account belongs to one business. To book with another, sign up with them too.'}
                  </p>

                  <div className="lp-field lp-field-full">
                    <label htmlFor="customerEmail">Email Address</label>
                    <input id="customerEmail" name="email" type="email" className="lp-input" autoComplete="email"
                      placeholder="Enter your email address" value={customer.email} onChange={handleCustomerChange} required />
                  </div>

                  <div className="lp-field lp-field-full">
                    <label htmlFor="customerFullName">Full Name</label>
                    <input id="customerFullName" name="fullName" className="lp-input" autoComplete="name"
                      placeholder="Enter your full name" value={customer.fullName} onChange={handleCustomerChange} required />
                  </div>

                  <div className="lp-field">
                    <label htmlFor="customerPassword">Password</label>
                    {/* minLength matches RegisterDto's [MinLength(6)]; without
                        it the only feedback is a 400 after a round trip. */}
                    <div className="lp-signup-pw">
                      <input id="customerPassword" name="password" type={showPassword ? 'text' : 'password'}
                        className="lp-input" autoComplete="new-password" placeholder="Create your password" minLength={6}
                        value={customer.password} onChange={handleCustomerChange} required />
                      {passwordToggle}
                    </div>
                  </div>

                  <div className="lp-field">
                    <label htmlFor="customerPhone">Phone</label>
                    <input id="customerPhone" name="phone" className="lp-input" autoComplete="tel"
                      placeholder="+94 77 000 0000" value={customer.phone} onChange={handleCustomerChange} />
                  </div>
                </div>
              )}

              <button type="submit" disabled={loading} className="lp-btn lp-btn-primary lp-auth-submit">
                {loading ? <><span className="lp-spinner" /> Creating…</> : 'Create an account'}
              </button>
            </form>

            <p className="lp-signup-alt">
              Already have an account? <Link to="/login">Login</Link>
            </p>
          </section>
        </div>
      </div>
    </main>
  );
};

export default RegisterPage;
