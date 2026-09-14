import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useGetBookingsQuery, useGetBranchesQuery, useGetResourcesQuery } from '../../api/bookingApi';
import { addDays, formatDayLabel, formatTime, toISODate } from '../../shared/dateUtils';
import { STATUS_COLORS } from './types';
import BookingDetailsModal from './BookingDetailsModal';
import type { Booking } from './types';

const WINDOW_START_HOUR = 7;
const WINDOW_END_HOUR = 19;
const WINDOW_MINUTES = (WINDOW_END_HOUR - WINDOW_START_HOUR) * 60;
const HOUR_MARKS = Array.from({ length: WINDOW_END_HOUR - WINDOW_START_HOUR + 1 }, (_, i) => WINDOW_START_HOUR + i);

export default function MultiBranchSchedulePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const [day, setDay] = useState(() => new Date());
  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);

  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });
  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 200 }, { skip: !tenantId });
  const { data: bookingsData, isLoading } = useGetBookingsQuery(
    { tenantId, dateFrom: toISODate(day), dateTo: toISODate(addDays(day, 1)), pageSize: 500 },
    { skip: !tenantId }
  );

  const bookingsByResource = useMemo(() => {
    const map = new Map<string, Booking[]>();
    for (const b of bookingsData?.items ?? []) {
      if (!map.has(b.resourceId)) map.set(b.resourceId, []);
      map.get(b.resourceId)!.push(b);
    }
    return map;
  }, [bookingsData]);

  const groupedByBranch = useMemo(() => {
    const resources = resourcesData?.items ?? [];
    const groups = new Map<string, { branchName: string; resources: typeof resources }>();
    const branchNameOf = (id?: string | null) => branches?.find((b) => b.id === id)?.name ?? 'Unassigned';

    for (const r of resources) {
      const key = r.branchId ?? 'unassigned';
      if (!groups.has(key)) groups.set(key, { branchName: branchNameOf(r.branchId), resources: [] });
      groups.get(key)!.resources.push(r);
    }
    return Array.from(groups.values());
  }, [resourcesData, branches]);

  const barPosition = (b: Booking) => {
    const windowStart = new Date(day);
    windowStart.setHours(WINDOW_START_HOUR, 0, 0, 0);
    const start = new Date(b.startTime);
    const end = new Date(b.endTime);
    const startMin = Math.max(0, (start.getTime() - windowStart.getTime()) / 60000);
    const endMin = Math.min(WINDOW_MINUTES, (end.getTime() - windowStart.getTime()) / 60000);
    if (endMin <= 0 || startMin >= WINDOW_MINUTES) return null;
    const left = (startMin / WINDOW_MINUTES) * 100;
    const width = Math.max(((endMin - startMin) / WINDOW_MINUTES) * 100, 1.5);
    return { left: `${left}%`, width: `${width}%` };
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Multi-Branch Schedule</h1>
          <p className="page-subtitle">Every resource across every branch, one day at a time.</p>
        </div>
        <div className="filter-bar">
          <button className="btn btn-secondary btn-sm" onClick={() => setDay((d) => addDays(d, -1))}>‹</button>
          <input className="input" type="date" value={toISODate(day)} onChange={(e) => setDay(new Date(`${e.target.value}T00:00:00`))} />
          <button className="btn btn-secondary btn-sm" onClick={() => setDay((d) => addDays(d, 1))}>›</button>
          <button className="btn btn-ghost btn-sm" onClick={() => setDay(new Date())}>Today</button>
        </div>
      </div>

      <p style={{ color: 'var(--color-text-secondary)', marginTop: -12, marginBottom: 20, fontSize: 13 }}>{formatDayLabel(day)}</p>

      {isLoading ? (
        <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading schedule…</div></div>
      ) : groupedByBranch.length === 0 ? (
        <div className="card"><div className="empty-state">No resources to display yet.</div></div>
      ) : (
        groupedByBranch.map((group) => (
          <div className="card" key={group.branchName} style={{ marginBottom: 20, overflow: 'hidden' }}>
            <div style={{ padding: '14px 20px', borderBottom: '1px solid var(--color-border)', fontWeight: 700, background: 'var(--color-surface-muted)' }}>
              {group.branchName}
            </div>
            <div className="gantt-header">
              <div />
              <div className="gantt-header-track" style={{ gridTemplateColumns: `repeat(${HOUR_MARKS.length - 1}, 1fr)` }}>
                {HOUR_MARKS.slice(0, -1).map((h) => (
                  <div className="gantt-header-col" key={h}>{h % 12 === 0 ? 12 : h % 12}{h < 12 ? 'am' : 'pm'}</div>
                ))}
              </div>
            </div>
            {group.resources.map((r) => (
              <div className="gantt-row" key={r.id}>
                <div className="gantt-row-label">
                  {r.name}
                  <span className="gantt-row-sub">{r.category}</span>
                </div>
                <div className="gantt-track">
                  {(bookingsByResource.get(r.id) ?? []).map((b) => {
                    const pos = barPosition(b);
                    if (!pos) return null;
                    return (
                      <div
                        key={b.id}
                        className="gantt-bar"
                        style={{ left: pos.left, width: pos.width, background: STATUS_COLORS[b.status].bg }}
                        title={`${b.title ?? b.bookingTypeName} — ${formatTime(b.startTime)}–${formatTime(b.endTime)}`}
                        onClick={() => setSelectedBooking(b)}
                      >
                        {b.title ?? b.bookingTypeName}
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        ))
      )}

      {selectedBooking && <BookingDetailsModal booking={selectedBooking} onClose={() => setSelectedBooking(null)} />}
    </div>
  );
}
