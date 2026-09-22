import { useSelector } from 'react-redux';
import { useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import CalendarDashboardPage from '../booking/CalendarDashboardPage';
import ClinicDashboard from './clinic/ClinicDashboard';
import RestaurantDashboard from './restaurant/RestaurantDashboard';
import GymDashboard from './gym/GymDashboard';
import SchoolDashboard from './school/SchoolDashboard';
import CustomerHomePage from '../customer/CustomerHomePage';
import SubtypeDashboard from './SubtypeDashboard';
import WhaleWatchingDashboard from './WhaleWatchingDashboard';
import { getSubtypeConfig } from './subtypes/subtypeRegistry';
import { parseTenantSubType } from './subtypes/tourismSubTypes';

/* Resolves the tenant's SubType and renders the dashboard for it.
 *
 * The fallback chain is deliberately conservative:
 *   - BusinessType Clinic
 *       -> the clinic operations dashboard (which still carries the month
 *          calendar under its "Calendar" view, so nothing is lost);
 *   - BusinessType Restaurant (or Cafe)
 *       -> the restaurant operations dashboard, same arrangement;
 *   - BusinessType Gym (or Fitness)
 *       -> the gym operations dashboard, same arrangement;
 *   - BusinessType School (Tuition, Education, Academy)
 *       -> the school dashboard, same arrangement;
 *   - SubType unset, unrecognised, or the business is not Tourism
 *       -> the exact CalendarDashboardPage that was here before, unchanged;
 *   - a recognised SubType with an operational module set
 *       -> that sub-type's own dashboard (only whaleWatching so far);
 *   - any other recognised SubType
 *       -> its terminology and KPIs above the same calendar.
 *
 * So no existing tenant loses anything, and nobody sees a half-built
 * specialised screen just because their sub-type string was recognised. */

export default function DashboardRouter() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const { data: tenant, isLoading } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const { data: profile } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });

  // A customer never sees an operations screen: their dashboard is their
  // own home - next booking, quick actions, the business's details.
  if (user?.role === 'Customer') return <CustomerHomePage />;

  // Render the generic dashboard while the tenant loads rather than a
  // spinner: it is what most tenants get anyway, and a flash of the right
  // screen beats a flash of nothing.
  if (isLoading || !tenant) return <CalendarDashboardPage />;

  // Matched case-insensitively: the registration form stores "Clinic", but
  // seeded tenants have been known to carry "clinic".
  const businessType = tenant.businessType?.trim().toLowerCase();
  if (businessType === 'clinic') {
    return <ClinicDashboard tenant={tenant} profile={profile} />;
  }
  if (businessType === 'restaurant' || businessType === 'cafe') {
    return <RestaurantDashboard tenant={tenant} profile={profile} />;
  }
  if (businessType === 'gym' || businessType === 'fitness') {
    return <GymDashboard tenant={tenant} profile={profile} />;
  }
  if (businessType === 'school' || businessType === 'tuition' || businessType === 'education' || businessType === 'academy') {
    return <SchoolDashboard tenant={tenant} profile={profile} />;
  }

  const subType = parseTenantSubType(tenant.subType);
  if (!subType) return <CalendarDashboardPage />;

  const config = getSubtypeConfig(subType);

  if (config.modules.departures) {
    return <WhaleWatchingDashboard config={config} tenant={tenant} profile={profile} />;
  }

  return <SubtypeDashboard config={config} />;
}
