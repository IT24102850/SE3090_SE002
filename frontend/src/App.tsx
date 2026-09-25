import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Provider } from 'react-redux';
import { Suspense, lazy, useEffect } from 'react';
import { store } from './store/store';
import { initializeAuth } from './store/authSlice';
import LandingPage from './features/marketing/LandingPage';
import ProtectedRoute from './components/ProtectedRoute';
import AppLayout from './shared/components/AppLayout';
import { ToastProvider } from './shared/components/Toast';
import './features/inventory/inventory.css';
import { ToastProvider as InventoryToastProvider } from './features/inventory/ui/ToastContext';

/* Everything past the landing page is split out of the initial bundle.
 *
 * These are all admin surfaces: nobody arriving at the marketing page needs
 * the booking manager, the inventory module or the analytics charts, and
 * shipping them anyway is what put a single 1MB chunk in front of a visitor
 * who came to read six paragraphs and press a button. They load on the first
 * navigation that actually needs them, which is behind a login.
 */
const LoginPage = lazy(() => import('./pages/LoginPage'));
const RegisterPage = lazy(() => import('./pages/RegisterPage'));
// Public, chrome-less: the booking widget a business embeds on its own site.
const EmbedBookingPage = lazy(() => import('./features/embed/EmbedBookingPage'));
const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const AdminPage = lazy(() => import('./pages/AdminPage'));
const DashboardRouter = lazy(() => import('./features/dashboard/DashboardRouter'));
const BookingManagerPage = lazy(() => import('./features/booking/BookingManagerPage'));
const ResourceManagerPage = lazy(() => import('./features/booking/ResourceManagerPage'));
const MultiBranchSchedulePage = lazy(() => import('./features/booking/MultiBranchSchedulePage'));
const CalendarDashboardPage = lazy(() => import('./features/booking/CalendarDashboardPage'));
const AvailabilitySlotsPage = lazy(() => import('./features/booking/AvailabilitySlotsPage'));
const RecurringSeriesPage = lazy(() => import('./features/booking/RecurringSeriesPage'));
const ReportsPage = lazy(() => import('./features/booking/ReportsPage'));
const ScheduleCopilotPage = lazy(() => import('./features/booking/copilot/ScheduleCopilotPage'));
const BookingTypeManagementPage = lazy(() => import('./features/booking/BookingTypeManagementPage'));
const MySchedulePage = lazy(() => import('./features/staff/MySchedulePage'));
const StaffManagementPage = lazy(() => import('./features/staff/StaffManagementPage'));
const BranchesPage = lazy(() => import('./features/branches/BranchesPage'));
const BusinessSettingsPage = lazy(() => import('./features/settings/BusinessSettingsPage'));
const BusinessProfilePage = lazy(() => import('./features/settings/BusinessProfilePage'));
const MyProfilePage = lazy(() => import('./features/settings/MyProfilePage'));
const CustomerBookPage = lazy(() => import('./features/customer/CustomerBookPage'));
const MyBookingsPage = lazy(() => import('./features/customer/MyBookingsPage'));
const CustomerAiPlannerPage = lazy(() => import('./features/customer/CustomerAiPlannerPage'));
const BusinessInfoPage = lazy(() => import('./features/customer/BusinessInfoPage'));
const InventoryManagerPage = lazy(() => import('./features/inventory/pages/InventoryManagerPage').then((m) => ({ default: m.InventoryManagerPage })));
const SuppliersPage = lazy(() => import('./features/inventory/pages/SuppliersPage').then((m) => ({ default: m.SuppliersPage })));
const StockMovementLogPage = lazy(() => import('./features/inventory/pages/StockMovementLogPage').then((m) => ({ default: m.StockMovementLogPage })));
const PurchaseOrderManagerPage = lazy(() => import('./features/inventory/pages/PurchaseOrderManagerPage').then((m) => ({ default: m.PurchaseOrderManagerPage })));
const AgentWorkflowMonitorPage = lazy(() => import('./features/inventory/pages/AgentWorkflowMonitor').then((m) => ({ default: m.AgentWorkflowMonitorPage })));
const LowStockAlertsPage = lazy(() => import('./features/inventory/pages/LowStockAlertsPage').then((m) => ({ default: m.LowStockAlertsPage })));
const BranchOverviewPage = lazy(() => import('./features/inventory/pages/BranchOverviewPage').then((m) => ({ default: m.BranchOverviewPage })));
const AnalyticsDashboardPage = lazy(() => import('./features/inventory/pages/AnalyticsDashboardCharts').then((m) => ({ default: m.AnalyticsDashboardPage })));
/* Billing & payments (component 3). */
const BillingDashboardPage = lazy(() => import('./features/billing/pages/BillingDashboardPage'));
const InvoicesPage = lazy(() => import('./features/billing/pages/InvoicesPage'));
const SubscriptionManagerPage = lazy(() => import('./features/billing/pages/SubscriptionManagerPage'));
const InsuranceClaimTrackerPage = lazy(() => import('./features/billing/pages/InsuranceClaimTrackerPage'));
const CommissionRulesPage = lazy(() => import('./features/billing/pages/CommissionRulesPage'));
const BillingAgentMonitorPage = lazy(() => import('./features/billing/pages/BillingAgentMonitorPage'));
const InvoiceDesignerPage = lazy(() => import('./features/billing/pages/InvoiceDesignerPage'));
const DynamicFormBuilderPage = lazy(() => import('./features/billing/pages/DynamicFormBuilderPage'));
const PaymentGatewaySettingsPage = lazy(() => import('./features/billing/pages/PaymentGatewaySettingsPage'));
const MyBillsPage = lazy(() => import('./features/billing/pages/MyBillsPage'));
const ForbiddenPage = lazy(() => import('./features/inventory/pages/ForbiddenPage').then((m) => ({ default: m.ForbiddenPage })));

