import type { RestaurantLive, RestaurantOverview } from '../../booking/types';
import { formatMinutes, formatMoney, formatPercent } from './restaurantReport';

/* Kitchen performance: the ticket-time SLA and station throughput.
 *
 * Top row is today, live: open tickets, how many are over their target,
 * the average prep time and the on-time rate. Under it, one card per
 * station / table / rider with its load right now and its throughput
 * for the day, so the head chef can see which station is the bottleneck
 * before the delayed count climbs. The range figures (bottom) come from
 * the overview so the same panel answers "and how was last week". */

const KIND_LABEL: Record<string, string> = { station: 'Station', table: 'Table', rider: 'Rider', staff: 'Staff', other: 'Resource' };

export default function RestaurantKitchenPanel({
  live, overview, loading, finance, onSelectStation, activeStation,
}: {
  live?: RestaurantLive;
  overview?: RestaurantOverview;
  loading: boolean;
  finance: boolean;
  onSelectStation: (id: string) => void;
  activeStation: string;
}) {
  const kitchen = live?.kitchen;
  const kpis = overview?.kpis;
  const stations = live?.stations ?? [];
  const maxOrders = Math.max(1, ...stations.map((s) => s.orders));

  return (
    <div>
      <div className="rest-stages">
        <Tile label="Open tickets" value={kitchen ? kitchen.openTickets : undefined} sub={kitchen?.longestOpenMinutes != null ? `longest ${formatMinutes(kitchen.longestOpenMinutes)}` : 'nothing in the kitchen'} loading={loading} />
        <Tile label="Over target" value={kitchen ? kitchen.delayed : undefined} sub={`target ${kitchen?.defaultTargetMinutes ?? 20} min unless the menu type sets its own`} loading={loading} alert={(kitchen?.delayed ?? 0) > 0} />
        <Tile label="Avg prep today" value={kitchen ? formatMinutes(kitchen.avgPrepMinutesToday) : undefined} sub="start prep → ready" loading={loading} />
        <Tile label="On time today" value={kitchen ? (kitchen.onTimeRateToday != null ? `${kitchen.onTimeRateToday}%` : '—') : undefined} sub={kitchen?.onTimeRateToday == null ? 'measured once tickets are marked ready' : 'tickets ready within target'} loading={loading} />
      </div>

      {loading && !live ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading stations…</div>
      ) : stations.length === 0 ? (
        <div className="rest-empty">No orders on any station today. Stations are your Equipment resources; tables are Rooms / Desks; riders are Vehicles.</div>
      ) : (
        <div className="rest-stations">
          {stations.map((s) => {
            const active = activeStation === s.resourceId;
            return (
              <button
                key={s.resourceId}
                type="button"
                className={`rest-station${s.delayed > 0 ? ' rest-station-late' : ''}${active ? ' is-active' : ''}`}
                onClick={() => onSelectStation(s.resourceId)}
                aria-pressed={active}
                title={active ? 'Clear the station filter' : `Filter the dashboard by ${s.name}`}
              >
                <div className="rest-station-head">
                  <span className="rest-station-kind">{KIND_LABEL[s.kind] ?? 'Resource'}</span>
                  <strong>{s.name}</strong>
                </div>
                <div className="rest-station-load" aria-label={`${s.open} open, ${s.queued} queued`}>
                  <span className="rest-station-open">{s.open}</span>
                  <span>open{s.queued > 0 && <> · {s.queued} queued</>}</span>
                </div>
                <span className="rest-mini-track"><span className="rest-mini-fill" style={{ width: `${(s.orders / maxOrders) * 100}%` }} /></span>
                <div className="rest-station-foot">
                  <span>{s.orders} today · {s.completed} done</span>
                  <span>{s.avgPrepMinutes != null ? `avg ${formatMinutes(s.avgPrepMinutes)}` : '—'}</span>
                </div>
                {s.delayed > 0 && <div className="rest-station-alert">{s.delayed} over target</div>}
                {finance && s.revenue > 0 && <div className="rest-station-rev">{formatMoney(s.revenue)}</div>}
              </button>
            );
          })}
        </div>
      )}

      {kpis && (
        <p className="rest-note">
          Selected range: avg prep <b>{formatMinutes(kpis.avgPrepMinutes)}</b> · avg ticket (kitchen start → served) <b>{formatMinutes(kpis.avgTicketMinutes)}</b> · on time <b>{formatPercent(kpis.onTimeRate)}</b> · <b>{kpis.delayed}</b> delayed of {kpis.prepSamples} measured ticket{kpis.prepSamples === 1 ? '' : 's'}.
          {kpis.prepSamples === 0 && ' Ticket times are measured from the moment an order is started and marked ready on the feed.'}
        </p>
      )}
    </div>
  );
}

function Tile({ label, value, sub, loading, alert }: { label: string; value: string | number | undefined; sub: string; loading: boolean; alert?: boolean }) {
  return (
    <div className={`rest-stage${alert ? ' rest-stage-alert' : ''}`}>
      <div className="rest-stage-label">{label}</div>
      <div className="rest-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="rest-stage-sub">{sub}</div>
    </div>
  );
}
