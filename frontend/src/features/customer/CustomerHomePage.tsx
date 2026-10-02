import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useGetBookingsQuery, useGetNotificationsQuery, useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { addDays, formatDateTime, toISODate } from '../../shared/dateUtils';
import type { Booking } from '../booking/types';
import { BookingCard, CheckInQr, isUpcoming } from './customerShared';

/* The customer's home - what the Flutter app opens on after sign-in: the
 * business they belong to, their next booking with its check-in code one
 * tap away, quick actions (book, my bookings, AI planner, business info),
 * recent bookings and the latest notifications. */

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export default function CustomerHomePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const { data: profile } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const today = useMemo(() => new Date(), []);
  const { data: bookings, isLoading } = useGetBookingsQuery({ tenantId, dateFrom: toISODate(addDays(today, -60)), dateTo: toISODate(addDays(today, 120)), pageSize: 200 }, { skip: !tenantId });
  const { data: notifications } = useGetNotificationsQuery();
  const [qrFor, setQrFor] = useState<Booking | null>(null);

  const items = bookings?.items ?? [];
  const upcoming = items.filter((b) => isUpcoming(b)).sort((a, b) => a.startTime.localeCompare(b.startTime));
  const next = upcoming[0];
  const recent = items.filter((b) => !isUpcoming(b)).sort((a, b) => b.startTime.localeCompare(a.startTime)).slice(0, 4);

  const todayHours = profile?.businessHours.find((h) => h.dayOfWeek === DAYS[today.getDay()]);
  const firstName = (user?.fullName ?? '').split(' ')[0];

  return (
    <div className="cust-page">
      <section className="cust-home-hero" aria-labelledby="cust-home-title">
        <div className="cust-home-hero-orbit" aria-hidden="true" />
        <div className="cust-home-top">
          <div className="cust-home-intro">
            <span className="cust-home-eyebrow"><i aria-hidden="true" /> YOUR CUSTOMER SPACE</span>
            <h1 id="cust-home-title">{firstName ? `Welcome back, ${firstName}` : 'Welcome back'}</h1>
            <p>Your appointments and orders{tenant?.name ? ` with ${tenant.name}` : ''}, all in one place.</p>
            {todayHours && (
              <span className={`cust-home-hours${todayHours.isClosed ? ' is-closed' : ''}`}>
                <i aria-hidden="true" />
                {todayHours.isClosed ? 'Closed today' : `Open today ${todayHours.openTime} – ${todayHours.closeTime}`}
              </span>
            )}
          </div>
          <div className="cust-home-actions">
            <Link className="cust-home-action cust-home-action-primary" to="/book"><span aria-hidden="true">＋</span> Book a service</Link>
            <Link className="cust-home-action" to="/shop"><span aria-hidden="true">🛍️</span> Browse items</Link>
            <Link className="cust-home-action cust-home-action-quiet" to="/my-bookings">My bookings <span aria-hidden="true">→</span></Link>
          </div>
        </div>
        <div className="cust-home-stats">
          <div className="cust-home-stat">
            <div className="cust-home-stat-label">Upcoming bookings</div>
            <div className="cust-home-stat-value">{isLoading ? '…' : upcoming.length}</div>
            <div className="cust-home-stat-sub">Your scheduled visits</div>
          </div>
          <div className="cust-home-stat">
            <div className="cust-home-stat-label">Next appointment</div>
            <div className="cust-home-stat-value is-date">{next ? formatDateTime(next.startTime) : '—'}</div>
            <div className="cust-home-stat-sub">{next ? next.bookingTypeName : 'Nothing scheduled yet'}</div>
          </div>
          <div className="cust-home-stat">
            <div className="cust-home-stat-label">Awaiting confirmation</div>
            <div className="cust-home-stat-value">{isLoading ? '…' : upcoming.filter((b) => b.status === 'Pending').length}</div>
            <div className="cust-home-stat-sub">Booking requests in progress</div>
          </div>
          <div className="cust-home-stat">
            <div className="cust-home-stat-label">Completed visits</div>
            <div className="cust-home-stat-value">{isLoading ? '…' : items.filter((b) => b.status === 'Completed').length}</div>
            <div className="cust-home-stat-sub">Your visit history</div>
          </div>
        </div>
      </section>

      <div className="cust-quick">
        <Link to="/book"><span className="cust-quick-icon" aria-hidden="true">📅</span><span><strong>Book a service</strong><span>Pick a service, a time and confirm</span></span></Link>
        <Link to="/my-bookings"><span className="cust-quick-icon" aria-hidden="true">🎟️</span><span><strong>My bookings</strong><span>Check-in codes, reschedule, cancel</span></span></Link>
        <Link to="/shop"><span className="cust-quick-icon" aria-hidden="true">🛍️</span><span><strong>Shop items</strong><span>Browse products and view your orders</span></span></Link>
        <Link to="/ai-planner"><span className="cust-quick-icon" aria-hidden="true">🤖</span><span><strong>AI planner</strong><span>“Find me the earliest slot this week”</span></span></Link>
        <Link to="/business"><span className="cust-quick-icon" aria-hidden="true">🏪</span><span><strong>{tenant?.name ?? 'The business'}</strong><span>Hours, contact, gallery</span></span></Link>
      </div>

      <div className="cust-grid">
        <section className="card chart-card">
          <p className="chart-title">Next up</p>
          <p className="chart-subtitle">Your upcoming bookings, soonest first</p>
          {isLoading ? (
            <div className="loading-row"><span className="spinner spinner-dark" /></div>
          ) : upcoming.length === 0 ? (
            <div className="cust-empty">Nothing booked yet. <Link to="/book">Make your first booking</Link>.</div>
          ) : (
            <div className="cust-list">
              {upcoming.slice(0, 5).map((b, i) => (
                <BookingCard key={b.id} booking={b} highlight={i === 0} actions={<button type="button" className="btn btn-secondary" onClick={() => setQrFor(b)}>Check-in code</button>} />
              ))}
              {upcoming.length > 5 && <Link className="btn btn-ghost btn-sm" to="/my-bookings">See all {upcoming.length}</Link>}
            </div>
          )}
        </section>

        <div style={{ display: 'grid', gap: 18, alignContent: 'start' }}>
          <section className="card chart-card">
            <p className="chart-title">Recent</p>
            <p className="chart-subtitle">Book the same again in one click</p>
            {recent.length === 0 ? (
              <div className="cust-empty">No past bookings yet.</div>
            ) : (
              <div className="cust-list">
                {recent.map((b) => (
                  <BookingCard key={b.id} booking={b} actions={<Link className="btn btn-secondary" to={`/book?type=${b.bookingTypeId}&resource=${b.resourceId}`}>Book again</Link>} />
                ))}
              </div>
            )}
          </section>

          <section className="card chart-card">
            <p className="chart-title">Notifications</p>
            <p className="chart-subtitle">Confirmations, reminders and changes</p>
            {(notifications?.items.length ?? 0) === 0 ? (
              <div className="cust-empty">Nothing new.</div>
            ) : (
              <div className="cust-requests">
                {notifications!.items.slice(0, 5).map((n) => (
                  <div key={n.id} className="cust-request" style={{ opacity: n.isRead ? 0.7 : 1 }}>
                    <div><strong>{n.title}</strong><span>{n.message}</span></div>
                    <span>{formatDateTime(n.createdAt).replace(/,.*$/, '')}</span>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>

      {qrFor && (
        <>
          <button type="button" className="cust-scrim" aria-label="Close" onClick={() => setQrFor(null)} />
          <div className="cust-modal" role="dialog" aria-label="Check-in code" style={{ width: 'min(420px, calc(100vw - 32px))' }}>
            <CheckInQr bookingId={qrFor.id} resourceName={qrFor.resourceName} />
            <div className="cust-modal-foot"><button type="button" className="btn btn-primary" onClick={() => setQrFor(null)}>Done</button></div>
          </div>
        </>
      )}
    </div>
  );
}
