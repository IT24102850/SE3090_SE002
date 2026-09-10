import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import {
  useGetBookingTypesQuery,
  useGetDepartureBoardQuery,
  useGetExcursionKpisQuery,
} from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import { businessHeroImage } from '../../shared/businessImagery';
import { formatDayLabel } from '../../shared/dateUtils';
import type { DepartureSummary, Tenant, TenantProfile } from '../booking/types';
import DepartureBoard from './components/DepartureBoard';
import KpiCards, { type KpiValues } from './components/KpiCards';
import ManifestModal from './components/ManifestModal';
import { PackagesAndTours, ServicesAndAddons } from './components/ProductSections';
import SafetyPanel from './components/SafetyPanel';
import ScheduleDeparturesModal from './components/ScheduleDeparturesModal';
import SightingsPanel, { LogSightingModal } from './components/SightingsPanel';
import WeatherCancelModal from './components/WeatherCancelModal';
import WeatherConsole from './components/WeatherConsole';
import { splitProducts } from './productCategory';
import type { SubtypeDashboardConfig } from './subtypes/SubtypeDashboardConfig';

/* The whale-watching operator's dashboard: a departure operations board,
 * not a calendar.
 *
 * Everything visible is either a departure the crew has to run today or a
 * number that changes what they do about it. The month calendar the generic
 * dashboard leads with is still one click away under Bookings - it is the
 * wrong first screen for a business whose day is four sailings long. */

