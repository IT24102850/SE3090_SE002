import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useGetBookingsQuery, useGetNotificationsQuery, useGetTenantProfileQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { addDays, formatDateTime, toISODate } from '../../shared/dateUtils';
import type { Booking } from '../booking/types';
import { BookingCard, CheckInQr, isUpcoming } from './customerShared';

/* The customer's home - what the Flutter app opens on after sign-in: the
 * business they belong to, their next booking with its check-in code one
 * tap away, quick actions (book, my bookings, AI planner, business info),
 * recent bookings and the latest notifications. */

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/* "Next up" and "Notifications" are the two cards that go stale on their
 * own: the business confirms, moves or cancels a booking from the admin
 * side and this page knows nothing about it. Both refresh on a timer and
 * again when the tab is focused, so a customer who leaves the page open is
 * not looking at yesterday's answer. */
const LIVE_POLL_MS = 30_000;
const LIVE_OPTS = { pollingInterval: LIVE_POLL_MS, skipPollingIfUnfocused: true, refetchOnFocus: true, refetchOnReconnect: true } as const;

export default function CustomerHomePage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { data: profile } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const today = useMemo(() => new Date(), []);
  // Customer bookings are account-wide. Leaving tenantId out lets the
  // backend resolve all memberships for this authenticated customer, rather
  // than showing only bookings from the currently selected business.
  const { data: bookings, isLoading } = useGetBookingsQuery({ dateFrom: toISODate(addDays(today, -60)), dateTo: toISODate(addDays(today, 120)), pageSize: 200 }, { skip: !user?.id, ...LIVE_OPTS });
  const { data: notifications } = useGetNotificationsQuery(undefined, LIVE_OPTS);
  const [qrFor, setQrFor] = useState<Booking | null>(null);

  const items = bookings?.items ?? [];
  const upcoming = items.filter((b) => isUpcoming(b)).sort((a, b) => a.startTime.localeCompare(b.startTime));
  const next = upcoming[0];
  const recent = items.filter((b) => !isUpcoming(b)).sort((a, b) => b.startTime.localeCompare(a.startTime)).slice(0, 4);

  const todayHours = profile?.businessHours.find((h) => h.dayOfWeek === DAYS[today.getDay()]);
  const firstName = (user?.fullName ?? '').split(' ')[0];

  return (
    <div className="cust-page">
      <section className="cust-home-hero cust-flutter-hero" aria-labelledby="cust-home-title">
        <div className="cust-home-hero-orbit" aria-hidden="true" />
        <div className="cust-home-top">
          <div className="cust-home-intro">
            <div className="cust-profile-row">
              {user?.profilePictureUrl ? (
                <img className="cust-profile-avatar" src={user.profilePictureUrl} alt="" />
              ) : (
                <span className="cust-profile-avatar cust-profile-initials" aria-hidden="true">
                  {(user?.fullName || '?').trim().charAt(0).toUpperCase()}
                </span>
              )}
              <div>
                <span className="cust-home-eyebrow"><i aria-hidden="true" /> WELCOME BACK</span>
                <h1 id="cust-home-title">{firstName || user?.fullName || 'Customer'}</h1>
                <p>{user?.email || 'Your Unify customer account'}</p>
              </div>
            </div>
            <span className="cust-role-pill">◉ Customer</span>
            {todayHours && (
              <span className={`cust-home-hours${todayHours.isClosed ? ' is-closed' : ''}`}>
                <i aria-hidden="true" />
                {todayHours.isClosed ? 'Closed today' : `Open today ${todayHours.openTime} – ${todayHours.closeTime}`}
              </span>
            )}
          </div>
          <div className="cust-home-actions">
            <Link className="cust-home-action cust-home-action-primary" to="/book"><span aria-hidden="true">＋</span> Book now</Link>
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

      <section className="cust-dashboard-section">
        <div className="cust-section-heading"><div><span className="cust-section-kicker">YOUR SPACE</span><h2>Quick actions</h2></div><span>Tap to continue</span></div>
        <div className="cust-quick">
          <Link to="/book"><span className="cust-quick-icon" aria-hidden="true">📅</span><span><strong>Appointments</strong><span>Book a service</span></span></Link>
          <Link to="/my-bills"><span className="cust-quick-icon" aria-hidden="true">💳</span><span><strong>Payments</strong><span>View your bills</span></span></Link>
          <Link to="/shop"><span className="cust-quick-icon" aria-hidden="true">🛍️</span><span><strong>Shop</strong><span>Browse items</span></span></Link>
          <Link to="/ai-planner"><span className="cust-quick-icon" aria-hidden="true">✨</span><span><strong>Ask AI</strong><span>Book with AI</span></span></Link>
          <Link to="/find-business"><span className="cust-quick-icon" aria-hidden="true">🔎</span><span><strong>Find a business</strong><span>Explore services</span></span></Link>
          <Link to="/customer-subscriptions"><span className="cust-quick-icon" aria-hidden="true">🔁</span><span><strong>Subscriptions</strong><span>Manage memberships</span></span></Link>
        </div>
      </section>

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
