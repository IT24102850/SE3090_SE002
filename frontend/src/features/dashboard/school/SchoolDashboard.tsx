import { Fragment, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import { useApproveSchoolUserMutation, useGetSchoolAlertsQuery, useGetSchoolOverviewQuery, useGetSchoolTodayQuery } from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { businessDescriptor, businessHeroImage } from '../../../shared/businessImagery';
import BusinessAvatar from '../../../shared/components/BusinessAvatar';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime } from '../../../shared/dateUtils';
import CalendarDashboardPage from '../../booking/CalendarDashboardPage';
import type { ClinicAlert, SchoolGroupBy, SchoolOverview, Tenant, TenantProfile } from '../../booking/types';
import { BarList, TREND_LABEL, TrendChart, type TrendMetric } from './SchoolCharts';
import SchoolGradebook from './SchoolGradebook';
import SchoolStudents from './SchoolStudents';
import SchoolTimetable from './SchoolTimetable';
import {
  canSeeFinance,
  canSeePayroll,
  defaultLayout,
  loadLayout,
  moveWidget,
  saveLayout,
  toggleWidget,
  widgetsFor,
  type SchoolLayout,
  type SchoolRole,
  type SchoolWidgetId,
} from './schoolLayout';
import {
  deltaPercent,
  downloadCsv,
  formatCount,
  formatDelta,
  formatMoney,
  formatPercent,
  MARK_LABEL,
  overviewToCsv,
  presetRange,
  tzOffsetMinutes,
  type SchoolRangePreset,
} from './schoolReport';
import './school.css';

/* The school's dashboard: today's registers, the gradebook, every
 * student's progress and the at-risk list, enrolment and retention,
 * tuition and payroll, the term calendar - one screen.
 *
 * Top to bottom: alerts, four headline cards with their change against
 * the previous period, the finer KPIs, then the panels. Breakdowns
 * cross-filter (a subject, a year group, a teacher, a room), the window
 * has the usual presets and the whole view exports as one CSV.
 *
 * Role views live in schoolLayout.ts: the owner sees finance, payroll
 * and approvals; the academic head sees academics, enrolment and tuition
 * status; a teacher sees the timetable, gradebook and students and
 * never money or user administration. The month calendar the generic
 * dashboard led with is still under "Calendar". */

const LIVE_POLL_MS = 60_000;

type View = 'operations' | 'calendar';

const PRESETS: { id: SchoolRangePreset; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: '7d', label: '7 days' },
  { id: '30d', label: '30 days' },
  { id: 'month', label: 'This month' },
];
const REPORT_PRESETS: { id: SchoolRangePreset; label: string; title: string }[] = [
  { id: 'daily', label: 'Daily', title: 'Daily report: the last 14 days, one row per day' },
  { id: 'weekly', label: 'Weekly', title: 'Weekly report: the last 12 weeks, one row per week' },
  { id: 'monthly', label: 'Monthly', title: 'Monthly report: the last 12 months, one row per month' },
];

const ROLE_VIEW: Record<SchoolRole, string> = { Admin: 'Admin view', Manager: 'Academic head view', Staff: 'Teacher view', Customer: '' };
const ICON: Record<ClinicAlert['severity'], string> = { critical: '!', warning: '△', info: 'i' };

