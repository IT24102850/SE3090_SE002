import { useState } from 'react';
import { useGetNotificationsQuery, useGetUnreadNotificationCountQuery, useMarkNotificationReadMutation } from '../../api/bookingApi';

// FR-C11/FR-AS21: in-app notification center (booking confirmations,
// reminders, cancellations, workflow-approval pings). There's no
// Firebase/APNs credential in this project, so this is genuinely in-app —
// polled on open, not real device push.
export default function NotificationBell() {
  const [open, setOpen] = useState(false);
  const { data: countData } = useGetUnreadNotificationCountQuery(undefined, { pollingInterval: 60000 });
  const { data, isLoading } = useGetNotificationsQuery(undefined, { skip: !open });
  const [markRead] = useMarkNotificationReadMutation();

  const unread = countData?.count ?? 0;

  const handleOpen = () => setOpen((v) => !v);

  const handleItemClick = (id: string, isRead: boolean) => {
    if (!isRead) markRead(id);
  };

  return (
    <div style={{ position: 'relative' }}>
      <button className="btn btn-ghost btn-sm" onClick={handleOpen} aria-label="Notifications" style={{ position: 'relative' }}>
        🔔
        {unread > 0 && (
          <span
            style={{
              position: 'absolute', top: -4, right: -4, minWidth: 16, height: 16, borderRadius: 8,
              background: 'var(--color-critical)', color: '#fff', fontSize: 10, fontWeight: 700,
              display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 3px',
            }}
          >
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      {open && (
        <>
          <div style={{ position: 'fixed', inset: 0, zIndex: 40 }} onClick={() => setOpen(false)} />
          <div
            className="card"
            style={{
              position: 'absolute', right: 0, top: '110%', width: 320, maxHeight: 400, overflowY: 'auto',
              zIndex: 50, padding: 0,
            }}
          >
            <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--color-border)', fontWeight: 700, fontSize: 13 }}>
              Notifications
            </div>
            {isLoading ? (
              <div className="loading-row"><span className="spinner spinner-dark" /></div>
            ) : !data || data.items.length === 0 ? (
              <div className="empty-state" style={{ padding: 20 }}>Nothing yet.</div>
            ) : (
              data.items.map((n) => (
                <div
                  key={n.id}
                  onClick={() => handleItemClick(n.id, n.isRead)}
                  style={{
                    padding: '10px 14px', borderBottom: '1px solid var(--color-border)', cursor: 'pointer',
                    background: n.isRead ? 'transparent' : 'var(--color-primary-soft, #eff6ff)',
                  }}
                >
                  <div style={{ fontWeight: 600, fontSize: 13 }}>{n.title}</div>
                  <div style={{ fontSize: 12, color: 'var(--color-text-secondary)', marginTop: 2 }}>{n.message}</div>
                  <div style={{ fontSize: 11, color: 'var(--color-text-muted)', marginTop: 4 }}>
                    {new Date(n.createdAt).toLocaleString()}
                  </div>
                </div>
              ))
            )}
          </div>
        </>
      )}
    </div>
  );
}
