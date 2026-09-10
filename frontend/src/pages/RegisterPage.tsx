import { useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';
import { TOURISM_SUB_TYPES } from '../features/booking/types';
import '../features/marketing/landing.css';

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:5298/api';

/* Business onboarding, on the public surface's neon-dark backdrop.
 *
 * The sub-type field is the important one: it is what decides which dashboard
 * the tenant gets, so it is surfaced with an explanation rather than left as
 * an unlabelled dropdown that looks optional. */

const BUSINESS_TYPES = [
  { value: 'Tourism', label: 'Tourism' },
  { value: 'Clinic', label: 'Clinic' },
  { value: 'Restaurant', label: 'Restaurant' },
  { value: 'Gym', label: 'Gym' },
  { value: 'School', label: 'School' },
  { value: 'RealEstate', label: 'Real Estate' },
  { value: 'General', label: 'General' },
];

const RegisterPage = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

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

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setForm((prev) => ({
      ...prev,
      [name]: value,
      ...(name === 'businessType' && value !== 'Tourism' ? { subType: '' } : {}),
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const response = await axios.post(`${API_BASE_URL}/tenant/onboard`, form);
      const { accessToken, user } = response.data;

      localStorage.setItem('token', accessToken);
      localStorage.setItem('user', JSON.stringify(user));

      window.location.href = '/dashboard';
    } catch (err: any) {
      setError(err.response?.data?.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="lp">
      <div className="lp-auth">
        <div className="lp-auth-inner" style={{ maxWidth: 560, gridTemplateColumns: '1fr' }}>
          <div style={{ textAlign: 'center', marginBottom: 4 }}>
            <Link className="lp-brand" to="/" style={{ justifyContent: 'center' }}>
              <span className="lp-brand-mark">U</span>
              Unify
            </Link>
          </div>

          <div className="lp-auth-card">
            <h1>Create your business</h1>
            <p>A couple of minutes, and the console configures itself around what you do.</p>

            {error && <div className="lp-alert">{error}</div>}

            <form onSubmit={handleSubmit}>
              <div className="lp-form-grid">
                <p className="lp-section-label">Business</p>

                <div className="lp-field lp-field-full">
                  <label htmlFor="businessName">Business name</label>
                  <input id="businessName" name="businessName" className="lp-input" placeholder="Mirissa Jetliner"
                    value={form.businessName} onChange={handleChange} required />
                </div>

                <div className={form.businessType === 'Tourism' ? 'lp-field' : 'lp-field lp-field-full'}>
                  <label htmlFor="businessType">Type</label>
                  <select id="businessType" name="businessType" className="lp-input"
                    value={form.businessType} onChange={handleChange}>
                    {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                  </select>
                </div>

                {form.businessType === 'Tourism' && (
                  <div className="lp-field">
                    <label htmlFor="subType">What kind</label>
                    <select id="subType" name="subType" className="lp-input"
                      value={form.subType} onChange={handleChange}>
                      <option value="">Select…</option>
                      {TOURISM_SUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                    </select>
                  </div>
                )}

                {form.businessType === 'Tourism' && (
                  <p className="lp-field-full" style={{ fontSize: '0.78rem', color: 'rgba(255,255,255,0.45)', margin: '-6px 0 12px' }}>
                    This decides your dashboard, your terminology and the fields your booking form
                    collects. You can change it later in settings.
                  </p>
                )}

                <div className="lp-field">
                  <label htmlFor="address">Address</label>
                  <input id="address" name="address" className="lp-input" placeholder="Mirissa Harbour"
                    value={form.address} onChange={handleChange} />
                </div>

                <div className="lp-field">
                  <label htmlFor="phone">Business phone</label>
                  <input id="phone" name="phone" className="lp-input" placeholder="+94 77 000 0000"
                    value={form.phone} onChange={handleChange} />
                </div>

                <p className="lp-section-label">Your admin account</p>

                <div className="lp-field lp-field-full">
                  <label htmlFor="adminFullName">Full name</label>
                  <input id="adminFullName" name="adminFullName" className="lp-input" autoComplete="name"
                    value={form.adminFullName} onChange={handleChange} required />
                </div>

                <div className="lp-field lp-field-full">
                  <label htmlFor="adminEmail">Email</label>
                  <input id="adminEmail" name="adminEmail" type="email" className="lp-input" autoComplete="email"
                    placeholder="you@business.com" value={form.adminEmail} onChange={handleChange} required />
                </div>

                <div className="lp-field">
                  <label htmlFor="adminPassword">Password</label>
                  <input id="adminPassword" name="adminPassword" type="password" className="lp-input"
                    autoComplete="new-password" placeholder="••••••••"
                    value={form.adminPassword} onChange={handleChange} required />
                </div>

                <div className="lp-field">
                  <label htmlFor="adminPhone">Phone</label>
                  <input id="adminPhone" name="adminPhone" className="lp-input" autoComplete="tel"
                    value={form.adminPhone} onChange={handleChange} />
                </div>
              </div>

              <button type="submit" disabled={loading} className="lp-btn lp-btn-primary lp-auth-submit">
                {loading ? <><span className="lp-spinner" /> Creating…</> : 'Create business account'}
              </button>
            </form>

            <p className="lp-auth-alt">
              Already have an account? <Link to="/login">Sign in</Link>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RegisterPage;