export default function SchoolDashboard({ tenant, profile }: { tenant: Tenant; profile?: TenantProfile }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const userId = user?.id ?? 'anon';
  const role = user?.role as SchoolRole | undefined;
  const finance = canSeeFinance(role);
  const payroll = canSeePayroll(role);
  const canAdmin = role === 'Admin' || role === 'Manager';
  const tz = useMemo(() => tzOffsetMinutes(), []);
  const toast = useToast();

  const [view, setView] = useState<View>(() => {
    try {
      return (localStorage.getItem(`school-dashboard-view:${tenantId}`) as View) || 'operations';
    } catch {
      return 'operations';
    }
  });
  useEffect(() => {
    try {
      localStorage.setItem(`school-dashboard-view:${tenantId}`, view);
    } catch {
      // Per-viewer convenience only.
    }
  }, [view, tenantId]);

  // ── Filters ──────────────────────────────────────────────────────────
  const [preset, setPreset] = useState<SchoolRangePreset>('30d');
  const [range, setRange] = useState(() => presetRange('30d'));
  const [branchId, setBranchId] = useState('');
  const [resourceId, setResourceId] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [grade, setGrade] = useState('');

  const applyPreset = (id: SchoolRangePreset) => {
    setPreset(id);
    if (id !== 'custom') {
      const r = presetRange(id);
      // The school has no hourly view; a single day still groups by day.
      setRange({ ...r, groupBy: r.groupBy === 'hour' ? 'day' : r.groupBy });
    }
  };
  const setCustom = (patch: Partial<typeof range>) => {
    setPreset('custom');
    setRange((r) => ({ ...r, ...patch }));
  };
  const clearFilters = () => { setBranchId(''); setResourceId(''); setBookingTypeId(''); setGrade(''); };
  const toggle = (setter: (v: string) => void, current: string) => (key: string) => setter(current === key ? '' : key);

  // ── Data ─────────────────────────────────────────────────────────────
  const overviewParams = useMemo(() => ({
    from: range.from, to: range.to, groupBy: range.groupBy as SchoolGroupBy, tz,
    branchId: branchId || undefined, resourceId: resourceId || undefined, bookingTypeId: bookingTypeId || undefined, grade: grade || undefined,
  }), [range, tz, branchId, resourceId, bookingTypeId, grade]);
  const { data: overview, isLoading: overviewLoading, isFetching: overviewFetching } = useGetSchoolOverviewQuery(overviewParams, { skip: !tenantId });
  const todayParams = useMemo(() => ({ tz, branchId: branchId || undefined, resourceId: resourceId || undefined }), [tz, branchId, resourceId]);
  const { data: today, isLoading: todayLoading } = useGetSchoolTodayQuery(todayParams, { skip: !tenantId, pollingInterval: LIVE_POLL_MS });
  const { data: alertsData, isLoading: alertsLoading } = useGetSchoolAlertsQuery({ tz, branchId: branchId || undefined }, { skip: !tenantId, pollingInterval: LIVE_POLL_MS * 2 });
  const [approve, { isLoading: approving }] = useApproveSchoolUserMutation();

  const kpis = overview?.kpis;
  const prev = overview?.previous;
  const options = overview?.filterOptions;
  const currency = kpis?.currency ?? 'LKR';

  // ── Layout ───────────────────────────────────────────────────────────
  const [layout, setLayout] = useState<SchoolLayout>(() => loadLayout(tenantId, userId, role));
  const [customising, setCustomising] = useState(false);
  const updateLayout = useCallback((next: SchoolLayout) => { setLayout(next); saveLayout(tenantId, userId, role, next); }, [tenantId, userId, role]);
  const widgets = widgetsFor(role);
  const visibleWidgets = layout.order.filter((id) => !layout.hidden.includes(id) && widgets.some((w) => w.id === id));

  const [trendMetric, setTrendMetric] = useState<TrendMetric>('attendanceRate');

  const exportCsv = () => {
    if (!overview) return;
    downloadCsv(`school-report-${range.groupBy}-${range.from}-to-${range.to}.csv`, overviewToCsv(overview, finance, payroll));
  };

  async function approveUser(id: string, name: string) {
    try {
      await approve({ userId: id }).unwrap();
      toast.show(`${name} approved.`, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not approve the registration.'), 'error');
    }
  }

  const heroImage = businessHeroImage({ businessType: tenant.businessType, subType: tenant.subType, coverImageUrl: profile?.coverImageUrl });
  const descriptor = businessDescriptor({ businessType: tenant.businessType, subType: tenant.subType });
  const criticalAlerts = (alertsData?.alerts ?? []).filter((a) => a.severity === 'critical').length;

  const activeFilters = [
    branchId && { key: 'branch', label: `Branch: ${options?.branches.find((b) => b.id === branchId)?.name ?? '…'}`, clear: () => setBranchId('') },
    resourceId && { key: 'resource', label: `${options?.rooms.some((r) => r.id === resourceId) ? 'Room' : 'Teacher'}: ${[...(options?.teachers ?? []), ...(options?.rooms ?? [])].find((r) => r.id === resourceId)?.name ?? '…'}`, clear: () => setResourceId('') },
    bookingTypeId && { key: 'subject', label: `Subject: ${options?.subjects.find((s) => s.id === bookingTypeId)?.name ?? '…'}`, clear: () => setBookingTypeId('') },
    grade && { key: 'grade', label: `Year group: ${grade}`, clear: () => setGrade('') },
  ].filter(Boolean) as { key: string; label: string; clear: () => void }[];

  const rangeLabel = range.from === range.to ? range.from : `${range.from} – ${range.to}`;

  // ── Widgets ──────────────────────────────────────────────────────────
  const renderWidget = (id: SchoolWidgetId): ReactNode => {
    switch (id) {
      case 'timetable':
        return (
          <Widget id="timetable" role={role} title="Today's timetable & registers" subtitle={`Refreshes every ${LIVE_POLL_MS / 1000}s · pick a session to mark its register`}>
            <SchoolTimetable today={today} loading={todayLoading} canMark />
          </Widget>
        );
      case 'attendance':
        return (
          <Widget
            id="attendance" role={role} title="Attendance" subtitle={`${rangeLabel} · marks on every register`}
            tools={(
              <div className="school-presets" role="tablist" aria-label="Trend metric">
                {(['attendanceRate', 'absences', 'sessions'] as TrendMetric[]).map((m) => (
                  <button key={m} type="button" role="tab" aria-selected={trendMetric === m} className={trendMetric === m ? 'active' : ''} onClick={() => setTrendMetric(m)}>{TREND_LABEL[m]}</button>
                ))}
              </div>
            )}
          >
            <BarList
              data={(overview?.attendanceMix ?? []).map((m) => ({ key: m.mark, label: MARK_LABEL[m.mark], value: m.count, color: m.mark === 'present' ? 'var(--color-good)' : m.mark === 'late' ? 'var(--color-warning)' : m.mark === 'absent' ? 'var(--color-critical)' : 'var(--color-neutral)' }))}
              emptyText="No registers marked in this range."
            />
            {kpis && <p className="school-note">{kpis.unmarked} register entr{kpis.unmarked === 1 ? 'y' : 'ies'} still unmarked across {kpis.unmarkedSessions} session{kpis.unmarkedSessions === 1 ? '' : 's'}.</p>}
            <div style={{ marginTop: 12 }}><TrendChart data={overview?.trend ?? []} metric={trendMetric} currency={currency} loading={overviewLoading} /></div>
          </Widget>
        );
      case 'behaviour':
        return (
          <Widget id="behaviour" role={role} title="Behaviour & participation" subtitle={`${rangeLabel} · logged with the +/− on registers`}>
            <div className="school-stages">
              <Tile label="Commendations" value={kpis?.commendations} sub="positive participation" loading={overviewLoading} />
              <Tile label="Incidents" value={kpis?.incidents} sub="behaviour flags" loading={overviewLoading} alert={(kpis?.incidents ?? 0) > 0} />
              <Tile label="Net points" value={kpis ? (kpis.behaviourPoints > 0 ? `+${kpis.behaviourPoints}` : kpis.behaviourPoints) : undefined} sub="across all students" loading={overviewLoading} />
            </div>
            <BarList
              data={(overview?.students ?? []).filter((s) => s.incidents > 0).sort((a, b) => b.incidents - a.incidents).slice(0, 8).map((s) => ({ key: s.studentId, label: s.name, value: s.incidents, sub: `${s.commendations} commendation${s.commendations === 1 ? '' : 's'}`, color: 'var(--color-critical)' }))}
              format={(v) => `${v} incident${v === 1 ? '' : 's'}`}
              emptyText="No incidents logged in this range."
            />
          </Widget>
        );
      case 'students':
        return (
          <Widget id="students" role={role} title="Student performance" subtitle={`${rangeLabel} · attendance, average and flags · click a student for charts`}>
            <SchoolStudents rows={overview?.students ?? []} loading={overviewLoading} thresholds={overview?.thresholds} from={range.from} to={range.to} tz={tz} finance={finance} />
          </Widget>
        );
      case 'gradebook':
        return (
          <Widget id="gradebook" role={role} title="Gradebook" subtitle={`${rangeLabel} · exams and assignments · enter marks inline`}>
            <SchoolGradebook from={range.from} to={range.to} tz={tz} branchId={branchId || undefined} bookingTypeId={bookingTypeId || undefined} grade={grade || undefined} canGrade />
          </Widget>
        );
      case 'assignments':
        return (
          <Widget id="assignments" role={role} title="Assignments due" subtitle="Set in the last two weeks or due in the next seven days">
            {todayLoading && !today ? (
              <div className="loading-row"><span className="spinner spinner-dark" /></div>
            ) : (today?.assignments.length ?? 0) === 0 ? (
              <div className="school-empty">No assignments due this week.</div>
            ) : (
              <div className="school-list">
                {today!.assignments.map((a) => (
                  <div key={`${a.bookingTypeId}-${a.dueAt}`} className={`school-list-row${a.isOverdue && a.graded < a.students ? ' school-list-row-urgent' : ''}`}>
                    <div className="school-list-main"><strong>{a.name}</strong><span>{[a.grade, `due ${formatDateTime(a.dueAt)}`].filter(Boolean).join(' · ')}{a.isOverdue ? ' · overdue' : ''}</span></div>
                    <div className="school-list-side"><b>{a.submitted}/{a.students}</b><small>submitted · {a.graded} graded</small></div>
                  </div>
                ))}
              </div>
            )}
          </Widget>
        );
      case 'subjects':
        return (
          <Widget id="subjects" role={role} title="Subjects & courses" subtitle={`${rangeLabel} · click a row to filter`}>
            <SubjectTable overview={overview} active={bookingTypeId} onSelect={toggle(setBookingTypeId, bookingTypeId)} loading={overviewLoading} />
          </Widget>
        );
      case 'grades':
        return (
          <Widget id="grades" role={role} title="Performance by year group" subtitle="Attendance and average per grade · click to filter">
            <BarList
              data={(overview?.byGrade ?? []).map((g) => ({ key: g.grade, label: g.grade, value: g.avgScore ?? 0, sub: `${g.students} students · attendance ${formatPercent(g.attendanceRate)}${g.atRisk ? ` · ${g.atRisk} at risk` : ''}` }))}
              active={grade}
              onSelect={toggle(setGrade, grade)}
              format={(v) => (v ? `${v.toFixed(1)}% avg` : '—')}
              max={100}
              emptyText="No graded work in this range. Set grade on each subject's config to group by year."
            />
            <p className="school-subhead" style={{ marginTop: 14 }}>Grade distribution</p>
            <BarList data={(overview?.distribution ?? []).map((d) => ({ key: d.grade, label: `${d.grade} (≥ ${d.min}%)`, value: d.count }))} format={(v) => `${v} result${v === 1 ? '' : 's'}`} emptyText="No graded work in this range." />
          </Widget>
        );
      case 'teachers':
        return (
          <Widget id="teachers" role={role} title="Teachers" subtitle={`${rangeLabel} · sessions, hours and registers · click to filter`}>
            <div className="table-wrap">
              <table className="data-table">
                <thead><tr><th>Teacher</th><th>Sessions</th><th>Hours</th><th>Students</th><th>Attendance</th><th>Registers due</th>{payroll && <th style={{ textAlign: 'right' }}>Pay est.</th>}</tr></thead>
                <tbody>
                  {(overview?.byTeacher ?? []).map((t) => (
                    <tr key={t.resourceId} className={`school-row-click${resourceId === t.resourceId ? ' is-active' : ''}`} onClick={() => setResourceId(resourceId === t.resourceId ? '' : t.resourceId)}>
                      <td><span className="school-strong">{t.name}</span><span className="school-sub">{t.specialty}</span></td>
                      <td>{t.sessions}</td><td>{t.hoursTaught}</td><td>{t.students}</td><td>{formatPercent(t.attendanceRate)}</td>
                      <td style={{ color: t.unmarkedSessions > 0 ? 'var(--color-warning)' : undefined }}>{t.unmarkedSessions}</td>
                      {payroll && <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{t.payEstimate != null ? formatMoney(t.payEstimate, currency) : <span className="school-muted">no rate</span>}</td>}
                    </tr>
                  ))}
                  {(overview?.byTeacher.length ?? 0) === 0 && <tr><td colSpan={7} className="school-empty">No sessions in this range.</td></tr>}
                </tbody>
              </table>
            </div>
            {payroll && kpis && <p className="school-note">Payroll in range (rostered hours × rate): <b>{formatMoney(kpis.payrollCost, currency)}</b> for {kpis.payrollHours} h. Pay estimates per teacher are hours actually timetabled.</p>}
          </Widget>
        );
      case 'rooms':
        return (
          <Widget id="rooms" role={role} title="Classrooms" subtitle="Booked hours against an 8-hour day · click to filter">
            <BarList
              data={(overview?.byRoom ?? []).map((r) => ({ key: r.resourceId, label: r.name, value: r.utilisationPercent ?? 0, sub: `${r.sessions} sessions · ${r.hoursBooked} h${r.capacity ? ` · seats ${r.capacity}` : ''}` }))}
              active={resourceId} onSelect={toggle(setResourceId, resourceId)} format={(v) => `${v.toFixed(1)}%`} max={100}
              emptyText="No classrooms. Add Room resources with a capacity."
            />
          </Widget>
        );
      case 'enrolment':
        return (
          <Widget
            id="enrolment" role={role} title="Enrolment & retention" subtitle={`${rangeLabel}`}
            tools={(
              <div className="school-presets" role="tablist" aria-label="Enrolment metric">
                {(['newStudents', 'avgScore'] as TrendMetric[]).map((m) => (
                  <button key={m} type="button" role="tab" aria-selected={trendMetric === m} className={trendMetric === m ? 'active' : ''} onClick={() => setTrendMetric(m)}>{TREND_LABEL[m]}</button>
                ))}
              </div>
            )}
          >
            <div className="school-stages">
              <Tile label="Enrolled" value={kpis?.enrolled} sub={kpis ? `${kpis.students} approved students` : ''} loading={overviewLoading} />
              <Tile label="New" value={kpis?.newStudents} sub={prev ? formatDelta(deltaPercent(kpis?.newStudents ?? 0, prev.newStudents)) : ''} loading={overviewLoading} />
              <Tile label="Lapsed" value={kpis?.lapsed} sub="enrolments ended in range" loading={overviewLoading} alert={(kpis?.lapsed ?? 0) > 0} />
              <Tile label="Retention" value={kpis ? formatPercent(kpis.retentionRate) : undefined} sub="enrolled at start, still enrolled" loading={overviewLoading} />
            </div>
            <BarList data={(overview?.byGradeEnrolment ?? []).map((g) => ({ key: g.grade, label: g.grade, value: g.students }))} format={(v) => `${v} student${v === 1 ? '' : 's'}`} emptyText="No current enrolments. Tuition plans named 'Grade N …' group here." />
            <div style={{ marginTop: 12 }}><TrendChart data={overview?.trend ?? []} metric={trendMetric === 'avgScore' ? 'avgScore' : 'newStudents'} currency={currency} loading={overviewLoading} /></div>
          </Widget>
        );
      case 'tuition':
        return (
          <Widget id="tuition" role={role} title="Tuition & payments" subtitle="Current enrolments by the state of their latest invoice">
            <BarList
              data={(overview?.payment ?? []).map((p) => ({ key: p.status, label: p.status, value: p.students, sub: formatMoney(p.amount, currency), color: p.status === 'Paid' ? 'var(--color-good)' : p.status === 'Pending' ? 'var(--color-warning)' : 'var(--color-critical)' }))}
              format={(v) => `${v} student${v === 1 ? '' : 's'}`}
              emptyText="No tuition enrolments on file."
            />
            {(overview?.outstanding.length ?? 0) > 0 && (
              <>
                <p className="school-subhead" style={{ marginTop: 14 }}>To chase</p>
                <div className="school-list">
                  {overview!.outstanding.map((o) => (
                    <div key={o.subscriptionId} className="school-list-row">
                      <div className="school-list-main"><strong>{o.studentName}</strong><span>{o.plan}{o.phone ? ` · ${o.phone}` : ''}{o.nextBillingAt ? ` · billed ${o.nextBillingAt.slice(0, 10)}` : ''}</span></div>
                      <div className="school-list-side"><b>{formatMoney(o.amount, currency)}</b><small className={o.paymentStatus === 'Pending' ? 'school-good' : 'school-bad'} style={{ color: o.paymentStatus === 'Pending' ? 'var(--color-warning)' : undefined }}>{o.paymentStatus}</small></div>
                    </div>
                  ))}
                </div>
              </>
            )}
            {kpis && <p className="school-note">Tuition paid in range <b>{formatMoney(kpis.tuitionPaid, currency)}</b> · recurring <b>{formatMoney(kpis.monthlyRecurring, currency)}</b> / month.</p>}
          </Widget>
        );
      case 'finance':
        return (
          <Widget
            id="finance" role={role} title="Income & costs" subtitle={`${rangeLabel} · tuition and fees against payroll and purchases`}
            tools={(
              <div className="school-presets" role="tablist" aria-label="Finance metric">
                <button type="button" role="tab" aria-selected={trendMetric === 'tuitionPaid'} className={trendMetric === 'tuitionPaid' ? 'active' : ''} onClick={() => setTrendMetric('tuitionPaid')}>Tuition paid</button>
              </div>
            )}
          >
            {kpis && (
              <div className="school-pnl">
                <div className="school-pnl-col">
                  <h5>Income</h5>
                  <div className="school-pnl-row"><span>Tuition paid</span><b>{formatMoney(kpis.tuitionPaid, currency)}</b></div>
                  <div className="school-pnl-row"><span>Tutoring & session fees</span><b>{formatMoney(kpis.tutoringFees, currency)}</b></div>
                  <div className="school-pnl-row school-pnl-total"><span>Total income</span><b>{formatMoney(kpis.income, currency)}</b></div>
                </div>
                <div className="school-pnl-col">
                  <h5>Costs</h5>
                  <div className="school-pnl-row"><span>Payroll (rostered hours × rate)</span><b>{formatMoney(kpis.payrollCost, currency)}</b></div>
                  <div className="school-pnl-row"><span>Purchases (stock received)</span><b>{formatMoney(kpis.purchases, currency)}</b></div>
                  <div className="school-pnl-row school-pnl-total"><span>Net</span><b style={{ color: kpis.net >= 0 ? 'var(--color-good)' : 'var(--color-critical)' }}>{formatMoney(kpis.net, currency)}</b></div>
                </div>
              </div>
            )}
            <TrendChart data={overview?.trend ?? []} metric="tuitionPaid" currency={currency} loading={overviewLoading} />
            <p className="school-note">Payroll is the roster, not a timesheet, and bonuses / expense claims are not recorded by the platform - this is an operating view, not the accounts.</p>
          </Widget>
        );
      case 'calendar':
        return (
          <Widget id="calendar" role={role} title="Term calendar" subtitle="Terms, holidays and timetable clashes">
            {overview?.calendar.currentTerm ? (
              <div className="school-term">
                <div className="school-term-head"><span>Current term</span><b>{overview.calendar.currentTerm.name}</b></div>
                <span className="school-term-track"><span className="school-term-fill" style={{ width: `${overview.calendar.currentTerm.progressPercent}%` }} /></span>
                <div className="school-term-foot"><span>{overview.calendar.currentTerm.from.slice(0, 10)} – {overview.calendar.currentTerm.to.slice(0, 10)}</span><span>{overview.calendar.currentTerm.daysLeft} days left</span></div>
              </div>
            ) : overview && <div className="school-empty">No term set. Add terms and holidays to the Scheduling module config.</div>}
            <p className="school-subhead">Holidays</p>
            <div className="school-list">
              {(overview?.calendar.holidays ?? []).map((h) => (
                <div key={`${h.date}-${h.name}`} className="school-list-row"><div className="school-list-main"><strong>{h.name}</strong><span>{h.date.slice(0, 10)}</span></div><div className="school-list-side"><b>{h.daysAway === 0 ? 'today' : h.daysAway === 1 ? 'tomorrow' : h.daysAway < 0 ? `${-h.daysAway}d ago` : `in ${h.daysAway}d`}</b></div></div>
              ))}
              {(overview?.calendar.holidays.length ?? 0) === 0 && <div className="school-empty">No holidays configured.</div>}
            </div>
            {(overview?.conflicts.length ?? 0) > 0 && (
              <>
                <p className="school-subhead" style={{ marginTop: 14 }}>Timetable clashes in range</p>
                <div className="school-list">
                  {overview!.conflicts.map((c, i) => (
                    <div key={i} className="school-list-row school-list-row-urgent"><div className="school-list-main"><strong>{c.resource}</strong><span>{c.first} overlaps {c.second} · {formatDateTime(c.startTime)}</span></div><div className="school-list-side"><b>{c.overlapMinutes} min</b></div></div>
                  ))}
                </div>
              </>
            )}
          </Widget>
        );
      case 'approvals':
        return (
          <Widget id="approvals" role={role} title="Registrations to approve" subtitle="New students and staff waiting for approval">
            {(today?.pendingApprovals.length ?? 0) === 0 ? (
              <div className="school-empty">Nothing waiting. New registrations land here.</div>
            ) : (
              <div className="school-list">
                {today!.pendingApprovals.map((p) => (
                  <div key={p.id} className="school-list-row">
                    <div className="school-list-main"><strong>{p.fullName}</strong><span>{p.role === 'Customer' ? 'Student' : p.role} · {p.email}{p.phone ? ` · ${p.phone}` : ''} · registered {formatDateTime(p.createdAt).replace(/,.*$/, '')}</span></div>
                    <div className="school-list-side">
                      {canAdmin && (p.role === 'Customer' || role === 'Admin')
                        ? <button type="button" className="btn btn-primary btn-sm" disabled={approving} onClick={() => approveUser(p.id, p.fullName)}>Approve</button>
                        : <Link className="btn btn-secondary btn-sm" to="/staff">Review</Link>}
                    </div>
                  </div>
                ))}
              </div>
            )}
            <p className="school-note">Staff registrations need a role assigned by an Admin; students are approved as-is.</p>
          </Widget>
        );
      default:
        return null;
    }
  };

  const alerts = alertsData?.alerts ?? [];

  return (
    <div className="school-dashboard">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant.name} src={profile?.logoUrl} />
              <div>
                <p className="hero-eyebrow">{descriptor}{role && ROLE_VIEW[role] && <> · <span className="school-role-pill">{ROLE_VIEW[role]}</span></>}</p>
                <h1 className="hero-title">{tenant.name}</h1>
                <div className="hero-figure">{today ? today.summary.sessions : '…'}</div>
                <p className="hero-sub">sessions today{today?.term ? ` · ${today.term}` : ''}{today && today.summary.needsMarking > 0 && <> · <b>{today.summary.needsMarking} register{today.summary.needsMarking === 1 ? '' : 's'} to mark</b></>}{criticalAlerts > 0 && <> · <b>{criticalAlerts} critical alert{criticalAlerts === 1 ? '' : 's'}</b></>}</p>
                <div className="school-hero-live"><i aria-hidden="true" />Live · timetable and alerts refresh every minute</div>
              </div>
            </div>
            <div className="school-hero-actions">
              <div className="school-presets" role="tablist" aria-label="Dashboard view" style={{ background: 'rgba(255,255,255,.16)', borderColor: 'rgba(255,255,255,.35)' }}>
                <button type="button" role="tab" aria-selected={view === 'operations'} className={view === 'operations' ? 'active' : ''} style={view !== 'operations' ? { color: '#fff' } : undefined} onClick={() => setView('operations')}>Dashboard</button>
                <button type="button" role="tab" aria-selected={view === 'calendar'} className={view === 'calendar' ? 'active' : ''} style={view !== 'calendar' ? { color: '#fff' } : undefined} onClick={() => setView('calendar')}>Calendar</button>
              </div>
              {view === 'operations' && (
                <>
                  <button type="button" className="btn btn-secondary" onClick={exportCsv} disabled={!overview} title="Download the current range and filters as a CSV report">⤓ Export CSV</button>
                  <div className="school-customise">
                    <button type="button" className="btn btn-secondary" aria-expanded={customising} onClick={() => setCustomising((c) => !c)}>⚙ Customise</button>
                    {customising && (
                      <>
                        <button type="button" className="school-customise-scrim" aria-label="Close" onClick={() => setCustomising(false)} />
                        <CustomisePanel layout={layout} role={role} onChange={updateLayout} onClose={() => setCustomising(false)} />
                      </>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>

          <div className="hero-tiles">
            <HeroTile label="Present today" value={today ? today.summary.presentSoFar : '…'} sub={today ? `${today.summary.absentSoFar} absent · ${today.summary.studentsExpected} expected` : ''} />
            <HeroTile label="Teachers on duty" value={today ? today.teachers.onDuty : '…'} sub={today ? `${today.teachers.rostered} rostered today` : ''} />
            <HeroTile label="At-risk students" value={kpis ? kpis.atRisk : '…'} sub={kpis ? `of ${kpis.students} · ${today?.summary.medicalAlerts ?? 0} medical alerts today` : ''} />
            {finance
              ? <HeroTile label="Outstanding fees" value={kpis ? formatMoney(kpis.outstandingAmount, currency) : '…'} sub={kpis ? `${kpis.outstandingCount} invoice${kpis.outstandingCount === 1 ? '' : 's'} · ${kpis.pendingApprovals} approval${kpis.pendingApprovals === 1 ? '' : 's'} pending` : ''} />
              : <HeroTile label="Registers to mark" value={today ? today.summary.needsMarking : '…'} sub={today ? `${today.assignments.filter((a) => a.graded < a.students).length} assignments to grade` : ''} />}
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
            <div className="school-alerts-clear" role="status"><b>✓</b> No operational alerts. Registers, grading, tuition, approvals and the timetable are all in order.</div>
          ) : (
            <div className="school-alerts" role="list" aria-label="Operational alerts">
              {alerts.map((alert) => {
                const inPage = alert.href.startsWith('/dashboard#');
                const body = (
                  <>
                    <span className="school-alert-icon" aria-hidden="true">{ICON[alert.severity]}</span>
                    <span>
                      <p className="school-alert-title"><span className="sr-only">{alert.severity}: </span>{alert.title}</p>
                      <p className="school-alert-detail">{alert.detail}</p>
                    </span>
                    <span className="school-alert-count">{alert.count}</span>
                  </>
                );
                const className = `school-alert school-alert-${alert.severity}`;
                return inPage
                  ? <a key={alert.id} className={className} href={alert.href.slice('/dashboard'.length)} role="listitem">{body}</a>
                  : <Link key={alert.id} className={className} to={alert.href} role="listitem">{body}</Link>;
              })}
            </div>
          )}

          <div className="filter-bar school-filters" role="group" aria-label="Report filters">
            <span className="school-filter-label">Range</span>
            <div className="school-presets">
              {PRESETS.map((p) => <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} onClick={() => applyPreset(p.id)}>{p.label}</button>)}
            </div>
            <span className="school-filter-label" title="Report presets set both the window and the grouping">Report</span>
            <div className="school-presets">
              {REPORT_PRESETS.map((p) => <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} title={p.title} onClick={() => applyPreset(p.id)}>{p.label}</button>)}
            </div>
            <input className="input" type="date" value={range.from} max={range.to} onChange={(e) => setCustom({ from: e.target.value })} aria-label="From date" />
            <span style={{ color: 'var(--color-text-muted)' }}>to</span>
            <input className="input" type="date" value={range.to} min={range.from} onChange={(e) => setCustom({ to: e.target.value })} aria-label="To date" />
            <select className="input" value={range.groupBy} onChange={(e) => setCustom({ groupBy: e.target.value as SchoolGroupBy })} aria-label="Group trend by">
              <option value="day">By day</option>
              <option value="week">By week</option>
              <option value="month">By month</option>
            </select>
            <span className="school-filters-spacer" />
            {(options?.branches.length ?? 0) > 1 && (
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)} aria-label="Branch">
                <option value="">All branches</option>
                {options!.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            )}
            <select className="input" value={grade} onChange={(e) => setGrade(e.target.value)} aria-label="Year group">
              <option value="">All year groups</option>
              {(options?.grades ?? []).map((g) => <option key={g} value={g}>{g}</option>)}
            </select>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} aria-label="Subject">
              <option value="">All subjects</option>
              {(options?.subjects ?? []).map((s) => <option key={s.id} value={s.id}>{s.name} · {s.kind}</option>)}
            </select>
            <select className="input" value={resourceId} onChange={(e) => setResourceId(e.target.value)} aria-label="Teacher or room">
              <option value="">All teachers & rooms</option>
              {(options?.teachers ?? []).map((t) => <option key={t.id} value={t.id}>{t.name} · teacher</option>)}
              {(options?.rooms ?? []).map((r) => <option key={r.id} value={r.id}>{r.name} · room</option>)}
            </select>
          </div>

          {activeFilters.length > 0 && (
            <div className="school-active-filters" aria-live="polite">
              {activeFilters.map((f) => <span key={f.key} className="school-chip">{f.label}<button type="button" aria-label={`Clear ${f.label}`} onClick={f.clear}>×</button></span>)}
              <button type="button" className="btn btn-ghost btn-sm" onClick={clearFilters}>Clear all</button>
            </div>
          )}

          <div className="school-kpis" aria-busy={overviewFetching}>
            <KpiCard icon="📋" label="Attendance rate" value={kpis ? formatPercent(kpis.attendanceRate) : '—'} delta={kpis && prev && kpis.attendanceRate != null && prev.attendanceRate != null ? Math.round((kpis.attendanceRate - prev.attendanceRate) * 10) / 10 : null} unit="pt" loading={overviewLoading} />
            <KpiCard icon="🎓" label="Average score" value={kpis ? formatPercent(kpis.avgScore) : '—'} delta={kpis && prev && kpis.avgScore != null && prev.avgScore != null ? Math.round((kpis.avgScore - prev.avgScore) * 10) / 10 : null} unit="pt" loading={overviewLoading} sub={kpis ? `${formatPercent(kpis.passRate)} pass · ${kpis.gradedEntries} graded` : undefined} />
            <KpiCard icon="🧑‍🎓" label="Students" value={formatCount(kpis?.students)} delta={null} sub={kpis ? `${kpis.newStudents} new · ${kpis.atRisk} at risk` : undefined} loading={overviewLoading} />
            {finance
              ? <KpiCard icon="💰" label={payroll ? 'Net (income − costs)' : 'Tuition paid'} value={kpis ? formatMoney(payroll ? kpis.net : kpis.tuitionPaid, currency) : '—'} delta={kpis && prev && !payroll ? deltaPercent(kpis.income, prev.income) : null} loading={overviewLoading} sub={kpis && payroll ? `${formatMoney(kpis.income, currency)} in · ${formatMoney(kpis.costs, currency)} out` : undefined} />
              : <KpiCard icon="📝" label="Sessions held" value={formatCount(kpis?.sessionsHeld)} delta={kpis && prev ? deltaPercent(kpis.sessionsHeld, prev.sessions) : null} loading={overviewLoading} />}
          </div>

          <div className="stat-grid" aria-busy={overviewFetching}>
            <Stat label="Sessions" value={kpis?.sessions} sub={kpis ? `${kpis.sessionsHeld} held · ${kpis.unmarkedSessions} unmarked` : ''} loading={overviewLoading} tone={kpis && kpis.unmarkedSessions > 0 ? 'warning' : undefined} />
            <Stat label="Absences" value={kpis?.absent} sub={kpis ? `${kpis.late} late · ${kpis.excused} excused` : ''} loading={overviewLoading} tone={kpis && kpis.absent > 0 ? 'critical' : undefined} />
            <Stat label="Assessments" value={kpis?.assessments} sub={kpis ? `${kpis.ungradedOverdue} overdue ungraded` : ''} loading={overviewLoading} tone={kpis && kpis.ungradedOverdue > 0 ? 'warning' : undefined} />
            <Stat label="Behaviour" value={kpis ? `${kpis.commendations} / ${kpis.incidents}` : undefined} sub="commendations / incidents" loading={overviewLoading} />
            <Stat label="Retention" value={kpis ? formatPercent(kpis.retentionRate) : undefined} sub={kpis ? `${kpis.enrolled} enrolled · ${kpis.lapsed} lapsed` : ''} loading={overviewLoading} tone="good" />
            <Stat label="Timetable clashes" value={kpis?.conflicts} sub={kpis ? `${kpis.teachers} teachers · ${kpis.rooms} rooms` : ''} loading={overviewLoading} tone={kpis && kpis.conflicts > 0 ? 'critical' : 'good'} />
            {finance && <Stat label="Outstanding fees" value={kpis ? formatMoney(kpis.outstandingAmount, currency) : undefined} sub={kpis ? `${kpis.outstandingCount} pending / failed / overdue` : ''} loading={overviewLoading} tone={kpis && kpis.outstandingCount > 0 ? 'critical' : 'good'} />}
            {canAdmin && <Stat label="Approvals pending" value={kpis?.pendingApprovals} sub={kpis ? `${kpis.pendingStudents} students · ${kpis.pendingStaff} staff` : ''} loading={overviewLoading} tone={kpis && kpis.pendingApprovals > 0 ? 'warning' : undefined} />}
            {!finance && <Stat label="Next holiday" value={overview?.calendar.nextHoliday ? overview.calendar.nextHoliday.name : (overview ? '—' : undefined)} sub={overview?.calendar.nextHoliday ? `in ${overview.calendar.nextHoliday.daysAway} days` : 'none configured'} loading={overviewLoading} />}
          </div>

          <div className="school-grid">
            {visibleWidgets.map((id) => <Fragment key={id}>{renderWidget(id)}</Fragment>)}
          </div>
          {visibleWidgets.length === 0 && <div className="school-empty">Every panel is hidden. Use Customise to bring some back.</div>}
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

