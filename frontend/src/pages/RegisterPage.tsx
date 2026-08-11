import { useState } from 'react';
import axios from 'axios';

const RegisterPage = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  
  const [form, setForm] = useState({
    businessName: '',
    businessType: 'Clinic',
    address: '',
    phone: '',
    adminEmail: '',
    adminPassword: '',
    adminFullName: '',
    adminPhone: '',
  });

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    setForm({ ...form, [e.target.name]: e.target.value });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const response = await axios.post('http://localhost:5298/api/tenant/onboard', form);
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
    <div style={{ maxWidth: '500px', margin: '3rem auto', padding: '2rem', boxShadow: '0 0 10px rgba(0,0,0,0.1)' }}>
      <h2>Register Your Business</h2>
      
      {error && (
        <div style={{ padding: '0.75rem', background: '#fee2e2', color: '#dc2626', borderRadius: '4px', marginBottom: '1rem' }}>
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <h4>Business Info</h4>
        <input name="businessName" placeholder="Business Name" value={form.businessName} onChange={handleChange} required style={inputStyle} />
        <select name="businessType" value={form.businessType} onChange={handleChange} style={inputStyle}>
          <option value="Clinic">Clinic</option>
          <option value="Restaurant">Restaurant</option>
          <option value="Gym">Gym</option>
          <option value="School">School</option>
          <option value="RealEstate">Real Estate</option>
          <option value="Tourism">Tourism</option>
          <option value="General">General</option>
        </select>
        <input name="address" placeholder="Address" value={form.address} onChange={handleChange} style={inputStyle} />
        <input name="phone" placeholder="Business Phone" value={form.phone} onChange={handleChange} style={inputStyle} />

        <h4 style={{ marginTop: '1rem' }}>Admin Account</h4>
        <input name="adminFullName" placeholder="Full Name" value={form.adminFullName} onChange={handleChange} required style={inputStyle} />
        <input name="adminEmail" type="email" placeholder="Admin Email" value={form.adminEmail} onChange={handleChange} required style={inputStyle} />
        <input name="adminPassword" type="password" placeholder="Password" value={form.adminPassword} onChange={handleChange} required style={inputStyle} />
        <input name="adminPhone" placeholder="Phone" value={form.adminPhone} onChange={handleChange} style={inputStyle} />

        <button type="submit" disabled={loading} style={{ ...inputStyle, background: loading ? '#9ca3af' : '#059669', color: 'white', cursor: loading ? 'not-allowed' : 'pointer' }}>
          {loading ? 'Creating Account...' : 'Create Business Account'}
        </button>
      </form>
    </div>
  );
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '0.5rem',
  marginBottom: '0.75rem',
  borderRadius: '4px',
  border: '1px solid #d1d5db',
};

export default RegisterPage;
