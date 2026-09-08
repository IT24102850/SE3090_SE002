import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import {
  useGetBookingsQuery, useGetResourcesQuery, useGetTenantQuery, useGetTenantProfileQuery,
} from '../../api/bookingApi';
import { businessHeroImage, businessDescriptor } from '../../shared/businessImagery';
import {
  addDays, buildMonthGrid, formatDayLabel, formatMonthYear, formatTime,
  isSameDay, startOfDay, toISODate, WEEKDAY_LABELS,
} from '../../shared/dateUtils';
import { BOOKING_STATUSES, STATUS_COLORS, type Booking } from './types';
import BookingDetailsModal from './BookingDetailsModal';

export default function CalendarDashboardPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const [anchor, setAnchor] = useState(() => new Date());
  const [resourceFilter, setResourceFilter] = useState('');
  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);

  const grid = useMemo(() => buildMonthGrid(anchor), [anchor]);
  const gridStart = grid[0];
  const gridEnd = grid[grid.length - 1];

  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });
  const { data, isLoading } = useGetBookingsQuery(
    {
      tenantId,
      dateFrom: toISODate(gridStart),
      dateTo: toISODate(addDays(gridEnd, 1)),
      resourceId: resourceFilter || undefined,
      pageSize: 500,
    },
    { skip: !tenantId }
  );

  const bookingsByDay = useMemo(() => {
    const map = new Map<string, Booking[]>();
    for (const b of data?.items ?? []) {
      const key = toISODate(startOfDay(new Date(b.startTime)));
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(b);
    }
    for (const list of map.values()) list.sort((a, b) => a.startTime.localeCompare(b.startTime));
    return map;
  }, [data]);

  const today = new Date();
  const currentMonth = anchor.getMonth();

  const todayCount = bookingsByDay.get(toISODate(startOfDay(today)))?.length ?? 0;
  const totalThisView = data?.items.length ?? 0;
  const pendingCount = (data?.items ?? []).filter((b) => b.status === 'Pending').length;
  const cancelledCount = (data?.items ?? []).filter((b) => b.status === 'Cancelled').length;
  const confirmedCount = (data?.items ?? []).filter((b) => b.status === 'Confirmed').length;
  const completedCount = (data?.items ?? []).filter((b) => b.status === 'Completed').length;

  // The hero photograph is keyed to what this tenant actually does — its own
  // cover image when the owner has set one, else its Tourism sub-type, else
  // its business type.
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const { data: profile } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const heroImage = businessHeroImage({
    businessType: tenant?.businessType,
    subType: tenant?.subType,
    coverImageUrl: profile?.coverImageUrl,
  });
  const descriptor = businessDescriptor({ businessType: tenant?.businessType, subType: tenant?.subType });

  // Status mix drives the segmented activity bar. Zero-width segments are
  // dropped so an empty month renders one flat track rather than slivers.
  const mix = [
    { name: 'Confirmed', count: confirmedCount, color: STATUS_COLORS.Confirmed.bg },
    { name: 'Pending', count: pendingCount, color: STATUS_COLORS.Pending.bg },
    { name: 'Completed', count: completedCount, color: STATUS_COLORS.Completed.bg },
    { name: 'Cancelled', count: cancelledCount, color: STATUS_COLORS.Cancelled.bg },
  ].filter((s) => s.count > 0);
  const mixTotal = mix.reduce((sum, s) => sum + s.count, 0);

  return (
    <div>
      <section className="hero">
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div>
              <p className="hero-eyebrow">{descriptor}</p>
              <h1 className="hero-title">{tenant?.name ?? 'Dashboard'}</h1>
              <div className="hero-figure">{totalThisView.toLocaleString()}</div>
              <p className="hero-sub">bookings in {formatMonthYear(anchor)}</p>
            </div>
            <div className="filter-bar" style={{ marginBottom: 0 }}>
              <select className="input" value={resourceFilter} onChange={(e) => setResourceFilter(e.target.value)}>
                <option value="">All resources</option>
                {resourcesData?.items.map((r) => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="hero-activity">
            {mixTotal === 0 ? (
              <span style={{ flexGrow: 1, background: 'rgba(255,255,255,0.1)' }} />
            ) : (
              mix.map((s) => (
                <span key={s.name} style={{ flexGrow: s.count, background: s.color, boxShadow: `0 0 12px -2px ${s.color}` }} />
              ))
            )}
          </div>

          <div className="hero-legend">
            {mix.length === 0 ? (
              <span className="hero-legend-name" style={{ fontSize: '0.8rem' }}>No bookings in this view yet.</span>
            ) : (
              mix.map((s) => (
                <span key={s.name} className="hero-legend-row">
                  <span className="hero-legend-dot" style={{ background: s.color }} />
                  <span className="hero-legend-name">{s.name}</span>
                  <span className="hero-legend-value">{s.count}</span>
                  <span className="hero-legend-name">{Math.round((s.count / mixTotal) * 100)}%</span>
                </span>
              ))
            )}
          </div>

          <div className="hero-tiles">
            <div className="hero-tile">
              <div className="hero-tile-label">Today</div>
              <div className="hero-tile-value">{todayCount}</div>
              <div className="hero-tile-sub">bookings scheduled</div>
            </div>
            <div className="hero-tile">
              <div className="hero-tile-label">This view</div>
              <div className="hero-tile-value">{totalThisView}</div>
              <div className="hero-tile-sub">total bookings shown</div>
            </div>
            <div className="hero-tile">
              <div className="hero-tile-label">Pending</div>
              <div className="hero-tile-value" style={{ color: STATUS_COLORS.Pending.bg }}>{pendingCount}</div>
              <div className="hero-tile-sub">awaiting confirmation</div>
            </div>
            <div className="hero-tile">
              <div className="hero-tile-label">Cancelled</div>
              <div className="hero-tile-value" style={{ color: STATUS_COLORS.Cancelled.bg }}>{cancelledCount}</div>
              <div className="hero-tile-sub">in this view</div>
            </div>
          </div>
        </div>
      </section>

      <div className="card">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: '1px solid var(--color-border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => setAnchor(addDays(startOfDay(anchor), -30))}>‹</button>
            <strong style={{ fontSize: '1rem', minWidth: 160, textAlign: 'center' }}>{formatMonthYear(anchor)}</strong>
            <button className="btn btn-secondary btn-sm" onClick={() => setAnchor(addDays(startOfDay(anchor), 30))}>›</button>
          </div>
          <button className="btn btn-ghost btn-sm" onClick={() => setAnchor(new Date())}>Today</button>
        </div>

        {isLoading ? (
          <div className="loading-row"><span className="spinner spinner-dark" /> Loading bookings…</div>
        ) : (
          <div className="calendar-grid">
            {WEEKDAY_LABELS.map((w) => (
              <div key={w} className="calendar-weekday">{w}</div>
            ))}
            {grid.map((day) => {
              const key = toISODate(day);
              const events = bookingsByDay.get(key) ?? [];
              const outside = day.getMonth() !== currentMonth;
              const isToday = isSameDay(day, today);
              const visible = events.slice(0, 3);
              const overflow = events.length - visible.length;
              return (
                <div key={key} className={`calendar-cell${outside ? ' is-outside' : ''}${isToday ? ' is-today' : ''}`}>
                  <span className="calendar-date">{day.getDate()}</span>
                  {visible.map((b) => {
                    const c = STATUS_COLORS[b.status];
                    return (
                      <div
                        key={b.id}
                        className="calendar-event"
                        style={{ background: c.bg }}
                        title={`${b.title ?? b.bookingTypeName} — ${b.status}`}
                        onClick={() => setSelectedBooking(b)}
                      >
                        {formatTime(b.startTime)} {b.title ?? b.bookingTypeName}
                      </div>
                    );
                  })}
                  {overflow > 0 && <div className="calendar-event-more">+{overflow} more</div>}
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="chart-legend" style={{ marginTop: 16 }}>
        {BOOKING_STATUSES.map((s) => (
          <div className="chart-legend-item" key={s}>
            <span className="chart-legend-swatch" style={{ background: STATUS_COLORS[s].bg }} />
            {s}
          </div>
        ))}
      </div>

      {selectedBooking && (
        <BookingDetailsModal booking={selectedBooking} onClose={() => setSelectedBooking(null)} />
      )}
    </div>
  );
}

export { formatDayLabel };
