import { useGetBookingHistoryQuery } from '../../api/bookingApi';
import { formatDateTime } from '../../shared/dateUtils';
import type { BookingEvent } from './types';

/* The booking's audit trail, read from GET /api/bookings/{id}/history.
 *
 * Every row is written by the server from EF Core's change tracker, so this
 * shows what actually happened rather than what a screen happened to report.
 * Each entry names the person, or "System" for a background service such as
 * the hold sweeper - which is the honest answer, not a missing one. */

function describe(event: BookingEvent): string {
  switch (event.type) {
    case 'Created':
      return `Booking created as ${event.to}`;
    case 'StatusChanged':
      return `Status changed from ${event.from} to ${event.to}`;
    case 'Rescheduled':
      return `Moved from ${formatWindow(event.from)} to ${formatWindow(event.to)}`;
    case 'ResourceChanged':
      return `Reassigned from ${event.from} to ${event.to}`;
    case 'Deleted':
      return 'Booking removed';
    default:
      return event.type;
  }
}

/** The server stores a reschedule as "<start>/<end>" in ISO 8601. */
function formatWindow(value: string | null): string {
  if (!value) return 'unknown';
  const [start, end] = value.split('/');
  return end ? `${formatDateTime(start)} – ${formatDateTime(end)}` : formatDateTime(start);
}

function actorOf(event: BookingEvent): string {
  if (event.actorName) return event.actorRole ? `${event.actorName} (${event.actorRole})` : event.actorName;
  return event.actorRole === 'System' ? 'System' : 'Unknown';
}

export default function BookingHistoryTimeline({ bookingId }: { bookingId: string }) {
  const { data, isLoading, isError } = useGetBookingHistoryQuery(bookingId);

  if (isLoading) return <p className="hint">Loading history…</p>;
  if (isError) return <p className="hint" role="alert">History could not be loaded.</p>;
  if (!data || data.length === 0) return <p className="hint">No changes recorded yet.</p>;

  return (
    <ol className="booking-timeline" aria-label="Booking history">
      {data.map((event) => (
        <li key={event.id} className={`booking-timeline-item is-${event.type.toLowerCase()}`}>
          <div className="booking-timeline-when">{formatDateTime(event.at)}</div>
          <div className="booking-timeline-what">
            <strong>{describe(event)}</strong>
            <div className="cell-sub">by {actorOf(event)}</div>
            {event.reason && <div className="cell-sub">Reason: {event.reason}</div>}
          </div>
        </li>
      ))}
    </ol>
  );
}
