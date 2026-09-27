import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import {
  useCreateBookingMutation,
  useCreateRecurringBookingMutation,
  useGetAvailableSlotsQuery,
  useGetBookingTypesQuery,
  useGetBranchesQuery,
  useGetResourcesQuery,
  useGetUnavailableRangesQuery,
} from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { apiErrorMessage, useToast } from '../../shared/components/Toast';
import { addDays, formatDayLabel, formatTime, toISODate } from '../../shared/dateUtils';
import type { AvailableSlot, BookingType, Resource } from '../booking/types';
import { CheckInQr, money, priceFor } from './customerShared';

/* The booking flow - the web twin of the Flutter BookingFlowScreen:
 *   1. Service      - the booking type (duration, approval, price)
 *   2. Who / where  - the resource: a person, a room, a table, a boat,
 *                     filtered by branch and specialty
 *   3. Date & time  - the next 14 days with the resource's free slots, or
 *                     a date range for night / multi-day types
 *   4. Confirm      - people, notes, optional weekly repeat, then book
 * then the success screen with the check-in QR. ?type= and ?resource=
 * prefill steps 1 and 2 ("Book again" from the home page). */

type Step = 0 | 1 | 2 | 3;
const LABELS = ['Service', 'Who / where', 'Date & time', 'Confirm'];

