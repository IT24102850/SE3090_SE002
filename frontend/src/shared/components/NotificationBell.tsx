import { useState } from 'react';
import { useGetNotificationsQuery, useGetUnreadNotificationCountQuery, useMarkNotificationReadMutation } from '../../api/bookingApi';

function relativeTime(value: string) {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ago`;
  return `${Math.floor(minutes / 1440)}d ago`;
}

// In-app centre for booking confirmations, reminders, cancellations and
// workflow updates. The panel is intentionally loaded only once opened.
export default function NotificationBell() {
  const [open, setOpen] = useState(false);
  const { data: countData } = useGetUnreadNotificationCountQuery(undefined, { pollingInterval: 60000 });
  const { data, isLoading } = useGetNotificationsQuery(undefined, { skip: !open });
  const [markRead] = useMarkNotificationReadMutation();
  const unread = countData?.count ?? 0;

  return <div className="notification-center">
    <button className={`notification-trigger${unread > 0 ? ' has-unread' : ''}`} type="button" onClick={() => setOpen((value) => !value)} aria-label={`Notifications${unread ? `, ${unread} unread` : ''}`} aria-expanded={open}>
      <span aria-hidden="true">♢</span><small>Updates</small>{unread > 0 && <b>{unread > 9 ? '9+' : unread}</b>}
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
