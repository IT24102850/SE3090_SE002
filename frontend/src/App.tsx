import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Provider } from 'react-redux';
import { useEffect } from 'react';
import { store } from './store/store';
import { initializeAuth } from './store/authSlice';
import LoginPage from './pages/LoginPage';
import RegisterPage from './pages/RegisterPage';
import DashboardPage from './pages/DashboardPage';
import ProtectedRoute from './components/ProtectedRoute';
import AppLayout from './shared/components/AppLayout';
import { ToastProvider } from './shared/components/Toast';
import CalendarDashboardPage from './features/booking/CalendarDashboardPage';
import BookingManagerPage from './features/booking/BookingManagerPage';
import ResourceManagerPage from './features/booking/ResourceManagerPage';
import MultiBranchSchedulePage from './features/booking/MultiBranchSchedulePage';
import ReportsPage from './features/booking/ReportsPage';
import AgentPlannerPage from './features/booking/AgentPlannerPage';

const AuthInitializer = ({ children }: { children: React.ReactNode }) => {
  useEffect(() => {
    store.dispatch(initializeAuth());
  }, []);
  return <>{children}</>;
};

function Shell({ children }: { children: React.ReactNode }) {
  return <AppLayout>{children}</AppLayout>;
}

function App() {
  return (
    <Provider store={store}>
      <ToastProvider>
        <AuthInitializer>
          <BrowserRouter>
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/register" element={<RegisterPage />} />

              <Route
                path="/dashboard"
                element={
                  <ProtectedRoute>
                    <Shell><CalendarDashboardPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/legacy-dashboard"
                element={
                  <ProtectedRoute>
                    <DashboardPage />
                  </ProtectedRoute>
                }
              />

              <Route
                path="/bookings"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><BookingManagerPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/resources"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><ResourceManagerPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/multi-branch"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><MultiBranchSchedulePage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/reports"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><ReportsPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/planner"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><AgentPlannerPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/admin"
                element={
                  <ProtectedRoute allowedRoles={['Admin']}>
                    <Shell><div><h1 className="page-title">Admin Panel</h1></div></Shell>
                  </ProtectedRoute>
                }
              />

              <Route path="/" element={<LoginPage />} />
              <Route path="*" element={<div style={{ padding: '2rem' }}><h1>404 - Page Not Found</h1></div>} />
            </Routes>
          </BrowserRouter>
        </AuthInitializer>
      </ToastProvider>
    </Provider>
  );
}

export default App;
