import { useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import Modal from '../../shared/components/Modal';
import { useCreateBookingTypeMutation, useDeleteBookingTypeMutation, useGetBookingTypesQuery, useUpdateBookingTypeMutation } from '../../api/bookingApi';
import { BOOKING_UNITS, type BookingType, type BookingUnit } from './types';

// Known config keys with dedicated inputs below; anything else typed into
// "Other details (JSON)" is preserved alongside them - same pattern as
// ResourceFormModal's custom attributes editor.
const KNOWN_CONFIG_KEYS = ['capacity', 'weatherDependent', 'cancellation', 'minNights', 'minDays', 'checkInTime', 'checkOutTime', 'itinerary'];

function parseConfig(json?: string | null) {
  if (!json) return { capacityMin: '', capacityMax: '', weatherDependent: false, cutoffHours: '', refundPercent: '', minNights: '', minDays: '', checkInTime: '', checkOutTime: '', itinerary: '', rest: '' };
  try {
    const obj = JSON.parse(json) as Record<string, any>;
    const capacity = obj.capacity ?? {};
    const cancellation = obj.cancellation ?? {};
    const itinerary = Array.isArray(obj.itinerary)
      ? (obj.itinerary as { day?: number; title?: string }[]).map((i) => i.title ?? '').join('\n')
      : '';
    const rest = Object.fromEntries(Object.entries(obj).filter(([k]) => !KNOWN_CONFIG_KEYS.includes(k)));
    return {
      capacityMin: capacity.min != null ? String(capacity.min) : '',
      capacityMax: capacity.max != null ? String(capacity.max) : '',
      weatherDependent: obj.weatherDependent === true,
      cutoffHours: cancellation.cutoffHours != null ? String(cancellation.cutoffHours) : '',
      refundPercent: cancellation.refundPercent != null ? String(cancellation.refundPercent) : '',
      minNights: obj.minNights != null ? String(obj.minNights) : '',
      minDays: obj.minDays != null ? String(obj.minDays) : '',
      checkInTime: obj.checkInTime ?? '',
      checkOutTime: obj.checkOutTime ?? '',
      itinerary,
      rest: Object.keys(rest).length ? JSON.stringify(rest, null, 2) : '',
    };
  } catch {
    return { capacityMin: '', capacityMax: '', weatherDependent: false, cutoffHours: '', refundPercent: '', minNights: '', minDays: '', checkInTime: '', checkOutTime: '', itinerary: '', rest: json };
  }
}

function buildConfig(fields: {
  capacityMin: string; capacityMax: string; weatherDependent: boolean;
  cutoffHours: string; refundPercent: string; minNights: string; minDays: string;
  checkInTime: string; checkOutTime: string; itinerary: string; rest: string;
}): string | undefined {
  let obj: Record<string, any> = {};
  if (fields.rest.trim()) {
    try {
      obj = JSON.parse(fields.rest);
    } catch {
      throw new Error('"Other details" must be valid JSON.');
    }
  }
  if (fields.capacityMin || fields.capacityMax) {
    obj.capacity = {
      ...(fields.capacityMin ? { min: Number(fields.capacityMin) } : {}),
      ...(fields.capacityMax ? { max: Number(fields.capacityMax) } : {}),
    };
  }
  if (fields.weatherDependent) obj.weatherDependent = true;
  if (fields.cutoffHours || fields.refundPercent) {
    obj.cancellation = {
      ...(fields.cutoffHours ? { cutoffHours: Number(fields.cutoffHours) } : {}),
      ...(fields.refundPercent ? { refundPercent: Number(fields.refundPercent) } : {}),
    };
  }
  if (fields.minNights) obj.minNights = Number(fields.minNights);
  if (fields.minDays) obj.minDays = Number(fields.minDays);
  if (fields.checkInTime) obj.checkInTime = fields.checkInTime;
  if (fields.checkOutTime) obj.checkOutTime = fields.checkOutTime;
  if (fields.itinerary.trim()) {
    obj.itinerary = fields.itinerary.split('\n').map((s) => s.trim()).filter(Boolean).map((title, i) => ({ day: i + 1, title }));
  }
  return Object.keys(obj).length ? JSON.stringify(obj) : undefined;
}

// FR-AS5: booking types (Consultation, Follow-up, …) with default duration and price.
export default function BookingTypeManagementPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { show } = useToast();

  const { data: types, isLoading } = useGetBookingTypesQuery({ tenantId }, { skip: !tenantId });
  const [deleteType] = useDeleteBookingTypeMutation();
  const [editing, setEditing] = useState<BookingType | 'new' | null>(null);

  const handleDelete = async (id: string) => {
    if (!window.confirm('Archive this booking type?')) return;
    try {
      await deleteType(id).unwrap();
      show('Booking type archived.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not archive booking type.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Booking Types</h1>
          <p className="page-subtitle">The services you offer — consultations, tours, classes, or sessions — with default duration and approval rules.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setEditing('new')}>+ New booking type</button>
      </div>

      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr><th>Name</th><th>Booking unit</th><th>Duration</th><th>Approval</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            {isLoading && <tr><td colSpan={6} className="loading-row"><span className="spinner spinner-dark" /> Loading…</td></tr>}
            {!isLoading && (!types || types.length === 0) && (
              <tr><td colSpan={6} className="empty-state">No booking types yet.</td></tr>
            )}
            {types?.map((t) => (
              <tr key={t.id}>
                <td>
                  <span className="badge" style={{ background: `${t.colorHex}22`, color: t.colorHex }}>{t.name}</span>
                </td>
                <td>{BOOKING_UNITS.find((u) => u.value === (t.bookingUnit ?? 'Slot'))?.label ?? 'Time slot'}</td>
                <td>
                  {(t.bookingUnit ?? 'Slot') === 'Slot' ? `${t.defaultDurationMinutes} min`
                    : t.bookingUnit === 'Night' ? 'Per night'
                    : t.bookingUnit === 'DateRange' ? 'Per day'
                    : 'Multi-day'}
                </td>
                <td>{t.requiresApproval ? 'Required' : 'Not required'}</td>
                <td><span className={`badge badge-${t.status === 'Active' ? 'good' : 'neutral'}`}>{t.status}</span></td>
                <td>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => setEditing(t)}>Edit</button>
                    <button className="btn btn-danger btn-sm" onClick={() => handleDelete(t.id)}>Archive</button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {editing && <BookingTypeFormModal tenantId={tenantId} bookingType={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function BookingTypeFormModal({ tenantId, bookingType, onClose }: { tenantId: string; bookingType: BookingType | null; onClose: () => void }) {
  const { show } = useToast();
  const [createType, { isLoading: creating }] = useCreateBookingTypeMutation();
  const [updateType, { isLoading: updating }] = useUpdateBookingTypeMutation();

  const [name, setName] = useState(bookingType?.name ?? '');
  const [description, setDescription] = useState(bookingType?.description ?? '');
  const [colorHex, setColorHex] = useState(bookingType?.colorHex ?? '#3B82F6');
  const [duration, setDuration] = useState(bookingType?.defaultDurationMinutes ?? 30);
  const [requiresApproval, setRequiresApproval] = useState(bookingType?.requiresApproval ?? false);
  const [bufferBefore, setBufferBefore] = useState(bookingType?.bufferMinutesBefore ?? 0);
  const [bufferAfter, setBufferAfter] = useState(bookingType?.bufferMinutesAfter ?? 0);
  const [maxParticipants, setMaxParticipants] = useState(bookingType?.maxParticipants?.toString() ?? '');
  const [bookingUnit, setBookingUnit] = useState<BookingUnit>(bookingType?.bookingUnit ?? 'Slot');
  const initialConfig = parseConfig(bookingType?.configJson);
  const [capacityMin, setCapacityMin] = useState(initialConfig.capacityMin);
  const [capacityMax, setCapacityMax] = useState(initialConfig.capacityMax);
  const [weatherDependent, setWeatherDependent] = useState(initialConfig.weatherDependent);
  const [cutoffHours, setCutoffHours] = useState(initialConfig.cutoffHours);
  const [refundPercent, setRefundPercent] = useState(initialConfig.refundPercent);
  const [minNights, setMinNights] = useState(initialConfig.minNights);
  const [minDays, setMinDays] = useState(initialConfig.minDays);
  const [checkInTime, setCheckInTime] = useState(initialConfig.checkInTime);
  const [checkOutTime, setCheckOutTime] = useState(initialConfig.checkOutTime);
  const [itinerary, setItinerary] = useState(initialConfig.itinerary);
  const [otherConfig, setOtherConfig] = useState(initialConfig.rest);
  const [error, setError] = useState<string | null>(null);
  const isLoading = creating || updating;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    let configJson: string | undefined;
    try {
      configJson = buildConfig({
        capacityMin, capacityMax, weatherDependent, cutoffHours, refundPercent,
        minNights, minDays, checkInTime, checkOutTime, itinerary, rest: otherConfig,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invalid config.');
      return;
    }
    const body = {
      name,
      description: description || undefined,
      colorHex,
      defaultDurationMinutes: duration,
      requiresApproval,
      bufferMinutesBefore: bufferBefore,
      bufferMinutesAfter: bufferAfter,
      maxParticipants: maxParticipants ? Number(maxParticipants) : undefined,
      bookingUnit,
      configJson,
    };
    try {
      if (bookingType) {
        await updateType({ id: bookingType.id, body }).unwrap();
        show('Booking type updated.', 'success');
      } else {
        await createType({ tenantId, ...body }).unwrap();
        show('Booking type created.', 'success');
      }
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not save booking type.'));
    }
  };

  return (
    <Modal
      title={bookingType ? 'Edit booking type' : 'New booking type'}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : bookingType ? 'Save changes' : 'Create booking type'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {error && <div className="banner banner-critical">{error}</div>}
        <div className="form-grid">
          <div className="field field-full">
            <label>Name</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="field field-full">
            <label>Booking unit</label>
            <select className="input" value={bookingUnit} onChange={(e) => setBookingUnit(e.target.value as BookingUnit)}>
              {BOOKING_UNITS.map((u) => <option key={u.value} value={u.value}>{u.label}</option>)}
            </select>
            <p style={{ fontSize: 12, opacity: 0.7, margin: '4px 0 0' }}>
              {BOOKING_UNITS.find((u) => u.value === bookingUnit)?.hint}
            </p>
          </div>
          {bookingUnit === 'Slot' && (
            <div className="field">
              <label>Default duration (min)</label>
              <input className="input" type="number" min={5} value={duration} onChange={(e) => setDuration(Number(e.target.value))} />
            </div>
          )}
          <div className="field">
            <label>Color</label>
            <input className="input" type="color" value={colorHex} onChange={(e) => setColorHex(e.target.value)} style={{ padding: 2, height: 38 }} />
          </div>
          {bookingUnit === 'Slot' && (
            <>
              <div className="field">
                <label>Buffer before (min)</label>
                <input className="input" type="number" min={0} value={bufferBefore} onChange={(e) => setBufferBefore(Number(e.target.value))} />
              </div>
              <div className="field">
                <label>Buffer after (min)</label>
                <input className="input" type="number" min={0} value={bufferAfter} onChange={(e) => setBufferAfter(Number(e.target.value))} />
              </div>
            </>
          )}
          <div className="field">
            <label>Max participants</label>
            <input
              className="input"
              type="number"
              min={1}
              value={maxParticipants}
              onChange={(e) => setMaxParticipants(e.target.value)}
              placeholder="Optional, e.g. boat/class capacity"
            />
          </div>
          <div className="field field-full">
            <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <input type="checkbox" checked={requiresApproval} onChange={(e) => setRequiresApproval(e.target.checked)} />
              Requires manager approval before it's confirmed
            </label>
          </div>
          <div className="field field-full">
            <label>Description</label>
            <textarea className="input" rows={2} value={description ?? ''} onChange={(e) => setDescription(e.target.value)} />
          </div>

          <div className="field field-full" style={{ borderTop: '1px solid var(--color-border)', paddingTop: 12, marginTop: 4 }}>
            <label style={{ fontWeight: 600 }}>
              {bookingUnit === 'Slot' ? 'Slot details' : bookingUnit === 'Night' ? 'Accommodation details' : bookingUnit === 'DateRange' ? 'Rental details' : 'Package details'}
            </label>
          </div>
          <div className="field">
            <label>Capacity (min)</label>
            <input className="input" type="number" min={0} value={capacityMin} onChange={(e) => setCapacityMin(e.target.value)} />
          </div>
          <div className="field">
            <label>Capacity (max)</label>
            <input className="input" type="number" min={0} value={capacityMax} onChange={(e) => setCapacityMax(e.target.value)} />
          </div>
          <div className="field field-full">
            <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <input type="checkbox" checked={weatherDependent} onChange={(e) => setWeatherDependent(e.target.checked)} />
              Weather-dependent (may be cancelled for weather/conditions)
            </label>
          </div>
          <div className="field">
            <label>Cancellation cutoff (hours)</label>
            <input className="input" type="number" min={0} value={cutoffHours} onChange={(e) => setCutoffHours(e.target.value)} />
          </div>
          <div className="field">
            <label>Refund on cancellation (%)</label>
            <input className="input" type="number" min={0} max={100} value={refundPercent} onChange={(e) => setRefundPercent(e.target.value)} />
          </div>
          {bookingUnit === 'Night' && (
            <>
              <div className="field">
                <label>Minimum nights</label>
                <input className="input" type="number" min={1} value={minNights} onChange={(e) => setMinNights(e.target.value)} />
              </div>
              <div className="field">
                <label>Check-in time</label>
                <input className="input" type="time" value={checkInTime} onChange={(e) => setCheckInTime(e.target.value)} placeholder="14:00" />
              </div>
              <div className="field">
                <label>Check-out time</label>
                <input className="input" type="time" value={checkOutTime} onChange={(e) => setCheckOutTime(e.target.value)} placeholder="11:00" />
              </div>
            </>
          )}
          {(bookingUnit === 'DateRange' || bookingUnit === 'Package') && (
            <div className="field">
              <label>Minimum days</label>
              <input className="input" type="number" min={1} value={minDays} onChange={(e) => setMinDays(e.target.value)} />
            </div>
          )}
          {bookingUnit === 'Package' && (
            <div className="field field-full">
              <label>Itinerary (one line per day)</label>
              <textarea
                className="input"
                rows={4}
                value={itinerary}
                onChange={(e) => setItinerary(e.target.value)}
                placeholder={'Day 1: Arrival, Colombo city tour\nDay 2: Sigiriya and Dambulla\n...'}
              />
            </div>
          )}
          <div className="field field-full">
            <label>Other details (JSON, optional)</label>
            <textarea
              className="input"
              rows={3}
              value={otherConfig}
              onChange={(e) => setOtherConfig(e.target.value)}
              placeholder='e.g. {"certificationRequired": "PADI Open Water"}'
              style={{ fontFamily: 'monospace', fontSize: 12 }}
            />
          </div>
        </div>
      </form>
    </Modal>
  );
}
