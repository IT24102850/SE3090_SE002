import { useState } from 'react';
import { useGetNotificationsQuery, useGetUnreadNotificationCountQuery, useMarkNotificationReadMutation } from '../../api/bookingApi';
import { useNotificationStream } from '../useNotificationStream';
import { useToast } from './Toast';

function relativeTime(value: string) {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ago`;
  return `${Math.floor(minutes / 1440)}d ago`;
}

/* In-app centre for booking confirmations, reminders, cancellations and
 * workflow updates.
 *
 * Live for real: an open Server-Sent Events connection pushes each
 * notification the moment its row commits, wherever it was raised - this tab,
 * another member of staff, a customer's phone, or one of the agents. The event
 * invalidates the Notification tags, so the badge and the list are still
 * served by the REST endpoints and remain the source of truth.
 *
 * The polls below are now a safety net rather than the mechanism, and are
 * deliberately slow: they cover the seconds between losing the connection and
 * the reconnect succeeding. They pause while the tab is in the background, so
 * an unattended dashboard is not requesting all night, and a tab returning to
 * focus refetches at once instead of waiting out an interval. */
const COUNT_POLL_MS = 120_000;
const LIST_POLL_MS = 120_000;

export default function NotificationBell() {
  const [open, setOpen] = useState(false);
  const { show } = useToast();
  // Arriving notifications refresh the cache; the toast is so a manager
  // watching another part of the screen still notices.
  const streamStatus = useNotificationStream((n) => show(n.title, 'info'));
  const { data: countData } = useGetUnreadNotificationCountQuery(undefined, {
    pollingInterval: COUNT_POLL_MS,
    skipPollingIfUnfocused: true,
    refetchOnFocus: true,
    refetchOnReconnect: true,
  });
  const { data, isLoading } = useGetNotificationsQuery(undefined, {
    skip: !open && !countData?.count,
    pollingInterval: open ? LIST_POLL_MS : 0,
    skipPollingIfUnfocused: true,
    refetchOnFocus: true,
    refetchOnReconnect: true,
    refetchOnMountOrArgChange: true,
  });
  const [markRead] = useMarkNotificationReadMutation();
  const unread = countData?.count ?? 0;

  return <div className="notification-center" data-live={streamStatus}>
    <button className={`notification-trigger${unread > 0 ? ' has-unread' : ''}`} type="button" onClick={() => setOpen((value) => !value)} aria-label={`Notifications${unread ? `, ${unread} unread` : ''}`} aria-expanded={open}>
      <span aria-hidden="true">🔔</span><small>Updates</small>{unread > 0 && <b>{unread > 9 ? '9+' : unread}</b>}
    </button>
    {open && <><button className="notification-scrim" type="button" aria-label="Close notifications" onClick={() => setOpen(false)} />
      <section className="notification-panel" aria-label="Notifications">
        <header><div><span>WORKSPACE PULSE</span><h2>Notifications</h2></div><button type="button" onClick={() => setOpen(false)} aria-label="Close notifications">×</button></header>
        {isLoading ? <div className="notification-loading"><span className="spinner spinner-dark" /> Loading your updates…</div>
          : !data || data.items.length === 0 ? <div className="notification-empty"><i>✓</i><strong>You’re all caught up.</strong><span>New booking, team and workflow updates will appear here.</span></div>
          : <div className="notification-list">{data.items.map((notification) => <button className={`notification-item${notification.isRead ? '' : ' is-unread'}`} type="button" key={notification.id} onClick={() => { if (!notification.isRead) markRead(notification.id); }}>
            <i aria-hidden="true">{notification.isRead ? '•' : '✦'}</i><span><strong>{notification.title}</strong><small>{notification.message}</small><time>{relativeTime(notification.createdAt)}</time></span>{!notification.isRead && <em>New</em>}
          </button>)}</div>}
      </section>
    </>}
  </div>;
}
