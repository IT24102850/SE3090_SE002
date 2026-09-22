import type { ReactNode } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import type { Booking, BookingType, Resource } from '../booking/types';
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
  Confirmed: 'Confirmed',
  CheckedIn: 'Checked in',
  InProgress: 'In progress',
  Completed: 'Completed',
  Cancelled: 'Cancelled',
  NoShow: 'Missed',
  Rejected: 'Declined',
  WeatherCancelled: 'Cancelled (weather)',
};

export function StatusBadge({ status }: { status: Booking['status'] }) {
  const tone = STATUS_COLORS[status]?.tone ?? 'neutral';
  return <span className={`badge badge-${tone}`}><span className="badge-dot" />{CUSTOMER_STATUS[status] ?? status}</span>;
}

export function isUpcoming(b: Booking, now = new Date()): boolean {
  return new Date(b.endTime) >= now && b.status !== 'Cancelled' && b.status !== 'Rejected' && b.status !== 'NoShow' && b.status !== 'WeatherCancelled' && b.status !== 'Completed';
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
  return (
    <article className={`cust-booking${highlight ? ' cust-booking-next' : ''}`}>
      <div className="cust-booking-when">
        <b>{new Date(booking.startTime).toLocaleDateString(undefined, { day: 'numeric' })}</b>
        <span>{new Date(booking.startTime).toLocaleDateString(undefined, { month: 'short' })}</span>
        <small>{formatTime(booking.startTime)}</small>
      </div>
      <div className="cust-booking-main">
        <strong><i style={{ background: booking.colorHex || 'var(--color-primary)' }} aria-hidden="true" />{booking.bookingTypeName}</strong>
        <span>{booking.resourceName} · {formatTime(booking.startTime)} – {formatTime(booking.endTime)}{booking.attendeeCount && booking.attendeeCount > 1 ? ` · ${booking.attendeeCount} people` : ''}</span>
        {booking.notes && <span className="cust-booking-notes">“{booking.notes}”</span>}
        <span className="cust-booking-meta"><StatusBadge status={booking.status} />{booking.totalCost != null && booking.totalCost > 0 && <em>{money(booking.totalCost)}</em>}{booking.checkInAt && <em>arrived {formatTime(booking.checkInAt)}</em>}</span>
      </div>
      {actions && <div className="cust-booking-actions">{actions}</div>}
    </article>
  );
}

export function whenLabel(iso: string): string {
  return formatDateTime(iso);
}
