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
  addDays, buildMonthGrid, buildWeekGrid, combineDateWithTimeOfDay, formatDayLabel, formatMonthYear, formatTime,
  isSameDay, startOfDay, toISODate, WEEKDAY_LABELS,
} from '../../shared/dateUtils';
import { BOOKING_STATUSES, STATUS_COLORS, parseTicketBreakdown, type Booking } from './types';
import { useSubtypeConfig } from '../dashboard/useSubtypeConfig';
import './reservations.css';

/* Reservations.
 *
 * Laid out as an operations desk rather than a report: a signal strip of
 * four numbers that change during the day, a two-week trend so a quiet
 * morning can be told from a quiet season, the list (or the drag-to-
 * reschedule week board) as the work surface, and a rail with a month
 * calendar that filters the list and a "next up" timeline.
 *
 * Everything the previous page could do is still here - check-in by ID,
 * status changes inline, cancel/delete, conflicts, the week board - it is
 * the arrangement and the reading of the data that changed.
 */

type View = 'list' | 'week';

const AVATAR_HUES = [212, 262, 330, 20, 152, 190];

const money = (n: number, currency = 'LKR') => `${currency} ${Math.round(n).toLocaleString()}`;
const guestName = (b: Booking) => (b.title ?? '').replace(/\s*·\s*website\s*$/i, '').trim() || b.bookingTypeName;
const initialsOf = (name: string) => name.split(/\s+/).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? '').join('') || '?';
const hueOf = (s: string) => AVATAR_HUES[[...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % AVATAR_HUES.length];

/** "2 adults · 1 child" from the ticket breakdown, else the attendee count. */
function partyOf(b: Booking): { seats: number; label: string } {
  const lines = parseTicketBreakdown(b.ticketBreakdown).filter((l) => l.qty > 0);
  if (lines.length) {
    return {
      seats: lines.reduce((n, l) => n + l.qty, 0),
      label: lines.map((l) => `${l.qty} ${plural(l.type.toLowerCase(), l.qty)}`).join(' · '),
    };
  }
  const n = b.attendeeCount ?? 1;
  return { seats: n, label: `${n} guest${n === 1 ? '' : 's'}` };
}

const plural = (word: string, n: number) =>
  n === 1 ? word : word === 'child' ? 'children' : word.endsWith('s') ? word : `${word}s`;

const isLive = (b: Booking) => !['Cancelled', 'Rejected', 'WeatherCancelled', 'NoShow'].includes(b.status);

export default function BookingManagerPage() {
  const subtype = useSubtypeConfig();
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const today = useMemo(() => startOfDay(new Date()), []);
  const [view, setView] = useState<View>('list');
  const [weekAnchor, setWeekAnchor] = useState(() => new Date());
  const [monthAnchor, setMonthAnchor] = useState(() => new Date());
  const [selectedDay, setSelectedDay] = useState<Date | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [statusFilter, setStatusFilter] = useState('');
  const [resourceFilter, setResourceFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [dragOverDay, setDragOverDay] = useState<string | null>(null);
  const [showConflicts, setShowConflicts] = useState(false);
  const [checkInId, setCheckInId] = useState('');

  const weekDays = useMemo(() => buildWeekGrid(weekAnchor), [weekAnchor]);
  const monthDays = useMemo(() => buildMonthGrid(monthAnchor), [monthAnchor]);

  // FR-AS1: Staff only see their own branch's bookings; Admin/Manager stay tenant-wide.
  const staffBranchId = user?.role === 'Staff' ? user.branchId : undefined;
  const scope = { tenantId, branchId: staffBranchId };

  const { data: resourcesData } = useGetResourcesQuery({ ...scope, pageSize: 100 }, { skip: !tenantId });

  /* One window of bookings - two weeks back to the end of the month grid -
   * feeds the KPI strip, the trend, the calendar dots and the timeline, so
   * they all agree with each other and cost one request. */
  const windowFrom = useMemo(() => addDays(today, -14), [today]);
  const windowTo = useMemo(() => addDays(monthDays[41], 1), [monthDays]);
  const { data: windowData, isFetching: windowLoading } = useGetBookingsQuery(
    { ...scope, dateFrom: toISODate(windowFrom < monthDays[0] ? windowFrom : monthDays[0]), dateTo: toISODate(windowTo), pageSize: 1000 },
    { skip: !tenantId },
  );
  const windowItems = useMemo(() => windowData?.items ?? [], [windowData]);

  const { data: weekData, isFetching: weekLoading } = useGetBookingsQuery(
    { ...scope, dateFrom: toISODate(weekDays[0]), dateTo: toISODate(addDays(weekDays[6], 1)), pageSize: 200 },
    { skip: !tenantId || view !== 'week' },
  );

  const { data: tableData, isFetching: tableLoading } = useGetBookingsQuery(
    {
      ...scope,
      status: statusFilter || undefined,
      resourceId: resourceFilter || undefined,
      dateFrom: selectedDay ? toISODate(selectedDay) : undefined,
      dateTo: selectedDay ? toISODate(addDays(selectedDay, 1)) : undefined,
      page, pageSize: 10,
    },
    { skip: !tenantId },
  );

  const { data: conflictsData } = useGetConflictsQuery({ tenantId }, { skip: !tenantId });

  const [reschedule] = useRescheduleBookingMutation();
  const [cancelBooking] = useCancelBookingMutation();
  const [deleteBooking] = useDeleteBookingMutation();
  const [updateStatus] = useUpdateBookingStatusMutation();
  const [checkIn, { isLoading: checkingIn }] = useCheckInBookingMutation();

  /* ── Derived: KPIs, trend, calendar dots, timeline ─────────────────── */

  const kpis = useMemo(() => {
    const now = new Date();
    const tomorrow = addDays(today, 1);
    const in7 = addDays(today, 7);
    const isOn = (b: Booking, from: Date, to: Date) => { const t = new Date(b.startTime); return t >= from && t < to; };
    const todays = windowItems.filter((b) => isOn(b, today, tomorrow));
    const week = windowItems.filter((b) => isOn(b, today, in7) && isLive(b));
    return {
      today: todays.filter(isLive).length,
      todaySeats: todays.filter(isLive).reduce((n, b) => n + partyOf(b).seats, 0),
      pending: windowItems.filter((b) => b.status === 'Pending' && new Date(b.startTime) >= now).length,
      checkedIn: todays.filter((b) => b.checkInAt).length,
      weekRevenue: week.reduce((n, b) => n + (b.totalCost ?? 0), 0),
      weekCount: week.length,
    };
  }, [windowItems, today]);

  const trend = useMemo(() => {
    const days = Array.from({ length: 14 }, (_, i) => addDays(today, i - 13));
    // By the day the reservation is *for* - the same axis as the calendar
    // dots and the KPI strip, and the axis the data window is fetched on.
    const counts = days.map((d) => windowItems.filter((b) => isLive(b) && isSameDay(new Date(b.startTime), d)).length);
    const max = Math.max(1, ...counts);
    const thisWeek = counts.slice(7).reduce((a, b) => a + b, 0);
    const lastWeek = counts.slice(0, 7).reduce((a, b) => a + b, 0);
    const delta = lastWeek === 0 ? (thisWeek > 0 ? 100 : 0) : Math.round(((thisWeek - lastWeek) / lastWeek) * 100);
    const inRange = windowItems.filter((b) => { const t = new Date(b.startTime); return isLive(b) && t >= days[0] && t < addDays(today, 1); });
    const revenue = inRange.reduce((n, b) => n + (b.totalCost ?? 0), 0);
    const guests = inRange.reduce((n, b) => n + partyOf(b).seats, 0);
    return { days, counts, max, thisWeek, lastWeek, delta, revenue, guests };
  }, [windowItems, today]);

  const countByDay = useMemo(() => {
    const m = new Map<string, number>();
    for (const b of windowItems) if (isLive(b)) { const k = toISODate(startOfDay(new Date(b.startTime))); m.set(k, (m.get(k) ?? 0) + 1); }
    return m;
  }, [windowItems]);

  const upcoming = useMemo(() => {
    const now = Date.now();
    return windowItems
      .filter((b) => isLive(b) && new Date(b.startTime).getTime() >= now - 30 * 60_000)
      .sort((a, b) => a.startTime.localeCompare(b.startTime))
      .slice(0, 6);
  }, [windowItems]);

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
    return items.filter((b) => guestName(b).toLowerCase().includes(q) || b.resourceName.toLowerCase().includes(q) || b.bookingTypeName.toLowerCase().includes(q));
  }, [tableData, search]);

  const currency = 'LKR';

  /* ── Actions ────────────────────────────────────────────────────────── */

  const handleDrop = async (day: Date, e: React.DragEvent) => {
    e.preventDefault();
    setDragOverDay(null);
    const bookingId = e.dataTransfer.getData('bookingId');
    const startIso = e.dataTransfer.getData('startIso');
    const endIso = e.dataTransfer.getData('endIso');
    if (!bookingId || !startIso || !endIso) return;
    if (isSameDay(new Date(startIso), day)) return;

    const durationMs = new Date(endIso).getTime() - new Date(startIso).getTime();
    const newStart = combineDateWithTimeOfDay(day, startIso);
    const newEnd = new Date(new Date(newStart).getTime() + durationMs).toISOString();
    try {
      await reschedule({ id: bookingId, newStartTime: newStart, newEndTime: newEnd }).unwrap();
      show('Booking rescheduled.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not reschedule — that slot may already be booked.'), 'error');
    }
  };

  const handleCancel = async (id: string) => {
    try { await cancelBooking(id).unwrap(); show('Booking cancelled.', 'success'); }
    catch (err) { show(apiErrorMessage(err, 'Could not cancel.'), 'error'); }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Delete this booking permanently?')) return;
    try { await deleteBooking(id).unwrap(); show('Booking deleted.', 'success'); }
    catch (err) { show(apiErrorMessage(err, 'Could not delete.'), 'error'); }
  };

  const handleStatusChange = async (id: string, status: string) => {
    try { await updateStatus({ id, status }).unwrap(); show('Status updated.', 'success'); }
    catch (err) { show(apiErrorMessage(err, 'Could not update status.'), 'error'); }
  };

  // FR-AS9: desk check-in without a camera - paste the booking ID from the
  // guest's confirmation/QR (mobile has the actual camera scanner).
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

  const pickDay = (d: Date) => {
    setSelectedDay((cur) => (cur && isSameDay(cur, d) ? null : d));
    setPage(1);
    setView('list');
  };

  /* ── Render ─────────────────────────────────────────────────────────── */

  return (
    <div className="booking-manager-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">{subtype.bookingTermPlural}</h1>
          <p className="page-subtitle">
            {kpis.today} today · {kpis.pending} awaiting approval · {formatDayLabel(new Date())}
          </p>
        </div>
        <div className="booking-page-actions" style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
          <form onSubmit={handleCheckIn} style={{ display: 'flex', gap: 6 }}>
            <input className="input" placeholder="Booking ID to check in…" value={checkInId}
              onChange={(e) => setCheckInId(e.target.value)} style={{ width: 200 }} />
            <button className="btn btn-secondary" type="submit" disabled={!checkInId.trim() || checkingIn}>
              {checkingIn ? <span className="spinner" /> : 'Check in'}
            </button>
          </form>
          <button className="btn btn-primary" onClick={() => setShowCreate(true)}>+ New {subtype.bookingTermPlural.replace(/s$/i, '').toLowerCase()}</button>
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

      <div className="rsv">
        <div className="rsv-main">
          {/* ── Signal strip ─────────────────────────────────────── */}
          <div className="rsv-kpis">
            <Kpi tone="blue" icon="🗓" value={windowLoading ? '…' : kpis.today} label="Today" sub={`${kpis.todaySeats} guests expected`} />
            <Kpi tone="amber" icon="⏳" value={windowLoading ? '…' : kpis.pending} label="Awaiting approval" sub="upcoming, needs a decision" />
            <Kpi tone="green" icon="✓" value={windowLoading ? '…' : kpis.checkedIn} label="Checked in today" sub={kpis.today ? `of ${kpis.today} booked` : 'nothing booked today'} />
            <Kpi tone="pink" icon="◈" value={windowLoading ? '…' : money(kpis.weekRevenue, currency)} label="Next 7 days" sub={`${kpis.weekCount} reservation${kpis.weekCount === 1 ? '' : 's'} on the books`} small />
          </div>

          {/* ── Trend ────────────────────────────────────────────── */}
          <div className="rsv-trend">
            <div className="rsv-card rsv-stat">
              <div className="rsv-stat-label">Reservations · last 14 days</div>
              <div className="rsv-stat-row">
                <span className="rsv-stat-value">{windowLoading ? '…' : trend.thisWeek + trend.lastWeek}</span>
                <span className={`rsv-delta ${trend.delta > 0 ? 'rsv-delta--up' : trend.delta < 0 ? 'rsv-delta--down' : 'rsv-delta--flat'}`}>
                  {trend.delta > 0 ? '▲' : trend.delta < 0 ? '▼' : '•'} {Math.abs(trend.delta)}% vs previous week
                </span>
              </div>
              <div className="rsv-bars" aria-label="Reservations per day, last 14 days">
                {trend.counts.map((n, i) => (
                  <div className="rsv-bar" key={i} title={`${formatDayLabel(trend.days[i])}: ${n}`}>
                    <i style={{ height: `${Math.max(n > 0 ? 8 : 0, Math.round((n / trend.max) * 100))}%` }} />
                  </div>
                ))}
              </div>
              <div className="rsv-bar-labels"><span>{formatDayLabel(trend.days[0])}</span><span>Today</span></div>
            </div>
            <div className="rsv-card rsv-stat">
              <div className="rsv-stat-label">Value · last 14 days</div>
              <div className="rsv-stat-row"><span className="rsv-stat-value">{windowLoading ? '…' : money(trend.revenue, currency)}</span></div>
              <div className="rsv-stat-label" style={{ marginTop: 16 }}>Guests · last 14 days</div>
              <div className="rsv-stat-row"><span className="rsv-stat-value">{windowLoading ? '…' : trend.guests.toLocaleString()}</span></div>
            </div>
          </div>

          {/* ── Work surface ─────────────────────────────────────── */}
          <div className="rsv-card">
            <div className="rsv-toolbar">
              <div className="rsv-search">
                <span aria-hidden="true">⌕</span>
                <input className="input" placeholder="Search guest, type or resource…" value={search} onChange={(e) => setSearch(e.target.value)} />
              </div>
              <select className="input" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}>
                <option value="">All statuses</option>
                {BOOKING_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
              <select className="input" value={resourceFilter} onChange={(e) => { setResourceFilter(e.target.value); setPage(1); }}>
                <option value="">All {subtype.resourceTermPlural.toLowerCase()}</option>
                {resourcesData?.items.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
              </select>
              {selectedDay && (
                <span className="rsv-chip">{formatDayLabel(selectedDay)}<button type="button" aria-label="Clear day filter" onClick={() => { setSelectedDay(null); setPage(1); }}>×</button></span>
              )}
              <div className="rsv-seg" style={{ marginLeft: 'auto' }} role="tablist" aria-label="View">
                <button type="button" role="tab" aria-selected={view === 'list'} className={view === 'list' ? 'is-on' : ''} onClick={() => setView('list')}>List</button>
                <button type="button" role="tab" aria-selected={view === 'week'} className={view === 'week' ? 'is-on' : ''} onClick={() => setView('week')}>Week board</button>
              </div>
            </div>

            {view === 'week' ? (
              <>
                <div className="rsv-card-head" style={{ borderTop: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => setWeekAnchor(addDays(weekAnchor, -7))}>‹</button>
                    <strong>{formatDayLabel(weekDays[0])} – {formatDayLabel(weekDays[6])}</strong>
                    <button className="btn btn-secondary btn-sm" onClick={() => setWeekAnchor(addDays(weekAnchor, 7))}>›</button>
                  </div>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <span className="rsv-card-sub">Drag a card onto another day to reschedule it.</span>
                    <button className="btn btn-ghost btn-sm" onClick={() => setWeekAnchor(new Date())}>This week</button>
                  </div>
                </div>
                <div className="rsv-week">
                  {weekDays.map((day) => {
                    const key = toISODate(day);
                    const events = bookingsByDay.get(key) ?? [];
                    return (
                      <div key={key}
                        className={`calendar-cell${isSameDay(day, new Date()) ? ' is-today' : ''}${dragOverDay === key ? ' is-drop-target' : ''}`}
                        onDragOver={(e) => { e.preventDefault(); setDragOverDay(key); }}
                        onDragLeave={() => setDragOverDay((cur) => (cur === key ? null : cur))}
                        onDrop={(e) => handleDrop(day, e)}>
                        <span className="calendar-date">{day.getDate()}</span>
                        {weekLoading ? <span style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>Loading…</span>
                          : events.map((b) => (
                            <div key={b.id} className="calendar-event" draggable title="Drag to reschedule"
                              onDragStart={(e) => { e.dataTransfer.setData('bookingId', b.id); e.dataTransfer.setData('startIso', b.startTime); e.dataTransfer.setData('endIso', b.endTime); }}
                              style={{ background: STATUS_COLORS[b.status].bg }}>
                              {formatTime(b.startTime)} {guestName(b)}
                            </div>
                          ))}
                      </div>
                    );
                  })}
                </div>
              </>
            ) : (
              <>
                <div className="table-wrap" style={{ border: 0, borderRadius: 0 }}>
                  <table className="rsv-table">
                    <thead>
                      <tr>
                        <th>Guest</th>
                        <th>When · {subtype.resourceTermPlural.replace(/s$/i, '').toLowerCase()}</th>
                        <th>Party</th>
                        <th>Amount</th>
                        <th>Status</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {tableLoading && (
                        <tr><td colSpan={6} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>
                      )}
                      {!tableLoading && filteredTableItems.length === 0 && (
                        <tr><td colSpan={6}><div className="rsv-empty"><b>Nothing here</b>No reservations match these filters.</div></td></tr>
                      )}
                      {!tableLoading && filteredTableItems.map((b) => {
                        const name = guestName(b);
                        const party = partyOf(b);
                        const sc = STATUS_COLORS[b.status];
                        const website = (b.source ?? '').toLowerCase() === 'website';
                        return (
                          <tr key={b.id}>
                            <td>
                              <div className="rsv-guest">
                                <span className="rsv-guest-avatar" style={{ background: `hsl(${hueOf(name)} 70% 52%)` }}>{initialsOf(name)}</span>
                                <div style={{ minWidth: 0 }}>
                                  <div className="rsv-guest-name" title={name}>{name}</div>
                                  <div className="rsv-guest-meta">
                                    <span className="rsv-type" style={{ color: b.colorHex, background: `${b.colorHex}1f` }}><i style={{ background: b.colorHex }} />{b.bookingTypeName}</span>
                                    {b.source && <span className={`rsv-src${website ? ' rsv-src--website' : ''}`}>{b.source}</span>}
                                  </div>
                                </div>
                              </div>
                            </td>
                            <td className="rsv-when">
                              <strong>{formatDayLabel(new Date(b.startTime))} · {formatTime(b.startTime)}</strong>
                              <span className="rsv-resource" title={b.resourceName}>{b.resourceName}</span>
                            </td>
                            <td className="rsv-party">{party.seats} <small>· {party.label}</small></td>
                            <td className="rsv-amount">{b.totalCost != null ? money(b.totalCost, currency) : <span style={{ color: 'var(--color-text-muted)', fontWeight: 500 }}>—</span>}</td>
                            <td>
                              <select className="rsv-status" value={b.status} aria-label="Status"
                                style={{ '--sc': sc.bg, color: sc.fg, background: `${sc.bg}26`, borderColor: `${sc.bg}55` } as React.CSSProperties}
                                onChange={(e) => handleStatusChange(b.id, e.target.value)}>
                                {BOOKING_STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
                              </select>
                            </td>
                            <td>
                              <div className="rsv-actions">
                                {b.status !== 'Cancelled' && (
                                  <button className="rsv-icon-btn" title="Cancel booking" aria-label="Cancel booking" onClick={() => handleCancel(b.id)}>⊘</button>
                                )}
                                <button className="rsv-icon-btn rsv-icon-btn--danger" title="Delete permanently" aria-label="Delete booking" onClick={() => handleDelete(b.id)}>🗑</button>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
                <div className="rsv-foot">
                  <span>{tableData ? `${tableData.total.toLocaleString()} reservation${tableData.total === 1 ? '' : 's'}` : ''}{selectedDay ? ` on ${formatDayLabel(selectedDay)}` : ''}</span>
                  {tableData && tableData.totalPages > 1 && (
                    <div>
                      <button className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>‹ Prev</button>
                      <span style={{ alignSelf: 'center', padding: '0 6px' }}>Page {page} of {tableData.totalPages}</span>
                      <button className="btn btn-secondary btn-sm" disabled={page >= tableData.totalPages} onClick={() => setPage((p) => p + 1)}>Next ›</button>
                    </div>
                  )}
                </div>
              </>
            )}
          </div>
        </div>

        {/* ── Rail ─────────────────────────────────────────────── */}
        <aside className="rsv-rail">
          <div className="rsv-card rsv-cal">
            <div className="rsv-cal-head">
              <strong>{formatMonthYear(monthAnchor)}</strong>
              <div className="rsv-cal-nav">
                <button className="btn btn-ghost btn-sm" aria-label="Previous month" onClick={() => setMonthAnchor(new Date(monthAnchor.getFullYear(), monthAnchor.getMonth() - 1, 1))}>‹</button>
                <button className="btn btn-ghost btn-sm" onClick={() => { setMonthAnchor(new Date()); }}>Today</button>
                <button className="btn btn-ghost btn-sm" aria-label="Next month" onClick={() => setMonthAnchor(new Date(monthAnchor.getFullYear(), monthAnchor.getMonth() + 1, 1))}>›</button>
              </div>
            </div>
            <div className="rsv-cal-grid">
              {WEEKDAY_LABELS.map((d) => <div className="rsv-cal-dow" key={d}>{d.slice(0, 2)}</div>)}
              {monthDays.map((d) => {
                const key = toISODate(d);
                const n = countByDay.get(key) ?? 0;
                const cls = ['rsv-cal-day',
                  d.getMonth() !== monthAnchor.getMonth() ? 'is-other' : '',
                  isSameDay(d, today) ? 'is-today' : '',
                  selectedDay && isSameDay(d, selectedDay) ? 'is-selected' : '',
                  n > 0 ? 'has-bookings' : ''].filter(Boolean).join(' ');
                return (
                  <button type="button" key={key} className={cls} onClick={() => pickDay(d)}
                    title={n ? `${n} reservation${n === 1 ? '' : 's'}` : undefined} aria-pressed={!!selectedDay && isSameDay(d, selectedDay)}>
                    {d.getDate()}
                  </button>
                );
              })}
            </div>
            <div className="rsv-cal-foot">
              <span>• a day with reservations</span>
              <span>{selectedDay ? 'Tap again to clear' : 'Tap a day to filter'}</span>
            </div>
          </div>

          <div className="rsv-card">
            <div className="rsv-card-head">
              <div>
                <h3 className="rsv-card-title">Next up</h3>
                <p className="rsv-card-sub">The next {upcoming.length || ''} reservation{upcoming.length === 1 ? '' : 's'} on the clock</p>
              </div>
            </div>
            <div className="rsv-up">
              {windowLoading && <div className="rsv-up-empty">Loading…</div>}
              {!windowLoading && upcoming.length === 0 && <div className="rsv-up-empty">Nothing scheduled ahead in this window.</div>}
              {upcoming.map((b) => {
                const start = new Date(b.startTime);
                const dayTag = isSameDay(start, today) ? 'Today' : isSameDay(start, addDays(today, 1)) ? 'Tmrw' : start.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
                const party = partyOf(b);
                return (
                  <div className="rsv-up-item" key={b.id}>
                    <div className="rsv-up-time" style={{ background: STATUS_COLORS[b.status].bg }}>
                      {formatTime(b.startTime)}<small>{dayTag}</small>
                    </div>
                    <div style={{ minWidth: 0 }}>
                      <div className="rsv-up-title">{guestName(b)}</div>
                      <div className="rsv-up-meta">{b.resourceName} · {party.label}{b.status !== 'Confirmed' ? ` · ${b.status}` : ''}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </aside>
      </div>

      {showCreate && user && (
        <BookingFormModal tenantId={tenantId} userId={user.id} defaultDate={selectedDay ?? weekDays[0]} onClose={() => setShowCreate(false)} />
      )}
    </div>
  );
}

function Kpi({ tone, icon, value, label, sub, small }: { tone: 'blue' | 'green' | 'amber' | 'pink'; icon: string; value: string | number; label: string; sub?: string; small?: boolean }) {
  return (
    <div className={`rsv-kpi rsv-kpi--${tone}`}>
      <div style={{ position: 'relative', zIndex: 1, minWidth: 0 }}>
        <div className="rsv-kpi-value" style={small ? { fontSize: '1.3rem' } : undefined}>{value}</div>
        <div className="rsv-kpi-label">{label}</div>
        {sub && <div className="rsv-kpi-sub">{sub}</div>}
      </div>
      <div className="rsv-kpi-icon" aria-hidden="true">{icon}</div>
    </div>
  );
}
