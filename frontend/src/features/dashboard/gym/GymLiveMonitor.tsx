import { useState } from 'react';
import { useUpdateBookingStatusMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import type { GymLive, GymLiveRow } from '../../booking/types';
import { FlowChart } from './GymCharts';
import { formatMinutes } from './gymReport';

/* The live check-in monitor: who is inside now against capacity, entries
 * and exits through the day, and the latest check-ins with the member's
 * membership state beside each - so a lapsed keycard shows up at the desk
 * the moment it is scanned. "Check out" closes a visit that the turnstile
 * or app did not; the parent polls every 30s so scans land here on their
 * own. */

const METHOD_ICON: Record<string, string> = { RFID: '🪪', App: '📱', Biometric: '🫆', 'Front desk': '🧑‍💻' };
const MEMBERSHIP_TONE: Record<GymLiveRow['membershipStatus'], 'good' | 'warning' | 'critical' | 'neutral'> = { active: 'good', frozen: 'warning', expired: 'critical', cancelled: 'critical', none: 'neutral' };
const MEMBERSHIP_LABEL: Record<GymLiveRow['membershipStatus'], string> = { active: 'Active', frozen: 'Frozen', expired: 'Expired', cancelled: 'Cancelled', none: 'No membership' };

export default function GymLiveMonitor({ live, loading }: { live?: GymLive; loading: boolean }) {
  const [view, setView] = useState<'inside' | 'recent'>('inside');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [updateStatus] = useUpdateBookingStatusMutation();
  const toast = useToast();

  async function checkOut(row: GymLiveRow) {
    setBusyId(row.bookingId);
    try {
      await updateStatus({ id: row.bookingId, status: 'Completed' }).unwrap();
      toast.show(`${row.memberName} checked out.`, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not check the member out.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  const rows = view === 'inside' ? live?.inside ?? [] : live?.recent ?? [];
  const occupancyAlert = (live?.occupancyPercent ?? 0) >= 90;

  return (
    <div>
      <div className="gym-stages">
        <Tile label="Inside now" value={live ? live.insideNow : undefined} sub={live ? (live.capacity ? `of ${live.capacity} capacity · ${live.occupancyPercent}%` : 'set facilityCapacity or zone capacities') : ''} loading={loading} alert={occupancyAlert} big />
        <Tile label="Entries today" value={live ? live.entriesToday : undefined} sub={live ? `${live.uniqueToday} unique member${live.uniqueToday === 1 ? '' : 's'}` : ''} loading={loading} />
        <Tile label="Exits today" value={live ? live.exitsToday : undefined} sub="checked out or completed" loading={loading} />
        <Tile label="Lapsed check-ins" value={live ? live.expiredInsideToday : undefined} sub="today, without a valid membership" loading={loading} alert={(live?.expiredInsideToday ?? 0) > 0} />
        <Tile label="Trainers on floor" value={live ? live.trainers.onFloor : undefined} sub={live ? `${live.trainers.rostered} rostered today` : ''} loading={loading} />
      </div>

      {live && live.capacity ? (
        <div className="gym-occupancy" aria-label={`Occupancy ${live.occupancyPercent}%`}>
          <span className="gym-occupancy-fill" style={{ width: `${Math.min(100, live.occupancyPercent ?? 0)}%`, background: occupancyAlert ? 'var(--color-critical)' : (live.occupancyPercent ?? 0) >= 70 ? 'var(--color-warning)' : 'var(--color-good)' }} />
        </div>
      ) : null}

      <div className="gym-split">
        <div>
          <p className="gym-subhead">Entries & exits by hour · today</p>
          <FlowChart data={live?.byHour ?? []} loading={loading} />
        </div>
        <div>
          <div className="gym-subhead" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span>{view === 'inside' ? 'On the floor' : 'Latest check-ins'}</span>
            <div className="gym-queue-filter" role="tablist" aria-label="Monitor view">
              <button type="button" role="tab" aria-selected={view === 'inside'} className={view === 'inside' ? 'active' : ''} onClick={() => setView('inside')}>Inside ({live?.insideNow ?? 0})</button>
              <button type="button" role="tab" aria-selected={view === 'recent'} className={view === 'recent' ? 'active' : ''} onClick={() => setView('recent')}>Recent</button>
            </div>
          </div>
          {loading && !live ? (
            <div className="loading-row"><span className="spinner spinner-dark" /> Loading the floor…</div>
          ) : rows.length === 0 ? (
            <div className="gym-empty">{view === 'inside' ? 'Nobody on the floor right now.' : 'No check-ins yet today.'}</div>
          ) : (
            <div className="gym-live-list">
              {rows.map((r) => (
                <div key={r.bookingId} className={`gym-live-row${r.membershipStatus !== 'active' ? ' gym-live-row-flag' : ''}`}>
                  <span className="gym-live-method" title={r.method} aria-label={r.method}>{METHOD_ICON[r.method] ?? '•'}</span>
                  <div className="gym-live-main">
                    <strong>{r.memberName}</strong>
                    <span>{[r.activity !== r.zone ? r.activity : null, r.zone, r.plan].filter(Boolean).join(' · ')}</span>
                  </div>
                  <div className="gym-live-side">
                    <span className={`badge badge-${MEMBERSHIP_TONE[r.membershipStatus]}`}><span className="badge-dot" />{MEMBERSHIP_LABEL[r.membershipStatus]}</span>
                    <small>{r.checkInAt ? `in ${formatTime(r.checkInAt)}` : ''}{r.checkOutAt ? ` · out ${formatTime(r.checkOutAt)}` : r.minutesInside != null ? ` · ${formatMinutes(r.minutesInside)}` : ''}</small>
                  </div>
                  {r.isInside && (
                    <button type="button" className="btn btn-secondary btn-sm" disabled={busyId === r.bookingId} onClick={() => checkOut(r)}>Check out</button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Tile({ label, value, sub, loading, alert, big }: { label: string; value: string | number | undefined; sub: string; loading: boolean; alert?: boolean; big?: boolean }) {
  return (
    <div className={`gym-stage${alert ? ' gym-stage-alert' : ''}${big ? ' gym-stage-big' : ''}`}>
      <div className="gym-stage-label">{label}</div>
      <div className="gym-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="gym-stage-sub">{sub}</div>
    </div>
  );
}
