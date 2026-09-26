import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import {
  useCancelBookingMutation,
  useGetAvailableSlotsQuery,
  useGetBookingsQuery,
  useGetTenantQuery,
  useRescheduleBookingMutation,
} from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { apiErrorMessage, useToast } from '../../shared/components/Toast';
import { addDays, formatDayLabel, formatTime, toISODate } from '../../shared/dateUtils';
import type { AvailableSlot, Booking } from '../booking/types';
import { AddToCalendarButton } from '../../shared/components/AddToCalendarButton';
import { BookingCard, CheckInQr, isUpcoming } from './customerShared';

/* My bookings - the web twin of the Flutter MyBookingsScreen: upcoming,
 * past and cancelled tabs; each upcoming booking can show its check-in QR,
 * be rescheduled to another free slot, or cancelled. The business's
 * cutoff hours are shown so a late change is explained before the API
 * refuses it. */

type Tab = 'upcoming' | 'past' | 'cancelled';

export default function MyBookingsPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const toast = useToast();
  const today = useMemo(() => new Date(), []);
  /* The business can confirm, move or cancel any of these from its own
   * side, so the list refreshes on a timer and on focus rather than only
   * when this page makes a change. */
  const { data, isLoading } = useGetBookingsQuery(
    { tenantId, dateFrom: toISODate(addDays(today, -365)), dateTo: toISODate(addDays(today, 365)), pageSize: 500 },
    { skip: !tenantId, pollingInterval: 30_000, skipPollingIfUnfocused: true, refetchOnFocus: true, refetchOnReconnect: true },
  );
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const [tab, setTab] = useState<Tab>('upcoming');
  const [qrFor, setQrFor] = useState<Booking | null>(null);
  const [moving, setMoving] = useState<Booking | null>(null);
  const [cancelBooking] = useCancelBookingMutation();
  const [busyId, setBusyId] = useState<string | null>(null);

  const items = data?.items ?? [];
  const lists = useMemo(() => ({
    upcoming: items.filter((b) => isUpcoming(b)).sort((a, b) => a.startTime.localeCompare(b.startTime)),
    past: items.filter((b) => !isUpcoming(b) && b.status !== 'Cancelled' && b.status !== 'Rejected' && b.status !== 'WeatherCancelled').sort((a, b) => b.startTime.localeCompare(a.startTime)),
    cancelled: items.filter((b) => b.status === 'Cancelled' || b.status === 'Rejected' || b.status === 'WeatherCancelled').sort((a, b) => b.startTime.localeCompare(a.startTime)),
  }), [items]);
  const rows = lists[tab];

  async function cancel(b: Booking) {
    if (!window.confirm(`Cancel ${b.bookingTypeName} with ${b.resourceName} on ${formatDayLabel(new Date(b.startTime))}? This cannot be undone.`)) return;
    setBusyId(b.id);
    try {
      await cancelBooking(b.id).unwrap();
      toast.show('Booking cancelled.', 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not cancel this booking.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  const canChange = (b: Booking, hours: number) => (new Date(b.startTime).getTime() - Date.now()) / 3_600_000 >= hours;

  return (
    <div className="cust-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">My bookings</h1>
          <p className="page-subtitle">
            Check-in codes, changes and history.
            {tenant && ` Reschedule up to ${tenant.rescheduleCutoffHours}h before, cancel up to ${tenant.cancellationCutoffHours}h before.`}
          </p>
        </div>
        <Link className="btn btn-primary" to="/book">+ New booking</Link>
      </div>

      <section className="card chart-card">
        <div className="cust-toolbar" style={{ marginBottom: 14 }}>
          <div className="cust-tabs" role="tablist" aria-label="Bookings">
            {(['upcoming', 'past', 'cancelled'] as Tab[]).map((t) => (
              <button key={t} type="button" role="tab" aria-selected={tab === t} className={tab === t ? 'active' : ''} onClick={() => setTab(t)}>
                {t[0].toUpperCase() + t.slice(1)} ({lists[t].length})
              </button>
            ))}
          </div>
        </div>

        {isLoading ? (
          <div className="loading-row"><span className="spinner spinner-dark" /> Loading your bookings…</div>
        ) : rows.length === 0 ? (
          <div className="cust-empty">{tab === 'upcoming' ? <>Nothing coming up. <Link to="/book">Book something</Link>.</> : tab === 'past' ? 'No past bookings yet.' : 'No cancelled bookings.'}</div>
        ) : (
          <div className="cust-list">
            {rows.map((b, i) => (
              <BookingCard
                key={b.id}
                booking={b}
                highlight={tab === 'upcoming' && i === 0}
                actions={tab === 'upcoming' ? (
                  <>
                    {b.status !== 'Pending' && <button type="button" className="btn btn-primary" onClick={() => setQrFor(b)}>Check-in code</button>}
                    <AddToCalendarButton bookingId={b.id} />
                    {tenant && canChange(b, tenant.rescheduleCutoffHours) && (b.status === 'Pending' || b.status === 'Confirmed') && (
                      <button type="button" className="btn btn-secondary" onClick={() => setMoving(b)}>Reschedule</button>
                    )}
                    {tenant && canChange(b, tenant.cancellationCutoffHours) && (b.status === 'Pending' || b.status === 'Confirmed') && (
                      <button type="button" className="btn btn-ghost" disabled={busyId === b.id} onClick={() => cancel(b)}>Cancel</button>
                    )}
                  </>
                ) : tab === 'past' ? (
                  <Link className="btn btn-secondary" to={`/book?type=${b.bookingTypeId}&resource=${b.resourceId}`}>Book again</Link>
                ) : undefined}
              />
            ))}
          </div>
        )}
      </section>

      {qrFor && (
        <>
          <button type="button" className="cust-scrim" aria-label="Close" onClick={() => setQrFor(null)} />
          <div className="cust-modal" role="dialog" aria-label="Check-in code" style={{ width: 'min(420px, calc(100vw - 32px))' }}>
            <CheckInQr bookingId={qrFor.id} resourceName={qrFor.resourceName} />
            <p className="cust-note" style={{ textAlign: 'center' }}>{qrFor.bookingTypeName} · {formatDayLabel(new Date(qrFor.startTime))} {formatTime(qrFor.startTime)}</p>
            <div className="cust-modal-foot"><button type="button" className="btn btn-primary" onClick={() => setQrFor(null)}>Done</button></div>
          </div>
        </>
      )}

      {moving && <RescheduleModal booking={moving} onClose={() => setMoving(null)} />}
    </div>
  );
}

function RescheduleModal({ booking, onClose }: { booking: Booking; onClose: () => void }) {
  const toast = useToast();
  const [day, setDay] = useState(() => toISODate(new Date(booking.startTime) > new Date() ? new Date(booking.startTime) : new Date()));
  const [slot, setSlot] = useState<AvailableSlot | null>(null);
  const duration = Math.max(15, Math.round((new Date(booking.endTime).getTime() - new Date(booking.startTime).getTime()) / 60000));
  const { data, isFetching } = useGetAvailableSlotsQuery({ resourceId: booking.resourceId, date: day, duration, bookingTypeId: booking.bookingTypeId });
  const [reschedule, { isLoading }] = useRescheduleBookingMutation();
  const days = useMemo(() => Array.from({ length: 14 }, (_, i) => addDays(new Date(), i)), []);

  async function save() {
    if (!slot) return;
    try {
      await reschedule({ id: booking.id, newStartTime: slot.startTime, newEndTime: slot.endTime }).unwrap();
      toast.show('Booking moved.', 'success');
      onClose();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not move this booking.'), 'error');
    }
  }

  return (
    <>
      <button type="button" className="cust-scrim" aria-label="Close" onClick={onClose} />
      <div className="cust-modal" role="dialog" aria-label="Reschedule">
        <h3>Reschedule {booking.bookingTypeName}</h3>
        <p className="cust-note" style={{ margin: '0 0 12px' }}>{booking.resourceName} · currently {formatDayLabel(new Date(booking.startTime))} at {formatTime(booking.startTime)}</p>
        <div className="cust-datetime">
          <div className="cust-days" style={{ maxHeight: 320, overflow: 'auto' }}>
            {days.map((d) => {
              const iso = toISODate(d);
              return <button key={iso} type="button" className={`cust-day${iso === day ? ' is-active' : ''}`} onClick={() => { setDay(iso); setSlot(null); }} aria-pressed={iso === day}><strong>{formatDayLabel(d)}</strong><small /></button>;
            })}
          </div>
          <div>
            {isFetching ? <div className="loading-row"><span className="spinner spinner-dark" /></div>
              : !data || !data.isOpen ? <div className="cust-empty">Closed on this day.</div>
              : (
                <div className="cust-slots">
                  {data.slots.map((s) => (
                    <button key={s.startTime} type="button" className={`cust-slot${slot?.startTime === s.startTime ? ' is-active' : ''}`} disabled={(!s.isAvailable && s.startTime !== booking.startTime) || new Date(s.startTime) < new Date()} onClick={() => setSlot(s)}>{formatTime(s.startTime)}</button>
                  ))}
                </div>
              )}
          </div>
        </div>
        <div className="cust-modal-foot">
          <button type="button" className="btn btn-ghost" onClick={onClose}>Keep it</button>
          <button type="button" className="btn btn-primary" disabled={!slot || isLoading} onClick={save}>{isLoading ? 'Moving…' : 'Move booking'}</button>
        </div>
      </div>
    </>
  );
}
