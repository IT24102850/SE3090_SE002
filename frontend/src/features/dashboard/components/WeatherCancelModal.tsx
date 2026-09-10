import { useState } from 'react';
import {
  useBulkRescheduleDepartureMutation,
  useCancelDepartureForWeatherMutation,
  useGetDepartureManifestQuery,
} from '../../../api/bookingApi';
import Modal from '../../../shared/components/Modal';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime, formatTime } from '../../../shared/dateUtils';
import type { DepartureSummary, RescheduleOption } from '../../booking/types';

/* Cancel-with-notify, in one action.
 *
 * Step 1 cancels: every booking on the sailing moves to WeatherCancelled and
 * every guest gets a notification, server-side, in one request. Step 2 is
 * the follow-up offer - rebooking those guests onto another departure with
 * their ticket breakdown intact. The two are separate requests on purpose:
 * the cancellation must not be held hostage to the operator deciding where
 * to move people, because the guests need telling now. */

export default function WeatherCancelModal({
  departure,
  onClose,
}: {
  departure: DepartureSummary;
  onClose: () => void;
}) {
  const { data: manifest } = useGetDepartureManifestQuery(departure.id);
  const [cancel, { isLoading: cancelling }] = useCancelDepartureForWeatherMutation();
  const [bulkReschedule, { isLoading: moving }] = useBulkRescheduleDepartureMutation();
  const toast = useToast();

  const [reason, setReason] = useState('');
  const [weather, setWeather] = useState({ wind: '', wave: '', visibility: '', seaState: '' });
  const [options, setOptions] = useState<RescheduleOption[] | null>(null);
  const [target, setTarget] = useState('');
  const [cancelledCount, setCancelledCount] = useState(0);

  const affected = manifest?.passengers ?? [];

  const doCancel = async () => {
    const num = (v: string) => (v.trim() === '' ? undefined : Number(v));
    try {
      const result = await cancel({
        id: departure.id,
        reason: reason.trim() || undefined,
        weather: {
          windSpeedKnots: num(weather.wind),
          waveHeightMetres: num(weather.wave),
          visibilityKm: num(weather.visibility),
          seaStateCode: num(weather.seaState),
        },
      }).unwrap();

      setCancelledCount(result.bookingsCancelled);
      setOptions(result.rescheduleOptions);
      toast.show(
        `${result.bookingsCancelled} booking(s) cancelled, ${result.guestsNotified} guest(s) notified.`,
        'success',
      );
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not cancel the departure.'), 'error');
    }
  };

  const doReschedule = async () => {
    if (!target) return;
    try {
      const result = await bulkReschedule({
        id: departure.id,
        targetDepartureId: target,
        bookingIds: affected.map((p) => p.bookingId),
      }).unwrap();

      if (result.skippedCount > 0) {
        toast.show(
          `${result.movedCount} guest(s) rebooked; ${result.skippedCount} could not be moved (the target departure filled up).`,
          'info',
        );
      } else {
        toast.show(`${result.movedCount} guest(s) rebooked.`, 'success');
      }
      onClose();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not rebook the guests.'), 'error');
    }
  };

  const totalSeats = affected.reduce((sum, p) => sum + p.seats, 0);

  return (
    <Modal
      title={`Cancel for weather — ${departure.vesselName}, ${formatTime(departure.scheduledDeparture)}`}
      onClose={onClose}
      footer={
        options === null ? (
          <>
            <button className="btn btn-ghost" onClick={onClose}>Keep the departure</button>
            <button className="btn btn-danger" onClick={doCancel} disabled={cancelling}>
              {cancelling ? 'Cancelling…' : `Cancel & notify ${affected.length} booking(s)`}
            </button>
          </>
        ) : (
          <>
            <button className="btn btn-ghost" onClick={onClose}>Done — do not rebook</button>
            <button className="btn btn-primary" onClick={doReschedule} disabled={!target || moving}>
              {moving ? 'Rebooking…' : 'Rebook guests'}
            </button>
          </>
        )
      }
    >
      {options === null ? (
        <div style={{ display: 'grid', gap: 12 }}>
          <p style={{ margin: 0, color: 'var(--color-text-secondary)' }}>
            This cancels <strong>{affected.length} booking(s)</strong> ({totalSeats} guests), marks them
            weather-cancelled, and notifies every guest. You will be offered alternative departures
            afterwards.
          </p>

          <div className="field">
            <label>Reason (shown to guests)</label>
            <input
              className="input"
              placeholder="Cancelled due to sea conditions."
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>

          <p className="chart-subtitle" style={{ margin: 0 }}>
            Optional: record the conditions that justified the call.
          </p>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(120px, 1fr))', gap: 8 }}>
            <div className="field">
              <label>Wind (kt)</label>
              <input className="input" type="number" value={weather.wind}
                onChange={(e) => setWeather({ ...weather, wind: e.target.value })} />
            </div>
            <div className="field">
              <label>Wave (m)</label>
              <input className="input" type="number" step="0.1" value={weather.wave}
                onChange={(e) => setWeather({ ...weather, wave: e.target.value })} />
            </div>
            <div className="field">
              <label>Visibility (km)</label>
              <input className="input" type="number" step="0.1" value={weather.visibility}
                onChange={(e) => setWeather({ ...weather, visibility: e.target.value })} />
            </div>
            <div className="field">
              <label>Sea state (0–9)</label>
              <input className="input" type="number" min={0} max={9} value={weather.seaState}
                onChange={(e) => setWeather({ ...weather, seaState: e.target.value })} />
            </div>
          </div>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: 12 }}>
          <p style={{ margin: 0 }}>
            <strong>{cancelledCount} booking(s) cancelled and every guest notified.</strong>
          </p>
          {options.length === 0 ? (
            <p style={{ color: 'var(--color-text-muted)', margin: 0 }}>
              No alternative departures are scheduled outside the reschedule cutoff, so there is nothing to
              rebook onto right now. Guests have been told.
            </p>
          ) : (
            <>
              <p style={{ margin: 0, color: 'var(--color-text-secondary)' }}>
                Move all {affected.length} booking(s) — {totalSeats} guests, ticket breakdowns kept — onto:
              </p>
              <div className="field">
                <label>Target departure</label>
                <select className="input" value={target} onChange={(e) => setTarget(e.target.value)}>
                  <option value="">Select a departure…</option>
                  {options.map((o) => (
                    <option
                      key={o.departureId}
                      value={o.departureId}
                      // A departure that cannot take the whole group is still
                      // offered: the backend moves who fits and reports the
                      // rest, which beats hiding a half-solution.
                      disabled={o.seatsRemaining === 0}
                    >
                      {formatDateTime(o.scheduledDeparture)} — {o.vesselName} ({o.seatsRemaining} seats free)
                    </option>
                  ))}
                </select>
              </div>
            </>
          )}
        </div>
      )}
    </Modal>
  );
}
