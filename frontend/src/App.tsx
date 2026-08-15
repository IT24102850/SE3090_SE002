import { Navigate, Route, Routes } from 'react-router-dom';
import { ProtectedRoute } from './auth/ProtectedRoute';
import { AppLayout } from './layout/AppLayout';
import { AnalyticsDashboardPage } from './pages/AnalyticsDashboardCharts';
import { ForbiddenPage } from './pages/ForbiddenPage';
import { InventoryManagerPage } from './pages/InventoryManagerPage';
import { LoginPage } from './pages/LoginPage';

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']} />}>
        <Route element={<AppLayout />}>
          <Route path="/inventory" element={<InventoryManagerPage />} />
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
