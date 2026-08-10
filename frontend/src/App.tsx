import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Provider } from 'react-redux';
import { useEffect } from 'react';
import { store } from './store/store';
import { initializeAuth } from './store/authSlice';
import LoginPage from './pages/LoginPage';
import RegisterPage from './pages/RegisterPage';
import DashboardPage from './pages/DashboardPage';
import ProtectedRoute from './components/ProtectedRoute';

const AuthInitializer = ({ children }: { children: React.ReactNode }) => {
  useEffect(() => {
    store.dispatch(initializeAuth());
  }, []);
  return <>{children}</>;
};

function App() {
  return (
    <Provider store={store}>
      <AuthInitializer>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<RegisterPage />} />
            
            <Route
              path="/dashboard"
              element={
                <ProtectedRoute>
                  <DashboardPage />
                </ProtectedRoute>
              }
            />
            
            <Route
              path="/admin"
              element={
                <ProtectedRoute allowedRoles={['Admin']}>
                  <div style={{ padding: '2rem' }}><h1>Admin Panel</h1></div>
                </ProtectedRoute>
              }
            />
            
            <Route
              path="/bookings"
              element={
                <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                  <div style={{ padding: '2rem' }}><h1>Booking Manager</h1></div>
                </ProtectedRoute>
              }
            />
            
            <Route path="/" element={<LoginPage />} />
            <Route path="*" element={<div style={{ padding: '2rem' }}><h1>404 - Page Not Found</h1></div>} />
          </Routes>
        </BrowserRouter>
      </AuthInitializer>
    </Provider>
  );
}

export default App;