export default function WhaleWatchingDashboard({
  config,
  tenant,
  profile,
}: {
  config: SubtypeDashboardConfig;
  tenant?: Tenant;
  profile?: TenantProfile;
}) {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = user?.role === 'Admin';

  const [horizon, setHorizon] = useState(7);
  const [manifestFor, setManifestFor] = useState<DepartureSummary | null>(null);
  const [sightingFor, setSightingFor] = useState<DepartureSummary | null>(null);
  const [cancelFor, setCancelFor] = useState<DepartureSummary | null>(null);
  const [scheduling, setScheduling] = useState(false);

  const { data: board, isLoading: boardLoading } = useGetDepartureBoardQuery({ days: horizon });
  const { data: kpis, isLoading: kpisLoading } = useGetExcursionKpisQuery({ forwardDays: horizon });
  const { data: bookingTypes, isLoading: productsLoading } = useGetBookingTypesQuery(
    { tenantId: user?.tenantId ?? '', status: 'Active' },
    { skip: !user?.tenantId },
  );

  // Archived products are gone, not hidden - they are excluded here so the
  // dashboard shows what the operator could sell today, while Inactive ones
  // stay visible flagged as hidden because they are one toggle from live.
  const { tours, addons } = useMemo(
    () => splitProducts(
      (bookingTypes ?? []).filter((bt) => bt.status !== 'Archived'),
      // config.subType is the config-key form ("whaleWatching"), which is
      // what ConfigJson.subType stores - NOT the Tenant.SubType label.
      config.subType,
    ),
    [bookingTypes, config.subType],
  );

  // Season is declared per product in ConfigJson (season.months), so the
  // badge reflects whatever the operator configured on their tours. No
  // declared season means no badge, rather than a guessed one.
  const season = useMemo(() => {
    const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const now = MONTHS[new Date().getMonth()];
    for (const product of tours) {
      try {
        const months = JSON.parse(product.configJson ?? '{}')?.season?.months;
        if (Array.isArray(months) && months.length > 0) {
          return months.some((m: string) => m?.toLowerCase() === now.toLowerCase())
            ? { label: 'Peak season', tone: 'badge-good' }
            : { label: 'Off season', tone: 'badge-warning' };
        }
      } catch {
        // Operator-authored config; a malformed one just means no badge.
      }
    }
    return null;
  }, [tours]);

  const heroImage = businessHeroImage({
    businessType: tenant?.businessType,
    subType: tenant?.subType,
    coverImageUrl: profile?.coverImageUrl,
  });

  const today = board?.today ?? [];
  // The board endpoint returns today inside `upcoming` too; the forward
  // list drops them so the two sections do not repeat the same sailing.
  const forward = useMemo(() => {
    const todayIds = new Set(today.map((d) => d.id));
    return (board?.upcoming ?? []).filter((d) => !todayIds.has(d.id));
  }, [board, today]);

  const forwardByDay = useMemo(() => {
    const groups = new Map<string, DepartureSummary[]>();
    for (const departure of forward) {
      const key = departure.scheduledDeparture.slice(0, 10);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key)!.push(departure);
    }
    return [...groups.entries()];
  }, [forward]);

  // KPI values are keyed by KpiDefinition.field, so the registry decides
  // which of these actually appear.
  const kpiValues: KpiValues = useMemo(() => {
    if (!kpis) return {};
    // departuresTodayByStatus is a map, not a scalar, so it is destructured
    // out rather than spread into the scalar-keyed KPI lookup.
    const { departuresTodayByStatus: _byStatus, ...scalars } = kpis;
    return {
      ...scalars,
      // The pax card reads better against the capacity it is measured on.
      paxBookedToday: `${kpis.paxBookedToday} / ${kpis.capacityToday || '—'}`,
    };
  }, [kpis]);

  return (
    <div>
      <section className="hero">
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div>
              <p className="hero-eyebrow">
                {config.icon} {config.label}
                {season && (
                  <span className={`badge ${season.tone}`} style={{ marginLeft: 8 }}>{season.label}</span>
                )}
              </p>
              <h1 className="hero-title">{tenant?.name ?? 'Departure operations'}</h1>
              <div className="hero-figure">{kpisLoading ? '…' : (kpis?.departuresToday ?? 0)}</div>
              <p className="hero-sub">
                {config.resourceTermPlural.toLowerCase()} today ·{' '}
                {kpis ? `${kpis.paxBookedToday} pax booked` : 'loading'}
              </p>
            </div>
            <div className="filter-bar" style={{ marginBottom: 0 }}>
              <select className="input" value={horizon} onChange={(e) => setHorizon(Number(e.target.value))}>
                <option value={1}>Today only</option>
                <option value={7}>Next 7 days</option>
                <option value={14}>Next 14 days</option>
                <option value={30}>Next 30 days</option>
              </select>
            </div>
          </div>
        </div>
      </section>

      <KpiCards kpis={config.kpis} values={kpiValues} loading={kpisLoading} />

      {config.modules.weather && (
        <div style={{ marginTop: 16 }}>
          <WeatherConsole />
        </div>
      )}

      <div className="page-header" style={{ marginTop: 24, marginBottom: 12 }}>
        <div>
          <h2 className="page-title" style={{ fontSize: '1.15rem' }}>Today's {config.resourceTermPlural.toLowerCase()}</h2>
          <p className="page-subtitle">{config.heroActionLabel}</p>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Link className="btn btn-secondary btn-sm" to="/bookings">
            All {config.bookingTermPlural.toLowerCase()}
          </Link>
          <button className="btn btn-primary btn-sm" onClick={() => setScheduling(true)}>
            Schedule {config.resourceTermPlural.toLowerCase()}
          </button>
        </div>
      </div>

      <DepartureBoard
        departures={today}
        loading={boardLoading}
        isAdmin={isAdmin}
        onOpenManifest={setManifestFor}
        onLogSighting={setSightingFor}
        onCancelWeather={setCancelFor}
        emptyMessage={`No ${config.resourceTermPlural.toLowerCase()} scheduled for today. Create them from the ${config.resourceTermSingular.toLowerCase()} schedule.`}
      />

      {horizon > 1 && (
        <>
          <h2 className="page-title" style={{ fontSize: '1.15rem', marginTop: 28, marginBottom: 12 }}>
            Next {horizon} days
          </h2>
          {forwardByDay.length === 0 ? (
            <div className="card" style={{ padding: 24, color: 'var(--color-text-muted)' }}>
              Nothing scheduled in the next {horizon} days.
            </div>
          ) : (
            forwardByDay.map(([day, departures]) => (
              <div key={day} style={{ marginBottom: 18 }}>
                <p
                  style={{
                    fontSize: '0.78rem',
                    textTransform: 'uppercase',
                    letterSpacing: '0.07em',
                    color: 'var(--color-text-muted)',
                    margin: '0 0 8px',
                  }}
                >
                  {formatDayLabel(new Date(day))}
                </p>
                <DepartureBoard
                  departures={departures}
                  loading={false}
                  isAdmin={isAdmin}
                  onOpenManifest={setManifestFor}
                  onLogSighting={setSightingFor}
                  onCancelWeather={setCancelFor}
                  emptyMessage=""
                />
              </div>
            ))
          )}
        </>
      )}

      <PackagesAndTours products={tours} loading={productsLoading} />
      <ServicesAndAddons products={addons} loading={productsLoading} />

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
          gap: 16,
          marginTop: 24,
        }}
      >
        {config.modules.sightings && <SightingsPanel />}
        {config.modules.safety && <SafetyPanel equipmentTerm={config.equipmentTerm} />}
      </div>

      {scheduling && (
        <ScheduleDeparturesModal
          config={config}
          tenantId={user?.tenantId ?? ''}
          onClose={() => setScheduling(false)}
        />
      )}
      {manifestFor && <ManifestModal departure={manifestFor} onClose={() => setManifestFor(null)} />}
      {sightingFor && <LogSightingModal departure={sightingFor} onClose={() => setSightingFor(null)} />}
      {cancelFor && <WeatherCancelModal departure={cancelFor} onClose={() => setCancelFor(null)} />}
    </div>
  );
}
