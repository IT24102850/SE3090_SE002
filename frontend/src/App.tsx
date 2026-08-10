import React, { useState } from 'react';
import { BrowserRouter, Routes, Route, Outlet, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { useAuth } from './context/AuthContext';
import { ProtectedRoute } from './shared/components/ProtectedRoute';
import { Sidebar } from './shared/components/Sidebar';

type DemoAccount = {
  label: string;
  email: string;
  password: string;
};

const demoAccounts: DemoAccount[] = [
  { label: 'Admin', email: 'admin@lumenis.com', password: 'Admin@123' },
  { label: 'Manager', email: 'manager@lumenis.com', password: 'Manager@123' },
  { label: 'Staff', email: 'staff@lumenis.com', password: 'Staff@123' },
  { label: 'Customer', email: 'customer@lumenis.com', password: 'Customer@123' },
];

const LoginPage: React.FC = () => {
  const { login, isAuthenticated } = useAuth();
  const [email, setEmail] = useState('admin@lumenis.com');
  const [password, setPassword] = useState('Admin@123');
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError('');
    setIsSubmitting(true);

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      if (!response.ok) {
        const payload = await response.json().catch(() => null);
        throw new Error(payload?.message || 'Login failed');
      }

      const payload = await response.json();
      login(payload.accessToken);
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : 'Login failed');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      display: 'grid',
      placeItems: 'center',
      background: 'linear-gradient(135deg, #1f2937 0%, #111827 45%, #f3f4f6 45%, #f9fafb 100%)',
      padding: '2rem',
    }}>
      <div style={{
        width: 'min(100%, 420px)',
        background: '#fff',
        borderRadius: '20px',
        padding: '2rem',
        boxShadow: '0 18px 50px rgba(0,0,0,0.18)',
      }}>
        <h1 style={{ margin: 0, fontSize: '1.7rem' }}>Sign in</h1>
        <p style={{ marginTop: '0.5rem', color: '#6b7280' }}>
          Use one of the seeded role accounts to enter the app.
        </p>

        <form onSubmit={handleSubmit} style={{ display: 'grid', gap: '1rem', marginTop: '1.5rem' }}>
          <label style={{ display: 'grid', gap: '0.4rem' }}>
            <span>Email</span>
            <input
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              type="email"
              autoComplete="email"
              style={{ padding: '0.8rem 0.9rem', borderRadius: '10px', border: '1px solid #d1d5db' }}
            />
          </label>

          <label style={{ display: 'grid', gap: '0.4rem' }}>
            <span>Password</span>
            <input
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              type="password"
              autoComplete="current-password"
              style={{ padding: '0.8rem 0.9rem', borderRadius: '10px', border: '1px solid #d1d5db' }}
            />
          </label>

          {error && (
            <div style={{ color: '#b91c1c', background: '#fef2f2', padding: '0.75rem', borderRadius: '10px' }}>
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={isSubmitting}
            style={{
              padding: '0.9rem 1rem',
              border: 'none',
              borderRadius: '10px',
              background: '#111827',
              color: '#fff',
              fontWeight: 700,
              cursor: 'pointer',
              opacity: isSubmitting ? 0.7 : 1,
            }}
          >
            {isSubmitting ? 'Signing in...' : 'Sign in'}
          </button>
        </form>

        <div style={{ marginTop: '1.5rem' }}>
          <p style={{ marginBottom: '0.75rem', color: '#6b7280', fontSize: '0.95rem' }}>
            Demo accounts
          </p>
          <div style={{ display: 'grid', gap: '0.5rem' }}>
            {demoAccounts.map((account) => (
              <button
                key={account.label}
                type="button"
                onClick={() => {
                  setEmail(account.email);
                  setPassword(account.password);
                }}
                style={{
                  textAlign: 'left',
                  padding: '0.7rem 0.9rem',
                  borderRadius: '10px',
                  border: '1px solid #e5e7eb',
                  background: '#f9fafb',
                  cursor: 'pointer',
                }}
              >
                {account.label}: {account.email}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

const RegisterPage = () => <div style={{ padding: 40 }}><h2>Register Page</h2></div>;
const Dashboard = () => <div style={{ padding: 40 }}><h2>Dashboard</h2></div>;
const ResourceManager = () => <div style={{ padding: 40 }}><h2>Resource Manager</h2></div>;
const BulkSchedulePage = () => <div style={{ padding: 40 }}><h2>Bulk Schedule</h2></div>;
const BookingManager = () => <div style={{ padding: 40 }}><h2>Booking Manager</h2></div>;
const AgentWorkflowsPage = () => <div style={{ padding: 40 }}><h2>AI Workflows</h2></div>;
const MyBookings = () => <div style={{ padding: 40 }}><h2>My Bookings</h2></div>;
const SettingsPage = () => <div style={{ padding: 40 }}><h2>Settings</h2></div>;
const UnauthorizedPage = () => <div style={{ padding: 40 }}><h2>Unauthorized</h2></div>;

// ─── Layout with Sidebar ────────────────────────────────────────────
const Layout: React.FC = () => {
  return (
    <div style={{ display: 'flex' }}>
      <Sidebar />
      <main style={{ flex: 1, padding: '1rem' }}>
        <Outlet />
      </main>
    </div>
  );
};

function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/" element={<Navigate to="/login" replace />} />

          {/* Public routes */}
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterPage />} />
          
          {/* Protected routes with sidebar layout */}
          <Route element={<Layout />}>
            
            {/* Admin/Manager only */}
            <Route 
              path="/resources" 
              element={
                <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                  <ResourceManager />
                </ProtectedRoute>
              } 
            />
            
            {/* Admin/Manager only */}
            <Route 
              path="/bulk-schedule" 
              element={
                <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                  <BulkSchedulePage />
                </ProtectedRoute>
              } 
            />
            
            {/* Staff and above */}
            <Route 
              path="/bookings" 
              element={
                <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                  <BookingManager />
                </ProtectedRoute>
              } 
            />

            {/* Staff and above */}
            <Route 
              path="/agent-workflows" 
              element={
                <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                  <AgentWorkflowsPage />
                </ProtectedRoute>
              } 
            />
            
            {/* All authenticated users */}
            <Route 
              path="/dashboard" 
              element={
                <ProtectedRoute>
                  <Dashboard />
                </ProtectedRoute>
              } 
            />
            
            {/* Customer only */}
            <Route 
              path="/my-bookings" 
              element={
                <ProtectedRoute allowedRoles={['Customer']}>
                  <MyBookings />
                </ProtectedRoute>
              } 
            />

            {/* All authenticated users */}
            <Route 
              path="/settings" 
              element={
                <ProtectedRoute>
                  <SettingsPage />
                </ProtectedRoute>
              } 
            />
          </Route>
          
          {/* Unauthorized fallback */}
          <Route path="/unauthorized" element={<UnauthorizedPage />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}

export default App;