/* The platform owner's console. Its own sign-in (password + authenticator
 * code), its own session store and its own shell - see features/platform.
 * Nothing under /platform is reachable with a tenant login. */
const PlatformLoginPage = lazy(() => import('./features/platform/PlatformLoginPage'));
const PlatformOverviewPage = lazy(() => import('./features/platform/PlatformOverviewPage'));
const PlatformTenantsPage = lazy(() => import('./features/platform/PlatformTenantsPage'));
const PlatformUsersPage = lazy(() => import('./features/platform/PlatformUsersPage'));
const PlatformAuditPage = lazy(() => import('./features/platform/PlatformAuditPage'));
const PlatformSecurityPage = lazy(() => import('./features/platform/PlatformSecurityPage'));

/* Deliberately near-empty. This shows for the length of one chunk fetch on a
 * local network, and a spinner that appears and vanishes inside 100ms reads
 * as a flicker of broken layout rather than as progress. */
function RouteFallback() {
  return <div style={{ minHeight: '60vh' }} aria-busy="true" />;
}

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
    <div className="inventory-scope">
      <InventoryToastProvider>
        <AppLayout>
          {children}
        </AppLayout>
      </InventoryToastProvider>
    </div>
  );
}

function App() {
  return (
    <Provider store={store}>
      <ToastProvider>
        <AuthInitializer>
          <BrowserRouter>
            <Suspense fallback={<RouteFallback />}>
            <Routes>
              <Route path="/login" element={<LoginPage />} />
              <Route path="/register" element={<RegisterPage />} />
              <Route path="/embed/book/:tenantId" element={<EmbedBookingPage />} />

              <Route
                path="/dashboard"
                element={
                  <ProtectedRoute>
                    <Shell><DashboardRouter /></Shell>
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

              {/* Customer side - the web twin of the Flutter customer screens. */}
              <Route
                path="/book"
                element={
                  <ProtectedRoute allowedRoles={['Customer']}>
                    <Shell><CustomerBookPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/my-bookings"
                element={
                  <ProtectedRoute allowedRoles={['Customer']}>
                    <Shell><MyBookingsPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/ai-planner"
                element={
                  <ProtectedRoute allowedRoles={['Customer']}>
                    <Shell><CustomerAiPlannerPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/business"
                element={
                  <ProtectedRoute>
                    <Shell><BusinessInfoPage /></Shell>
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

              {/* Spec 2.5's calendar dashboard. The page existed but was
                  never routed, so nobody could reach it. */}
              <Route
                path="/calendar"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><CalendarDashboardPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/availability"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><AvailabilitySlotsPage /></Shell>
                  </ProtectedRoute>
                }
              />

              <Route
                path="/recurring"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><RecurringSeriesPage /></Shell>
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
                    <Shell><ScheduleCopilotPage /></Shell>
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
                    <Shell><AdminPage /></Shell>
                  </ProtectedRoute>
                }
              />

              {/* ── Billing & payments ─────────────────────────────── */}
              <Route
                path="/billing"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><BillingDashboardPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/invoices"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><InvoicesPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/subscriptions"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><SubscriptionManagerPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/insurance-claims"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff', 'Customer']}>
                    <Shell><InsuranceClaimTrackerPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/commission-rules"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <Shell><CommissionRulesPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/billing-agent"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><BillingAgentMonitorPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/invoice-designer"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><InvoiceDesignerPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/form-builder"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager']}>
                    <Shell><DynamicFormBuilderPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/payment-gateways"
                element={
                  <ProtectedRoute allowedRoles={['Admin']}>
                    <Shell><PaymentGatewaySettingsPage /></Shell>
                  </ProtectedRoute>
                }
              />
              <Route
                path="/my-bills"
                element={
                  <ProtectedRoute allowedRoles={['Customer']}>
                    <Shell><MyBillsPage /></Shell>
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
                path="/suppliers"
                element={
                  <ProtectedRoute allowedRoles={['Admin', 'Manager', 'Staff']}>
                    <InventoryShell><SuppliersPage /></InventoryShell>
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

              {/* ── Platform console (owner only; guarded inside PlatformLayout) ── */}
              <Route path="/platform/login" element={<PlatformLoginPage />} />
              <Route path="/platform" element={<PlatformOverviewPage />} />
              <Route path="/platform/tenants" element={<PlatformTenantsPage />} />
              <Route path="/platform/users" element={<PlatformUsersPage />} />
              <Route path="/platform/audit" element={<PlatformAuditPage />} />
              <Route path="/platform/security" element={<PlatformSecurityPage />} />

              <Route path="/" element={<LandingPage />} />
              <Route path="*" element={<div style={{ padding: '2rem' }}><h1>404 - Page Not Found</h1></div>} />
            </Routes>
            </Suspense>
          </BrowserRouter>
        </AuthInitializer>
      </ToastProvider>
    </Provider>
  );
}

export default App;
