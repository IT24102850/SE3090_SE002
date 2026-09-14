import { useCallback, useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store/store';
import { useGetNoShowStatsQuery, useGetResourcesQuery, useGetTenantQuery } from '../../api/bookingApi';
import { addDays, toISODate } from '../../shared/dateUtils';
import HorizontalBarChart from './HorizontalBarChart';
import ResourceMetricsCollector, { type ResourceMetrics } from './ResourceMetricsCollector';
import { STATUS_COLORS } from './types';
import ExcursionReports from '../dashboard/ExcursionReports';
import { getSubtypeConfig } from '../dashboard/subtypes/subtypeRegistry';
import { parseTenantSubType } from '../dashboard/subtypes/tourismSubTypes';

export default function ReportsPage() {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';

  const [from, setFrom] = useState(() => toISODate(addDays(new Date(), -13)));
  const [to, setTo] = useState(() => toISODate(new Date()));
  const [metrics, setMetrics] = useState<Record<string, ResourceMetrics>>({});

  const { data: stats, isLoading: statsLoading } = useGetNoShowStatsQuery(
    { tenantId, from, to: toISODate(addDays(new Date(to), 1)) },
    { skip: !tenantId }
  );
  const { data: resourcesData } = useGetResourcesQuery({ tenantId, pageSize: 50 }, { skip: !tenantId });
  // Sub-type-specific report sections are additive: an unrecognised or
  // unset SubType resolves to the generic config, whose departures module
  // is off, so this page renders exactly as it did before.
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });
  const subtypeConfig = useMemo(() => getSubtypeConfig(parseTenantSubType(tenant?.subType)), [tenant]);

  const handleMetrics = useCallback((m: ResourceMetrics) => {
    setMetrics((prev) => ({ ...prev, [m.resourceId]: m }));
  }, []);

  const resources = resourcesData?.items ?? [];
  const metricsList = useMemo(
    () => resources.map((r) => ({ resource: r, metrics: metrics[r.id] })).filter((x) => x.metrics),
    [resources, metrics]
  );

  const totalRevenue = metricsList.reduce((sum, m) => sum + (m.metrics?.estimatedRevenue ?? 0), 0);

  const outcomeData = stats
    ? [
        { label: 'Completed', value: stats.completed, color: STATUS_COLORS.Completed.bg },
        { label: 'No-show', value: stats.noShows, color: STATUS_COLORS.NoShow.bg },
        { label: 'Cancelled', value: stats.cancelled, color: STATUS_COLORS.Cancelled.bg },
        { label: 'Other', value: Math.max(stats.total - stats.completed - stats.noShows - stats.cancelled, 0), color: STATUS_COLORS.Pending.bg },
      ]
    : [];

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Reports</h1>
          <p className="page-subtitle">Booking utilization, no-show statistics and estimated revenue per resource.</p>
        </div>
        <div className="filter-bar">
          <input className="input" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          <span style={{ color: 'var(--color-text-muted)' }}>to</span>
          <input className="input" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        </div>
      </div>

      {resources.map((r) => (
        <ResourceMetricsCollector key={r.id} resource={r} from={from} to={to} onData={handleMetrics} />
      ))}

      <div className="stat-grid">
        <div className="stat-tile">
          <div className="stat-tile-label">Total bookings</div>
          <div className="stat-tile-value">{stats?.total ?? (statsLoading ? '…' : 0)}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Utilization rate</div>
          <div className="stat-tile-value" style={{ color: 'var(--color-good)' }}>{stats ? `${stats.utilizationRate.toFixed(1)}%` : '—'}</div>
          <div className="stat-tile-sub">completed of total bookings</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">No-show rate</div>
          <div className="stat-tile-value" style={{ color: 'var(--color-critical)' }}>{stats ? `${stats.noShowRate.toFixed(1)}%` : '—'}</div>
        </div>
        <div className="stat-tile">
          <div className="stat-tile-label">Est. revenue</div>
          <div className="stat-tile-value">${totalRevenue.toFixed(0)}</div>
          <div className="stat-tile-sub">booked hours × hourly rate</div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
        <div className="card chart-card">
          <p className="chart-title">Booking outcomes</p>
          <p className="chart-subtitle">{from} – {to}</p>
          {statsLoading ? <div className="loading-row"><span className="spinner spinner-dark" /></div> : <HorizontalBarChart data={outcomeData} />}
        </div>

        <div className="card chart-card">
          <p className="chart-title">Utilization by resource</p>
          <p className="chart-subtitle">Average % of open hours booked</p>
          <HorizontalBarChart
            maxValue={100}
            data={metricsList.map(({ resource, metrics: m }) => ({
              label: resource.name,
              value: m!.avgUtilizationPercent,
              displayValue: `${m!.avgUtilizationPercent}%`,
              color: 'var(--color-primary)',
            }))}
          />
        </div>

        <div className="card chart-card" style={{ gridColumn: '1 / -1' }}>
          <p className="chart-title">Estimated revenue per resource</p>
          <p className="chart-subtitle">Booked hours in range × resource hourly rate</p>
          <HorizontalBarChart
            data={metricsList
              .filter(({ metrics: m }) => (m?.estimatedRevenue ?? 0) > 0)
              .sort((a, b) => (b.metrics?.estimatedRevenue ?? 0) - (a.metrics?.estimatedRevenue ?? 0))
              .map(({ resource, metrics: m }) => ({
                label: resource.name,
                value: m!.estimatedRevenue,
                displayValue: `$${m!.estimatedRevenue.toFixed(0)}`,
                color: 'var(--color-good)',
              }))}
          />
        </div>
      </div>

      {subtypeConfig.modules.departures && (
        <ExcursionReports from={from} to={to} config={subtypeConfig} />
      )}
    </div>
  );
}
