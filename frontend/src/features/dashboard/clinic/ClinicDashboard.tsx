import { Fragment, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useSelector } from 'react-redux';
import {
  useGetClinicAlertsQuery,
  useGetClinicFlowQuery,
  useGetClinicOverviewQuery,
  useGetClinicRemindersQuery,
} from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { businessDescriptor, businessHeroImage } from '../../../shared/businessImagery';
import BusinessAvatar from '../../../shared/components/BusinessAvatar';
import CalendarDashboardPage from '../../booking/CalendarDashboardPage';
import type { ClinicGroupBy, ClinicOverview, Tenant, TenantProfile } from '../../booking/types';
import ClinicAlerts from './ClinicAlerts';
import { BarList, HourChart, StatusMix, TrendChart } from './ClinicCharts';
import ClinicFlowBoard from './ClinicFlowBoard';
import ClinicRemindersPanel from './ClinicRemindersPanel';
import {
  CLINIC_WIDGETS,
  DEFAULT_LAYOUT,
  loadLayout,
  moveWidget,
  saveLayout,
  toggleWidget,
  type ClinicLayout,
  type ClinicWidgetId,
} from './clinicLayout';
import {
  downloadCsv,
  formatMinutes,
  formatMoney,
  formatPercent,
  overviewToCsv,
  presetRange,
  type ClinicRangePreset,
} from './clinicReport';
import './clinic.css';

/* The clinic's dashboard: an operations desk, not a calendar.
 *
 * Top to bottom: what needs attention right now (alerts), the numbers that
 * describe the practice over a chosen window (KPIs), and then the panels -
 * the live waiting room, trends and breakdowns, and the reminder worklist.
 * Every breakdown cross-filters the others (click a doctor, the trend and
 * the treatment mix follow), the window and grouping are the daily / weekly
 * / monthly report presets, and the whole thing exports as one CSV.
 *
 * The month calendar the generic dashboard led with is still here under
 * the "Calendar" view - nothing a clinic had before is gone. */

const LIVE_POLL_MS = 60_000;

type View = 'operations' | 'calendar';

const PRESETS: { id: ClinicRangePreset; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: '7d', label: '7 days' },
  { id: '30d', label: '30 days' },
  { id: 'month', label: 'This month' },
];
const REPORT_PRESETS: { id: ClinicRangePreset; label: string; title: string }[] = [
  { id: 'daily', label: 'Daily', title: 'Daily operational report: the last 14 days, one row per day' },
  { id: 'weekly', label: 'Weekly', title: 'Weekly report: the last 12 weeks, one row per week' },
  { id: 'monthly', label: 'Monthly', title: 'Monthly report: the last 12 months, one row per month' },
];

