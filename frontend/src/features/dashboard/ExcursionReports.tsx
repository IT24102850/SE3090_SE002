import {
  useGetChannelSplitQuery,
  useGetPerDepartureReportQuery,
  useGetRevenueByTicketTypeQuery,
  useGetSightingAnalyticsQuery,
  useGetWeatherCancellationReportQuery,
} from '../../api/bookingApi';
import { formatDateTime } from '../../shared/dateUtils';
import HorizontalBarChart from '../booking/HorizontalBarChart';
import type { SubtypeDashboardConfig } from './subtypes/SubtypeDashboardConfig';

/* The reports a fixed-departure excursion operator needs, appended to the
 * existing Reports page rather than replacing it.
 *
 * Rendered only when the tenant's sub-type turns the departures module on,
 * so a clinic's Reports page is byte-for-byte what it was. */

function humanise(species: string): string {
  const spaced = species.replace(/([a-z])([A-Z])/g, '$1 $2');
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
}

export default function ExcursionReports({
  from,
  to,
  config,
}: {
  from: string;
  to: string;
  config: SubtypeDashboardConfig;
}) {
  const range = { from, to };
  const { data: byTicket } = useGetRevenueByTicketTypeQuery(range);
  const { data: perDeparture } = useGetPerDepartureReportQuery(range);
  const { data: weather } = useGetWeatherCancellationReportQuery(range);
  const { data: channels } = useGetChannelSplitQuery(range);
  const { data: sightings } = useGetSightingAnalyticsQuery(range);

  const term = config.resourceTermPlural.toLowerCase();

  return (
    <>
      <h2 className="page-title" style={{ fontSize: '1.15rem', marginTop: 32, marginBottom: 4 }}>
        {config.label}
      </h2>
      <p className="page-subtitle" style={{ marginBottom: 16 }}>
        Ticket mix, per-{config.resourceTermSingular.toLowerCase()} performance, sighting trend and
        weather losses for {from} – {to}.
      </p>

      <div className="stat-grid">
        <div className="stat-tile">
          <div className="stat-tile-label">Tickets sold</div>
          <div className="stat-tile-value">{byTicket?.totalTickets ?? '—'}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Ticketed revenue</div>
          <div className="stat-tile-value">
            {byTicket ? Math.round(byTicket.totalRevenue).toLocaleString() : '—'}
          </div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Avg occupancy</div>
          <div className="stat-tile-value" style={{ color: 'var(--color-good)' }}>
            {perDeparture ? `${perDeparture.averageOccupancyPercent.toFixed(1)}%` : '—'}
          </div>
          <div className="stat-tile-sub">per {config.resourceTermSingular.toLowerCase()}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Weather-cancelled</div>
          <div className="stat-tile-value" style={{ color: 'var(--color-critical)' }}>
            {weather?.totalCancelled ?? '—'}
          </div>
          <div className="stat-tile-sub">
            {weather ? `${Math.round(weather.totalRefundableAmount).toLocaleString()} at risk` : ''}
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: 20, marginTop: 20 }}>
        <div className="card chart-card">
          <p className="chart-title">Revenue by ticket type</p>
          <p className="chart-subtitle">Adult / child / infant split across the range</p>
          <HorizontalBarChart
            data={(byTicket?.byTicketType ?? []).map((row) => ({
              label: `${row.ticketType} (${row.quantity})`,
              value: row.revenue,
              displayValue: Math.round(row.revenue).toLocaleString(),
              color: 'var(--color-primary)',
            }))}
          />
          {(byTicket?.unbrokenDownRevenue ?? 0) > 0 && (
            <p style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', marginTop: 8 }}>
              A further {Math.round(byTicket!.unbrokenDownRevenue).toLocaleString()} came from bookings
              made before ticket breakdowns were recorded, so it cannot be split by type.
            </p>
          )}
        </div>

        <div className="card chart-card">
          <p className="chart-title">Booking channel</p>
          <p className="chart-subtitle">Where reservations came from</p>
          <HorizontalBarChart
            data={(channels?.byChannel ?? []).map((row) => ({
              label: `${row.channel} (${row.pax} pax)`,
              value: row.revenue,
              displayValue: Math.round(row.revenue).toLocaleString(),
              color: row.channel === 'Unknown' ? 'var(--color-neutral)' : 'var(--color-accent-cyan)',
            }))}
          />
          {channels?.nationalityCaptured ? (
            <div style={{ marginTop: 12 }}>
              <p className="chart-subtitle">Guest nationality</p>
              <HorizontalBarChart
                data={channels.byNationality.slice(0, 6).map((row) => ({
                  label: row.nationality,
                  value: row.bookings,
                  color: 'var(--color-good)',
                }))}
              />
            </div>
          ) : (
            <p style={{ fontSize: '0.78rem', color: 'var(--color-text-muted)', marginTop: 8 }}>
              No nationality captured on these bookings — add a nationality field to the booking form to
              break guests down this way.
            </p>
          )}
        </div>

        <div className="card chart-card">
          <p className="chart-title">Sighting success trend</p>
          <p className="chart-subtitle">Share of {term} that had at least one sighting</p>
          <HorizontalBarChart
            maxValue={100}
            data={(sightings?.monthly ?? [])
              .filter((m) => m.departures > 0)
              .map((m) => ({
                label: m.label,
                value: m.successRate,
                displayValue: `${m.successRate.toFixed(0)}% (${m.departuresWithSighting}/${m.departures})`,
                color:
                  m.successRate >= 75
                    ? 'var(--color-good)'
                    : m.successRate >= 40
                      ? 'var(--color-warning)'
                      : 'var(--color-critical)',
              }))}
          />
        </div>

        <div className="card chart-card">
          <p className="chart-title">Species seen</p>
          <p className="chart-subtitle">Sightings logged in the range</p>
          <HorizontalBarChart
            data={(sightings?.speciesFrequency ?? []).slice(0, 8).map((row) => ({
              label: humanise(row.species),
              value: row.sightings,
              displayValue: `${row.sightings} (${row.individuals} animals)`,
              color: 'var(--color-primary)',
            }))}
          />
        </div>
      </div>

      <div className="card" style={{ marginTop: 20 }}>
        <p className="chart-title" style={{ padding: '16px 16px 0' }}>
          Revenue and occupancy per {config.resourceTermSingular.toLowerCase()}
        </p>
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Departure</th>
                <th>Vessel</th>
                <th>Status</th>
                <th>Pax</th>
                <th>Occupancy</th>
                <th>Revenue</th>
                <th>Per seat</th>
                <th>Sightings</th>
              </tr>
            </thead>
            <tbody>
              {(perDeparture?.departures ?? []).length === 0 ? (
                <tr>
                  <td colSpan={8} className="empty-state">No {term} in this range.</td>
                </tr>
              ) : (
                perDeparture!.departures.map((d) => (
                  <tr key={d.departureId}>
                    <td>{formatDateTime(d.scheduledDeparture)}</td>
                    <td>{d.vesselName}</td>
                    <td>{d.status}</td>
                    <td>{d.pax} / {d.capacity || '—'}</td>
                    <td>{d.occupancyPercent.toFixed(0)}%</td>
                    <td>{Math.round(d.revenue).toLocaleString()}</td>
                    <td>{d.revenuePerSeat.toLocaleString()}</td>
                    <td>{d.sightings}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {(weather?.departures.length ?? 0) > 0 && (
        <div className="card" style={{ marginTop: 20 }}>
          <p className="chart-title" style={{ padding: '16px 16px 0' }}>Weather cancellations</p>
          <p className="chart-subtitle" style={{ padding: '0 16px' }}>
            {weather!.totalBookingsAffected} bookings affected · {weather!.totalRebooked} rebooked ·{' '}
            {Math.round(weather!.totalRefundableAmount).toLocaleString()} at risk. There is no payment
            gateway in this system, so this is value at risk, not a settled refund total.
          </p>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Departure</th>
                  <th>Vessel</th>
                  <th>Reason</th>
                  <th>Bookings</th>
                  <th>Pax</th>
                  <th>At risk</th>
                  <th>Rebooked</th>
                </tr>
              </thead>
              <tbody>
                {weather!.departures.map((d) => (
                  <tr key={d.departureId}>
                    <td>{formatDateTime(d.scheduledDeparture)}</td>
                    <td>{d.vesselName}</td>
                    <td>{d.cancellationReason ?? '—'}</td>
                    <td>{d.bookingsAffected}</td>
                    <td>{d.paxAffected}</td>
                    <td>{Math.round(d.refundableAmount).toLocaleString()}</td>
                    <td>{d.rebookedCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </>
  );
}
