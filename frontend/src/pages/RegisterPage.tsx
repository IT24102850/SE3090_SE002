import { useState } from 'react';
import axios from 'axios';
import { TOURISM_SUB_TYPES } from '../features/booking/types';

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:5298/api';

const RegisterPage = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const [form, setForm] = useState({
    businessName: '',
    businessType: 'Clinic',
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
    <div className="card card-pad" style={{ maxWidth: '500px', margin: '3rem auto' }}>
      <h2>Register Your Business</h2>
      
      {error && (
        <div className="banner banner-critical">
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <h4>Business Info</h4>
        <input name="businessName" placeholder="Business Name" value={form.businessName} onChange={handleChange} required className="input" style={inputStyle} />
        <select name="businessType" value={form.businessType} onChange={handleChange} className="input" style={inputStyle}>
          <option value="Clinic">Clinic</option>
          <option value="Restaurant">Restaurant</option>
          <option value="Gym">Gym</option>
          <option value="School">School</option>
          <option value="RealEstate">Real Estate</option>
          <option value="Tourism">Tourism</option>
          <option value="General">General</option>
        </select>
        {form.businessType === 'Tourism' && (
          <select name="subType" value={form.subType} onChange={handleChange} className="input" style={inputStyle}>
            <option value="">Select tourism sub-type...</option>
            {TOURISM_SUB_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        )}
        <input name="address" placeholder="Address" value={form.address} onChange={handleChange} className="input" style={inputStyle} />
        <input name="phone" placeholder="Business Phone" value={form.phone} onChange={handleChange} className="input" style={inputStyle} />

        <h4 style={{ marginTop: '1rem' }}>Admin Account</h4>
        <input name="adminFullName" placeholder="Full Name" value={form.adminFullName} onChange={handleChange} required className="input" style={inputStyle} />
        <input name="adminEmail" type="email" placeholder="Admin Email" value={form.adminEmail} onChange={handleChange} required className="input" style={inputStyle} />
        <input name="adminPassword" type="password" placeholder="Password" value={form.adminPassword} onChange={handleChange} required className="input" style={inputStyle} />
        <input name="adminPhone" placeholder="Phone" value={form.adminPhone} onChange={handleChange} className="input" style={inputStyle} />

        <button type="submit" disabled={loading} className="btn btn-primary" style={{ ...inputStyle, marginTop: '0.5rem' }}>
          {loading ? 'Creating Account...' : 'Create Business Account'}
        </button>
      </form>
    </div>
  );
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  marginBottom: '0.75rem',
};

export default RegisterPage;
