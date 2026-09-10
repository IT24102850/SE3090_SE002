import { useMemo, useState } from 'react';
import Modal from '../../shared/components/Modal';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import {
  useCreateBookingMutation,
  useCreateRecurringBookingMutation,
  useGetBookingTypesQuery,
  useGetResourcesQuery,
  useGetTenantQuery,
} from '../../api/bookingApi';
import { addDays, toISODate } from '../../shared/dateUtils';
import TicketBreakdownField from '../dashboard/components/TicketBreakdownField';
import { getSubtypeConfig } from '../dashboard/subtypes/subtypeRegistry';
import { parseTenantSubType } from '../dashboard/subtypes/tourismSubTypes';
import type { BookingPriority, TicketLine } from './types';

export default function BookingFormModal({
  tenantId,
  userId,
  defaultDate,
  onClose,
  onCreated,
}: {
  tenantId: string;
  userId: string;
  defaultDate?: Date;
  onClose: () => void;
  onCreated?: () => void;
}) {
  const { show } = useToast();
  const { data: resources } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });
  const { data: bookingTypes } = useGetBookingTypesQuery({ tenantId }, { skip: !tenantId });
  // The sub-type decides which extra fields this form collects - ticket
  // types for a whale-watching boat, certification level for a dive centre.
  // An unrecognised sub-type resolves to the generic config, whose
  // bookingFormFields list is empty and whose modules are all off, so the
  // form renders exactly as it did before.
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const subtypeConfig = useMemo(
    () => getSubtypeConfig(parseTenantSubType(tenant?.subType)),
    [tenant],
  );
  const [createBooking, { isLoading }] = useCreateBookingMutation();
  const [createRecurringBooking, { isLoading: creatingRecurring }] = useCreateRecurringBookingMutation();

  const [resourceId, setResourceId] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [title, setTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [date, setDate] = useState(() => toISODate(defaultDate ?? new Date()));
  const [time, setTime] = useState('09:00');
  const [priority, setPriority] = useState<BookingPriority>('Normal');
  const [attendeeCount, setAttendeeCount] = useState('');
  const [tickets, setTickets] = useState<TicketLine[]>([]);
  const [source, setSource] = useState('');
  const [extraFields, setExtraFields] = useState<Record<string, string | boolean>>({});
  const [repeatWeekly, setRepeatWeekly] = useState(false);
  const [repeatUntil, setRepeatUntil] = useState(() => toISODate(addDays(defaultDate ?? new Date(), 28)));
  const [formError, setFormError] = useState<string | null>(null);

  const selectedType = useMemo(() => bookingTypes?.find((t) => t.id === bookingTypeId), [bookingTypes, bookingTypeId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);
    if (!resourceId || !bookingTypeId) {
      setFormError('Please choose a resource and a booking type.');
      return;
    }
    const duration = selectedType?.defaultDurationMinutes ?? 60;
    const start = new Date(`${date}T${time}:00`);

    try {
      if (repeatWeekly) {
        if (repeatUntil < date) {
          setFormError('Repeat-until date must be on or after the start date.');
          return;
        }
        const result = await createRecurringBooking({
          tenantId,
          resourceId,
          bookingTypeId,
          bookedBy: userId,
          title: title || undefined,
          notes: notes || undefined,
          firstStartTime: start.toISOString(),
          durationMinutes: duration,
          endDate: repeatUntil,
        }).unwrap();
        if ('workflowId' in result) {
          show(`This recurring series affects ${result.totalOccurrences} bookings and requires manager approval.`, 'success');
        } else {
          show(`Recurring series created: ${result.created} of ${result.totalRequested} booking(s).`, 'success');
        }
      } else {
        const end = new Date(start.getTime() + duration * 60000);
        const populatedExtras = Object.fromEntries(
          Object.entries(extraFields).filter(([, v]) => v !== '' && v !== false),
        );
        const created = await createBooking({
          tenantId,
          resourceId,
          bookingTypeId,
          bookedBy: userId,
          title: title || undefined,
          notes: notes || undefined,
          startTime: start.toISOString(),
          endTime: end.toISOString(),
          priority,
          attendeeCount: attendeeCount ? Number(attendeeCount) : undefined,
          // Ticket breakdown is priced server-side; only the type and the
          // quantity are sent.
          ticketBreakdown: tickets.length > 0 ? tickets : undefined,
          source: source || undefined,
          formData: Object.keys(populatedExtras).length > 0 ? JSON.stringify(populatedExtras) : undefined,
        }).unwrap();
        // The 90%-full warning is informational: the booking was made.
        const warning = (created as { capacityWarning?: string | null })?.capacityWarning;
        show(warning ? `Booking created. ${warning}` : 'Booking created.', warning ? 'info' : 'success');
      }
      onCreated?.();
      onClose();
    } catch (err: any) {
      if (err?.status === 409) {
        setFormError(apiErrorMessage(err, 'This time slot is already booked.'));
      } else {
        show(apiErrorMessage(err, 'Could not create booking.'), 'error');
      }
    }
  };

  return (
    <Modal
      title="New booking"
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading || creatingRecurring}>
            {isLoading || creatingRecurring ? <span className="spinner" /> : repeatWeekly ? 'Create series' : 'Create booking'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {formError && <div className="banner banner-critical">{formError}</div>}

        <div className="form-grid">
          <div className="field">
            <label>Resource</label>
            <select className="input" value={resourceId} onChange={(e) => setResourceId(e.target.value)} required>
              <option value="">Select…</option>
              {resources?.items.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
          </div>
          <div className="field">
            <label>Booking type</label>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} required>
              <option value="">Select…</option>
              {bookingTypes?.map((t) => <option key={t.id} value={t.id}>{t.name} ({t.defaultDurationMinutes}m)</option>)}
            </select>
          </div>
          <div className="field">
            <label>Date</label>
            <input className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
          </div>
          <div className="field">
            <label>Start time</label>
            <input className="input" type="time" value={time} onChange={(e) => setTime(e.target.value)} required />
          </div>
          <div className="field">
            <label>Priority</label>
            <select className="input" value={priority} onChange={(e) => setPriority(e.target.value as BookingPriority)}>
              <option value="Low">Low</option>
              <option value="Normal">Normal</option>
              <option value="High">High</option>
              <option value="Urgent">Urgent</option>
            </select>
          </div>
          {!repeatWeekly && (
            <div className="field">
              <label>Attendee count</label>
              <input
                className="input"
                type="number"
                min={1}
                value={attendeeCount}
                onChange={(e) => setAttendeeCount(e.target.value)}
                placeholder="Optional, e.g. group size"
              />
            </div>
          )}
          {!repeatWeekly && subtypeConfig.modules.ticketTypes && bookingTypeId && (
            <TicketBreakdownField
              bookingTypeId={bookingTypeId}
              startTime={new Date(`${date}T${time}:00`).toISOString()}
              value={tickets}
              onChange={setTickets}
            />
          )}
          {!repeatWeekly && subtypeConfig.modules.ticketTypes && (
            <div className="field">
              <label>Booking channel</label>
              <select className="input" value={source} onChange={(e) => setSource(e.target.value)}>
                <option value="">Not recorded</option>
                <option value="WalkIn">Walk-in</option>
                <option value="Online">Online</option>
                <option value="OTA">OTA / agent</option>
                <option value="Phone">Phone</option>
              </select>
            </div>
          )}
          {!repeatWeekly && subtypeConfig.bookingFormFields.map((f) => (
            <div className={f.type === 'textArea' ? 'field field-full' : 'field'} key={f.key}>
              <label>{f.label}</label>
              {f.type === 'dropdown' ? (
                <select
                  className="input"
                  value={String(extraFields[f.key] ?? '')}
                  onChange={(e) => setExtraFields({ ...extraFields, [f.key]: e.target.value })}
                >
                  <option value="">Select…</option>
                  {(f.options ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
                </select>
              ) : f.type === 'checkbox' ? (
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 400 }}>
                  <input
                    type="checkbox"
                    checked={extraFields[f.key] === true}
                    onChange={(e) => setExtraFields({ ...extraFields, [f.key]: e.target.checked })}
                  />
                  {f.hint ?? 'Yes'}
                </label>
              ) : f.type === 'textArea' ? (
                <textarea
                  className="input"
                  rows={2}
                  value={String(extraFields[f.key] ?? '')}
                  onChange={(e) => setExtraFields({ ...extraFields, [f.key]: e.target.value })}
                />
              ) : (
                <input
                  className="input"
                  type={f.type === 'numberStepper' ? 'number' : f.type === 'date' ? 'date' : 'text'}
                  value={String(extraFields[f.key] ?? '')}
                  onChange={(e) => setExtraFields({ ...extraFields, [f.key]: e.target.value })}
                />
              )}
              {f.hint && f.type !== 'checkbox' && (
                <span style={{ fontSize: '0.75rem', color: 'var(--color-text-muted)' }}>{f.hint}</span>
              )}
            </div>
          ))}
          <div className="field">
            <label>Title</label>
            <input className="input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Optional" />
          </div>
          <div className="field field-full">
            <label>Notes</label>
            <textarea className="input" rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          <div className="field field-full">
            <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <input type="checkbox" checked={repeatWeekly} onChange={(e) => setRepeatWeekly(e.target.checked)} />
              Repeat weekly (e.g. weekly physiotherapy sessions)
            </label>
          </div>
          {repeatWeekly && (
            <div className="field">
              <label>Repeat until</label>
              <input className="input" type="date" value={repeatUntil} min={date} onChange={(e) => setRepeatUntil(e.target.value)} required />
            </div>
          )}
        </div>
      </form>
    </Modal>
  );
}
