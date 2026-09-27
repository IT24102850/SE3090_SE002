import { Fragment, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import { useGetGymAlertsQuery, useGetGymLiveQuery, useGetGymOverviewQuery } from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { businessDescriptor, businessHeroImage } from '../../../shared/businessImagery';
import { formatTime } from '../../../shared/dateUtils';
import BusinessAvatar from '../../../shared/components/BusinessAvatar';
import CalendarDashboardPage from '../../booking/CalendarDashboardPage';
import type { ClinicAlert, GymGroupBy, GymOverview, Tenant, TenantProfile } from '../../booking/types';
import GymAttendanceLog from './GymAttendanceLog';
import { BarList, Heatmap, TargetBar, TREND_LABEL, TrendChart, type TrendMetric } from './GymCharts';
import GymLiveMonitor from './GymLiveMonitor';
import {
  canSeeFinance,
  defaultLayout,
  loadLayout,
  moveWidget,
  saveLayout,
  toggleWidget,
  widgetsFor,
  type GymLayout,
  type GymRole,
  type GymWidgetId,
} from './gymLayout';
import {
  deltaPercent,
  downloadCsv,
  formatCount,
  formatDelta,
  formatMinutes,
  formatMoney,
  formatPercent,
  hourLabel,
  overviewToCsv,
  presetRange,
  tzOffsetMinutes,
  type GymRangePreset,
} from './gymReport';
import './gym.css';

/* The gym's dashboard: the floor right now, the membership book, the
 * money against target, and the equipment - one screen.
 *
 * Top to bottom: alerts, four headline cards with their change against
 * the previous period, the finer KPIs for the window, then the panels:
 * the live check-in monitor, the peak-hours heatmap, memberships and
 * renewals, the searchable attendance log, revenue against MTD / YTD
 * targets, payment status, plans and sign-ups, demographics, classes,
 * trainers, zones, equipment utilisation and maintenance. Breakdowns
 * cross-filter (a class, a trainer, a zone, a plan), the window has the
 * usual presets and the whole view exports as one CSV.
 *
 * Role views live in gymLayout.ts: owners get the money, front-desk and
 * trainers get the floor, the log, classes and equipment and never a
 * revenue figure. The month calendar is still under "Calendar". */

const LIVE_POLL_MS = 30_000;

type View = 'operations' | 'calendar';

const PRESETS: { id: GymRangePreset; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: '7d', label: '7 days' },
  { id: '30d', label: '30 days' },
  { id: 'month', label: 'This month' },
];
const REPORT_PRESETS: { id: GymRangePreset; label: string; title: string }[] = [
  { id: 'daily', label: 'Daily', title: 'Daily report: the last 14 days, one row per day' },
  { id: 'weekly', label: 'Weekly', title: 'Weekly report: the last 12 weeks, one row per week' },
  { id: 'monthly', label: 'Monthly', title: 'Monthly report: the last 12 months, one row per month' },
];

const ROLE_VIEW: Record<GymRole, string> = { Admin: 'Owner view', Manager: 'Manager view', Staff: 'Floor view', Customer: '' };
const ICON: Record<ClinicAlert['severity'], string> = { critical: '!', warning: '△', info: 'i' };
const MAINT_LABEL: Record<string, string> = { none: 'No schedule', scheduled: 'Scheduled', dueSoon: 'Due soon', overdue: 'Overdue', usageDue: 'Due by usage', inService: 'In service' };

