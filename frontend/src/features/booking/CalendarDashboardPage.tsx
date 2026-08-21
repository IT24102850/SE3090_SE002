import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useGetBookingsQuery, useGetResourcesQuery } from '../../api/bookingApi';
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

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Dashboard</h1>
          <p className="page-subtitle">All bookings across branches, color-coded by status.</p>
        </div>
        <div className="filter-bar">
          <select className="input" value={resourceFilter} onChange={(e) => setResourceFilter(e.target.value)}>
            <option value="">All resources</option>
            {resourcesData?.items.map((r) => (
              <option key={r.id} value={r.id}>{r.name}</option>
            ))}
          </select>
        </div>
      </div>

      <div className="stat-grid">
        <div className="stat-tile">
          <div className="stat-tile-label">Today</div>
          <div className="stat-tile-value">{todayCount}</div>
          <div className="stat-tile-sub">bookings scheduled</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">This view</div>
          <div className="stat-tile-value">{totalThisView}</div>
          <div className="stat-tile-sub">total bookings shown</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Pending</div>
          <div className="stat-tile-value" style={{ color: STATUS_COLORS.Pending.bg }}>{pendingCount}</div>
          <div className="stat-tile-sub">awaiting confirmation</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Cancelled</div>
          <div className="stat-tile-value" style={{ color: STATUS_COLORS.Cancelled.bg }}>{cancelledCount}</div>
          <div className="stat-tile-sub">in this view</div>
        </div>
      </div>

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
