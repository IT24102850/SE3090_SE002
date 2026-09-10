import { useState } from 'react';
import {
  useCheckInBookingMutation,
  useGetDepartureManifestQuery,
  useSetBookingWaiverMutation,
  useUpdateBookingStatusMutation,
} from '../../../api/bookingApi';
import Modal from '../../../shared/components/Modal';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import type { DepartureSummary } from '../../booking/types';

/* The per-departure passenger manifest: who is aboard, on what ticket, with
 * a signed waiver or not, checked in or not.
 *
 * Check-in reuses the existing POST /bookings/{id}/checkin endpoint that the
 * mobile QR scanner already calls - no new check-in path, so scanning at the
 * jetty and ticking a box here update exactly the same row. */

export default function ManifestModal({
  departure,
  onClose,
}: {
  departure: DepartureSummary;
  onClose: () => void;
}) {
  const { data, isLoading } = useGetDepartureManifestQuery(departure.id);
  const [checkIn] = useCheckInBookingMutation();
  const [setStatus] = useUpdateBookingStatusMutation();
  const [setWaiver] = useSetBookingWaiverMutation();
  const [signingFor, setSigningFor] = useState<string | null>(null);
  const [signerName, setSignerName] = useState('');
  const [minorCount, setMinorCount] = useState(0);
  const toast = useToast();

  const passengers = data?.passengers ?? [];

  const doCheckIn = async (bookingId: string) => {
    try {
      await checkIn(bookingId).unwrap();
      toast.show('Guest checked in.', 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not check the guest in.'), 'error');
    }
  };

  const markNoShow = async (bookingId: string) => {
    try {
      await setStatus({ id: bookingId, status: 'NoShow' }).unwrap();
      toast.show('Marked as a no-show.', 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not update the booking.'), 'error');
    }
  };

  const saveWaiver = async (bookingId: string) => {
    if (!signerName.trim()) {
      toast.show('A signer name is required to record a waiver.', 'error');
      return;
    }
    try {
      await setWaiver({ id: bookingId, signerName: signerName.trim(), minorCount }).unwrap();
      toast.show('Waiver recorded.', 'success');
      setSigningFor(null);
      setSignerName('');
      setMinorCount(0);
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not record the waiver.'), 'error');
    }
  };

  return (
    <Modal
      title={`Manifest — ${departure.vesselName}, ${formatTime(departure.scheduledDeparture)}`}
      onClose={onClose}
    >
      {isLoading ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading manifest…</div>
      ) : (
        <>
          <div className="stat-grid" style={{ marginBottom: 16 }}>
            <div className="stat-tile">
              <div className="stat-tile-label">Pax aboard</div>
              <div className="stat-tile-value">
                {passengers.reduce((sum, p) => sum + p.seats, 0)}
                <span style={{ fontSize: '0.9rem', color: 'var(--color-text-muted)' }}>
                  {' '}/ {departure.capacity || '—'}
                </span>
              </div>
            </div>
            <div className="stat-tile">
              <div className="stat-tile-label">Waivers signed</div>
              <div
                className="stat-tile-value"
                style={{
                  color: (data?.waiverCompletionPercent ?? 0) >= 100
                    ? 'var(--color-good)'
                    : 'var(--color-warning)',
                }}
              >
                {(data?.waiverCompletionPercent ?? 0).toFixed(0)}%
              </div>
            </div>
            <div className="stat-tile">
              <div className="stat-tile-label">Checked in</div>
              <div className="stat-tile-value">{data?.checkedInCount ?? 0}</div>
            </div>
            <div className="stat-tile">
              <div className="stat-tile-label">No-shows</div>
              <div className="stat-tile-value" style={{ color: 'var(--color-critical)' }}>
                {data?.noShowCount ?? 0}
              </div>
            </div>
          </div>

          {passengers.length === 0 ? (
            <p style={{ color: 'var(--color-text-muted)' }}>No reservations on this departure yet.</p>
          ) : (
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Guest</th>
                    <th>Tickets</th>
                    <th>Waiver</th>
                    <th>Check-in</th>
                    <th>Source</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {passengers.map((p) => (
                    <tr key={p.bookingId}>
                      <td>
                        <div>{p.guestName}</div>
                        {p.guestPhone && (
                          <div style={{ fontSize: '0.75rem', color: 'var(--color-text-muted)' }}>{p.guestPhone}</div>
                        )}
                      </td>
                      <td>
                        {p.tickets.length > 0
                          ? p.tickets.map((t) => `${t.qty} ${t.type.toLowerCase()}`).join(', ')
                          : `${p.seats} guest${p.seats === 1 ? '' : 's'}`}
                        {p.minorCount > 0 && (
                          <div style={{ fontSize: '0.75rem', color: 'var(--color-warning)' }}>
                            {p.minorCount} minor{p.minorCount === 1 ? '' : 's'}
                          </div>
                        )}
                      </td>
                      <td>
                        {p.waiverSigned ? (
                          <span className="badge badge-good">Signed</span>
                        ) : signingFor === p.bookingId ? (
                          <div style={{ display: 'grid', gap: 4, minWidth: 170 }}>
                            <input
                              className="input"
                              placeholder="Signer name"
                              value={signerName}
                              onChange={(e) => setSignerName(e.target.value)}
                            />
                            <input
                              className="input"
                              type="number"
                              min={0}
                              placeholder="Minors"
                              value={minorCount}
                              onChange={(e) => setMinorCount(Number(e.target.value) || 0)}
                            />
                            <div style={{ display: 'flex', gap: 4 }}>
                              <button className="btn btn-primary btn-sm" onClick={() => saveWaiver(p.bookingId)}>
                                Save
                              </button>
                              <button className="btn btn-ghost btn-sm" onClick={() => setSigningFor(null)}>
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : (
                          <button
                            className="btn btn-secondary btn-sm"
                            onClick={() => { setSigningFor(p.bookingId); setSignerName(p.guestName); }}
                          >
                            Record
                          </button>
                        )}
                      </td>
                      <td>
                        {p.checkedIn ? (
                          <span className="badge badge-good">
                            {p.checkInAt ? formatTime(p.checkInAt) : 'Checked in'}
                          </span>
                        ) : p.noShow ? (
                          <span className="badge badge-critical">No-show</span>
                        ) : (
                          <button className="btn btn-secondary btn-sm" onClick={() => doCheckIn(p.bookingId)}>
                            Check in
                          </button>
                        )}
                      </td>
                      <td style={{ color: 'var(--color-text-muted)', fontSize: '0.8rem' }}>{p.source ?? '—'}</td>
                      <td>
                        {!p.checkedIn && !p.noShow && (
                          <button className="btn btn-ghost btn-sm" onClick={() => markNoShow(p.bookingId)}>
                            No-show
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}
