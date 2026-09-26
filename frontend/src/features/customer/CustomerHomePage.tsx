import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { useGetBookingsQuery, useGetNotificationsQuery, useGetTenantProfileQuery, useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { businessDescriptor, businessHeroImage } from '../../shared/businessImagery';
import BusinessAvatar from '../../shared/components/BusinessAvatar';
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
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const { data: profile } = useGetTenantProfileQuery({ tenantId }, { skip: !tenantId });
  const today = useMemo(() => new Date(), []);
  const { data: bookings, isLoading } = useGetBookingsQuery({ tenantId, dateFrom: toISODate(addDays(today, -60)), dateTo: toISODate(addDays(today, 120)), pageSize: 200 }, { skip: !tenantId, ...LIVE_OPTS });
  const { data: notifications } = useGetNotificationsQuery(undefined, LIVE_OPTS);
  const [qrFor, setQrFor] = useState<Booking | null>(null);

  const items = bookings?.items ?? [];
  const upcoming = items.filter((b) => isUpcoming(b)).sort((a, b) => a.startTime.localeCompare(b.startTime));
  const next = upcoming[0];
  const recent = items.filter((b) => !isUpcoming(b)).sort((a, b) => b.startTime.localeCompare(a.startTime)).slice(0, 4);

  const heroImage = businessHeroImage({ businessType: tenant?.businessType, subType: tenant?.subType, coverImageUrl: profile?.coverImageUrl });
  const descriptor = businessDescriptor({ businessType: tenant?.businessType, subType: tenant?.subType });
  const todayHours = profile?.businessHours.find((h) => h.dayOfWeek === DAYS[today.getDay()]);
  const firstName = (user?.fullName ?? '').split(' ')[0];

  return (
    <div className="cust-page">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant?.name} src={profile?.logoUrl} />
              <div>
                <p className="hero-eyebrow">{descriptor}</p>
                <h1 className="hero-title">{firstName ? `Hi ${firstName}` : 'Welcome'}</h1>
                <p className="hero-sub">{tenant?.name ?? 'Your business'}{profile?.shortTagline ? ` · ${profile.shortTagline}` : ''}</p>
                <p className="hero-sub" style={{ marginTop: 4 }}>
                  {todayHours ? (todayHours.isClosed ? 'Closed today' : `Open today ${todayHours.openTime} – ${todayHours.closeTime}`) : ''}
                </p>
              </div>
            </div>
            <div className="cust-hero-actions">
              <Link className="btn btn-primary" to="/book">+ New booking</Link>
              <Link className="btn btn-secondary" to="/my-bookings">My bookings</Link>
            </div>
          </div>
          <div className="hero-tiles">
            <div className="hero-tile"><div className="hero-tile-label">Upcoming</div><div className="hero-tile-value">{isLoading ? '…' : upcoming.length}</div><div className="hero-tile-sub">bookings ahead</div></div>
            <div className="hero-tile"><div className="hero-tile-label">Next</div><div className="hero-tile-value" style={{ fontSize: '1.1rem' }}>{next ? formatDateTime(next.startTime) : '—'}</div><div className="hero-tile-sub">{next ? next.bookingTypeName : 'nothing booked yet'}</div></div>
            <div className="hero-tile"><div className="hero-tile-label">Awaiting approval</div><div className="hero-tile-value">{isLoading ? '…' : upcoming.filter((b) => b.status === 'Pending').length}</div><div className="hero-tile-sub">the business decides</div></div>
            <div className="hero-tile"><div className="hero-tile-label">Visits</div><div className="hero-tile-value">{isLoading ? '…' : items.filter((b) => b.status === 'Completed').length}</div><div className="hero-tile-sub">completed so far</div></div>
          </div>
        </div>
      </section>

      <div className="cust-quick">
        <Link to="/book"><span className="cust-quick-icon" aria-hidden="true">📅</span><span><strong>Book a service</strong><span>Pick a service, a time and confirm</span></span></Link>
        <Link to="/my-bookings"><span className="cust-quick-icon" aria-hidden="true">🎟️</span><span><strong>My bookings</strong><span>Check-in codes, reschedule, cancel</span></span></Link>
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
