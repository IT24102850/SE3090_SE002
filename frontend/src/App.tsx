import React from 'react';
import { BrowserRouter, Routes, Route, Outlet, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { ProtectedRoute } from './shared/components/ProtectedRoute';
import { Sidebar } from './shared/components/Sidebar';

// ─── Placeholder pages (replace with your actual components) ────────
const LoginPage = () => <div style={{ padding: 40 }}><h2>Login Page</h2></div>;
const RegisterPage = () => <div style={{ padding: 40 }}><h2>Register Page</h2></div>;
const Dashboard = () => <div style={{ padding: 40 }}><h2>Dashboard</h2></div>;
const ResourceManager = () => <div style={{ padding: 40 }}><h2>Resource Manager</h2></div>;
const BulkSchedulePage = () => <div style={{ padding: 40 }}><h2>Bulk Schedule</h2></div>;
const BookingManager = () => <div style={{ padding: 40 }}><h2>Booking Manager</h2></div>;
const MyBookings = () => <div style={{ padding: 40 }}><h2>My Bookings</h2></div>;
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