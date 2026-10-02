import { useEffect, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import {
  useGetNotificationsQuery,
  useGetUnreadNotificationCountQuery,
  useMarkNotificationReadMutation,
} from '../../api/bookingApi';
import { useToast } from './Toast';
import type { RootState } from '../../store/store';

const NOTIFICATION_POLL_INTERVAL = 15000;

function relativeTime(value: string) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) return 'Recently';
  const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ago`;
  return `${Math.floor(minutes / 1440)}d ago`;
}

function notificationIcon(type: string) {
  const value = type.toLowerCase();
  if (value.includes('booking')) return '◷';
  if (value.includes('inventory') || value.includes('stock')) return '▦';
  if (value.includes('payment') || value.includes('bill')) return '¤';
  if (value.includes('approval')) return '✓';
  if (value.includes('cancel')) return '×';
  return '✦';
}

export default function NotificationBell() {
  const { user } = useSelector((state: RootState) => state.auth);
  const isCustomer = user?.role === 'Customer';
  const [open, setOpen] = useState(false);
  const [freshIds, setFreshIds] = useState<Set<string>>(() => new Set());
  const seenIds = useRef<Set<string> | null>(null);
  const freshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { show } = useToast();
  const { data: countData } = useGetUnreadNotificationCountQuery(undefined, {
    pollingInterval: NOTIFICATION_POLL_INTERVAL,
  });
  const {
    data,
    isLoading,
    isFetching,
    error,
  } = useGetNotificationsQuery(undefined, {
    pollingInterval: NOTIFICATION_POLL_INTERVAL,
  });
  const [markRead, { isLoading: isMarkingRead }] = useMarkNotificationReadMutation();
  const unread = countData?.count ?? 0;

  useEffect(() => {
    if (!data) return;
    const currentIds = new Set(data.items.map((notification) => notification.id));
    const previousIds = seenIds.current;
    seenIds.current = currentIds;
    if (!previousIds) return;

    const newNotifications = data.items.filter(
      (notification) => !notification.isRead && !previousIds.has(notification.id),
    );
    if (newNotifications.length === 0) return;

    setFreshIds(new Set(newNotifications.map((notification) => notification.id)));
    if (freshTimer.current) clearTimeout(freshTimer.current);
    freshTimer.current = setTimeout(() => setFreshIds(new Set()), 5000);
    const headline = newNotifications[0].title || 'New notification';
    show(
      newNotifications.length === 1
        ? `New update: ${headline}`
        : `${newNotifications.length} new updates. Open Notifications to review them.`,
      'info',
    );
  }, [data, show]);

  useEffect(() => () => {
    if (freshTimer.current) clearTimeout(freshTimer.current);
  }, []);

  const handleMarkRead = async (id: string) => {
    try {
      await markRead(id).unwrap();
    } catch {
      show('Could not mark this update as read. Please try again.', 'error');
    }
  };

  return (
    <div className="notification-center">
      <button
        className={`notification-trigger${unread > 0 ? ' has-unread' : ''}${freshIds.size > 0 ? ' has-new' : ''}`}
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-label={`Notifications${unread ? `, ${unread} unread` : ''}`}
        aria-expanded={open}
      >
        <span className="notification-bell-glyph" aria-hidden="true">🔔</span>
        <small>Updates</small>
        {unread > 0 && <b key={unread}>{unread > 9 ? '9+' : unread}</b>}
      </button>
      {open && (
        <>
          <button
            className="notification-scrim"
            type="button"
            aria-label="Close notifications"
            onClick={() => setOpen(false)}
          />
          <section className="notification-panel" aria-label="Notifications">
            <header className="notification-panel-header">
              <div>
                <span>{isCustomer ? 'YOUR UPDATES' : 'WORKSPACE PULSE'}</span>
                <h2>Notifications</h2>
              </div>
              <div className="notification-panel-header-actions">
                <span className="notification-live-indicator">
                  <i className={isFetching ? 'is-syncing' : ''} />
                  {isFetching ? 'Syncing' : 'Live · 15s'}
                </span>
                {unread > 0 && <span className="notification-unread-total">{unread} unread</span>}
                <button type="button" onClick={() => setOpen(false)} aria-label="Close notifications">×</button>
              </div>
            </header>
            {isLoading ? (
              <div className="notification-loading">
                <span className="spinner spinner-dark" />
                Loading your updates…
              </div>
            ) : error ? (
              <div className="notification-empty is-error" role="alert">
                <i>!</i>
                <strong>Updates are temporarily unavailable.</strong>
                <span>We’ll try again automatically.</span>
              </div>
            ) : !data || data.items.length === 0 ? (
              <div className="notification-empty">
                <i>✓</i>
                <strong>You’re all caught up.</strong>
                <span>{isCustomer ? 'Booking and order updates for you will appear here.' : 'New workspace updates will appear here automatically.'}</span>
              </div>
            ) : (
              <div className="notification-list">
                {data.items.map((notification) => (
                  <button
                    className={`notification-item${notification.isRead ? '' : ' is-unread'}${freshIds.has(notification.id) ? ' is-new' : ''}`}
                    type="button"
                    key={notification.id}
                    onClick={() => {
                      if (!notification.isRead && !isMarkingRead) void handleMarkRead(notification.id);
                    }}
                    disabled={isMarkingRead && !notification.isRead}
                    aria-label={`${notification.isRead ? '' : 'Unread: '}${notification.title}. ${notification.message}`}
                  >
                    <i aria-hidden="true">{notificationIcon(notification.type)}</i>
                    <span>
                      <strong>{notification.title}</strong>
                      <small>{notification.message}</small>
                      <time>{relativeTime(notification.createdAt)}</time>
                    </span>
                    {!notification.isRead && <em>{freshIds.has(notification.id) ? 'Just in' : 'New'}</em>}
                  </button>
                ))}
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}