export default function ClinicDashboard({ tenant, profile }: { tenant: Tenant; profile?: TenantProfile }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const userId = user?.id ?? 'anon';
  const canSeeReports = user?.role === 'Admin' || user?.role === 'Manager';

  const [view, setView] = useState<View>(() => {
    try {
      return (localStorage.getItem(`clinic-dashboard-view:${tenantId}`) as View) || 'operations';
    } catch {
      return 'operations';
    }
  });
  useEffect(() => {
    try {
      localStorage.setItem(`clinic-dashboard-view:${tenantId}`, view);
    } catch {
      // Per-viewer convenience only.
    }
  }, [view, tenantId]);

  // ── Filters ──────────────────────────────────────────────────────────
  const [preset, setPreset] = useState<ClinicRangePreset>('30d');
  const [range, setRange] = useState(() => presetRange('30d'));
  const [branchId, setBranchId] = useState('');
  const [resourceId, setResourceId] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [insuranceProvider, setInsuranceProvider] = useState('');

  const applyPreset = (id: ClinicRangePreset) => {
    setPreset(id);
    if (id !== 'custom') setRange(presetRange(id));
  };
  const setCustom = (patch: Partial<typeof range>) => {
    setPreset('custom');
    setRange((r) => ({ ...r, ...patch }));
  };
  const clearFilters = () => {
    setBranchId('');
    setResourceId('');
    setBookingTypeId('');
    setInsuranceProvider('');
  };
  const toggle = (setter: (v: string) => void, current: string) => (key: string) => setter(current === key ? '' : key);

  // ── Data ─────────────────────────────────────────────────────────────
  const overviewParams = useMemo(() => ({
    from: range.from,
    to: range.to,
    groupBy: range.groupBy,
    branchId: branchId || undefined,
    resourceId: resourceId || undefined,
    bookingTypeId: bookingTypeId || undefined,
    insuranceProvider: insuranceProvider || undefined,
  }), [range, branchId, resourceId, bookingTypeId, insuranceProvider]);

  const { data: overview, isLoading: overviewLoading, isFetching: overviewFetching } = useGetClinicOverviewQuery(overviewParams, { skip: !tenantId });
  const liveParams = useMemo(() => ({ branchId: branchId || undefined, resourceId: resourceId || undefined }), [branchId, resourceId]);
  const { data: flow, isLoading: flowLoading } = useGetClinicFlowQuery(liveParams, { skip: !tenantId, pollingInterval: LIVE_POLL_MS });
  const { data: alertsData, isLoading: alertsLoading } = useGetClinicAlertsQuery({ branchId: branchId || undefined }, { skip: !tenantId, pollingInterval: LIVE_POLL_MS });
  const { data: reminders, isLoading: remindersLoading } = useGetClinicRemindersQuery({ withinHours: 48, branchId: branchId || undefined }, { skip: !tenantId, pollingInterval: LIVE_POLL_MS * 5 });

  const kpis = overview?.kpis;
  const options = overview?.filterOptions;
  const currency = kpis?.currency ?? 'LKR';

  // ── Layout customisation ─────────────────────────────────────────────
  const [layout, setLayout] = useState<ClinicLayout>(() => loadLayout(tenantId, userId));
  const [customising, setCustomising] = useState(false);
  const updateLayout = useCallback((next: ClinicLayout) => {
    setLayout(next);
    saveLayout(tenantId, userId, next);
  }, [tenantId, userId]);

  const visibleWidgets = layout.order.filter((id) => !layout.hidden.includes(id));

  // ── Export ───────────────────────────────────────────────────────────
  const exportCsv = () => {
    if (!overview) return;
    downloadCsv(`clinic-report-${range.groupBy}-${range.from}-to-${range.to}.csv`, overviewToCsv(overview));
  };

  const heroImage = businessHeroImage({ businessType: tenant.businessType, subType: tenant.subType, coverImageUrl: profile?.coverImageUrl });
  const descriptor = businessDescriptor({ businessType: tenant.businessType, subType: tenant.subType });
  const criticalAlerts = (alertsData?.alerts ?? []).filter((a) => a.severity === 'critical').length;

  const activeFilters = [
    branchId && { key: 'branch', label: `Branch: ${options?.branches.find((b) => b.id === branchId)?.name ?? '…'}`, clear: () => setBranchId('') },
    resourceId && { key: 'doctor', label: `Doctor: ${options?.doctors.find((d) => d.id === resourceId)?.name ?? '…'}`, clear: () => setResourceId('') },
    bookingTypeId && { key: 'treatment', label: `Treatment: ${options?.treatments.find((t) => t.id === bookingTypeId)?.name ?? '…'}`, clear: () => setBookingTypeId('') },
    insuranceProvider && { key: 'insurance', label: `Insurer: ${insuranceProvider}`, clear: () => setInsuranceProvider('') },
  ].filter(Boolean) as { key: string; label: string; clear: () => void }[];

  // ── Widgets ──────────────────────────────────────────────────────────
  const rangeLabel = `${range.from} – ${range.to}`;

  const renderWidget = (id: ClinicWidgetId): ReactNode => {
    switch (id) {
      case 'flow':
        return (
          <Widget id="flow" title="Patient flow" subtitle={`Today · refreshes every ${LIVE_POLL_MS / 1000}s`}>
            <ClinicFlowBoard flow={flow} loading={flowLoading} />
          </Widget>
        );
      case 'trend':
        return (
          <Widget id="trend" title="Appointment trend" subtitle={`${rangeLabel} · by ${range.groupBy}`}>
            <TrendChart data={overview?.trend ?? []} loading={overviewLoading} />
          </Widget>
        );
      case 'status':
        return (
          <Widget id="status" title="Appointment status" subtitle={rangeLabel}>
            <StatusMix mix={overview?.statusMix ?? []} loading={overviewLoading} />
            {kpis && (
              <p className="clinic-note">
                Completion {formatPercent(kpis.completionRate)} · No-show {formatPercent(kpis.noShowRate)} · Cancellation {formatPercent(kpis.cancellationRate)} — of appointments with a known outcome.
              </p>
            )}
          </Widget>
        );
      case 'treatments':
        return (
          <Widget id="treatments" title="Treatment demand" subtitle="Appointments by treatment type">
            <BarList
              data={(overview?.byTreatment ?? []).map((t) => ({ key: t.bookingTypeId, label: t.name, value: t.appointments, sub: t.revenue > 0 ? formatMoney(t.revenue, currency) : undefined }))}
              active={bookingTypeId}
              onSelect={toggle(setBookingTypeId, bookingTypeId)}
              hint="Click a treatment to filter the whole dashboard by it."
            />
          </Widget>
        );
      case 'doctors':
        return (
          <Widget id="doctors" title="Doctor performance" subtitle={`${rangeLabel} · click a row to filter by that doctor`}>
            <DoctorTable rows={overview?.byDoctor ?? []} active={resourceId} onSelect={toggle(setResourceId, resourceId)} currency={currency} loading={overviewLoading} />
          </Widget>
        );
      case 'branches':
        return (
          <Widget id="branches" title="Branch comparison" subtitle="Patients seen and revenue realised per branch">
            {(overview?.byBranch.length ?? 0) <= 1 && !branchId ? (
              <div className="clinic-empty">{overview?.byBranch.length === 1 ? 'One branch in this range. Add branches under Branches to compare them here.' : 'No appointments in this range.'}</div>
            ) : (
              <>
                <BarList
                  data={(overview?.byBranch ?? []).map((b) => ({ key: b.branchId ?? 'none', label: b.name, value: b.patients, sub: `${formatMoney(b.revenue, currency)}${b.completionRate != null ? ` · ${formatPercent(b.completionRate)} completed` : ''}` }))}
                  active={branchId}
                  onSelect={(key) => setBranchId(branchId === key || key === 'none' ? '' : key)}
                  format={(v) => `${v} patient${v === 1 ? '' : 's'}`}
                  hint="Click a branch to scope every panel to it."
                />
              </>
            )}
          </Widget>
        );
      case 'insurance':
        return (
          <Widget id="insurance" title="Insurance providers" subtitle="Registered patients by insurer">
            <BarList
              data={(overview?.byInsurance ?? []).map((i) => ({ key: i.provider, label: i.provider, value: i.patients, sub: i.appointments > 0 ? `${i.appointments} appt · ${formatMoney(i.revenue, currency)}` : undefined }))}
              active={insuranceProvider}
              onSelect={toggle(setInsuranceProvider, insuranceProvider)}
              format={(v) => `${v} patient${v === 1 ? '' : 's'}`}
              emptyText="No patients registered yet."
              hint="Click an insurer to filter appointments and revenue by it."
            />
          </Widget>
        );
      case 'hours':
        return (
          <Widget id="hours" title="Peak hours" subtitle="Appointment starts by hour of day">
            <HourChart data={overview?.byHour ?? []} loading={overviewLoading} />
          </Widget>
        );
      case 'sources':
        return (
          <Widget id="sources" title="Booking channels" subtitle="Where appointments were made">
            <BarList data={(overview?.bySource ?? []).map((s) => ({ key: s.source, label: s.source, value: s.appointments }))} />
          </Widget>
        );
      case 'reminders':
        return (
          <Widget id="reminders" title="Reminders & follow-ups" subtitle="Upcoming appointments and patients due back">
            <ClinicRemindersPanel data={reminders} loading={remindersLoading} />
          </Widget>
        );
      default:
        return null;
    }
  };

  return (
    <div className="clinic-dashboard">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant.name} src={profile?.logoUrl} />
              <div>
                <p className="hero-eyebrow">{descriptor}</p>
                <h1 className="hero-title">{tenant.name}</h1>
                <div className="hero-figure">{flow ? flow.stages.scheduled + flow.stages.waiting + flow.stages.inConsultation : '…'}</div>
                <p className="hero-sub">patients still to see today{criticalAlerts > 0 && <> · <b>{criticalAlerts} critical alert{criticalAlerts === 1 ? '' : 's'}</b></>}</p>
                <div className="clinic-hero-live"><i aria-hidden="true" />Live · waiting room and alerts refresh every minute</div>
              </div>
            </div>
            <div className="clinic-hero-actions">
              <div className="clinic-presets" role="tablist" aria-label="Dashboard view" style={{ background: 'rgba(255,255,255,.16)', borderColor: 'rgba(255,255,255,.35)' }}>
                <button type="button" role="tab" aria-selected={view === 'operations'} className={view === 'operations' ? 'active' : ''} style={view !== 'operations' ? { color: '#fff' } : undefined} onClick={() => setView('operations')}>Operations</button>
                <button type="button" role="tab" aria-selected={view === 'calendar'} className={view === 'calendar' ? 'active' : ''} style={view !== 'calendar' ? { color: '#fff' } : undefined} onClick={() => setView('calendar')}>Calendar</button>
              </div>
              {view === 'operations' && (
                <>
                  <button type="button" className="btn btn-secondary" onClick={exportCsv} disabled={!overview} title="Download the current range and grouping as a CSV report">
                    ⤓ Export CSV
                  </button>
                  <div className="clinic-customise">
                    <button type="button" className="btn btn-secondary" aria-expanded={customising} onClick={() => setCustomising((c) => !c)}>
                      ⚙ Customise
                    </button>
                    {customising && (
                      <>
                        <button type="button" className="clinic-scrim" aria-label="Close" onClick={() => setCustomising(false)} />
                        <CustomisePanel layout={layout} onChange={updateLayout} onClose={() => setCustomising(false)} />
                      </>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>

          <div className="hero-tiles">
            <HeroTile label="Appointments today" value={flow ? flow.queue.filter((q) => q.stage !== 'cancelled').length : '…'} sub={flow ? `${flow.stages.completed} completed` : ''} />
            <HeroTile label="Waiting now" value={flow ? flow.stages.waiting : '…'} sub={flow?.longestWaitMinutes != null ? `longest ${formatMinutes(flow.longestWaitMinutes)}` : 'nobody waiting'} />
            <HeroTile label="In consultation" value={flow ? flow.stages.inConsultation : '…'} sub={flow && flow.rooms.total > 0 ? `${flow.rooms.occupied}/${flow.rooms.total} rooms in use` : 'right now'} />
            <HeroTile label="Doctors on duty" value={flow ? flow.doctorsOnDuty : '…'} sub={flow?.patientsPerDoctor != null ? `${flow.patientsPerDoctor} patients each` : 'no appointments yet'} />
          </div>
        </div>
      </section>

      {view === 'calendar' ? (
        <CalendarDashboardPage />
      ) : (
        <>
          <ClinicAlerts alerts={alertsData?.alerts ?? []} loading={alertsLoading} />

          <div className="filter-bar clinic-filters" role="group" aria-label="Report filters">
            <span className="clinic-filter-label">Range</span>
            <div className="clinic-presets">
              {PRESETS.map((p) => (
                <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} onClick={() => applyPreset(p.id)}>{p.label}</button>
              ))}
            </div>
            <span className="clinic-filter-label" title="Report presets set both the window and the grouping">Report</span>
            <div className="clinic-presets">
              {REPORT_PRESETS.map((p) => (
                <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} title={p.title} onClick={() => applyPreset(p.id)}>{p.label}</button>
              ))}
            </div>
            <input className="input" type="date" value={range.from} max={range.to} onChange={(e) => setCustom({ from: e.target.value })} aria-label="From date" />
            <span style={{ color: 'var(--color-text-muted)' }}>to</span>
            <input className="input" type="date" value={range.to} min={range.from} onChange={(e) => setCustom({ to: e.target.value })} aria-label="To date" />
            <select className="input" value={range.groupBy} onChange={(e) => setCustom({ groupBy: e.target.value as ClinicGroupBy })} aria-label="Group trend by">
              <option value="day">By day</option>
              <option value="week">By week</option>
              <option value="month">By month</option>
            </select>
            <span className="clinic-filters-spacer" />
            {(options?.branches.length ?? 0) > 1 && (
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)} aria-label="Branch">
                <option value="">All branches</option>
                {options!.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            )}
            <select className="input" value={resourceId} onChange={(e) => setResourceId(e.target.value)} aria-label="Doctor">
              <option value="">All doctors</option>
              {(options?.doctors ?? []).map((d) => <option key={d.id} value={d.id}>{d.name}{d.specialty ? ` · ${d.specialty}` : ''}</option>)}
            </select>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} aria-label="Treatment type">
              <option value="">All treatments</option>
              {(options?.treatments ?? []).map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
            <select className="input" value={insuranceProvider} onChange={(e) => setInsuranceProvider(e.target.value)} aria-label="Insurance provider">
              <option value="">All insurers</option>
              {(options?.insuranceProviders ?? []).map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>

          {activeFilters.length > 0 && (
            <div className="clinic-active-filters" aria-live="polite">
              {activeFilters.map((f) => (
                <span key={f.key} className="clinic-chip">{f.label}<button type="button" aria-label={`Clear ${f.label}`} onClick={f.clear}>×</button></span>
              ))}
              <button type="button" className="btn btn-ghost btn-sm" onClick={clearFilters}>Clear all</button>
            </div>
          )}

          <div className="stat-grid" aria-busy={overviewFetching}>
            <Stat label="Patients" value={kpis?.totalPatients} sub={kpis ? `${kpis.newPatients} new · ${kpis.activePatients} seen in range` : ''} loading={overviewLoading} />
            <Stat label="Doctors" value={kpis?.totalDoctors} sub={kpis ? `${kpis.doctorsOnDutyToday} on duty today${kpis.rooms > 0 ? ` · ${kpis.rooms} rooms` : ''}` : ''} loading={overviewLoading} />
            <Stat label="Appointments" value={kpis?.totalAppointments} sub={kpis ? `${kpis.appointmentsToday} today · ${kpis.pending} awaiting confirmation` : ''} loading={overviewLoading} />
            {canSeeReports && (
              <Stat label="Revenue" value={kpis ? formatMoney(kpis.revenueRealised, currency) : undefined} sub={kpis ? `${formatMoney(kpis.revenueBooked, currency)} booked` : ''} loading={overviewLoading} />
            )}
            <Stat label="Completion rate" value={kpis ? formatPercent(kpis.completionRate) : undefined} sub={kpis ? `${kpis.completed} completed` : ''} loading={overviewLoading} tone="good" />
            <Stat label="No-show rate" value={kpis ? formatPercent(kpis.noShowRate) : undefined} sub={kpis ? `${kpis.noShows} no-shows · ${kpis.cancelled} cancelled` : ''} loading={overviewLoading} tone="critical" />
            <Stat label="Avg wait" value={kpis ? formatMinutes(kpis.avgWaitMinutes) : undefined} sub={kpis ? (kpis.waitSamples > 0 ? `check-in to consult · ${kpis.waitSamples} visits` : 'measured once consults are started from the flow board') : ''} loading={overviewLoading} tone="warning" />
            <Stat label="Patients per doctor" value={kpis?.patientsPerDoctorToday ?? (kpis ? '—' : undefined)} sub={kpis ? `today · avg visit ${formatMinutes(kpis.avgVisitMinutes)}` : ''} loading={overviewLoading} />
          </div>

          <div className="clinic-grid">
            {visibleWidgets.map((id) => <Fragment key={id}>{renderWidget(id)}</Fragment>)}
          </div>
          {visibleWidgets.length === 0 && (
            <div className="clinic-empty">Every panel is hidden. Use Customise to bring some back.</div>
          )}
        </>
      )}
    </div>
  );
}

// ── Small pieces ───────────────────────────────────────────────────────

function HeroTile({ label, value, sub }: { label: string; value: ReactNode; sub: string }) {
  return (
    <div className="hero-tile">
      <div className="hero-tile-label">{label}</div>
      <div className="hero-tile-value">{value}</div>
      <div className="hero-tile-sub">{sub}</div>
    </div>
  );
}

function Stat({ label, value, sub, loading, tone }: { label: string; value: ReactNode | undefined; sub: string; loading: boolean; tone?: 'good' | 'warning' | 'critical' }) {
  const color = tone ? `var(--color-${tone})` : undefined;
  return (
    <div className="stat-tile">
      <div className="stat-tile-label">{label}</div>
      <div className="stat-tile-value" style={color ? { color } : undefined}>{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="stat-tile-sub">{loading ? '…' : sub}</div>
    </div>
  );
}

function Widget({ id, title, subtitle, children }: { id: ClinicWidgetId; title: string; subtitle: string; children: ReactNode }) {
  const meta = CLINIC_WIDGETS.find((w) => w.id === id);
  return (
    <section id={id} className={`card chart-card clinic-widget${meta?.wide ? ' clinic-widget-wide' : ''}`} aria-labelledby={`clinic-${id}-title`}>
      <div className="clinic-widget-head">
        <div>
          <p className="chart-title" id={`clinic-${id}-title`}>{title}</p>
          <p className="chart-subtitle">{subtitle}</p>
        </div>
      </div>
      {children}
    </section>
  );
}

function DoctorTable({
  rows, active, onSelect, currency, loading,
}: {
  rows: ClinicOverview['byDoctor'];
  active: string;
  onSelect: (id: string) => void;
  currency: string;
  loading: boolean;
}) {
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="clinic-empty">No appointments in this range.</div>;
  const maxLoad = Math.max(1, ...rows.map((r) => r.appointments));
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            <th>Doctor</th>
            <th>Load</th>
            <th>Completed</th>
            <th>No-shows</th>
            <th>Avg wait</th>
            <th style={{ textAlign: 'right' }}>Revenue</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const decided = r.completed + r.noShows;
            return (
              <tr
                key={r.resourceId}
                className={`clinic-doctor-row${active === r.resourceId ? ' is-active' : ''}`}
                onClick={() => onSelect(r.resourceId)}
                tabIndex={0}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(r.resourceId); } }}
                aria-pressed={active === r.resourceId}
                title={active === r.resourceId ? 'Clear the doctor filter' : `Filter the dashboard by ${r.name}`}
              >
                <td>
                  <span className="clinic-doctor-name">{r.name}</span>
                  <span className="clinic-doctor-sub">{[r.specialty, r.branchName].filter(Boolean).join(' · ')}</span>
                </td>
                <td style={{ whiteSpace: 'nowrap' }}>
                  <span className="clinic-mini-track"><span className="clinic-mini-fill" style={{ width: `${(r.appointments / maxLoad) * 100}%`, background: 'var(--clinic-chart-a)' }} /></span>
                  {r.appointments}
                </td>
                <td>{r.completed}{decided > 0 && <span className="clinic-doctor-sub">{Math.round((r.completed / decided) * 100)}% of decided</span>}</td>
                <td style={{ color: r.noShows > 0 ? 'var(--color-critical)' : undefined }}>{r.noShows}</td>
                <td>{formatMinutes(r.avgWaitMinutes)}</td>
                <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{formatMoney(r.revenue, currency)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function CustomisePanel({ layout, onChange, onClose }: { layout: ClinicLayout; onChange: (l: ClinicLayout) => void; onClose: () => void }) {
  return (
    <div className="clinic-customise-panel" role="dialog" aria-label="Customise dashboard panels">
      <h4>Panels — tick to show, arrows to reorder</h4>
      {layout.order.map((id, index) => {
        const meta = CLINIC_WIDGETS.find((w) => w.id === id)!;
        const shown = !layout.hidden.includes(id);
        return (
          <div key={id} className="clinic-customise-row">
            <input id={`clinic-widget-${id}`} type="checkbox" checked={shown} onChange={() => onChange(toggleWidget(layout, id))} />
            <label htmlFor={`clinic-widget-${id}`}>{meta.label}<small>{meta.hint}</small></label>
            <span className="clinic-reorder">
              <button type="button" aria-label={`Move ${meta.label} up`} disabled={index === 0} onClick={() => onChange(moveWidget(layout, id, -1))}>▲</button>
              <button type="button" aria-label={`Move ${meta.label} down`} disabled={index === layout.order.length - 1} onClick={() => onChange(moveWidget(layout, id, 1))}>▼</button>
            </span>
          </div>
        );
      })}
      <div className="clinic-customise-foot">
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(DEFAULT_LAYOUT)}>Reset to default</button>
        <button type="button" className="btn btn-primary btn-sm" onClick={onClose}>Done</button>
      </div>
    </div>
  );
}
