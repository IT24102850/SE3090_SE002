import { useSelector } from 'react-redux';
import { useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import CalendarDashboardPage from '../booking/CalendarDashboardPage';
import SubtypeDashboard from './SubtypeDashboard';
import WhaleWatchingDashboard from './WhaleWatchingDashboard';
import { getSubtypeConfig } from './subtypes/subtypeRegistry';
import { parseTenantSubType } from './subtypes/tourismSubTypes';

/* Resolves the tenant's SubType and renders the dashboard for it.
 *
 * The fallback chain is deliberately conservative:
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

  // Render the generic dashboard while the tenant loads rather than a
  // spinner: it is what most tenants get anyway, and a flash of the right
  // screen beats a flash of nothing.
  if (isLoading || !tenant) return <CalendarDashboardPage />;

  const subType = parseTenantSubType(tenant.subType);
  if (!subType) return <CalendarDashboardPage />;

  const config = getSubtypeConfig(subType);

  if (config.modules.departures) {
    return <WhaleWatchingDashboard config={config} tenant={tenant} profile={profile} />;
  }

  return <SubtypeDashboard config={config} />;
}