function KpiCard({ icon, label, value, delta, unit, loading, sub }: { icon: string; label: string; value: string; delta: number | null; unit?: 'pt'; loading: boolean; sub?: string }) {
  const tone = delta === null || delta === 0 ? 'flat' : delta > 0 ? 'up' : 'down';
  const arrow = delta === null || delta === 0 ? '·' : delta > 0 ? '↑' : '↓';
  const text = sub ?? (delta === null ? 'no previous period' : unit === 'pt' ? `${delta > 0 ? '+' : ''}${delta.toFixed(1)} pt vs previous period` : formatDelta(delta));
  return (
    <div className="school-kpi">
      <div className="school-kpi-icon" aria-hidden="true">{icon}</div>
      <div>
        <div className="school-kpi-value">{loading && value === '—' ? '…' : value}</div>
        <div className="school-kpi-label">{label}</div>
        <div className={`school-kpi-delta school-kpi-delta-${sub ? 'flat' : tone}`}><i aria-hidden="true">{sub ? '·' : arrow}</i>{text}</div>
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
    <div className={`school-stage${alert ? ' school-stage-alert' : ''}`}>
      <div className="school-stage-label">{label}</div>
      <div className="school-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="school-stage-sub">{sub}</div>
    </div>
  );
}

function Widget({ id, role, title, subtitle, tools, children }: { id: SchoolWidgetId; role: SchoolRole | undefined; title: string; subtitle: string; tools?: ReactNode; children: ReactNode }) {
  const meta = widgetsFor(role).find((w) => w.id === id);
  return (
    <section id={id} className={`card chart-card school-widget${meta?.wide ? ' school-widget-wide' : ''}`} aria-labelledby={`school-${id}-title`}>
      <div className="school-widget-head">
        <div>
          <p className="chart-title" id={`school-${id}-title`}>{title}</p>
          <p className="chart-subtitle">{subtitle}</p>
        </div>
        {tools && <div className="school-widget-tools">{tools}</div>}
      </div>
      {children}
    </section>
  );
}