export default function CustomerBookPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const [params] = useSearchParams();
  const toast = useToast();

  const { data: types, isLoading: typesLoading } = useGetBookingTypesQuery({ tenantId, status: 'Active' }, { skip: !tenantId });
  const { data: resourcesData, isLoading: resourcesLoading } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });
  const { data: branches } = useGetBranchesQuery({ tenantId }, { skip: !tenantId });

  const [step, setStep] = useState<Step>(0);
  const [typeId, setTypeId] = useState(params.get('type') ?? '');
  const [resourceId, setResourceId] = useState(params.get('resource') ?? '');
  const [branchId, setBranchId] = useState('');
  const [specialty, setSpecialty] = useState('');
  const [day, setDay] = useState(() => toISODate(new Date()));
  const [slot, setSlot] = useState<AvailableSlot | null>(null);
  const [rangeFrom, setRangeFrom] = useState(() => toISODate(addDays(new Date(), 1)));
  const [rangeTo, setRangeTo] = useState(() => toISODate(addDays(new Date(), 2)));
  const [attendees, setAttendees] = useState(1);
  const [notes, setNotes] = useState('');
  const [repeatWeekly, setRepeatWeekly] = useState(false);
  const [repeatUntil, setRepeatUntil] = useState(() => toISODate(addDays(new Date(), 56)));
  const [done, setDone] = useState<{ id: string; totalCost?: number | null; count?: number } | null>(null);

  // A prefilled type + resource skips straight to the calendar.
  useEffect(() => {
    if (params.get('type') && params.get('resource') && types && resourcesData) setStep(2);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [types, resourcesData]);

  const type = types?.find((t) => t.id === typeId);
  const resources = useMemo(() => (resourcesData?.items ?? []).filter((r) => r.status === 'Available' && (!branchId || r.branchId === branchId) && (!specialty || r.specialty === specialty)), [resourcesData, branchId, specialty]);
  const resource = resourcesData?.items.find((r) => r.id === resourceId);
  const specialties = useMemo(() => Array.from(new Set((resourcesData?.items ?? []).map((r) => r.specialty).filter((s): s is string => !!s))).sort(), [resourcesData]);
  const isRange = type ? type.bookingUnit !== 'Slot' : false;

  const days = useMemo(() => Array.from({ length: 14 }, (_, i) => addDays(new Date(), i)), []);
  const { data: slotsData, isFetching: slotsLoading } = useGetAvailableSlotsQuery(
    { resourceId, date: day, duration: type?.defaultDurationMinutes ?? 60, bookingTypeId: typeId },
    { skip: !resourceId || !typeId || isRange || step !== 2 },
  );
  const { data: unavailable } = useGetUnavailableRangesQuery(
    { resourceId, from: toISODate(new Date()), to: toISODate(addDays(new Date(), 120)) },
    { skip: !resourceId || !isRange || step !== 2 },
  );

  const [createBooking, { isLoading: creating }] = useCreateBookingMutation();
  const [createRecurring, { isLoading: creatingSeries }] = useCreateRecurringBookingMutation();

  // The window the booking occupies: the chosen slot for slot types, or a
  // day range - check-in 14:00 to check-out 11:00 for nights, a working
  // day for date ranges and packages.
  const window = useMemo(() => {
    if (!isRange) return slot ? { start: slot.startTime, end: slot.endTime } : null;
    if (!rangeFrom || !rangeTo || rangeTo <= rangeFrom) return null;
    const nights = type?.bookingUnit === 'Night';
    return { start: new Date(`${rangeFrom}T${nights ? '14:00' : '09:00'}:00`).toISOString(), end: new Date(`${rangeTo}T${nights ? '11:00' : '18:00'}:00`).toISOString() };
  }, [isRange, slot, rangeFrom, rangeTo, type]);
  const minutes = window ? Math.max(0, (new Date(window.end).getTime() - new Date(window.start).getTime()) / 60000) : (type?.defaultDurationMinutes ?? 0);
  const price = priceFor(type, resource, minutes, attendees);
  const rangeClash = useMemo(() => {
    if (!isRange || !window || !unavailable) return false;
    const s = new Date(window.start).getTime(); const e = new Date(window.end).getTime();
    return unavailable.some((u) => new Date(u.startTime).getTime() < e && new Date(u.endTime).getTime() > s);
  }, [isRange, window, unavailable]);

  async function confirm() {
    if (!type || !resource || !window || !user) return;
    try {
      if (repeatWeekly && !isRange) {
        const result = await createRecurring({
          tenantId, resourceId: resource.id, bookingTypeId: type.id, bookedBy: user.id,
          title: `${type.name} - ${user.fullName}`, notes: notes.trim() || undefined,
          firstStartTime: window.start, durationMinutes: type.defaultDurationMinutes, endDate: repeatUntil,
        }).unwrap();
        const created = 'created' in result ? result.created : result.totalOccurrences;
        setDone({ id: '', count: created });
        toast.show(`${created} weekly booking${created === 1 ? '' : 's'} created.`, 'success');
        return;
      }
      const result = await createBooking({
        tenantId, resourceId: resource.id, bookingTypeId: type.id, bookedBy: user.id,
        startTime: window.start, endTime: window.end, priority: 'Normal',
        title: `${type.name} - ${user.fullName}`, notes: notes.trim() || undefined, attendeeCount: attendees, source: 'Online',
      }).unwrap();
      setDone({ id: result.id, totalCost: result.totalCost });
      if (result.capacityWarning) toast.show(result.capacityWarning, 'info');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not make the booking.'), 'error');
    }
  }

  if (done) {
    return (
      <div className="cust-page">
        <section className="card chart-card">
          <div className="cust-success">
            <div className="cust-success-mark" aria-hidden="true">✓</div>
            <h2>{type?.requiresApproval ? 'Request sent' : done.count ? `${done.count} bookings made` : 'You’re booked'}</h2>
            <p>
              {type?.requiresApproval
                ? `${resource?.name} · ${type?.name}. The business will confirm it - you'll get a notification.`
                : done.count
                  ? `${type?.name} with ${resource?.name}, weekly from ${window ? formatDayLabel(new Date(window.start)) : ''}. Each week's check-in code is under My bookings.`
                  : `${resource?.name} · ${type?.name} on ${window ? `${formatDayLabel(new Date(window.start))} at ${formatTime(window.start)}` : ''}.`}
              {done.totalCost != null && done.totalCost > 0 && ` Total ${money(done.totalCost)}.`}
            </p>
            {done.id && !type?.requiresApproval && <CheckInQr bookingId={done.id} resourceName={resource?.name} />}
            <div className="cust-hero-actions" style={{ marginTop: 6 }}>
              <Link className="btn btn-primary" to="/my-bookings">My bookings</Link>
              <Link className="btn btn-ghost" to="/dashboard">Home</Link>
            </div>
          </div>
        </section>
      </div>
    );
  }

  const canNext = step === 0 ? !!type : step === 1 ? !!resource : step === 2 ? !!window && !rangeClash : true;
  const next = () => { if (step < 3) setStep((step + 1) as Step); };
  const back = () => { if (step > 0) setStep((step - 1) as Step); };

  return (
    <div className="cust-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">New booking</h1>
          <p className="page-subtitle">Four quick steps. Nothing is booked until you confirm.</p>
        </div>
        <Link className="btn btn-ghost" to="/dashboard">Cancel</Link>
      </div>

      <section className="card chart-card">
        <div className="cust-steps" role="list">
          {LABELS.map((label, i) => (
            <div key={label} role="listitem" className={`cust-step${i === step ? ' is-current' : i < step ? ' is-done' : ''}`} aria-current={i === step ? 'step' : undefined}>
              <i>{i < step ? '✓' : i + 1}</i>{label}
            </div>
          ))}
        </div>

        {step === 0 && (
          <>
            <p className="cust-subhead">What would you like to book?</p>
            {typesLoading ? <div className="loading-row"><span className="spinner spinner-dark" /></div>
              : (types?.length ?? 0) === 0 ? <div className="cust-empty">No bookable services yet.</div>
              : (
                <div className="cust-options">
                  {types!.map((t) => <TypeOption key={t.id} type={t} active={t.id === typeId} onSelect={() => { setTypeId(t.id); setSlot(null); }} />)}
                </div>
              )}
          </>
        )}

        {step === 1 && (
          <>
            <div className="cust-toolbar" style={{ marginBottom: 12 }}>
              <p className="cust-subhead" style={{ margin: 0 }}>Who or where?</p>
              <div className="cust-chips">
                {(branches?.length ?? 0) > 1 && (
                  <>
                    <button type="button" className={`cust-chip${!branchId ? ' active' : ''}`} onClick={() => setBranchId('')}>All branches</button>
                    {branches!.map((b) => <button key={b.id} type="button" className={`cust-chip${branchId === b.id ? ' active' : ''}`} onClick={() => setBranchId(b.id)}>{b.name}</button>)}
                  </>
                )}
                {specialties.length > 1 && (
                  <>
                    <button type="button" className={`cust-chip${!specialty ? ' active' : ''}`} onClick={() => setSpecialty('')}>All specialties</button>
                    {specialties.map((s) => <button key={s} type="button" className={`cust-chip${specialty === s ? ' active' : ''}`} onClick={() => setSpecialty(s)}>{s}</button>)}
                  </>
                )}
              </div>
            </div>
            {resourcesLoading ? <div className="loading-row"><span className="spinner spinner-dark" /></div>
              : resources.length === 0 ? <div className="cust-empty">Nothing available with these filters.</div>
              : (
                <div className="cust-options">
                  {resources.map((r) => <ResourceOption key={r.id} resource={r} active={r.id === resourceId} onSelect={() => { setResourceId(r.id); setSlot(null); }} />)}
                </div>
              )}
          </>
        )}

        {step === 2 && !isRange && (
          <div className="cust-datetime">
            <div>
              <p className="cust-subhead">Pick a day</p>
              <div className="cust-days">
                {days.map((d) => {
                  const iso = toISODate(d);
                  return (
                    <button key={iso} type="button" className={`cust-day${iso === day ? ' is-active' : ''}`} onClick={() => { setDay(iso); setSlot(null); }} aria-pressed={iso === day}>
                      <strong>{formatDayLabel(d)}</strong><small>{iso === toISODate(new Date()) ? 'today' : ''}</small>
                    </button>
                  );
                })}
              </div>
            </div>
            <div>
              <p className="cust-subhead">{resource?.name} · {type?.defaultDurationMinutes} min slots</p>
              {slotsLoading ? <div className="loading-row"><span className="spinner spinner-dark" /></div>
                : !slotsData || !slotsData.isOpen ? <div className="cust-empty">Closed on this day.</div>
                : slotsData.slots.filter((s) => s.isAvailable).length === 0 ? <div className="cust-empty">Fully booked on this day - try another.</div>
                : (
                  <div className="cust-slots">
                    {slotsData.slots.map((s) => (
                      <button key={s.startTime} type="button" className={`cust-slot${slot?.startTime === s.startTime ? ' is-active' : ''}`} disabled={!s.isAvailable || new Date(s.startTime) < new Date()} onClick={() => setSlot(s)} aria-pressed={slot?.startTime === s.startTime}>
                        {formatTime(s.startTime)}
                      </button>
                    ))}
                  </div>
                )}
            </div>
          </div>
        )}

        {step === 2 && isRange && (
          <>
            <p className="cust-subhead">{type?.bookingUnit === 'Night' ? 'Check-in and check-out' : 'From and to'}</p>
            <div className="cust-range">
              <label>{type?.bookingUnit === 'Night' ? 'Check-in' : 'From'}<input className="input" type="date" min={toISODate(new Date())} value={rangeFrom} onChange={(e) => setRangeFrom(e.target.value)} /></label>
              <label>{type?.bookingUnit === 'Night' ? 'Check-out' : 'To'}<input className="input" type="date" min={rangeFrom} value={rangeTo} onChange={(e) => setRangeTo(e.target.value)} /></label>
            </div>
            {rangeClash && <div className="cust-warning" style={{ marginTop: 12 }}>⚠ {resource?.name} is already taken for part of those dates. Pick different dates.</div>}
            {unavailable && unavailable.length > 0 && !rangeClash && <p className="cust-note">Already booked: {unavailable.slice(0, 4).map((u) => `${u.startTime.slice(0, 10)} → ${u.endTime.slice(0, 10)}`).join(', ')}{unavailable.length > 4 ? '…' : ''}</p>}
          </>
        )}

        {step === 3 && type && resource && window && (
          <div className="cust-grid">
            <div className="cust-summary">
              <h3>{type.name}</h3>
              <p>{resource.name}{resource.specialty ? ` · ${resource.specialty}` : ''}</p>
              <div className="cust-summary-rows">
                <span>📅 {formatDayLabel(new Date(window.start))}{isRange ? ` → ${formatDayLabel(new Date(window.end))}` : ''}</span>
                {!isRange && <span>🕒 {formatTime(window.start)} – {formatTime(window.end)}</span>}
                <span>👥 {attendees} {attendees === 1 ? 'person' : 'people'}</span>
                <span>💳 {price ? `${money(price.amount)}${price.perPerson ? ' (per person)' : ''}` : 'Price confirmed by the business'}</span>
              </div>
              {type.requiresApproval && <p style={{ marginTop: 4 }}>⏳ This service needs the business's approval before it is confirmed.</p>}
            </div>
            <div className="cust-form">
              <label>People
                <span className="cust-stepper">
                  <button type="button" disabled={attendees <= 1} onClick={() => setAttendees((n) => n - 1)} aria-label="Fewer">−</button>
                  <b>{attendees}</b>
                  <button type="button" disabled={!!type.maxParticipants && attendees >= type.maxParticipants} onClick={() => setAttendees((n) => n + 1)} aria-label="More">+</button>
                  {type.maxParticipants ? <small className="cust-note" style={{ margin: 0 }}>max {type.maxParticipants}</small> : null}
                </span>
              </label>
              <label>Notes (optional)<textarea className="input" placeholder="Anything the business should know?" value={notes} onChange={(e) => setNotes(e.target.value)} /></label>
              {!isRange && (
                <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <input type="checkbox" checked={repeatWeekly} onChange={(e) => setRepeatWeekly(e.target.checked)} /> Repeat weekly
                  {repeatWeekly && <>until <input className="input" type="date" min={day} value={repeatUntil} onChange={(e) => setRepeatUntil(e.target.value)} style={{ maxWidth: 170 }} /></>}
                </label>
              )}
            </div>
          </div>
        )}

        <div className="cust-flow-foot">
          <button type="button" className="btn btn-ghost" disabled={step === 0} onClick={back}>‹ Back</button>
          <span className="cust-note" style={{ margin: 0 }}>
            {type && step > 0 ? type.name : ''}{resource && step > 1 ? ` · ${resource.name}` : ''}{window && step > 2 ? ` · ${formatDayLabel(new Date(window.start))}` : ''}
          </span>
          {step < 3
            ? <button type="button" className="btn btn-primary" disabled={!canNext} onClick={next}>Continue ›</button>
            : <button type="button" className="btn btn-primary" disabled={creating || creatingSeries || !window} onClick={confirm}>{creating || creatingSeries ? 'Booking…' : type?.requiresApproval ? 'Send request' : 'Confirm booking'}</button>}
        </div>
      </section>
    </div>
  );
}

function TypeOption({ type, active, onSelect }: { type: BookingType; active: boolean; onSelect: () => void }) {
  const price = priceFor(type, undefined, type.defaultDurationMinutes, 1);
  return (
    <button type="button" className={`cust-option${active ? ' is-active' : ''}`} onClick={onSelect} aria-pressed={active}>
      <strong><i style={{ background: type.colorHex || 'var(--color-primary)' }} aria-hidden="true" />{type.name}</strong>
      {type.description && <p>{type.description}</p>}
      <span className="cust-option-meta">
        <span>{type.bookingUnit === 'Slot' ? `${type.defaultDurationMinutes} min` : type.bookingUnit === 'Night' ? 'per night' : 'multi-day'}</span>
        {type.maxParticipants && type.maxParticipants > 1 && <span>up to {type.maxParticipants}</span>}
        {type.requiresApproval && <span className="approval">needs approval</span>}
        {price && <span className="price">{money(price.amount)}{price.perPerson ? ' pp' : ''}</span>}
      </span>
    </button>
  );
}

function ResourceOption({ resource, active, onSelect }: { resource: Resource; active: boolean; onSelect: () => void }) {
  const initials = resource.name.split(/\s+/).filter((p) => /^[A-Za-z]/.test(p)).slice(0, 2).map((p) => p[0].toUpperCase()).join('');
  return (
    <button type="button" className={`cust-option cust-resource${active ? ' is-active' : ''}`} onClick={onSelect} aria-pressed={active}>
      <span className="cust-avatar" aria-hidden="true">{initials || '•'}</span>
      <div>
        <strong>{resource.name}</strong>
        {(resource.specialty || resource.description) && <p>{[resource.specialty, resource.description].filter(Boolean).join(' · ')}</p>}
        <span className="cust-option-meta">
          {resource.capacity ? <span>seats {resource.capacity}</span> : null}
          {resource.hourlyRate ? <span className="price">LKR {resource.hourlyRate.toLocaleString()}/hr</span> : null}
        </span>
      </div>
    </button>
  );
}
