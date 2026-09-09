import { Navigate, Route, Routes } from 'react-router-dom';
import { ProtectedRoute } from './auth/ProtectedRoute';
import { AppLayout } from './layout/AppLayout';
import { AnalyticsDashboardPage } from './pages/AnalyticsDashboardCharts';
import { ForbiddenPage } from './pages/ForbiddenPage';
import { InventoryManagerPage } from './pages/InventoryManagerPage';
import { LoginPage } from './pages/LoginPage';
import { PurchaseOrderManagerPage } from './pages/PurchaseOrderManagerPage';
import { StockMovementLogPage } from './pages/StockMovementLogPage';
import { LowStockAlertsPage } from './pages/LowStockAlertsPage';
import { BranchOverviewPage } from './pages/BranchOverviewPage';
import { AgentWorkflowMonitorPage } from './pages/AgentWorkflowMonitor';
import { ManageUsersPage } from './pages/ManageUsersPage';

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']} />}>
        <Route element={<AppLayout />}>
          <Route path="/inventory" element={<InventoryManagerPage />} />
          <Route path="/stock-movements" element={<StockMovementLogPage />} />
          <Route path="/low-stock-alerts" element={<LowStockAlertsPage />} />
        </Route>
      </Route>
      <Route element={<ProtectedRoute allowedRoles={['Admin', 'Manager']} />}>
        <Route element={<AppLayout />}>
          <Route path="/purchase-orders" element={<PurchaseOrderManagerPage />} />
          <Route path="/branch-overview" element={<BranchOverviewPage />} />
          <Route path="/agent-workflows" element={<AgentWorkflowMonitorPage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={['Admin']} />}>
          <Route element={<AppLayout />}>
            <Route path="/manage-users" element={<ManageUsersPage />} />
          </Route>
        </Route>
      </Route>
      <Route element={<ProtectedRoute allowedRoles={['Admin', 'Manager']} />}>
        <Route element={<AppLayout />}>
          <Route path="/analytics" element={<AnalyticsDashboardPage />} />
        </Route>
      </Route>
      <Route path="/forbidden" element={<ForbiddenPage />} />
      <Route path="/" element={<Navigate to="/inventory" replace />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
