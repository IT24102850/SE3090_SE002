import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import {
  useCancelBookingMutation,
  useCheckInBookingMutation,
  useDeleteBookingMutation,
  useGetBookingsQuery,
  useGetConflictsQuery,
  useGetResourcesQuery,
  useRescheduleBookingMutation,
  useUpdateBookingStatusMutation,
} from '../../api/bookingApi';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import BookingFormModal from './BookingFormModal';
import {
  addDays, buildWeekGrid, combineDateWithTimeOfDay, formatDayLabel, formatTime,
  isSameDay, startOfDay, toISODate,
} from '../../shared/dateUtils';
import { BOOKING_STATUSES, STATUS_COLORS, type Booking } from './types';

export default function BookingManagerPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const [weekAnchor, setWeekAnchor] = useState(() => new Date());
  const [showCreate, setShowCreate] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [resourceFilter, setResourceFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [dragOverDay, setDragOverDay] = useState<string | null>(null);
  const [showConflicts, setShowConflicts] = useState(false);
  const [checkInId, setCheckInId] = useState('');

  const weekDays = useMemo(() => buildWeekGrid(weekAnchor), [weekAnchor]);

  // FR-AS1: Staff only see their own branch's bookings; Admin/Manager stay tenant-wide.
  const staffBranchId = user?.role === 'Staff' ? user.branchId : undefined;

  const { data: resourcesData } = useGetResourcesQuery({ tenantId, branchId: staffBranchId, pageSize: 100 }, { skip: !tenantId });

  const { data: weekData, isFetching: weekLoading } = useGetBookingsQuery(
    { tenantId, branchId: staffBranchId, dateFrom: toISODate(weekDays[0]), dateTo: toISODate(addDays(weekDays[6], 1)), pageSize: 200 },
    { skip: !tenantId }
  );

  const { data: tableData, isFetching: tableLoading } = useGetBookingsQuery(
    { tenantId, branchId: staffBranchId, status: statusFilter || undefined, resourceId: resourceFilter || undefined, page, pageSize: 10 },
    { skip: !tenantId }
  );

  const { data: conflictsData } = useGetConflictsQuery({ tenantId }, { skip: !tenantId });

  const [reschedule] = useRescheduleBookingMutation();
  const [cancelBooking] = useCancelBookingMutation();
  const [deleteBooking] = useDeleteBookingMutation();
  const [updateStatus] = useUpdateBookingStatusMutation();
  const [checkIn, { isLoading: checkingIn }] = useCheckInBookingMutation();

  const bookingsByDay = useMemo(() => {
    const map = new Map<string, Booking[]>();
    for (const b of weekData?.items ?? []) {
      const key = toISODate(startOfDay(new Date(b.startTime)));
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(b);
    }
    for (const list of map.values()) list.sort((a, b) => a.startTime.localeCompare(b.startTime));
    return map;
  }, [weekData]);

  const filteredTableItems = useMemo(() => {
    const items = tableData?.items ?? [];
    if (!search.trim()) return items;
    const q = search.toLowerCase();
    return items.filter((b) => (b.title ?? '').toLowerCase().includes(q) || b.resourceName.toLowerCase().includes(q));
  }, [tableData, search]);

  const handleDrop = async (day: Date, e: React.DragEvent) => {
    e.preventDefault();
    setDragOverDay(null);
    const bookingId = e.dataTransfer.getData('bookingId');
    const startIso = e.dataTransfer.getData('startIso');
    const endIso = e.dataTransfer.getData('endIso');
    if (!bookingId || !startIso || !endIso) return;

    if (isSameDay(new Date(startIso), day)) return; // dropped on the same day, no-op

    const durationMs = new Date(endIso).getTime() - new Date(startIso).getTime();
    const newStart = combineDateWithTimeOfDay(day, startIso);
    const newEnd = new Date(new Date(newStart).getTime() + durationMs).toISOString();

    try {
      await reschedule({ id: bookingId, newStartTime: newStart, newEndTime: newEnd }).unwrap();
      show('Booking rescheduled.', 'success');
    } catch (err: any) {
      show(apiErrorMessage(err, 'Could not reschedule — that slot may already be booked.'), 'error');
    }
  };

  const handleCancel = async (id: string) => {
    try {
      await cancelBooking(id).unwrap();
      show('Booking cancelled.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not cancel.'), 'error');
    }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Delete this booking permanently?')) return;
    try {
      await deleteBooking(id).unwrap();
      show('Booking deleted.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not delete.'), 'error');
    }
  };

  const handleStatusChange = async (id: string, status: string) => {
    try {
      await updateStatus({ id, status }).unwrap();
      show('Status updated.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not update status.'), 'error');
    }
  };

  // FR-AS9: desk check-in without a camera — paste the booking ID from the
  // patient's confirmation/QR (mobile has the actual camera scanner).
  const handleCheckIn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!checkInId.trim()) return;
    try {
      const result = await checkIn(checkInId.trim()).unwrap();
      show(result.message, 'success');
      setCheckInId('');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not check in — is the booking ID correct?'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Booking Manager</h1>
          <p className="page-subtitle">Drag a booking card onto another day to reschedule it.</p>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <form onSubmit={handleCheckIn} style={{ display: 'flex', gap: 6 }}>
            <input
              className="input"
              placeholder="Paste booking ID to check in…"
              value={checkInId}
              onChange={(e) => setCheckInId(e.target.value)}
              style={{ width: 220 }}
            />
            <button className="btn btn-secondary" type="submit" disabled={!checkInId.trim() || checkingIn}>
              {checkingIn ? <span className="spinner" /> : 'Check in'}
            </button>
          </form>
          <button className="btn btn-primary" onClick={() => setShowCreate(true)}>+ New booking</button>
        </div>
      </div>

      {!!conflictsData?.totalConflicts && (
        <div className="banner banner-critical">
          ⚠ {conflictsData.totalConflicts} scheduling conflict{conflictsData.totalConflicts > 1 ? 's' : ''} detected.
          <button className="btn btn-ghost btn-sm" style={{ marginLeft: 'auto' }} onClick={() => setShowConflicts((v) => !v)}>
            {showConflicts ? 'Hide' : 'Review'}
          </button>
        </div>
      )}
      {showConflicts && conflictsData?.conflicts.map((c, i) => (
        <div className="banner banner-warning" key={i}>
          <strong>{c.resourceName}:</strong>&nbsp;
          "{c.bookingA.title ?? 'Booking'}" ({formatTime(c.bookingA.startTime)}–{formatTime(c.bookingA.endTime)}) overlaps
          "{c.bookingB.title ?? 'Booking'}" ({formatTime(c.bookingB.startTime)}–{formatTime(c.bookingB.endTime)})
        </div>
      ))}

      <div className="card" style={{ marginBottom: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: '1px solid var(--color-border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => setWeekAnchor(addDays(weekAnchor, -7))}>‹</button>
            <strong>{formatDayLabel(weekDays[0])} – {formatDayLabel(weekDays[6])}</strong>
            <button className="btn btn-secondary btn-sm" onClick={() => setWeekAnchor(addDays(weekAnchor, 7))}>›</button>
          </div>
          <button className="btn btn-ghost btn-sm" onClick={() => setWeekAnchor(new Date())}>This week</button>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)' }}>
          {weekDays.map((day) => {
            const key = toISODate(day);
            const events = bookingsByDay.get(key) ?? [];
            const isDropTarget = dragOverDay === key;
            return (
              <div
                key={key}
                className={`calendar-cell${isSameDay(day, new Date()) ? ' is-today' : ''}${isDropTarget ? ' is-drop-target' : ''}`}
                style={{ minHeight: 160 }}
                onDragOver={(e) => { e.preventDefault(); setDragOverDay(key); }}
                onDragLeave={() => setDragOverDay((cur) => (cur === key ? null : cur))}
                onDrop={(e) => handleDrop(day, e)}
              >
                <span className="calendar-date">{day.getDate()}</span>
                {weekLoading ? (
                  <span style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>Loading…</span>
                ) : events.map((b) => (
                  <div
                    key={b.id}
                    className="calendar-event"
                    draggable
                    onDragStart={(e) => {
                      e.dataTransfer.setData('bookingId', b.id);
                      e.dataTransfer.setData('startIso', b.startTime);
                      e.dataTransfer.setData('endIso', b.endTime);
                    }}
                    style={{ background: STATUS_COLORS[b.status].bg }}
                    title="Drag to reschedule"
                  >
                    {formatTime(b.startTime)} {b.title ?? b.bookingTypeName}
                  </div>
                ))}
              </div>
            );
          })}
        </div>
      </div>

      <div className="filter-bar">
        <input className="input" placeholder="Search title or resource…" value={search} onChange={(e) => setSearch(e.target.value)} style={{ minWidth: 220 }} />
        <select className="input" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}>
          <option value="">All statuses</option>
          {BOOKING_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <select className="input" value={resourceFilter} onChange={(e) => { setResourceFilter(e.target.value); setPage(1); }}>
          <option value="">All resources</option>
          {resourcesData?.items.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Booking</th>
              <th>Resource</th>
              <th>When</th>
              <th>Status</th>
              <th>Priority</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {tableLoading && (
              <tr><td colSpan={6} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>
            )}
            {!tableLoading && filteredTableItems.length === 0 && (
              <tr><td colSpan={6} className="empty-state">No bookings match these filters.</td></tr>
            )}
            {filteredTableItems.map((b) => (
              <tr key={b.id}>
                <td>
                  <div style={{ fontWeight: 600 }}>{b.title ?? b.bookingTypeName}</div>
                  <span className="badge" style={{ background: `${b.colorHex}22`, color: b.colorHex, marginTop: 4 }}>{b.bookingTypeName}</span>
                </td>
                <td>{b.resourceName}</td>
                <td>{formatTime(b.startTime)} – {formatTime(b.endTime)}<br /><span style={{ color: 'var(--color-text-muted)', fontSize: 12 }}>{formatDayLabel(new Date(b.startTime))}</span></td>
                <td>
                  <select
                    className="input"
                    style={{ padding: '4px 8px', fontSize: 12, width: 'auto' }}
                    value={b.status}
                    onChange={(e) => handleStatusChange(b.id, e.target.value)}
                  >
                    {BOOKING_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
                  </select>
                </td>
                <td><StatusBadgeLikePriority priority={b.priority} /></td>
                <td>
                  <div style={{ display: 'flex', gap: 6 }}>
                    {b.status !== 'Cancelled' && (
                      <button className="btn btn-ghost btn-sm" onClick={() => handleCancel(b.id)}>Cancel</button>
                    )}
                    <button className="btn btn-danger btn-sm" onClick={() => handleDelete(b.id)}>Delete</button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {tableData && tableData.totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 8, marginTop: 16 }}>
          <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
          <span style={{ alignSelf: 'center', fontSize: 13, color: 'var(--color-text-secondary)' }}>Page {page} of {tableData.totalPages}</span>
          <button className="btn btn-secondary btn-sm" disabled={page >= tableData.totalPages} onClick={() => setPage((p) => p + 1)}>Next</button>
        </div>
      )}

      {showCreate && user && (
        <BookingFormModal
          tenantId={tenantId}
          userId={user.id}
          defaultDate={weekDays[0]}
          onClose={() => setShowCreate(false)}
        />
      )}
    </div>
  );
}

function StatusBadgeLikePriority({ priority }: { priority: string }) {
  const tone = priority === 'Urgent' ? 'critical' : priority === 'High' ? 'warning' : priority === 'Low' ? 'neutral' : 'primary';
  return <span className={`badge badge-${tone}`}>{priority}</span>;
}
