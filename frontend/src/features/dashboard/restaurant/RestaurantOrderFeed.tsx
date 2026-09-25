import { useMemo, useState } from 'react';
import { useUpdateBookingStatusMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import { STATUS_COLORS, type RestaurantLive, type RestaurantOrder, type RestaurantStage } from '../../booking/types';
import { STATUS_LABEL } from './RestaurantCharts';
import { formatMinutes, formatMoney } from './restaurantReport';

/* Today's order feed, new to served.
 *
 * The stage tiles are the glance; the table is the queue the desk and the
 * pass work from. Every row carries the one action that moves the order
 * to the next stage - accept, start prep, ready, served / delivered - so
 * the board drives the flow as well as showing it. The parent polls the
 * endpoint, so an order accepted on the mobile app lands here within the
 * minute, and a status change here invalidates the Booking tag so the
 * KPIs and the kitchen panel follow. */

const STAGES: { id: RestaurantStage; label: string; color: string; sub: string }[] = [
  { id: 'new', label: 'New', color: STATUS_COLORS.Pending.bg, sub: 'awaiting acceptance' },
  { id: 'accepted', label: 'Accepted', color: STATUS_COLORS.Confirmed.bg, sub: 'queued for the kitchen' },
  { id: 'preparing', label: 'Preparing', color: STATUS_COLORS.CheckedIn.bg, sub: 'in the kitchen' },
  { id: 'ready', label: 'Ready', color: STATUS_COLORS.InProgress.bg, sub: 'serving / out for delivery' },
  { id: 'completed', label: 'Completed', color: STATUS_COLORS.Completed.bg, sub: 'served or delivered' },
  { id: 'cancelled', label: 'Cancelled', color: STATUS_COLORS.Cancelled.bg, sub: 'incl. no-shows' },
];

type FeedView = 'active' | 'queue' | 'kitchen' | 'done' | 'all';

const MODE_ICON: Record<string, string> = { 'Dine-in': '🍽', Takeaway: '🥡', Delivery: '🛵', 'Drive-thru': '🚗' };

export default function RestaurantOrderFeed({ live, loading, finance }: { live?: RestaurantLive; loading: boolean; finance: boolean }) {
  const [view, setView] = useState<FeedView>('active');
  const [mode, setMode] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [updateStatus] = useUpdateBookingStatusMutation();
  const toast = useToast();

  const rows = useMemo(() => {
    const feed = (live?.feed ?? []).filter((o) => !mode || o.serviceMode === mode);
    const byStage = (...stages: RestaurantStage[]) => feed.filter((o) => stages.includes(o.stage));
    switch (view) {
      case 'queue': return byStage('new', 'accepted');
      case 'kitchen': return byStage('preparing', 'ready');
      case 'done': return byStage('completed', 'cancelled', 'noShow');
      case 'all': return feed;
      default: return byStage('new', 'accepted', 'preparing', 'ready');
    }
  }, [live, view, mode]);

  const modes = useMemo(() => Array.from(new Set((live?.feed ?? []).map((o) => o.serviceMode))).sort(), [live]);

  async function move(order: RestaurantOrder, status: string, done: string, failed: string) {
    setBusyId(order.bookingId);
    try {
      await updateStatus({ id: order.bookingId, status }).unwrap();
      toast.show(done, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, failed), 'error');
    } finally {
      setBusyId(null);
    }
  }

  const actionsFor = (o: RestaurantOrder) => {
    const busy = busyId === o.bookingId;
    const who = o.customerName;
    switch (o.stage) {
      case 'new':
        return (
          <>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => move(o, 'Confirmed', `Order for ${who} accepted.`, 'Could not accept the order.')}>Accept</button>
            <button type="button" className="btn btn-danger" disabled={busy} onClick={() => move(o, 'Rejected', 'Order rejected.', 'Could not reject the order.')}>Reject</button>
          </>
        );
      case 'accepted':
        return (
          <>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => move(o, 'CheckedIn', `${o.menuItem} for ${who} is in the kitchen.`, 'Could not start the order.')}>Start prep</button>
            {o.isLateStart && o.serviceMode === 'Dine-in' && (
              <button type="button" className="btn btn-danger" disabled={busy} onClick={() => move(o, 'NoShow', 'Marked as a no-show.', 'Could not update the order.')}>No-show</button>
            )}
            {!o.isLateStart && (
              <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => move(o, 'Cancelled', 'Order cancelled.', 'Could not cancel the order.')}>Cancel</button>
            )}
          </>
        );
      case 'preparing':
        return <button type="button" className="btn btn-primary" disabled={busy} onClick={() => move(o, 'InProgress', `${o.menuItem} for ${who} is ready.`, 'Could not mark the order ready.')}>Ready</button>;
      case 'ready':
        return (
          <button type="button" className="btn btn-primary" disabled={busy} onClick={() => move(o, 'Completed', o.serviceMode === 'Delivery' ? 'Marked delivered.' : 'Marked served.', 'Could not complete the order.')}>
            {o.serviceMode === 'Delivery' ? 'Delivered' : o.serviceMode === 'Dine-in' ? 'Served' : 'Collected'}
          </button>
        );
      default:
        return null;
    }
  };

  const stages = live?.stages;
  const kitchen = live?.kitchen;

  return (
    <div>
      <div className="rest-stages">
        {STAGES.map((s) => {
          const value = s.id === 'cancelled' ? (stages ? stages.cancelled + stages.noShow : undefined) : stages?.[s.id];
          const alert = (s.id === 'preparing' && (kitchen?.delayed ?? 0) > 0) || (s.id === 'new' && (kitchen?.stale ?? 0) > 0);
          const sub = s.id === 'preparing' && kitchen && kitchen.delayed > 0
            ? `${kitchen.delayed} over target`
            : s.id === 'new' && kitchen && kitchen.stale > 0
              ? `${kitchen.stale} waiting 10+ min`
              : s.sub;
          return (
            <div key={s.id} className={`rest-stage${alert ? ' rest-stage-alert' : ''}`}>
              <div className="rest-stage-label"><i style={{ background: s.color }} aria-hidden="true" />{s.label}</div>
              <div className="rest-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
              <div className="rest-stage-sub">{sub}</div>
            </div>
          );
        })}
      </div>

      {live && (
        <div className="rest-flow-meta">
          <span>Open tickets <b>{kitchen?.openTickets ?? 0}</b>{kitchen?.longestOpenMinutes != null && <> · longest <b>{formatMinutes(kitchen.longestOpenMinutes)}</b></>}</span>
          <span>Avg prep today <b>{formatMinutes(kitchen?.avgPrepMinutesToday)}</b></span>
          <span>On time <b>{kitchen?.onTimeRateToday != null ? `${kitchen.onTimeRateToday}%` : '—'}</b></span>
          {live.tables.total > 0 && <span>Tables in use <b>{live.tables.occupied}/{live.tables.total}</b></span>}
          {finance && <span>Sales today <b>{formatMoney(live.sales.revenue, live.sales.currency)}</b>{live.sales.averageOrderValue != null && <> · AOV <b>{formatMoney(live.sales.averageOrderValue, live.sales.currency)}</b></>}</span>}
          {(kitchen?.lateStarts ?? 0) > 0 && <span className="rest-late">{kitchen!.lateStarts} accepted past their time with no prep</span>}
        </div>
      )}

      <div className="rest-feed-tools">
        <div className="rest-queue-filter" role="tablist" aria-label="Feed view">
          {([['active', 'Active'], ['queue', 'Queue'], ['kitchen', 'Kitchen'], ['done', 'Done'], ['all', 'All']] as [FeedView, string][]).map(([id, label]) => (
            <button key={id} type="button" role="tab" aria-selected={view === id} className={view === id ? 'active' : ''} onClick={() => setView(id)}>{label}</button>
          ))}
        </div>
        {modes.length > 1 && (
          <select className="input" value={mode} onChange={(e) => setMode(e.target.value)} aria-label="Service mode">
            <option value="">All modes</option>
            {modes.map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        )}
        <span className="rest-note" style={{ margin: 0 }}>{rows.length} of {live?.feed.length ?? 0} orders</span>
      </div>

      {loading && !live ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading today's orders…</div>
      ) : rows.length === 0 ? (
        <div className="rest-empty">{live && live.feed.length === 0 ? 'No orders today yet.' : 'Nothing in this view.'}</div>
      ) : (
        <div className="table-wrap">
          <table className="data-table rest-feed-table">
            <thead>
              <tr>
                <th>Time</th>
                <th>Customer</th>
                <th>Order</th>
                <th>Where</th>
                <th>Status</th>
                <th>Ticket</th>
                {finance && <th style={{ textAlign: 'right' }}>Total</th>}
                <th style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((o) => {
                const status = STATUS_COLORS[o.status];
                const done = o.stage === 'completed' || o.stage === 'cancelled' || o.stage === 'noShow';
                return (
                  <tr key={o.bookingId} className={done ? 'rest-row-done' : o.isDelayed ? 'rest-row-delayed' : undefined}>
                    <td style={{ whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>
                      {formatTime(o.startTime)}
                      {o.isLateStart && <div className="rest-late">late start</div>}
                      {o.isStale && <div className="rest-late">unaccepted {formatMinutes(o.waitingMinutes)}</div>}
                    </td>
                    <td>
                      <div className="rest-customer">
                        <strong>{o.customerName}</strong>
                        <span>{[o.customerPhone, o.channel, o.priority !== 'Normal' ? `${o.priority} priority` : null].filter(Boolean).join(' · ')}</span>
                      </div>
                    </td>
                    <td>
                      <span className="rest-menu-chip"><i style={{ background: o.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{o.menuItem}</span>
                      <span className="rest-order-sub">{MODE_ICON[o.serviceMode] ?? ''} {o.serviceMode} · {o.covers} cover{o.covers === 1 ? '' : 's'}{o.notes ? ` · ${o.notes}` : ''}</span>
                    </td>
                    <td>{o.resourceName}<span className="rest-order-sub">{o.resourceKind}</span></td>
                    <td>
                      <span className={`badge badge-${status?.tone ?? 'neutral'}`}><span className="badge-dot" />{STATUS_LABEL[o.status] ?? o.status}</span>
                    </td>
                    <td>
                      {o.kitchenMinutes != null ? (
                        <span className={`rest-ticket${o.isDelayed || o.wasDelayed ? ' rest-ticket-late' : ''}`} title={`Target ${o.prepTargetMinutes} min`}>
                          {formatMinutes(o.kitchenMinutes)}{(o.isDelayed || o.wasDelayed) && <small> / {o.prepTargetMinutes}</small>}
                        </span>
                      ) : (
                        <span style={{ color: 'var(--color-text-muted)' }}>—</span>
                      )}
                    </td>
                    {finance && <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{o.totalCost != null ? formatMoney(o.totalCost) : '—'}</td>}
                    <td><div className="rest-actions">{actionsFor(o)}</div></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
