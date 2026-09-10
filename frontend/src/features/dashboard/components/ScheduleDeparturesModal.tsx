import { useState } from 'react';
import {
  useCreateDepartureMutation,
  useGetBookingTypesQuery,
  useGetResourcesQuery,
} from '../../../api/bookingApi';
import Modal from '../../../shared/components/Modal';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { addDays, toISODate } from '../../../shared/dateUtils';
import type { SubtypeDashboardConfig } from '../subtypes/SubtypeDashboardConfig';

/* Bulk-creates the departure rows the board runs on: pick the vessels, the
 * daily sailing times, and a date range.
 *
 * A departure that already exists is skipped, not duplicated - the backend
 * rejects a second departure for the same vessel and time with a 409, so
 * re-running over an overlapping range is safe and simply tops up the gaps. */

export default function ScheduleDeparturesModal({
  config,
  tenantId,
  onClose,
}: {
  config: SubtypeDashboardConfig;
  tenantId: string;
  onClose: () => void;
}) {
  const { data: resources } = useGetResourcesQuery({ tenantId, pageSize: 100 }, { skip: !tenantId });
  const { data: bookingTypes } = useGetBookingTypesQuery({ tenantId }, { skip: !tenantId });
  const [createDeparture] = useCreateDepartureMutation();
  const toast = useToast();

  const [vesselIds, setVesselIds] = useState<string[]>([]);
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [times, setTimes] = useState<string[]>(['06:30']);
  const [from, setFrom] = useState(() => toISODate(new Date()));
  const [to, setTo] = useState(() => toISODate(addDays(new Date(), 13)));
  const [busy, setBusy] = useState(false);

  // Vehicles are the vessels/jeeps a departure runs on; staff and rooms are
  // not things that sail.
  const vessels = (resources?.items ?? []).filter(
    (r) => r.category === 'Vehicle' && r.status !== 'Archived',
  );
  const duration = bookingTypes?.find((t) => t.id === bookingTypeId)?.defaultDurationMinutes ?? 240;

  const toggleVessel = (id: string) =>
    setVesselIds((prev) => (prev.includes(id) ? prev.filter((v) => v !== id) : [...prev, id]));

  const submit = async () => {
    if (vesselIds.length === 0 || times.length === 0) {
      toast.show(`Pick at least one vessel and one ${config.resourceTermSingular.toLowerCase()} time.`, 'error');
      return;
    }
    if (to < from) {
      toast.show('The end date must be on or after the start date.', 'error');
      return;
    }

    setBusy(true);
    let created = 0;
    let skipped = 0;

    for (let day = new Date(from); toISODate(day) <= to; day = addDays(day, 1)) {
      for (const vesselId of vesselIds) {
        for (const time of times) {
          const start = new Date(`${toISODate(day)}T${time}:00`);
          try {
            await createDeparture({
              resourceId: vesselId,
              bookingTypeId: bookingTypeId || undefined,
              scheduledDeparture: start.toISOString(),
              scheduledReturn: new Date(start.getTime() + duration * 60000).toISOString(),
            }).unwrap();
            created++;
          } catch (error) {
            // 409 means it already exists, which is the expected outcome of
            // re-running over a range and not worth surfacing as a failure.
            if ((error as { status?: number })?.status === 409) skipped++;
            else {
              toast.show(apiErrorMessage(error, 'Could not schedule departures.'), 'error');
              setBusy(false);
              return;
            }
          }
        }
      }
    }

    setBusy(false);
    toast.show(
      skipped > 0
        ? `${created} ${config.resourceTermPlural.toLowerCase()} scheduled, ${skipped} already existed.`
        : `${created} ${config.resourceTermPlural.toLowerCase()} scheduled.`,
      'success',
    );
    onClose();
  };

  return (
    <Modal
      title={`Schedule ${config.resourceTermPlural.toLowerCase()}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-ghost" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn btn-primary" onClick={submit} disabled={busy}>
            {busy ? 'Scheduling…' : 'Schedule'}
          </button>
        </>
      }
    >
      <div style={{ display: 'grid', gap: 12 }}>
        <div className="field">
          <label>Vessels</label>
          {vessels.length === 0 ? (
            <p style={{ color: 'var(--color-text-muted)', fontSize: '0.85rem', margin: 0 }}>
              No Vehicle-category resources yet. Add your boats under {config.resourceTermPlural} first.
            </p>
          ) : (
            vessels.map((v) => (
              <label key={v.id} style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 400 }}>
                <input
                  type="checkbox"
                  checked={vesselIds.includes(v.id)}
                  onChange={() => toggleVessel(v.id)}
                />
                {v.name}
                {v.capacity ? ` (${v.capacity} pax)` : ''}
              </label>
            ))
          )}
        </div>

        <div className="field">
          <label>Booking type</label>
          <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)}>
            <option value="">None (4-hour default)</option>
            {(bookingTypes ?? []).map((t) => (
              <option key={t.id} value={t.id}>{t.name} ({t.defaultDurationMinutes}m)</option>
            ))}
          </select>
        </div>

        <div className="field">
          <label>Daily departure times</label>
          {times.map((time, index) => (
            <div key={index} style={{ display: 'flex', gap: 6, marginBottom: 4 }}>
              <input
                className="input"
                type="time"
                value={time}
                onChange={(e) => setTimes(times.map((t, i) => (i === index ? e.target.value : t)))}
              />
              {times.length > 1 && (
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  onClick={() => setTimes(times.filter((_, i) => i !== index))}
                >
                  Remove
                </button>
              )}
            </div>
          ))}
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setTimes([...times, '10:00'])}>
            Add a departure time
          </button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
          <div className="field">
            <label>From</label>
            <input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="field">
            <label>To</label>
            <input className="input" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
          </div>
        </div>

        <p style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', margin: 0 }}>
          {vesselIds.length * times.length} sailing(s) per day. Re-running over a range you have already
          scheduled tops up the gaps rather than duplicating anything.
        </p>
      </div>
    </Modal>
  );
}
