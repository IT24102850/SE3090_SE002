import { Link } from 'react-router-dom';
import type { RestaurantLive, RestaurantOverview } from '../../booking/types';
import { formatMoney, formatPercent } from './restaurantReport';

/* Staff & labor.
 *
 * There is no time clock in this platform, so "on shift" means "rostered
 * for this hour" (the staff resource's weekly schedule) and the labor
 * figure is rostered hours x the resource's hourly rate. The panel says
 * so in plain words rather than presenting a roster as a clock-in. Labor
 * as a share of sales is the number a manager watches through a service;
 * the range figure underneath is the same ratio over the report window. */

export default function RestaurantStaffPanel({ live, overview, loading }: { live?: RestaurantLive; overview?: RestaurantOverview; loading: boolean }) {
  const labor = live?.labor;
  const kpis = overview?.kpis;
  const currency = live?.sales.currency ?? 'LKR';
  const unrated = labor ? labor.shifts.filter((s) => !s.hourlyRate).length : 0;

  return (
    <div>
      <div className="rest-stages">
        <Tile label="On shift now" value={labor ? labor.onShiftNow : undefined} sub={labor ? `${labor.scheduledToday} rostered today · ${labor.headcountRostered} staff resources` : ''} loading={loading} />
        <Tile label="Hours so far" value={labor ? labor.hoursSoFar.toFixed(1) : undefined} sub={labor ? `of ${labor.hoursScheduled.toFixed(1)} rostered today` : ''} loading={loading} />
        <Tile label="Labor cost so far" value={labor ? formatMoney(labor.costSoFar, currency) : undefined} sub={labor ? `${formatMoney(labor.costScheduled, currency)} for the full roster` : ''} loading={loading} />
        <Tile
          label="Labor % of sales"
          value={labor ? formatPercent(labor.laborPercent) : undefined}
          sub={labor ? (labor.laborPercent == null ? (labor.rated === 0 ? 'set hourly rates on staff resources' : 'no completed sales yet today') : `against ${formatMoney(live!.sales.revenue, currency)} today`) : ''}
          loading={loading}
          alert={(labor?.laborPercent ?? 0) > 35}
        />
      </div>

      {loading && !live ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading the roster…</div>
      ) : !labor || labor.shifts.length === 0 ? (
        <div className="rest-empty">
          Nobody is rostered today. Add staff as <Link to="/resources">Staff resources</Link> with a weekly schedule and an hourly rate, and this panel fills in.
        </div>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Staff</th>
                <th>Shift</th>
                <th>Status</th>
                <th>Hours</th>
                <th>Orders handled</th>
                <th style={{ textAlign: 'right' }}>Cost so far</th>
              </tr>
            </thead>
            <tbody>
              {labor.shifts.map((s) => (
                <tr key={`${s.resourceId}-${s.shiftStart}`} className={s.status === 'finished' ? 'rest-row-done' : undefined}>
                  <td><span className="rest-strong">{s.name}</span>{s.role && <span className="rest-order-sub">{s.role}</span>}</td>
                  <td style={{ whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{s.shiftStart} – {s.shiftEnd}</td>
                  <td>
                    <span className={`badge badge-${s.status === 'busy' ? 'warning' : s.status === 'on shift' ? 'good' : 'neutral'}`}><span className="badge-dot" />{s.status}</span>
                  </td>
                  <td style={{ fontVariantNumeric: 'tabular-nums' }}>{s.hoursSoFar.toFixed(1)} / {s.scheduledHours.toFixed(1)}</td>
                  <td>{s.ordersHandled}</td>
                  <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>
                    {s.hourlyRate ? formatMoney(s.hoursSoFar * s.hourlyRate, currency) : <span style={{ color: 'var(--color-text-muted)' }} title="No hourly rate on this staff resource">no rate</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="rest-note">
        Rostered, not clocked in: shifts come from each staff resource's weekly schedule.
        {unrated > 0 && <> {unrated} rostered staff have no hourly rate, so labor cost is understated.</>}
        {kpis && kpis.laborHours > 0 && <> Selected range: <b>{kpis.laborHours.toLocaleString()} h</b> rostered, <b>{formatMoney(kpis.laborCost, currency)}</b>, <b>{formatPercent(kpis.laborPercent)}</b> of sales.</>}
      </p>
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
