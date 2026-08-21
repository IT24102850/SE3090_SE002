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
import BookingTypeManagementPage from './features/booking/BookingTypeManagementPage';
import MySchedulePage from './features/staff/MySchedulePage';
import StaffManagementPage from './features/staff/StaffManagementPage';
import BranchesPage from './features/branches/BranchesPage';
import BusinessSettingsPage from './features/settings/BusinessSettingsPage';
import BusinessProfilePage from './features/settings/BusinessProfilePage';
import MyProfilePage from './features/settings/MyProfilePage';
import './features/inventory/inventory.css';
import { ToastProvider as InventoryToastProvider } from './features/inventory/ui/ToastContext';
import { InventoryManagerPage } from './features/inventory/pages/InventoryManagerPage';
import { StockMovementLogPage } from './features/inventory/pages/StockMovementLogPage';
import { PurchaseOrderManagerPage } from './features/inventory/pages/PurchaseOrderManagerPage';
import { AgentWorkflowMonitorPage } from './features/inventory/pages/AgentWorkflowMonitor';
import { LowStockAlertsPage } from './features/inventory/pages/LowStockAlertsPage';
import { BranchOverviewPage } from './features/inventory/pages/BranchOverviewPage';
import { AnalyticsDashboardPage } from './features/inventory/pages/AnalyticsDashboardCharts';
import { ForbiddenPage } from './features/inventory/pages/ForbiddenPage';

const AuthInitializer = ({ children }: { children: React.ReactNode }) => {
  useEffect(() => {
    store.dispatch(initializeAuth());
  }, []);
  return <>{children}</>;
};

function Shell({ children }: { children: React.ReactNode }) {
  return <AppLayout>{children}</AppLayout>;
}

// Inventory pages were ported from their own app and use their own toast
// context (different API shape than shared/components/Toast) - nest it
// locally rather than touch every already-working booking page.
function InventoryShell({ children }: { children: React.ReactNode }) {
  return (
    <InventoryToastProvider>
      <AppLayout>
        <div className="inventory-scope">{children}</div>
      </AppLayout>
    </InventoryToastProvider>
  );
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
                path="/profile"
                element={
                  <ProtectedRoute>
                    <Shell><MyProfilePage /></Shell>
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
                path="/booking-types"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><BookingTypeManagementPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/my-schedule"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><MySchedulePage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/staff"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><StaffManagementPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/branches"
                element={
                  <ProtectedRoute allowedRoles={['Admin']}>
                    <Shell><BranchesPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/settings"
                element={
                  <ProtectedRoute allowedRoles={['Admin']}>
                    <Shell><BusinessSettingsPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/business-profile"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><BusinessProfilePage /></Shell>
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

              {/* ── Inventory module ───────────────────────────────── */}
              <Route
                path="/inventory"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><InventoryManagerPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/stock-movements"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><StockMovementLogPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/purchase-orders"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><PurchaseOrderManagerPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/agent-workflows"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><AgentWorkflowMonitorPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/low-stock-alerts"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><LowStockAlertsPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/branch-overview"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><BranchOverviewPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/inventory-analytics"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <InventoryShell><AnalyticsDashboardPage /></InventoryShell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/unauthorized"
                element={
                  <ProtectedRoute>
                    <ForbiddenPage />
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