function SubjectTable({ overview, active, onSelect, loading }: { overview?: SchoolOverview; active: string; onSelect: (id: string) => void; loading: boolean }) {
  const rows = overview?.bySubject ?? [];
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="school-empty">No sessions or assessments in this range.</div>;
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead><tr><th>Subject</th><th>Teacher</th><th>Sessions</th><th>Students</th><th>Attendance</th><th>Assessments</th><th>Average</th></tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.bookingTypeId} className={`school-row-click${active === r.bookingTypeId ? ' is-active' : ''}`} onClick={() => onSelect(r.bookingTypeId)} tabIndex={0}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(r.bookingTypeId); } }} aria-pressed={active === r.bookingTypeId}>
              <td><span className="school-strong"><i style={{ display: 'inline-block', width: 8, height: 8, borderRadius: 2, marginRight: 6, background: r.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{r.name}</span><span className="school-sub">{[r.grade, r.kind].filter(Boolean).join(' · ')}</span></td>
              <td>{r.teacher ?? <span className="school-muted">—</span>}</td>
              <td>{r.sessions}</td>
              <td>{r.students}</td>
              <td style={{ color: r.attendanceRate != null && overview && r.attendanceRate < overview.thresholds.atRiskAttendancePercent ? 'var(--color-critical)' : undefined }}>{formatPercent(r.attendanceRate)}</td>
              <td>{r.assessments > 0 ? `${r.graded}/${r.assessments} graded` : <span className="school-muted">—</span>}</td>
              <td style={{ color: r.avgScore != null && overview && r.avgScore < overview.thresholds.atRiskGradePercent ? 'var(--color-critical)' : undefined }}>{formatPercent(r.avgScore)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CustomisePanel({ layout, role, onChange, onClose }: { layout: SchoolLayout; role: SchoolRole | undefined; onChange: (l: SchoolLayout) => void; onClose: () => void }) {
  const widgets = widgetsFor(role);
  return (
    <div className="school-customise-panel" role="dialog" aria-label="Customise dashboard panels">
      <h4>Panels — tick to show, arrows to reorder</h4>
      {layout.order.map((id, index) => {
        const meta = widgets.find((w) => w.id === id);
        if (!meta) return null;
        const shown = !layout.hidden.includes(id);
        return (
          <div key={id} className="school-customise-row">
            <input id={`school-widget-${id}`} type="checkbox" checked={shown} onChange={() => onChange(toggleWidget(layout, id))} />
            <label htmlFor={`school-widget-${id}`}>{meta.label}<small>{meta.hint}</small></label>
            <span className="school-reorder">
              <button type="button" aria-label={`Move ${meta.label} up`} disabled={index === 0} onClick={() => onChange(moveWidget(layout, id, -1))}>▲</button>
              <button type="button" aria-label={`Move ${meta.label} down`} disabled={index === layout.order.length - 1} onClick={() => onChange(moveWidget(layout, id, 1))}>▼</button>
            </span>
          </div>
        );
      })}
      <div className="school-customise-foot">
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(defaultLayout(role))}>Reset to default</button>
        <button type="button" className="btn btn-primary btn-sm" onClick={onClose}>Done</button>
      </div>
    </div>
  );
}
