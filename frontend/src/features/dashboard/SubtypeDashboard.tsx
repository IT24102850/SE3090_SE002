import { useMemo } from 'react';
import { useSelector } from 'react-redux';
import { useGetBookingsQuery, useGetResourcesQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { addDays, startOfDay, toISODate } from '../../shared/dateUtils';
import CalendarDashboardPage from '../booking/CalendarDashboardPage';
import type { Booking, Resource } from '../booking/types';
import KpiCards, { type KpiValues } from './components/KpiCards';
import type { SubtypeDashboardConfig } from './subtypes/SubtypeDashboardConfig';

/* The dashboard for the sub-types that do not (yet) have their own
 * operational board: the registry's terminology and KPI strip on top of the
 * month calendar that was already there.
 *
 * Nothing is removed - the calendar underneath is the same component the
 * generic dashboard renders - so a dive centre or a homestay gains a header
 * that speaks its own language without losing anything it had. */

/** Derives the `bookings`- and `resources`-sourced KPI fields the registry
 *  can ask for. A field no sub-type requests is simply never read.
 *
 *  Every value here is computed from data already on screen; nothing is
 *  estimated. Fields that cannot be computed from the booking list are left
 *  undefined so KpiCards renders an em dash instead of a misleading zero -
 *  deposits held, for instance, has no column behind it yet. */
function deriveKpis(bookings: Booking[], resources: Resource[]): KpiValues {
  const today = startOfDay(new Date());
  const todayKey = toISODate(today);
  const weekEnd = addDays(today, 7);

  const live = bookings.filter(
    (b) => b.status !== 'Cancelled' && b.status !== 'Rejected' && b.status !== 'WeatherCancelled',
  );
  const todays = live.filter((b) => toISODate(startOfDay(new Date(b.startTime))) === todayKey);
  const attendees = (list: Booking[]) => list.reduce((sum, b) => sum + (b.attendeeCount ?? 1), 0);
  const revenue = (list: Booking[]) => list.reduce((sum, b) => sum + (b.totalCost ?? 0), 0);

  const thisWeek = live.filter((b) => {
    const start = new Date(b.startTime);
    return start >= today && start < weekEnd;
  });

  // Occupancy tonight for night-unit businesses: rooms whose stay spans
  // tonight, over the rooms that exist. Only meaningful when the tenant has
  // resources at all, hence the guard rather than a divide by zero.
  const roomCount = resources.filter((r) => r.status !== 'Archived').length;
  const occupiedTonight = live.filter((b) => {
    const start = new Date(b.startTime);
    const end = new Date(b.endTime);
    return start <= addDays(today, 1) && end > today;
  }).length;

  const withCost = live.filter((b) => (b.totalCost ?? 0) > 0);
  const adr = withCost.length > 0 ? revenue(withCost) / withCost.length : undefined;

  return {
    today: todays.length,
    thisWeek: thisWeek.length,
    pending: live.filter((b) => b.status === 'Pending').length,
    confirmed: live.filter((b) => b.status === 'Confirmed').length,
    inProgress: live.filter((b) => b.status === 'InProgress' || b.status === 'CheckedIn').length,
    attendeesToday: attendees(todays),
    avgGroupSize: live.length > 0 ? Number((attendees(live) / live.length).toFixed(1)) : undefined,
    revenue: revenue(live),
    confirmedRevenue: revenue(live.filter((b) => b.status === 'Confirmed' || b.status === 'Completed')),
    avgValue: withCost.length > 0 ? Math.round(revenue(withCost) / withCost.length) : undefined,
    checkInsToday: todays.filter((b) => toISODate(startOfDay(new Date(b.startTime))) === todayKey).length,
    checkOutsToday: live.filter((b) => toISODate(startOfDay(new Date(b.endTime))) === todayKey).length,
    endingToday: live.filter((b) => toISODate(startOfDay(new Date(b.endTime))) === todayKey).length,
    occupancyTonight: roomCount > 0 ? (occupiedTonight / roomCount) * 100 : undefined,
    adr,
    revpar: adr !== undefined && roomCount > 0 ? (adr * occupiedTonight) / roomCount : undefined,
    // Resource-derived: share of resources with at least one booking today.
    utilisation:
      roomCount > 0
        ? (new Set(todays.map((b) => b.resourceId)).size / roomCount) * 100
        : undefined,
    availableStaff: resources.filter((r) => r.category === 'Staff' && r.status === 'Available').length,
  };
}

export default function SubtypeDashboard({ config }: { config: SubtypeDashboardConfig }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const from = toISODate(addDays(startOfDay(new Date()), -14));
  const to = toISODate(addDays(startOfDay(new Date()), 31));

  const { data, isLoading } = useGetBookingsQuery(
    { tenantId, dateFrom: from, dateTo: to, pageSize: 500 },
    { skip: !tenantId },
  );
  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });

  const values = useMemo(
    () => deriveKpis(data?.items ?? [], resourcesData?.items ?? []),
    [data, resourcesData],
  );

  return (
    <div>
      <div className="page-header" style={{ marginBottom: 12 }}>
        <div>
          <p className="hero-eyebrow" style={{ color: config.themeColor }}>
            {config.icon} {config.label}
          </p>
          <h1 className="page-title" style={{ margin: 0 }}>{config.resourceTermPlural}</h1>
          <p className="page-subtitle">{config.heroActionLabel}</p>
        </div>
      </div>

      <KpiCards kpis={config.kpis} values={values} loading={isLoading} />

      <div style={{ marginTop: 20 }}>
        <CalendarDashboardPage />
      </div>
    </div>
  );
}
