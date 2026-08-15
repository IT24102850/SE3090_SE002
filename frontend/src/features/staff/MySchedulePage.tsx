import { useMemo } from 'react';
import { useGetMyScheduleQuery, useUpdateBookingStatusMutation } from '../../api/bookingApi';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { formatDayLabel, formatTime, isSameDay } from '../../shared/dateUtils';
import { STATUS_COLORS, type Booking } from '../booking/types';

// FR-AS8: a staff member's own daily/weekly schedule (doctor, guide, trainer,
// tutor, ...), with status marking (Completed/No-show/In-progress). Backed
// by GET /bookings/my-schedule, which is filtered server-side to the
// Resource(s) linked to this login — mirrors the mobile app's
// my_schedule_screen.dart.
export default function MySchedulePage() {
  const { data: bookings, isLoading } = useGetMyScheduleQuery();
  const [updateStatus] = useUpdateBookingStatusMutation();
  const { show } = useToast();

  const { today, upcoming } = useMemo(() => {
    const now = new Date();
    const list = bookings ?? [];
    return {
      today: list.filter((b) => isSameDay(new Date(b.startTime), now)).sort((a, b) => a.startTime.localeCompare(b.startTime)),
      upcoming: list
        .filter((b) => new Date(b.startTime) > now && !isSameDay(new Date(b.startTime), now))
        .sort((a, b) => a.startTime.localeCompare(b.startTime)),
    };
  }, [bookings]);

  const handleStatus = async (id: string, status: string) => {
    try {
      await updateStatus({ id, status }).unwrap();
      show(`Marked as ${status}.`, 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not update status.'), 'error');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">My Schedule</h1>
          <p className="page-subtitle">Your own bookings — mark each one's outcome as it happens.</p>
        </div>
      </div>

      {isLoading ? (
        <div className="card"><div className="loading-row"><span className="spinner spinner-dark" /> Loading…</div></div>
      ) : (
        <>
          <p className="chart-title" style={{ marginBottom: 12 }}>Today</p>
          <ScheduleList bookings={today} onStatus={handleStatus} emptyMessage="Nothing scheduled today." />

          <p className="chart-title" style={{ margin: '24px 0 12px' }}>Upcoming</p>
          <ScheduleList bookings={upcoming} onStatus={handleStatus} emptyMessage="Nothing else coming up." />
        </>
      )}
    </div>
  );
}

function ScheduleList({ bookings, onStatus, emptyMessage }: { bookings: Booking[]; onStatus: (id: string, status: string) => void; emptyMessage: string }) {
  if (bookings.length === 0) {
    return <div className="card"><div className="empty-state">{emptyMessage}</div></div>;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {bookings.map((b) => (
        <div className="card" style={{ padding: 16, display: 'flex', alignItems: 'center', gap: 14 }} key={b.id}>
          <div style={{ width: 5, height: 40, borderRadius: 3, background: STATUS_COLORS[b.status]?.bg ?? b.colorHex }} />
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 700 }}>{b.title || `${b.resourceName} · ${b.bookingTypeName}`}</div>
            <div style={{ fontSize: 12.5, color: 'var(--color-text-secondary)', marginTop: 2 }}>
              {formatDayLabel(new Date(b.startTime))} · {formatTime(b.startTime)} – {formatTime(b.endTime)}
            </div>
          </div>
          <span className={`badge badge-${STATUS_COLORS[b.status]?.tone ?? 'neutral'}`}>{b.status}</span>
          <select
            className="input"
            style={{ padding: '4px 8px', fontSize: 12, width: 'auto' }}
            value=""
            onChange={(e) => { if (e.target.value) onStatus(b.id, e.target.value); e.target.value = ''; }}
          >
            <option value="">Mark as…</option>
            <option value="InProgress">In progress</option>
            <option value="Completed">Completed</option>
            <option value="NoShow">No-show</option>
          </select>
        </div>
      ))}
    </div>
  );
}