export default function GymDashboard({ tenant, profile }: { tenant: Tenant; profile?: TenantProfile }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const userId = user?.id ?? 'anon';
  const role = user?.role as GymRole | undefined;
  const finance = canSeeFinance(role);
  const tz = useMemo(() => tzOffsetMinutes(), []);

  const [view, setView] = useState<View>(() => {
    try {
      return (localStorage.getItem(`gym-dashboard-view:${tenantId}`) as View) || 'operations';
    } catch {
      return 'operations';
    }
  });
  useEffect(() => {
    try {
      localStorage.setItem(`gym-dashboard-view:${tenantId}`, view);
    } catch {
      // Per-viewer convenience only.
    }
  }, [view, tenantId]);

  // ── Filters ──────────────────────────────────────────────────────────
  const [preset, setPreset] = useState<GymRangePreset>('30d');
  const [range, setRange] = useState(() => presetRange('30d'));
  const [branchId, setBranchId] = useState('');
  const [resourceId, setResourceId] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [plan, setPlan] = useState('');

  const applyPreset = (id: GymRangePreset) => {
    setPreset(id);
    if (id !== 'custom') setRange(presetRange(id));
  };
  const setCustom = (patch: Partial<typeof range>) => {
    setPreset('custom');
    setRange((r) => ({ ...r, ...patch }));
  };
  const clearFilters = () => { setBranchId(''); setResourceId(''); setBookingTypeId(''); setPlan(''); };
  const toggle = (setter: (v: string) => void, current: string) => (key: string) => setter(current === key ? '' : key);

  // ── Data ─────────────────────────────────────────────────────────────
  const overviewParams = useMemo(() => ({
    from: range.from, to: range.to, groupBy: range.groupBy, tz,
    branchId: branchId || undefined, resourceId: resourceId || undefined, bookingTypeId: bookingTypeId || undefined, plan: plan || undefined,
  }), [range, tz, branchId, resourceId, bookingTypeId, plan]);
  const { data: overview, isLoading: overviewLoading, isFetching: overviewFetching } = useGetGymOverviewQuery(overviewParams, { skip: !tenantId });
  const liveParams = useMemo(() => ({ tz, branchId: branchId || undefined, resourceId: resourceId || undefined }), [tz, branchId, resourceId]);
  const { data: live, isLoading: liveLoading } = useGetGymLiveQuery(liveParams, { skip: !tenantId, pollingInterval: LIVE_POLL_MS });
  const { data: alertsData, isLoading: alertsLoading } = useGetGymAlertsQuery({ tz, branchId: branchId || undefined }, { skip: !tenantId, pollingInterval: LIVE_POLL_MS * 2 });

  const kpis = overview?.kpis;
  const prev = overview?.previous;
  const options = overview?.filterOptions;
  const targets = overview?.targets;
  const currency = kpis?.currency ?? 'LKR';

  // ── Layout ───────────────────────────────────────────────────────────
  const [layout, setLayout] = useState<GymLayout>(() => loadLayout(tenantId, userId, role));
  const [customising, setCustomising] = useState(false);
  const updateLayout = useCallback((next: GymLayout) => { setLayout(next); saveLayout(tenantId, userId, role, next); }, [tenantId, userId, role]);
  const widgets = widgetsFor(role);
  const visibleWidgets = layout.order.filter((id) => !layout.hidden.includes(id) && widgets.some((w) => w.id === id));

  const [trendMetric, setTrendMetric] = useState<TrendMetric>(finance ? 'revenue' : 'visits');

  const exportCsv = () => {
    if (!overview) return;
    downloadCsv(`gym-report-${range.groupBy}-${range.from}-to-${range.to}.csv`, overviewToCsv(overview, finance));
  };

  const heroImage = businessHeroImage({ businessType: tenant.businessType, subType: tenant.subType, coverImageUrl: profile?.coverImageUrl });
  const descriptor = businessDescriptor({ businessType: tenant.businessType, subType: tenant.subType });
  const criticalAlerts = (alertsData?.alerts ?? []).filter((a) => a.severity === 'critical').length;

  const activeFilters = [
    branchId && { key: 'branch', label: `Branch: ${options?.branches.find((b) => b.id === branchId)?.name ?? '…'}`, clear: () => setBranchId('') },
    resourceId && { key: 'resource', label: `${options?.zones.some((z) => z.id === resourceId) ? 'Zone' : 'Trainer'}: ${[...(options?.zones ?? []), ...(options?.trainers ?? [])].find((r) => r.id === resourceId)?.name ?? '…'}`, clear: () => setResourceId('') },
    bookingTypeId && { key: 'class', label: `Activity: ${options?.bookingTypes.find((t) => t.id === bookingTypeId)?.name ?? '…'}`, clear: () => setBookingTypeId('') },
    plan && { key: 'plan', label: `Plan: ${plan}`, clear: () => setPlan('') },
  ].filter(Boolean) as { key: string; label: string; clear: () => void }[];

  const rangeLabel = range.from === range.to ? range.from : `${range.from} – ${range.to}`;

  // ── Widgets ──────────────────────────────────────────────────────────
  const renderWidget = (id: GymWidgetId): ReactNode => {
    switch (id) {
      case 'live':
        return (
          <Widget id="live" role={role} title="Live check-in monitor" subtitle={`Today · refreshes every ${LIVE_POLL_MS / 1000}s`}>
            <GymLiveMonitor live={live} loading={liveLoading} />
          </Widget>
        );
      case 'heatmap':
        return (
          <Widget id="heatmap" role={role} title="Peak hours" subtitle={`${rangeLabel} · check-ins by day and hour, local time`}>
            <Heatmap data={overview?.heatmap ?? []} loading={overviewLoading} />
            {kpis && kpis.peakHour != null && <p className="gym-note">Busiest hour overall: <b>{hourLabel(kpis.peakHour)}</b> with {kpis.peakHourCheckIns} check-ins. Roster the floor around it.</p>}
          </Widget>
        );
      case 'members':
        return (
          <Widget id="members" role={role} title="Memberships" subtitle="Where the book stands, and who is due to renew">
            <div className="gym-stages">
              <Tile label="Active" value={kpis?.activeMembers} sub={kpis ? `${kpis.frozenMembers} frozen` : ''} loading={overviewLoading} />
              <Tile label="Expired" value={kpis?.expiredMembers} sub={kpis ? `${kpis.cancelledMembers} cancelled · ${kpis.withoutMembership} none` : ''} loading={overviewLoading} alert={(kpis?.expiredMembers ?? 0) > 0} />
              <Tile label="Renewals due" value={kpis?.renewalsDue30} sub={kpis ? `${kpis.renewalsDue7} within 7 days` : ''} loading={overviewLoading} alert={(kpis?.renewalsDue7 ?? 0) > 0} />
              <Tile label="Churn" value={kpis ? formatPercent(kpis.churnRate) : undefined} sub={kpis ? `${kpis.lapsed} lapsed · ${kpis.signUps} signed up in range` : ''} loading={overviewLoading} />
            </div>
            <p className="gym-subhead">Renewals in the next 30 days</p>
            {overviewLoading && !overview ? (
              <div className="loading-row"><span className="spinner spinner-dark" /></div>
            ) : (overview?.renewals.length ?? 0) === 0 ? (
              <div className="gym-empty">Nothing expiring in the next 30 days.</div>
            ) : (
              <div className="gym-list">
                {overview!.renewals.map((r) => (
                  <div key={r.subscriptionId} className={`gym-list-row${r.daysLeft <= 7 ? ' gym-list-row-urgent' : ''}`}>
                    <div className="gym-list-main">
                      <strong>{r.memberName}</strong>
                      <span>{r.plan}{r.autoRenew ? ' · auto-renews' : ' · manual renewal'}{r.phone ? ` · ${r.phone}` : ''}{r.paymentStatus !== 'Paid' ? ` · ${r.paymentStatus.toLowerCase()} payment` : ''}</span>
                    </div>
                    <div className="gym-list-side">
                      <b style={{ color: r.daysLeft <= 7 ? 'var(--color-warning)' : undefined }}>{r.daysLeft <= 0 ? 'today' : `${r.daysLeft} day${r.daysLeft === 1 ? '' : 's'}`}</b>
                      <small>{finance ? formatMoney(r.amount, currency) : r.endDate.slice(0, 10)}</small>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Widget>
        );
      case 'attendance':
        return (
          <Widget id="attendance" role={role} title="Attendance log" subtitle={`${rangeLabel} · every check-in, newest first`}>
            <GymAttendanceLog from={range.from} to={range.to} tz={tz} branchId={branchId || undefined} resourceId={resourceId || undefined} />
          </Widget>
        );
      case 'revenue':
        return (
          <Widget
            id="revenue" role={role} title="Revenue vs target" subtitle="Memberships paid plus drop-in and PT sales"
            tools={(
              <div className="gym-presets" role="tablist" aria-label="Trend metric">
                {(Object.keys(TREND_LABEL) as TrendMetric[]).map((m) => (
                  <button key={m} type="button" role="tab" aria-selected={trendMetric === m} className={trendMetric === m ? 'active' : ''} onClick={() => setTrendMetric(m)}>{TREND_LABEL[m]}</button>
                ))}
              </div>
            )}
          >
            {kpis && targets && (
              <div className="gym-targets">
                <TargetBar label="Month to date" value={kpis.revenueMtd} target={targets.monthlyRevenueTarget} currency={currency} sub={targets.monthTargetToDate != null ? `${kpis.revenueMtd >= targets.monthTargetToDate ? 'ahead of' : 'behind'} pace (${formatMoney(targets.monthTargetToDate, currency)} expected by today)` : undefined} />
                <TargetBar label="Year to date" value={kpis.revenueYtd} target={targets.yearlyRevenueTarget} currency={currency} sub={`recurring ${formatMoney(kpis.monthlyRecurring, currency)} / month`} />
              </div>
            )}
            <TrendChart data={overview?.trend ?? []} metric={trendMetric} currency={currency} loading={overviewLoading} />
          </Widget>
        );
      case 'payments':
        return (
          <Widget id="payments" role={role} title="Payment status" subtitle="Current memberships by the state of their latest billing">
            <BarList
              data={(overview?.payment ?? []).map((p) => ({ key: p.status, label: p.status, value: p.memberships, sub: formatMoney(p.amount, currency), color: p.status === 'Paid' ? 'var(--color-good)' : p.status === 'Pending' ? 'var(--color-warning)' : 'var(--color-critical)' }))}
              format={(v) => `${v} membership${v === 1 ? '' : 's'}`}
              emptyText="No memberships on file."
            />
            {(overview?.outstanding.length ?? 0) > 0 && (
              <>
                <p className="gym-subhead" style={{ marginTop: 14 }}>To chase</p>
                <div className="gym-list">
                  {overview!.outstanding.map((o) => (
                    <div key={o.subscriptionId} className="gym-list-row">
                      <div className="gym-list-main"><strong>{o.memberName}</strong><span>{o.plan}{o.phone ? ` · ${o.phone}` : ''}{o.nextBillingAt ? ` · billed ${o.nextBillingAt.slice(0, 10)}` : ''}</span></div>
                      <div className="gym-list-side"><b>{formatMoney(o.amount, currency)}</b><small className={o.paymentStatus === 'Pending' ? 'gym-maint-due' : 'gym-maint-overdue'}>{o.paymentStatus}</small></div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </Widget>
        );
      case 'sales':
        return (
          <Widget id="sales" role={role} title="Sales & plans" subtitle={`${rangeLabel} · popular plans, sign-ups and drop-in revenue`}>
            {kpis && (
              <div className="gym-stages">
                <Tile label="Sign-ups" value={kpis.signUps} sub={prev ? formatDelta(deltaPercent(kpis.signUps, prev.signUps)) : ''} loading={overviewLoading} />
                <Tile label="Membership revenue" value={formatMoney(kpis.membershipRevenue, currency)} sub="paid in range" loading={overviewLoading} />
                <Tile label="Drop-in & PT" value={formatMoney(kpis.dropInRevenue, currency)} sub="day passes, trials, sessions" loading={overviewLoading} />
              </div>
            )}
            <BarList
              data={(overview?.byPlan ?? []).map((p) => ({ key: p.plan, label: p.plan, value: p.members, sub: `${formatMoney(p.monthlyValue, currency)} / month · ${p.signUpsInRange} new` }))}
              active={plan}
              onSelect={toggle(setPlan, plan)}
              format={(v) => `${v} active`}
              hint="Click a plan to filter attendance and revenue by its members."
              emptyText="No memberships on file."
            />
          </Widget>
        );
      case 'demographics':
        return (
          <Widget id="demographics" role={role} title="Demographics" subtitle="Active members by age band, gender and tier">
            <div className="gym-split-3">
              <div><p className="gym-subhead">Age</p><BarList data={(overview?.byAge ?? []).filter((a) => a.members > 0).map((a) => ({ key: a.band, label: a.band, value: a.members }))} emptyText="No active members." /></div>
              <div><p className="gym-subhead">Gender</p><BarList data={(overview?.byGender ?? []).map((g) => ({ key: g.gender, label: g.gender, value: g.members }))} emptyText="No active members." /></div>
              <div><p className="gym-subhead">Tier</p><BarList data={(overview?.byPlan ?? []).map((p) => ({ key: p.plan, label: p.plan, value: p.members }))} active={plan} onSelect={toggle(setPlan, plan)} emptyText="No active members." /></div>
            </div>
            <p className="gym-note">Age and gender are self-declared on the member profile; blanks show as "Not stated".</p>
          </Widget>
        );
      case 'classes':
        return (
          <Widget id="classes" role={role} title="Class attendance" subtitle={`${rangeLabel} · click a class to filter · today's sessions below`}>
            <ClassTable overview={overview} active={bookingTypeId} onSelect={toggle(setBookingTypeId, bookingTypeId)} currency={currency} finance={finance} loading={overviewLoading} />
            {live && live.classesToday.length > 0 && (
              <>
                <p className="gym-subhead" style={{ marginTop: 14 }}>Today</p>
                <div className="gym-list" style={{ maxHeight: 'none' }}>
                  {live.classesToday.map((c) => (
                    <div key={`${c.bookingTypeId}-${c.startTime}`} className={`gym-list-row${c.isFull ? ' gym-list-row-urgent' : ''}`}>
                      <div className="gym-list-main">
                        <strong>{formatTime(c.startTime)} · {c.name}</strong>
                        <span>{c.resourceName} · {c.state === 'done' ? 'finished' : c.state === 'inProgress' ? 'in progress' : 'upcoming'}{c.checkedIn > 0 ? ` · ${c.checkedIn} checked in` : ''}</span>
                      </div>
                      <div className="gym-list-side">
                        <b>{c.booked}{c.capacity ? ` / ${c.capacity}` : ''}</b>
                        <small>{c.isFull ? 'full' : c.fillPercent != null ? `${c.fillPercent}% booked` : 'booked'}</small>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </Widget>
        );
      case 'trainers':
        return (
          <Widget id="trainers" role={role} title="Trainer load" subtitle="Sessions and bookings per trainer · click to filter">
            <BarList
              data={(overview?.byTrainer ?? []).map((t) => ({ key: t.resourceId, label: t.name, value: t.bookings, sub: [t.specialty, `${t.sessions} sessions`, finance && t.revenue > 0 ? formatMoney(t.revenue, currency) : null].filter(Boolean).join(' · ') }))}
              active={resourceId}
              onSelect={toggle(setResourceId, resourceId)}
              format={(v) => `${v} booking${v === 1 ? '' : 's'}`}
              emptyText="No trainer sessions in this range."
            />
            {live && live.trainers.list.length > 0 && (
              <p className="gym-note">Now: {live.trainers.list.filter((t) => t.onFloor).map((t) => t.name).join(', ') || 'nobody rostered'} · {live.trainers.rostered} rostered today.</p>
            )}
          </Widget>
        );
      case 'zones':
        return (
          <Widget id="zones" role={role} title="Zone utilisation" subtitle={`Booked hours against ${targets?.openHoursPerDay ?? 15} opening hours a day · click to filter`}>
            <BarList
              data={(overview?.byZone ?? []).map((z) => ({ key: z.resourceId, label: z.name, value: z.utilisationPercent ?? 0, sub: `${z.visits} visits · ${z.hoursBooked} h${z.capacity ? ` · cap ${z.capacity}` : ''}` }))}
              active={resourceId}
              onSelect={toggle(setResourceId, resourceId)}
              format={(v) => `${v.toFixed(1)}%`}
              emptyText="No zones. Add Room resources (weights floor, studio, cardio…) with a capacity."
            />
          </Widget>
        );
      case 'equipment':
        return (
          <Widget id="equipment" role={role} title="Equipment & maintenance" subtitle={`${rangeLabel} · usage per machine, and what is due for service (every ${targets?.maintenanceEveryUses ?? 200} uses or by date)`}>
            <EquipmentTable overview={overview} loading={overviewLoading} />
          </Widget>
        );
      case 'methods':
        return (
          <Widget id="methods" role={role} title="Check-in methods" subtitle="How members came through the door">
            <BarList data={(overview?.byMethod ?? []).map((m) => ({ key: m.method, label: m.method, value: m.checkIns }))} emptyText="No check-ins in this range." />
            <p className="gym-note">The method is the booking's Source: the RFID reader, the mobile app and the biometric gate each write their own when they check a member in.</p>
          </Widget>
        );
      case 'branches':
        return (
          <Widget id="branches" role={role} title="Branch comparison" subtitle="Visits and members per branch">
            {(overview?.byBranch.length ?? 0) <= 1 && !branchId ? (
              <div className="gym-empty">{overview?.byBranch.length === 1 ? 'One branch in this range. Add branches under Branches to compare them here.' : 'No visits in this range.'}</div>
            ) : (
              <BarList data={(overview?.byBranch ?? []).map((b) => ({ key: b.branchId ?? 'none', label: b.name, value: b.visits, sub: `${b.members} members` }))} active={branchId} onSelect={(key) => setBranchId(branchId === key || key === 'none' ? '' : key)} format={(v) => `${v} visit${v === 1 ? '' : 's'}`} />
            )}
          </Widget>
        );
      default:
        return null;
    }
  };

  const alerts = alertsData?.alerts ?? [];

  return (
    <div className="gym-dashboard">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant.name} src={profile?.logoUrl} />
              <div>
                <p className="hero-eyebrow">{descriptor}{role && ROLE_VIEW[role] && <> · <span className="gym-role-pill">{ROLE_VIEW[role]}</span></>}</p>
                <h1 className="hero-title">{tenant.name}</h1>
                <div className="hero-figure">{live ? live.insideNow : '…'}</div>
                <p className="hero-sub">members on the floor right now{live?.capacity ? ` · ${live.occupancyPercent}% of ${live.capacity}` : ''}{criticalAlerts > 0 && <> · <b>{criticalAlerts} critical alert{criticalAlerts === 1 ? '' : 's'}</b></>}</p>
                <div className="gym-hero-live"><i aria-hidden="true" />Live · check-ins, occupancy and alerts refresh every {LIVE_POLL_MS / 1000}s</div>
              </div>
            </div>
            <div className="gym-hero-actions">
              <div className="gym-presets" role="tablist" aria-label="Dashboard view" style={{ background: 'rgba(255,255,255,.16)', borderColor: 'rgba(255,255,255,.35)' }}>
                <button type="button" role="tab" aria-selected={view === 'operations'} className={view === 'operations' ? 'active' : ''} style={view !== 'operations' ? { color: '#fff' } : undefined} onClick={() => setView('operations')}>Operations</button>
                <button type="button" role="tab" aria-selected={view === 'calendar'} className={view === 'calendar' ? 'active' : ''} style={view !== 'calendar' ? { color: '#fff' } : undefined} onClick={() => setView('calendar')}>Calendar</button>
              </div>
              {view === 'operations' && (
                <>
                  <button type="button" className="btn btn-secondary" onClick={exportCsv} disabled={!overview} title="Download the current range and filters as a CSV report">⤓ Export CSV</button>
                  <div className="gym-customise">
                    <button type="button" className="btn btn-secondary" aria-expanded={customising} onClick={() => setCustomising((c) => !c)}>⚙ Customise</button>
                    {customising && (
                      <>
                        <button type="button" className="gym-scrim" aria-label="Close" onClick={() => setCustomising(false)} />
                        <CustomisePanel layout={layout} role={role} onChange={updateLayout} onClose={() => setCustomising(false)} />
                      </>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>

          <div className="hero-tiles">
            <HeroTile label="Check-ins today" value={live ? live.entriesToday : '…'} sub={live ? `${live.uniqueToday} unique · ${live.exitsToday} out` : ''} />
            <HeroTile label="Classes today" value={live ? live.classesToday.length : '…'} sub={live ? `${live.classesToday.filter((c) => c.isFull).length} full · ${live.classesToday.reduce((s, c) => s + c.booked, 0)} booked` : ''} />
            <HeroTile label="Trainers on floor" value={live ? live.trainers.onFloor : '…'} sub={live ? `${live.trainers.rostered} rostered today` : ''} />
            {finance ? (
              <HeroTile label="Revenue MTD" value={kpis ? formatMoney(kpis.revenueMtd, currency) : '…'} sub={targets?.monthlyRevenueTarget ? `${Math.round((kpis!.revenueMtd / targets.monthlyRevenueTarget) * 100)}% of ${formatMoney(targets.monthlyRevenueTarget, currency)}` : 'no monthly target set'} />
            ) : (
              <HeroTile label="Renewals due" value={kpis ? kpis.renewalsDue30 : '…'} sub={kpis ? `${kpis.renewalsDue7} within 7 days` : ''} />
            )}
          </div>
        </div>
      </section>

      {view === 'calendar' ? (
        <CalendarDashboardPage />
      ) : (
        <>
          {alertsLoading && alerts.length === 0 ? (
            <div className="loading-row"><span className="spinner spinner-dark" /> Checking for alerts…</div>
          ) : alerts.length === 0 ? (
            <div className="gym-alerts-clear" role="status"><b>✓</b> No operational alerts. Occupancy, renewals, billing, equipment and classes are all within limits.</div>
          ) : (
            <div className="gym-alerts" role="list" aria-label="Operational alerts">
              {alerts.map((alert) => {
                const inPage = alert.href.startsWith('/dashboard#');
                const body = (
                  <>
                    <span className="gym-alert-icon" aria-hidden="true">{ICON[alert.severity]}</span>
                    <span>
                      <p className="gym-alert-title"><span className="sr-only">{alert.severity}: </span>{alert.title}</p>
                      <p className="gym-alert-detail">{alert.detail}</p>
                    </span>
                    <span className="gym-alert-count">{alert.count}</span>
                  </>
                );
                const className = `gym-alert gym-alert-${alert.severity}`;
                return inPage
                  ? <a key={alert.id} className={className} href={alert.href.slice('/dashboard'.length)} role="listitem">{body}</a>
                  : <Link key={alert.id} className={className} to={alert.href} role="listitem">{body}</Link>;
              })}
            </div>
          )}

          <div className="filter-bar gym-filters" role="group" aria-label="Report filters">
            <span className="gym-filter-label">Range</span>
            <div className="gym-presets">
              {PRESETS.map((p) => <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} onClick={() => applyPreset(p.id)}>{p.label}</button>)}
            </div>
            <span className="gym-filter-label" title="Report presets set both the window and the grouping">Report</span>
            <div className="gym-presets">
              {REPORT_PRESETS.map((p) => <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} title={p.title} onClick={() => applyPreset(p.id)}>{p.label}</button>)}
            </div>
            <input className="input" type="date" value={range.from} max={range.to} onChange={(e) => setCustom({ from: e.target.value })} aria-label="From date" />
            <span style={{ color: 'var(--color-text-muted)' }}>to</span>
            <input className="input" type="date" value={range.to} min={range.from} onChange={(e) => setCustom({ to: e.target.value })} aria-label="To date" />
            <select className="input" value={range.groupBy} onChange={(e) => setCustom({ groupBy: e.target.value as GymGroupBy })} aria-label="Group trend by">
              <option value="hour">By hour</option>
              <option value="day">By day</option>
              <option value="week">By week</option>
              <option value="month">By month</option>
            </select>
            <span className="gym-filters-spacer" />
            {(options?.branches.length ?? 0) > 1 && (
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)} aria-label="Branch">
                <option value="">All branches</option>
                {options!.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            )}
            <select className="input" value={resourceId} onChange={(e) => setResourceId(e.target.value)} aria-label="Zone or trainer">
              <option value="">All zones & trainers</option>
              {(options?.zones ?? []).map((z) => <option key={z.id} value={z.id}>{z.name} · zone</option>)}
              {(options?.trainers ?? []).map((t) => <option key={t.id} value={t.id}>{t.name} · trainer</option>)}
            </select>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} aria-label="Activity">
              <option value="">All activities</option>
              {(options?.bookingTypes ?? []).map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
            <select className="input" value={plan} onChange={(e) => setPlan(e.target.value)} aria-label="Membership plan">
              <option value="">All plans</option>
              {(options?.plans ?? []).map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>

          {activeFilters.length > 0 && (
            <div className="gym-active-filters" aria-live="polite">
              {activeFilters.map((f) => <span key={f.key} className="gym-chip">{f.label}<button type="button" aria-label={`Clear ${f.label}`} onClick={f.clear}>×</button></span>)}
              <button type="button" className="btn btn-ghost btn-sm" onClick={clearFilters}>Clear all</button>
            </div>
          )}

          <div className="gym-kpis" aria-busy={overviewFetching}>
            <KpiCard icon="🏋️" label="Visits" value={formatCount(kpis?.visits)} delta={kpis && prev ? deltaPercent(kpis.visits, prev.visits) : null} loading={overviewLoading} />
            <KpiCard icon="🧑‍🤝‍🧑" label="Active members" value={formatCount(kpis?.activeMembers)} delta={null} sub={kpis ? `${kpis.newMembers} new in range · ${formatPercent(kpis.churnRate)} churn` : undefined} loading={overviewLoading} />
            {finance ? (
              <KpiCard icon="💰" label="Revenue" value={kpis ? formatMoney(kpis.revenue, currency) : '—'} delta={kpis && prev ? deltaPercent(kpis.revenue, prev.revenue) : null} loading={overviewLoading} />
            ) : (
              <KpiCard icon="🎟️" label="Class fill rate" value={kpis ? formatPercent(kpis.classFillRate) : '—'} delta={null} sub={kpis ? `${kpis.classBookings} bookings across ${kpis.classSessions} sessions` : undefined} loading={overviewLoading} />
            )}
            <KpiCard icon="🔔" label="Renewals due" value={formatCount(kpis?.renewalsDue30)} delta={null} sub={kpis ? `${kpis.renewalsDue7} within 7 days · ${kpis.overduePayments} unpaid` : undefined} loading={overviewLoading} />
          </div>

          <div className="stat-grid" aria-busy={overviewFetching}>
            <Stat label="Unique visitors" value={kpis?.uniqueVisitors} sub={kpis ? `${kpis.visitsPerDay} visits per day` : ''} loading={overviewLoading} />
            <Stat label="Avg visit" value={kpis ? formatMinutes(kpis.avgVisitMinutes) : undefined} sub={kpis ? (kpis.visitSamples > 0 ? `check-in to check-out · ${kpis.visitSamples} visits` : 'measured once members check out') : ''} loading={overviewLoading} />
            <Stat label="Peak hour" value={kpis ? hourLabel(kpis.peakHour) : undefined} sub={kpis ? `${kpis.peakHourCheckIns} check-ins` : ''} loading={overviewLoading} />
            <Stat label="Class fill rate" value={kpis ? formatPercent(kpis.classFillRate) : undefined} sub={kpis ? `${kpis.classSessions} sessions · ${kpis.classBookings} bookings` : ''} loading={overviewLoading} tone="good" />
            <Stat label="Equipment utilisation" value={kpis ? formatPercent(kpis.equipmentUtilisation) : undefined} sub={kpis ? `${kpis.equipmentItems} machines · ${kpis.maintenanceDue} due for service` : ''} loading={overviewLoading} tone={kpis && kpis.maintenanceDue > 0 ? 'warning' : undefined} />
            {finance && <Stat label="Monthly recurring" value={kpis ? formatMoney(kpis.monthlyRecurring, currency) : undefined} sub={kpis ? `${kpis.activeMembers} active memberships` : ''} loading={overviewLoading} />}
            {finance && <Stat label="Outstanding" value={kpis ? formatMoney(kpis.overdueAmount, currency) : undefined} sub={kpis ? `${kpis.overduePayments} pending / failed / overdue` : ''} loading={overviewLoading} tone={kpis && kpis.overduePayments > 0 ? 'critical' : 'good'} />}
            {!finance && <Stat label="Sign-ups" value={kpis?.signUps} sub={kpis ? `${kpis.lapsed} lapsed in range` : ''} loading={overviewLoading} />}
            <Stat label="Zones & trainers" value={kpis ? `${kpis.zones} / ${kpis.trainers}` : undefined} sub={targets?.facilityCapacity ? `capacity ${targets.facilityCapacity}` : 'set a capacity on each zone'} loading={overviewLoading} />
          </div>

          <div className="gym-grid">
            {visibleWidgets.map((id) => <Fragment key={id}>{renderWidget(id)}</Fragment>)}
          </div>
          {visibleWidgets.length === 0 && <div className="gym-empty">Every panel is hidden. Use Customise to bring some back.</div>}
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

function KpiCard({ icon, label, value, delta, loading, sub }: { icon: string; label: string; value: string; delta: number | null; loading: boolean; sub?: string }) {
  const tone = delta === null || delta === 0 ? 'flat' : delta > 0 ? 'up' : 'down';
  const arrow = delta === null || delta === 0 ? '·' : delta > 0 ? '↑' : '↓';
  return (
    <div className="gym-kpi">
      <div className="gym-kpi-icon" aria-hidden="true">{icon}</div>
      <div>
        <div className="gym-kpi-value">{loading && value === '—' ? '…' : value}</div>
        <div className="gym-kpi-label">{label}</div>
        <div className={`gym-kpi-delta gym-kpi-delta-${sub ? 'flat' : tone}`}><i aria-hidden="true">{sub ? '·' : arrow}</i>{sub ?? formatDelta(delta)}</div>
      </div>
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

function Tile({ label, value, sub, loading, alert }: { label: string; value: string | number | undefined; sub: string; loading: boolean; alert?: boolean }) {
  return (
    <div className={`gym-stage${alert ? ' gym-stage-alert' : ''}`}>
      <div className="gym-stage-label">{label}</div>
      <div className="gym-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="gym-stage-sub">{sub}</div>
    </div>
  );
}

function Widget({ id, role, title, subtitle, tools, children }: { id: GymWidgetId; role: GymRole | undefined; title: string; subtitle: string; tools?: ReactNode; children: ReactNode }) {
  const meta = widgetsFor(role).find((w) => w.id === id);
  return (
    <section id={id} className={`card chart-card gym-widget${meta?.wide ? ' gym-widget-wide' : ''}`} aria-labelledby={`gym-${id}-title`}>
      <div className="gym-widget-head">
        <div>
          <p className="chart-title" id={`gym-${id}-title`}>{title}</p>
          <p className="chart-subtitle">{subtitle}</p>
        </div>
        {tools && <div className="gym-widget-tools">{tools}</div>}
      </div>
      {children}
    </section>
  );
}

function ClassTable({ overview, active, onSelect, currency, finance, loading }: { overview?: GymOverview; active: string; onSelect: (id: string) => void; currency: string; finance: boolean; loading: boolean }) {
  const rows = overview?.byClass ?? [];
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="gym-empty">No class bookings in this range. Classes are booking types with a capacity (MaxParticipants) or kind "class".</div>;
  const max = Math.max(1, ...rows.map((r) => r.bookings));
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr><th>Class</th><th>Sessions</th><th>Bookings</th><th>Fill rate</th><th>Attended</th><th>No-shows</th>{finance && <th style={{ textAlign: 'right' }}>Revenue</th>}</tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.bookingTypeId} className={`gym-row-click${active === r.bookingTypeId ? ' is-active' : ''}`} onClick={() => onSelect(r.bookingTypeId)} tabIndex={0}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(r.bookingTypeId); } }} aria-pressed={active === r.bookingTypeId}>
              <td><span className="gym-strong"><i style={{ display: 'inline-block', width: 8, height: 8, borderRadius: 2, marginRight: 6, background: r.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{r.name}</span><span className="gym-sub">{r.capacityPerSession ? `capacity ${r.capacityPerSession} per session` : 'no capacity set'}{r.avgPerSession != null ? ` · avg ${r.avgPerSession} per session` : ''}</span></td>
              <td>{r.sessions}</td>
              <td style={{ whiteSpace: 'nowrap' }}><span className="gym-inline-track"><span className="gym-inline-fill" style={{ width: `${(r.bookings / max) * 100}%` }} /></span>{r.bookings}</td>
              <td style={{ color: r.fillRate != null && r.fillRate >= 90 ? 'var(--color-good)' : undefined }}>{formatPercent(r.fillRate)}</td>
              <td>{r.attended}</td>
              <td style={{ color: r.noShows > 0 ? 'var(--color-critical)' : undefined }}>{r.noShows}</td>
              {finance && <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{formatMoney(r.revenue, currency)}</td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function EquipmentTable({ overview, loading }: { overview?: GymOverview; loading: boolean }) {
  const rows = overview?.byEquipment ?? [];
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="gym-empty">No equipment on file. Add machines under Equipment (one row per model, units = how many are on the floor).</div>;
  const max = Math.max(1, ...rows.map((r) => r.hoursUsed));
  const cls = (s: string) => (s === 'overdue' || s === 'inService' ? 'gym-maint-overdue' : s === 'dueSoon' || s === 'usageDue' ? 'gym-maint-due' : 'gym-maint-ok');
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr><th>Machine</th><th>Units</th><th>Hours used</th><th>Utilisation</th><th>Uses since service</th><th>Next service</th><th>Status</th></tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.equipmentItemId}>
              <td><span className="gym-strong">{r.name}</span><span className="gym-sub">{r.category}{r.lastServicedAt ? ` · last serviced ${r.lastServicedAt.slice(0, 10)}` : ' · never serviced'}</span></td>
              <td>{r.units}</td>
              <td style={{ whiteSpace: 'nowrap' }}><span className="gym-inline-track"><span className="gym-inline-fill" style={{ width: `${(r.hoursUsed / max) * 100}%` }} /></span>{r.hoursUsed} h</td>
              <td>{formatPercent(r.utilisationPercent)}</td>
              <td style={{ color: r.usesSinceService >= r.maintenanceEveryUses ? 'var(--color-warning)' : undefined }}>{r.usesSinceService} / {r.maintenanceEveryUses}</td>
              <td style={{ whiteSpace: 'nowrap' }}>{r.nextDueAt ? r.nextDueAt.slice(0, 10) : '—'}</td>
              <td><span className={cls(r.maintenanceStatus)}>{MAINT_LABEL[r.maintenanceStatus] ?? r.maintenanceStatus}</span>{r.maintenanceNotes && <span className="gym-sub">{r.maintenanceNotes}</span>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CustomisePanel({ layout, role, onChange, onClose }: { layout: GymLayout; role: GymRole | undefined; onChange: (l: GymLayout) => void; onClose: () => void }) {
  const widgets = widgetsFor(role);
  return (
    <div className="gym-customise-panel" role="dialog" aria-label="Customise dashboard panels">
      <h4>Panels — tick to show, arrows to reorder</h4>
      {layout.order.map((id, index) => {
        const meta = widgets.find((w) => w.id === id);
        if (!meta) return null;
        const shown = !layout.hidden.includes(id);
        return (
          <div key={id} className="gym-customise-row">
            <input id={`gym-widget-${id}`} type="checkbox" checked={shown} onChange={() => onChange(toggleWidget(layout, id))} />
            <label htmlFor={`gym-widget-${id}`}>{meta.label}<small>{meta.hint}</small></label>
            <span className="gym-reorder">
              <button type="button" aria-label={`Move ${meta.label} up`} disabled={index === 0} onClick={() => onChange(moveWidget(layout, id, -1))}>▲</button>
              <button type="button" aria-label={`Move ${meta.label} down`} disabled={index === layout.order.length - 1} onClick={() => onChange(moveWidget(layout, id, 1))}>▼</button>
            </span>
          </div>
        );
      })}
      <div className="gym-customise-foot">
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(defaultLayout(role))}>Reset to default</button>
        <button type="button" className="btn btn-primary btn-sm" onClick={onClose}>Done</button>
      </div>
    </div>
  );
}
