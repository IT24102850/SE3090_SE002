import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useSendReminderMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime } from '../../../shared/dateUtils';
import type { ClinicReminders } from '../../booking/types';

/* The reminder worklist and the follow-up list.
 *
 * The backend's ReminderDispatchService already sends a reminder 24h out
 * on its own; this panel is for the rest - seeing which appointments in the
 * next two days are still unreminded, nudging one (or all) early, and
 * spotting patients seen recently who have nothing booked ahead. */

export default function ClinicRemindersPanel({ data, loading }: { data?: ClinicReminders; loading: boolean }) {
  const [sendReminder] = useSendReminderMutation();
  const [busy, setBusy] = useState<string | null>(null);
  const toast = useToast();

  async function remind(id: string, name: string) {
    setBusy(id);
    try {
      await sendReminder({ id, channel: 'Email' }).unwrap();
      toast.show(`Reminder sent to ${name}.`, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not send the reminder.'), 'error');
    } finally {
      setBusy(null);
    }
  }

  async function remindAll() {
    const unsent = (data?.items ?? []).filter((i) => !i.reminderSent);
    if (unsent.length === 0) return;
    setBusy('all');
    let ok = 0;
    for (const item of unsent) {
      try {
        await sendReminder({ id: item.bookingId, channel: 'Email' }).unwrap();
        ok += 1;
      } catch {
        // Counted below; one failure should not stop the rest of the list.
      }
    }
    setBusy(null);
    toast.show(ok === unsent.length ? `${ok} reminder${ok === 1 ? '' : 's'} sent.` : `${ok} of ${unsent.length} reminders sent.`, ok === unsent.length ? 'success' : 'warning');
  }

  if (loading && !data) return <div className="loading-row"><span className="spinner spinner-dark" /> Loading reminders…</div>;

  const items = data?.items ?? [];
  const followUps = data?.followUps ?? [];

  return (
    <div className="clinic-reminders">
      <div>
        <p className="clinic-subhead">
          <span>Next {data?.withinHours ?? 48}h · {items.length} appointment{items.length === 1 ? '' : 's'}</span>
          {data && data.unsent > 0 && (
            <button type="button" className="btn btn-secondary btn-sm" disabled={busy !== null} onClick={remindAll}>
              {busy === 'all' ? 'Sending…' : `Remind all unsent (${data.unsent})`}
            </button>
          )}
        </p>
        {items.length === 0 ? (
          <div className="clinic-empty">Nothing scheduled in the next {data?.withinHours ?? 48} hours.</div>
        ) : (
          <div className="clinic-reminder-list">
            {items.map((item) => (
              <div key={item.bookingId} className="clinic-reminder">
                <div className="clinic-reminder-main">
                  <strong>{item.patientName}</strong>
                  <span>{formatDateTime(item.startTime)} · {item.doctorName} · {item.treatment}{item.patientPhone ? ` · ${item.patientPhone}` : ''}</span>
                </div>
                <div className="clinic-reminder-side">
                  {item.reminderSent ? (
                    <span className="badge badge-good" title={item.lastReminderAt ? `Sent ${formatDateTime(item.lastReminderAt)}${item.lastChannel ? ` via ${item.lastChannel}` : ''}` : undefined}>
                      <span className="badge-dot" />Reminded
                    </span>
                  ) : (
                    <span className="badge badge-warning"><span className="badge-dot" />Not yet</span>
                  )}
                  <button type="button" className="btn btn-secondary" disabled={busy !== null} onClick={() => remind(item.bookingId, item.patientName)}>
                    {busy === item.bookingId ? '…' : item.reminderSent ? 'Send again' : 'Send'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div>
        <p className="clinic-subhead"><span>Follow-up candidates</span><span style={{ fontWeight: 600, textTransform: 'none', letterSpacing: 0 }}>seen in the last 30 days, nothing booked</span></p>
        {followUps.length === 0 ? (
          <div className="clinic-empty">Every patient seen recently has a next visit booked.</div>
        ) : (
          <div className="clinic-followup-list">
            {followUps.map((f) => (
              <div key={f.patientId} className="clinic-reminder">
                <div className="clinic-reminder-main">
                  <strong>{f.patientName}</strong>
                  <span>{f.daysSince === 0 ? 'Seen today' : `${f.daysSince} day${f.daysSince === 1 ? '' : 's'} ago`} · {f.doctorName} · {f.treatment}{f.patientPhone ? ` · ${f.patientPhone}` : ''}</span>
                </div>
                <Link className="btn btn-secondary btn-sm" to="/bookings">Book follow-up</Link>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
