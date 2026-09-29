import { useState } from 'react';
import { API_BASE_URL } from '../../api/apiBaseUrl';
import { useToast } from './Toast';

/* "Add to calendar" — downloads the booking as an .ics file.
 *
 * A file rather than a Google Calendar integration: no API key, no OAuth
 * consent screen, no rate limit, and it works in Google, Apple and Outlook
 * alike. The event carries a 2-hour alarm the guest's own device raises,
 * which still fires when our SMS and push do not.
 *
 * Fetched with the JWT rather than linked directly, because the endpoint is
 * authorised — a bare <a href> would send no Authorization header and get a
 * 401 the user would read as a broken button. */
export function AddToCalendarButton({
  bookingId,
  label = 'Add to calendar',
  className = 'btn btn-secondary',
}: {
  bookingId: string;
  label?: string;
  className?: string;
}) {
  const { show } = useToast();
  const [busy, setBusy] = useState(false);

  const download = async () => {
    setBusy(true);
    try {
      const response = await fetch(`${API_BASE_URL}/bookings/${bookingId}/calendar.ics`, {
        headers: { Authorization: `Bearer ${localStorage.getItem('token') ?? ''}` },
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `booking-${bookingId}.ics`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      // Revoking immediately can cancel the download in some browsers.
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);

      show('Calendar file downloaded — open it to add the booking.', 'success');
    } catch {
      show('Could not build the calendar file. Please try again.', 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <button type="button" className={className} disabled={busy} onClick={download}>
      {busy ? <span className="spinner" /> : `📅 ${label}`}
    </button>
  );
}
