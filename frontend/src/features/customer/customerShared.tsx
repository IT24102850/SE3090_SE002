import type { ReactNode } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { parseTicketBreakdown, parseWaiver, type Booking, type BookingType, type Resource } from '../booking/types';
import { STATUS_COLORS } from '../booking/types';
import { formatDateTime, formatTime } from '../../shared/dateUtils';
import './customer.css';

/* Pieces shared by the customer-side pages - the same vocabulary the
 * Flutter customer screens use: a booking card, the check-in QR (the raw
 * booking id, which PUT /bookings/{id}/checkin scans), a price line, and
 * the status badge in customer words. */

/** What a booking costs, in the same order of precedence the mobile flow
 *  uses: a published base price on the booking type (per person when the
 *  config says so), else the resource's hourly rate over the duration, else
 *  nothing - the business confirms the price. */
export function priceFor(type: BookingType | undefined, resource: Resource | undefined, minutes: number, attendees: number): { amount: number; perPerson: boolean } | null {
  if (type?.configJson) {
    try {
      const cfg = JSON.parse(type.configJson) as { basePrice?: { amount?: number; per?: string } };
      const amount = cfg.basePrice?.amount;
      if (typeof amount === 'number' && amount >= 0) {
        const perPerson = cfg.basePrice?.per === 'cover' || cfg.basePrice?.per === 'person' || cfg.basePrice?.per === 'pax';
        return { amount: perPerson ? amount * Math.max(1, attendees) : amount, perPerson };
      }
    } catch {
      // Malformed config: fall through to the hourly rate.
    }
  }
  if (resource?.hourlyRate != null && minutes > 0) return { amount: Math.round((resource.hourlyRate * minutes) / 60), perPerson: false };
  return null;
}

export function money(amount: number, currency = 'LKR'): string {
  return amount === 0 ? 'Free' : `${currency} ${Math.round(amount).toLocaleString()}`;
}

const CUSTOMER_STATUS: Partial<Record<Booking['status'], string>> = {
  Pending: 'Awaiting approval',
  PendingPayment: 'Payment pending',
  Confirmed: 'Confirmed',
  CheckedIn: 'Checked in',
  InProgress: 'In progress',
  Completed: 'Completed',
  Cancelled: 'Cancelled',
  NoShow: 'Missed',
  Rejected: 'Declined',
  WeatherCancelled: 'Cancelled (weather)',
  Expired: 'Payment expired',
};

export function StatusBadge({ status }: { status: Booking['status'] }) {
  const tone = STATUS_COLORS[status]?.tone ?? 'neutral';
  return <span className={`badge badge-${tone}`}><span className="badge-dot" />{CUSTOMER_STATUS[status] ?? status}</span>;
}

export function isUpcoming(b: Booking, now = new Date()): boolean {
  return new Date(b.endTime) >= now && b.status !== 'Cancelled' && b.status !== 'Rejected' && b.status !== 'NoShow' && b.status !== 'WeatherCancelled' && b.status !== 'Completed' && b.status !== 'Expired';
}

export function CheckInQr({ bookingId, resourceName, size = 180 }: { bookingId: string; resourceName?: string; size?: number }) {
  return (
    <div className="cust-qr">
      <div className="cust-qr-frame"><QRCodeSVG value={bookingId} size={size} level="M" /></div>
      <p className="cust-qr-title">{resourceName ? `${resourceName} check-in` : 'Check-in code'}</p>
      <p className="cust-qr-sub">Show this to reception on arrival. Code <code>{bookingId.slice(0, 8)}</code></p>
    </div>
  );
}

export function BookingCard({ booking, actions, highlight }: { booking: Booking; actions?: ReactNode; highlight?: boolean }) {
  const start = new Date(booking.startTime);
  const end = new Date(booking.endTime);
  const durationMinutes = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
  const duration = durationMinutes >= 60
    ? `${Math.floor(durationMinutes / 60)}h${durationMinutes % 60 ? ` ${durationMinutes % 60}m` : ''}`
    : `${durationMinutes}m`;
  const tickets = parseTicketBreakdown(booking.ticketBreakdown);
  const waiver = parseWaiver(booking.waiver);

  return (
    <article className={`cust-booking${highlight ? ' cust-booking-next' : ''}`}>
      <div className="cust-booking-when">
        <b>{start.toLocaleDateString(undefined, { day: 'numeric' })}</b>
        <span>{start.toLocaleDateString(undefined, { month: 'short' })}</span>
        <small>{formatTime(booking.startTime)}</small>
      </div>
      <div className="cust-booking-main">
        <strong><i style={{ background: booking.colorHex || 'var(--color-primary)' }} aria-hidden="true" />{booking.bookingTypeName}</strong>
        <span className="cust-booking-date">{start.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}</span>
        <span>{booking.resourceName} · {formatTime(booking.startTime)} – {formatTime(booking.endTime)} · {duration}</span>
        <div className="cust-booking-details" aria-label="Booking details">
          <span>👥 {booking.attendeeCount && booking.attendeeCount > 1 ? `${booking.attendeeCount} guests` : '1 guest'}</span>
          <span>🔖 {booking.id.slice(0, 8).toUpperCase()}</span>
          {booking.source && <span>📱 {booking.source}</span>}
        </div>
        {tickets.length > 0 && (
          <div className="cust-booking-tickets">
            {tickets.map((ticket) => <span key={ticket.type}>{ticket.type} × {ticket.qty}</span>)}
          </div>
        )}
        {booking.notes && <span className="cust-booking-notes">“{booking.notes}”</span>}
        <span className="cust-booking-meta">
          <StatusBadge status={booking.status} />
          {booking.totalCost != null && <em>{money(booking.totalCost)}</em>}
          {booking.checkInAt && <em>Arrived {formatTime(booking.checkInAt)}</em>}
          {waiver?.signedAt && <em>Waiver signed</em>}
        </span>
      </div>
      {actions && <div className="cust-booking-actions">{actions}</div>}
    </article>
  );
}

export function whenLabel(iso: string): string {
  return formatDateTime(iso);
}
