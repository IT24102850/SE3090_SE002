import { Fragment, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useSelector } from 'react-redux';
import {
  useGetRestaurantAlertsQuery,
  useGetRestaurantInventoryQuery,
  useGetRestaurantLiveQuery,
  useGetRestaurantOverviewQuery,
} from '../../../api/bookingApi';
import type { RootState } from '../../../store/store';
import { businessDescriptor, businessHeroImage } from '../../../shared/businessImagery';
import { formatTime } from '../../../shared/dateUtils';
import BusinessAvatar from '../../../shared/components/BusinessAvatar';
import CalendarDashboardPage from '../../booking/CalendarDashboardPage';
import type { RestaurantGroupBy, RestaurantOverview, RestaurantShift, Tenant, TenantProfile } from '../../booking/types';
import RestaurantAlerts from './RestaurantAlerts';
import { BarList, FlowChart, HourChart, SalesTrendChart, StatusMix, type SalesMetric } from './RestaurantCharts';
import RestaurantInventoryPanel from './RestaurantInventoryPanel';
import RestaurantKitchenPanel from './RestaurantKitchenPanel';
import RestaurantOrderFeed from './RestaurantOrderFeed';
import RestaurantStaffPanel from './RestaurantStaffPanel';
import {
  canSeeFinance,
  defaultLayout,
  loadLayout,
  moveWidget,
  saveLayout,
  toggleWidget,
  widgetsFor,
  type RestaurantLayout,
  type RestaurantRole,
  type RestaurantWidgetId,
} from './restaurantLayout';
import {
  deltaPercent,
  downloadCsv,
  formatCount,
  formatDelta,
  formatMinutes,
  formatMoney,
  formatPercent,
  overviewToCsv,
  presetRange,
  tzOffsetMinutes,
  type RestaurantRangePreset,
} from './restaurantReport';
import './restaurant.css';

/* The restaurant's dashboard: a service desk, a kitchen board and a
 * report in one screen.
 *
 * Top to bottom: what needs attention right now (alerts), the four
 * headline cards with their change against the previous period, the
 * finer KPIs for the chosen window, and then the panels - the live order
 * feed, kitchen performance, sales and customer-flow charts, breakdowns
 * by channel / menu / station / shift, staff and labor, stock and waste.
 * Every breakdown cross-filters the others (click a station, a menu type,
 * a channel or a shift and everything follows), the window and grouping
 * are the daily / weekly / monthly report presets plus a per-shift view,
 * and the whole thing exports as one CSV.
 *
 * What each role sees is decided in restaurantLayout.ts: an owner gets
 * the money, a floor manager the service plus the day's sales, a chef the
 * kitchen and the stock and never a revenue figure. The month calendar
 * the generic dashboard led with is still here under the "Calendar"
 * view. */

const LIVE_POLL_MS = 30_000;

type View = 'operations' | 'calendar';

const PRESETS: { id: RestaurantRangePreset; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: 'yesterday', label: 'Yesterday' },
  { id: '7d', label: '7 days' },
  { id: '30d', label: '30 days' },
  { id: 'month', label: 'This month' },
];
const REPORT_PRESETS: { id: RestaurantRangePreset; label: string; title: string }[] = [
  { id: 'daily', label: 'Daily', title: 'Daily report: the last 14 days, one row per day' },
  { id: 'weekly', label: 'Weekly', title: 'Weekly report: the last 12 weeks, one row per week' },
  { id: 'monthly', label: 'Monthly', title: 'Monthly report: the last 12 months, one row per month' },
];

const ROLE_VIEW: Record<RestaurantRole, string> = { Admin: 'Owner view', Manager: 'Floor view', Staff: 'Kitchen view', Customer: '' };

export default function RestaurantDashboard({ tenant, profile }: { tenant: Tenant; profile?: TenantProfile }) {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const userId = user?.id ?? 'anon';
  const role = user?.role as RestaurantRole | undefined;
  const finance = canSeeFinance(role);
  const canLogWaste = role === 'Admin' || role === 'Manager' || role === 'Staff';
  const tz = useMemo(() => tzOffsetMinutes(), []);

  const [view, setView] = useState<View>(() => {
    try {
      return (localStorage.getItem(`restaurant-dashboard-view:${tenantId}`) as View) || 'operations';
    } catch {
      return 'operations';
    }
  });
  useEffect(() => {
    try {
      localStorage.setItem(`restaurant-dashboard-view:${tenantId}`, view);
    } catch {
      // Per-viewer convenience only.
    }
  }, [view, tenantId]);

  // ── Filters ──────────────────────────────────────────────────────────
  const [preset, setPreset] = useState<RestaurantRangePreset>('7d');
  const [range, setRange] = useState(() => presetRange('7d'));
  const [shift, setShift] = useState<RestaurantShift | ''>('');
  const [branchId, setBranchId] = useState('');
  const [resourceId, setResourceId] = useState('');
  const [bookingTypeId, setBookingTypeId] = useState('');
  const [channel, setChannel] = useState('');
  const [serviceMode, setServiceMode] = useState('');

  const applyPreset = (id: RestaurantRangePreset) => {
    setPreset(id);
    if (id !== 'custom') setRange(presetRange(id));
  };
  const setCustom = (patch: Partial<typeof range>) => {
    setPreset('custom');
    setRange((r) => ({ ...r, ...patch }));
  };
  const clearFilters = () => {
    setShift('');
    setBranchId('');
    setResourceId('');
    setBookingTypeId('');
    setChannel('');
    setServiceMode('');
  };
  const toggle = (setter: (v: string) => void, current: string) => (key: string) => setter(current === key ? '' : key);

  // ── Data ─────────────────────────────────────────────────────────────
  const overviewParams = useMemo(() => ({
    from: range.from,
    to: range.to,
    groupBy: range.groupBy,
    tz,
    shift: shift || undefined,
    branchId: branchId || undefined,
    resourceId: resourceId || undefined,
    bookingTypeId: bookingTypeId || undefined,
    channel: channel || undefined,
    serviceMode: serviceMode || undefined,
  }), [range, tz, shift, branchId, resourceId, bookingTypeId, channel, serviceMode]);

  const { data: overview, isLoading: overviewLoading, isFetching: overviewFetching } = useGetRestaurantOverviewQuery(overviewParams, { skip: !tenantId });
  const liveParams = useMemo(() => ({ tz, branchId: branchId || undefined, resourceId: resourceId || undefined }), [tz, branchId, resourceId]);
  const { data: live, isLoading: liveLoading } = useGetRestaurantLiveQuery(liveParams, { skip: !tenantId, pollingInterval: LIVE_POLL_MS });
  const { data: alertsData, isLoading: alertsLoading } = useGetRestaurantAlertsQuery({ tz, branchId: branchId || undefined }, { skip: !tenantId, pollingInterval: LIVE_POLL_MS * 2 });
  const inventoryParams = useMemo(() => ({ from: range.from, to: range.to, tz, branchId: branchId || undefined }), [range, tz, branchId]);
  const { data: inventory, isLoading: inventoryLoading } = useGetRestaurantInventoryQuery(inventoryParams, { skip: !tenantId, pollingInterval: LIVE_POLL_MS * 4 });

  const kpis = overview?.kpis;
  const prev = overview?.previous;
  const options = overview?.filterOptions;
  const currency = kpis?.currency ?? 'LKR';

  // ── Layout customisation ─────────────────────────────────────────────
  const [layout, setLayout] = useState<RestaurantLayout>(() => loadLayout(tenantId, userId, role));
  const [customising, setCustomising] = useState(false);
  const updateLayout = useCallback((next: RestaurantLayout) => {
    setLayout(next);
    saveLayout(tenantId, userId, role, next);
  }, [tenantId, userId, role]);
  const widgets = widgetsFor(role);
  const visibleWidgets = layout.order.filter((id) => !layout.hidden.includes(id) && widgets.some((w) => w.id === id));

  // ── Chart toggles ────────────────────────────────────────────────────
  const [salesMetric, setSalesMetric] = useState<SalesMetric>(finance ? 'revenue' : 'orders');
  const [hourMetric, setHourMetric] = useState<'orders' | 'revenue'>('orders');

  // ── Export ───────────────────────────────────────────────────────────
  const exportCsv = () => {
    if (!overview) return;
    downloadCsv(`restaurant-report-${range.groupBy}-${range.from}-to-${range.to}.csv`, overviewToCsv(overview, finance, inventory));
  };

  const heroImage = businessHeroImage({ businessType: tenant.businessType, subType: tenant.subType, coverImageUrl: profile?.coverImageUrl });
  const descriptor = businessDescriptor({ businessType: tenant.businessType, subType: tenant.subType });
  const criticalAlerts = (alertsData?.alerts ?? []).filter((a) => a.severity === 'critical').length;
  const openNow = live ? live.stages.new + live.stages.accepted + live.stages.preparing + live.stages.ready : undefined;

  const activeFilters = [
    shift && { key: 'shift', label: `Shift: ${options?.shifts.find((s) => s.id === shift)?.label ?? shift}`, clear: () => setShift('') },
    branchId && { key: 'branch', label: `Branch: ${options?.branches.find((b) => b.id === branchId)?.name ?? '…'}`, clear: () => setBranchId('') },
    resourceId && { key: 'station', label: `Station: ${options?.stations.find((s) => s.id === resourceId)?.name ?? '…'}`, clear: () => setResourceId('') },
    bookingTypeId && { key: 'menu', label: `Menu: ${options?.menu.find((m) => m.id === bookingTypeId)?.name ?? '…'}`, clear: () => setBookingTypeId('') },
    channel && { key: 'channel', label: `Channel: ${channel}`, clear: () => setChannel('') },
    serviceMode && { key: 'mode', label: `Mode: ${serviceMode}`, clear: () => setServiceMode('') },
  ].filter(Boolean) as { key: string; label: string; clear: () => void }[];

  const rangeLabel = range.from === range.to ? range.from : `${range.from} – ${range.to}`;

  // ── Widgets ──────────────────────────────────────────────────────────
  const renderWidget = (id: RestaurantWidgetId): ReactNode => {
    switch (id) {
      case 'feed':
        return (
          <Widget id="feed" role={role} title="Live order feed" subtitle={`Today · refreshes every ${LIVE_POLL_MS / 1000}s`}>
            <RestaurantOrderFeed live={live} loading={liveLoading} finance={finance} />
          </Widget>
        );
      case 'kitchen':
        return (
          <Widget id="kitchen" role={role} title="Kitchen performance" subtitle="Ticket times against target · station throughput today · click a station to filter">
            <RestaurantKitchenPanel live={live} overview={overview} loading={liveLoading} finance={finance} activeStation={resourceId} onSelectStation={toggle(setResourceId, resourceId)} />
          </Widget>
        );
      case 'sales':
        return (
          <Widget
            id="sales"
            role={role}
            title="Sales trend"
            subtitle={`${rangeLabel} · by ${range.groupBy}`}
            tools={(
              <div className="rest-presets" role="tablist" aria-label="Sales metric">
                {(['revenue', 'orders', 'covers'] as SalesMetric[]).map((m) => (
                  <button key={m} type="button" role="tab" aria-selected={salesMetric === m} className={salesMetric === m ? 'active' : ''} onClick={() => setSalesMetric(m)}>{m[0].toUpperCase() + m.slice(1)}</button>
                ))}
              </div>
            )}
          >
            <SalesTrendChart data={overview?.trend ?? []} metric={salesMetric} currency={currency} loading={overviewLoading} />
          </Widget>
        );
      case 'flow':
        return (
          <Widget id="flow" role={role} title="Customer flow" subtitle={`${rangeLabel} · dine-in vs takeaway & delivery`}>
            <FlowChart data={overview?.trend ?? []} loading={overviewLoading} />
          </Widget>
        );
      case 'hours':
        return (
          <Widget
            id="hours"
            role={role}
            title="Peak hours"
            subtitle="By hour of day, in your local time"
            tools={finance ? (
              <div className="rest-presets" role="tablist" aria-label="Hour metric">
                <button type="button" role="tab" aria-selected={hourMetric === 'orders'} className={hourMetric === 'orders' ? 'active' : ''} onClick={() => setHourMetric('orders')}>Orders</button>
                <button type="button" role="tab" aria-selected={hourMetric === 'revenue'} className={hourMetric === 'revenue' ? 'active' : ''} onClick={() => setHourMetric('revenue')}>Revenue</button>
              </div>
            ) : undefined}
          >
            <HourChart data={overview?.byHour ?? []} metric={finance ? hourMetric : 'orders'} currency={currency} loading={overviewLoading} />
          </Widget>
        );
      case 'channels':
        return (
          <Widget id="channels" role={role} title="Channels & service modes" subtitle="Where orders come from and how they are served">
            <div className="rest-split">
              <div>
                <p className="rest-subhead">By channel</p>
                <BarList
                  data={(overview?.byChannel ?? []).map((c) => ({ key: c.channel, label: c.channel, value: c.orders, sub: finance ? formatMoney(c.revenue, currency) : `${c.covers} covers` }))}
                  active={channel}
                  onSelect={toggle(setChannel, channel)}
                  hint="Click a channel to filter everything by it."
                />
              </div>
              <div>
                <p className="rest-subhead">By service mode</p>
                <BarList
                  data={(overview?.byServiceMode ?? []).map((m) => ({ key: m.mode, label: m.mode, value: m.orders, sub: [finance ? formatMoney(m.revenue, currency) : `${m.covers} covers`, m.avgPrepMinutes != null ? `prep ${formatMinutes(m.avgPrepMinutes)}` : null].filter(Boolean).join(' · ') }))}
                  active={serviceMode}
                  onSelect={toggle(setServiceMode, serviceMode)}
                  hint="Set serviceMode in a menu type's config to override the name-based guess."
                />
              </div>
            </div>
          </Widget>
        );
      case 'menu':
        return (
          <Widget id="menu" role={role} title="Menu performance" subtitle="Orders, prep time against target and on-time rate per menu type · click a row to filter">
            <MenuTable overview={overview} active={bookingTypeId} onSelect={toggle(setBookingTypeId, bookingTypeId)} currency={currency} finance={finance} loading={overviewLoading} />
          </Widget>
        );
      case 'stations':
        return (
          <Widget id="stations" role={role} title="Stations & tables" subtitle={`${rangeLabel} · throughput per station, table and rider · click a row to filter`}>
            <StationTable overview={overview} active={resourceId} onSelect={toggle(setResourceId, resourceId)} currency={currency} finance={finance} loading={overviewLoading} />
          </Widget>
        );
      case 'shifts':
        return (
          <Widget id="shifts" role={role} title="Shift comparison" subtitle="Breakfast, lunch, dinner and late night">
            <BarList
              data={(overview?.byShift ?? []).map((s) => ({ key: s.shift, label: `${s.label} (${s.hours})`, value: s.orders, sub: finance ? `${formatMoney(s.revenue, currency)} · ${s.covers} covers` : `${s.covers} covers` }))}
              active={shift}
              onSelect={(key) => setShift(shift === key ? '' : (key as RestaurantShift))}
              format={(v) => `${v} order${v === 1 ? '' : 's'}`}
              hint="Click a shift to report on that service only."
            />
          </Widget>
        );
      case 'staff':
        return (
          <Widget id="staff" role={role} title="Staff & labor" subtitle="Rostered now, hours and labor as a share of sales">
            <RestaurantStaffPanel live={live} overview={overview} loading={liveLoading} />
          </Widget>
        );
      case 'inventory':
        return (
          <Widget id="inventory" role={role} title="Stock levels & waste" subtitle="Ingredients against reorder level · waste log for the selected range">
            <RestaurantInventoryPanel data={inventory} loading={inventoryLoading} finance={finance} canLog={canLogWaste} />
          </Widget>
        );
      case 'waste':
        return (
          <Widget id="waste" role={role} title="Waste & variance" subtitle={`${rangeLabel} · cost written off, by item and by reason`}>
            {kpis && (
              <p className="rest-note" style={{ margin: '0 0 12px' }}>
                <b>{formatMoney(kpis.wasteCost, currency)}</b> wasted ({formatPercent(kpis.wastePercent)} of sales) · <b>{formatMoney(kpis.consumptionCost, currency)}</b> of ingredients auto-consumed by recipes across {kpis.consumptionMovements} movements.
              </p>
            )}
            <div className="rest-split">
              <div>
                <p className="rest-subhead">By item</p>
                <BarList data={(overview?.waste.byItem ?? []).map((w) => ({ key: w.inventoryItemId, label: w.name, value: w.cost, sub: `${w.units.toLocaleString()} units` }))} format={(v) => formatMoney(v, currency)} emptyText="No waste logged in this range." />
              </div>
              <div>
                <p className="rest-subhead">By reason</p>
                <BarList data={(overview?.waste.byReason ?? []).map((w) => ({ key: w.reason, label: w.reason, value: w.cost, sub: `${w.entries} entr${w.entries === 1 ? 'y' : 'ies'}` }))} format={(v) => formatMoney(v, currency)} emptyText="No waste logged in this range." />
              </div>
            </div>
          </Widget>
        );
      case 'status':
        return (
          <Widget id="status" role={role} title="Order status" subtitle={rangeLabel}>
            <StatusMix mix={overview?.statusMix ?? []} loading={overviewLoading} />
            {kpis && (
              <p className="rest-note">
                Completion {formatPercent(kpis.completionRate)} · Cancellation {formatPercent(kpis.cancellationRate)} · {kpis.noShows} no-show{kpis.noShows === 1 ? '' : 's'} — of orders with a known outcome.
              </p>
            )}
          </Widget>
        );
      case 'branches':
        return (
          <Widget id="branches" role={role} title="Branch comparison" subtitle="Orders and revenue per branch">
            {(overview?.byBranch.length ?? 0) <= 1 && !branchId ? (
              <div className="rest-empty">{overview?.byBranch.length === 1 ? 'One branch in this range. Add branches under Branches to compare them here.' : 'No orders in this range.'}</div>
            ) : (
              <BarList
                data={(overview?.byBranch ?? []).map((b) => ({ key: b.branchId ?? 'none', label: b.name, value: b.orders, sub: `${formatMoney(b.revenue, currency)} · ${b.covers} covers` }))}
                active={branchId}
                onSelect={(key) => setBranchId(branchId === key || key === 'none' ? '' : key)}
                format={(v) => `${v} order${v === 1 ? '' : 's'}`}
                hint="Click a branch to scope every panel to it."
              />
            )}
          </Widget>
        );
      case 'upcoming':
        return (
          <Widget id="upcoming" role={role} title="Upcoming orders" subtitle="Reservations and pre-orders due in the next 24 hours">
            {liveLoading && !live ? (
              <div className="loading-row"><span className="spinner spinner-dark" /></div>
            ) : (live?.upcoming.length ?? 0) === 0 ? (
              <div className="rest-empty">Nothing scheduled in the next 24 hours.</div>
            ) : (
              <div className="rest-upcoming">
                {live!.upcoming.map((u) => {
                  const when = new Date(u.startTime);
                  const today = new Date();
                  const isToday = when.toDateString() === today.toDateString();
                  return (
                    <div key={u.bookingId} className="rest-upcoming-row">
                      <div className="rest-upcoming-time">{formatTime(u.startTime)}<small>{isToday ? 'today' : 'tomorrow'}</small></div>
                      <div className="rest-upcoming-main">
                        <strong>{u.customerName} <span style={{ fontWeight: 500, color: 'var(--color-text-muted)' }}>· {u.covers} cover{u.covers === 1 ? '' : 's'}</span></strong>
                        <span>{u.menuItem} · {u.serviceMode} · {u.resourceName}{u.notes ? ` · ${u.notes}` : ''}</span>
                      </div>
                      <span className={`badge badge-${u.status === 'Pending' ? 'warning' : 'good'}`}><span className="badge-dot" />{u.status === 'Pending' ? 'To confirm' : 'Confirmed'}</span>
                    </div>
                  );
                })}
              </div>
            )}
          </Widget>
        );
      default:
        return null;
    }
  };

  return (
    <div className="rest-dashboard">
      <section className="hero" style={{ marginBottom: 0 }}>
        <div className="hero-media" style={{ backgroundImage: `url(${heroImage})` }} />
        <div className="hero-scrim" />
        <div className="hero-body">
          <div className="page-header" style={{ marginBottom: 0 }}>
            <div className="hero-identity">
              <BusinessAvatar name={tenant.name} src={profile?.logoUrl} />
              <div>
                <p className="hero-eyebrow">{descriptor}{role && ROLE_VIEW[role] && <> · <span className="rest-role-pill">{ROLE_VIEW[role]}</span></>}</p>
                <h1 className="hero-title">{tenant.name}</h1>
                <div className="hero-figure">{openNow ?? '…'}</div>
                <p className="hero-sub">orders open right now{criticalAlerts > 0 && <> · <b>{criticalAlerts} critical alert{criticalAlerts === 1 ? '' : 's'}</b></>}</p>
                <div className="rest-hero-live"><i aria-hidden="true" />Live · orders, kitchen and alerts refresh every {LIVE_POLL_MS / 1000}s</div>
              </div>
            </div>
            <div className="rest-hero-actions">
              <div className="rest-presets" role="tablist" aria-label="Dashboard view" style={{ background: 'rgba(255,255,255,.16)', borderColor: 'rgba(255,255,255,.35)' }}>
                <button type="button" role="tab" aria-selected={view === 'operations'} className={view === 'operations' ? 'active' : ''} style={view !== 'operations' ? { color: '#fff' } : undefined} onClick={() => setView('operations')}>Operations</button>
                <button type="button" role="tab" aria-selected={view === 'calendar'} className={view === 'calendar' ? 'active' : ''} style={view !== 'calendar' ? { color: '#fff' } : undefined} onClick={() => setView('calendar')}>Calendar</button>
              </div>
              {view === 'operations' && (
                <>
                  <button type="button" className="btn btn-secondary" onClick={exportCsv} disabled={!overview} title="Download the current range, grouping and filters as a CSV report">
                    ⤓ Export CSV
                  </button>
                  <div className="rest-customise">
                    <button type="button" className="btn btn-secondary" aria-expanded={customising} onClick={() => setCustomising((c) => !c)}>
                      ⚙ Customise
                    </button>
                    {customising && (
                      <>
                        <button type="button" className="rest-scrim" aria-label="Close" onClick={() => setCustomising(false)} />
                        <CustomisePanel layout={layout} role={role} onChange={updateLayout} onClose={() => setCustomising(false)} />
                      </>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>

          <div className="hero-tiles">
            <HeroTile label="Orders today" value={live ? live.feed.filter((o) => o.stage !== 'cancelled' && o.stage !== 'noShow').length : '…'} sub={live ? `${live.stages.completed} completed` : ''} />
            <HeroTile label="In the kitchen" value={live ? live.kitchen.openTickets : '…'} sub={live ? (live.kitchen.delayed > 0 ? `${live.kitchen.delayed} over target` : live.kitchen.longestOpenMinutes != null ? `longest ${formatMinutes(live.kitchen.longestOpenMinutes)}` : 'all clear') : ''} />
            <HeroTile label="Tables in use" value={live ? (live.tables.total > 0 ? `${live.tables.occupied}/${live.tables.total}` : live.stages.new + live.stages.accepted) : '…'} sub={live ? (live.tables.total > 0 ? `${live.tables.occupancyPercent ?? 0}% occupied` : 'queued orders · add Room resources for tables') : ''} />
            {finance ? (
              <HeroTile label="Sales today" value={live ? formatMoney(live.sales.revenue, live.sales.currency) : '…'} sub={live ? (live.sales.averageOrderValue != null ? `AOV ${formatMoney(live.sales.averageOrderValue, live.sales.currency)} · ${live.sales.covers} covers` : `${formatMoney(live.sales.revenueBooked, live.sales.currency)} booked`) : ''} />
            ) : (
              <HeroTile label="On time today" value={live ? (live.kitchen.onTimeRateToday != null ? `${live.kitchen.onTimeRateToday}%` : '—') : '…'} sub={live ? `avg prep ${formatMinutes(live.kitchen.avgPrepMinutesToday)}` : ''} />
            )}
          </div>
        </div>
      </section>

      {view === 'calendar' ? (
        <CalendarDashboardPage />
      ) : (
        <>
          <RestaurantAlerts alerts={alertsData?.alerts ?? []} loading={alertsLoading} />

          <div className="filter-bar rest-filters" role="group" aria-label="Report filters">
            <span className="rest-filter-label">Range</span>
            <div className="rest-presets">
              {PRESETS.map((p) => (
                <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} onClick={() => applyPreset(p.id)}>{p.label}</button>
              ))}
            </div>
            <span className="rest-filter-label" title="Report presets set both the window and the grouping">Report</span>
            <div className="rest-presets">
              {REPORT_PRESETS.map((p) => (
                <button key={p.id} type="button" className={preset === p.id ? 'active' : ''} title={p.title} onClick={() => applyPreset(p.id)}>{p.label}</button>
              ))}
            </div>
            <input className="input" type="date" value={range.from} max={range.to} onChange={(e) => setCustom({ from: e.target.value })} aria-label="From date" />
            <span style={{ color: 'var(--color-text-muted)' }}>to</span>
            <input className="input" type="date" value={range.to} min={range.from} onChange={(e) => setCustom({ to: e.target.value })} aria-label="To date" />
            <select className="input" value={range.groupBy} onChange={(e) => setCustom({ groupBy: e.target.value as RestaurantGroupBy })} aria-label="Group trend by">
              <option value="hour">By hour</option>
              <option value="day">By day</option>
              <option value="week">By week</option>
              <option value="month">By month</option>
            </select>
            <select className="input" value={shift} onChange={(e) => setShift(e.target.value as RestaurantShift | '')} aria-label="Shift">
              <option value="">All shifts</option>
              {(options?.shifts ?? []).map((s) => <option key={s.id} value={s.id}>{s.label} ({s.hours})</option>)}
            </select>
            <span className="rest-filters-spacer" />
            {(options?.branches.length ?? 0) > 1 && (
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)} aria-label="Branch">
                <option value="">All branches</option>
                {options!.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            )}
            <select className="input" value={resourceId} onChange={(e) => setResourceId(e.target.value)} aria-label="Station or table">
              <option value="">All stations & tables</option>
              {(options?.stations ?? []).map((s) => <option key={s.id} value={s.id}>{s.name} · {s.kind}</option>)}
            </select>
            <select className="input" value={bookingTypeId} onChange={(e) => setBookingTypeId(e.target.value)} aria-label="Menu type">
              <option value="">All menu types</option>
              {(options?.menu ?? []).map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
            <select className="input" value={channel} onChange={(e) => setChannel(e.target.value)} aria-label="Channel">
              <option value="">All channels</option>
              {(options?.channels ?? []).map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <select className="input" value={serviceMode} onChange={(e) => setServiceMode(e.target.value)} aria-label="Service mode">
              <option value="">All modes</option>
              {(options?.serviceModes ?? []).map((m) => <option key={m} value={m}>{m}</option>)}
            </select>
          </div>

          {activeFilters.length > 0 && (
            <div className="rest-active-filters" aria-live="polite">
              {activeFilters.map((f) => (
                <span key={f.key} className="rest-chip">{f.label}<button type="button" aria-label={`Clear ${f.label}`} onClick={f.clear}>×</button></span>
              ))}
              <button type="button" className="btn btn-ghost btn-sm" onClick={clearFilters}>Clear all</button>
            </div>
          )}

          <div className="rest-kpis" aria-busy={overviewFetching}>
            <KpiCard icon="🧾" label="Total orders" value={formatCount(kpis?.orders)} delta={kpis && prev ? deltaPercent(kpis.orders, prev.orders) : null} loading={overviewLoading} />
            <KpiCard icon="✅" label="Completed" value={formatCount(kpis?.completed)} delta={kpis && prev ? deltaPercent(kpis.completed, prev.completed) : null} loading={overviewLoading} />
            <KpiCard icon="🚫" label="Cancelled" value={formatCount(kpis?.cancelled)} delta={kpis && prev ? deltaPercent(kpis.cancelled, prev.cancelled) : null} invert loading={overviewLoading} />
            {finance ? (
              <KpiCard icon="💰" label="Revenue" value={kpis ? formatMoney(kpis.revenue, currency) : '—'} delta={kpis && prev ? deltaPercent(kpis.revenue, prev.revenue) : null} loading={overviewLoading} />
            ) : (
              <KpiCard icon="⏱" label="On-time tickets" value={kpis ? formatPercent(kpis.onTimeRate) : '—'} delta={null} loading={overviewLoading} sub={kpis ? `${kpis.delayed} delayed of ${kpis.prepSamples} measured` : undefined} />
            )}
          </div>

          <div className="stat-grid" aria-busy={overviewFetching}>
            {finance && <Stat label="Average order value" value={kpis ? formatMoney(kpis.averageOrderValue, currency) : undefined} sub={kpis && prev?.averageOrderValue != null ? formatDelta(deltaPercent(kpis.averageOrderValue ?? 0, prev.averageOrderValue)) : 'per completed order'} loading={overviewLoading} />}
            <Stat label="Covers" value={kpis?.covers} sub={kpis ? (finance ? `${formatMoney(kpis.revenuePerCover, currency)} per cover` : `${kpis.ordersPerDay} orders per day`) : ''} loading={overviewLoading} />
            <Stat label="Avg prep time" value={kpis ? formatMinutes(kpis.avgPrepMinutes) : undefined} sub={kpis ? (kpis.prepSamples > 0 ? `start prep → ready · ${formatPercent(kpis.onTimeRate)} on time` : 'measured once orders are started and marked ready') : ''} loading={overviewLoading} tone="warning" />
            <Stat label="Avg ticket time" value={kpis ? formatMinutes(kpis.avgTicketMinutes) : undefined} sub={kpis ? 'start prep → served / delivered' : ''} loading={overviewLoading} />
            <Stat label="Table turnover" value={kpis?.tableTurnover ?? (kpis ? '—' : undefined)} sub={kpis ? (kpis.tables > 0 ? `dine-in orders per table per day · ${kpis.tables} tables` : 'add Room resources as tables') : ''} loading={overviewLoading} />
            {finance && <Stat label="Labor % of sales" value={kpis ? formatPercent(kpis.laborPercent) : undefined} sub={kpis ? (kpis.laborPercent != null ? `${formatMoney(kpis.laborCost, currency)} · ${kpis.laborHours} h rostered` : kpis.laborRated === 0 ? 'set hourly rates on staff resources' : 'no sales in range') : ''} loading={overviewLoading} tone={kpis && (kpis.laborPercent ?? 0) > 35 ? 'critical' : undefined} />}
            {finance && <Stat label="Waste % of sales" value={kpis ? formatPercent(kpis.wastePercent) : undefined} sub={kpis ? `${formatMoney(kpis.wasteCost, currency)} · ${kpis.wasteEntries} entries` : ''} loading={overviewLoading} tone={kpis && (kpis.wastePercent ?? 0) > 5 ? 'critical' : undefined} />}
            <Stat label="Low stock" value={kpis?.lowStockItems} sub={kpis ? `items at or below reorder level` : ''} loading={overviewLoading} tone={kpis && kpis.lowStockItems > 0 ? 'warning' : 'good'} />
            {!finance && <Stat label="Completion rate" value={kpis ? formatPercent(kpis.completionRate) : undefined} sub={kpis ? `${kpis.cancelled} cancelled · ${kpis.noShows} no-shows` : ''} loading={overviewLoading} tone="good" />}
          </div>

          <div className="rest-grid">
            {visibleWidgets.map((id) => <Fragment key={id}>{renderWidget(id)}</Fragment>)}
          </div>
          {visibleWidgets.length === 0 && (
            <div className="rest-empty">Every panel is hidden. Use Customise to bring some back.</div>
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

/** The headline card: a big number and its change against the previous
 *  period. `invert` is for metrics where up is bad (cancellations), so
 *  the arrow keeps pointing the way the number moved but the colour says
 *  whether that is good news. */
function KpiCard({ icon, label, value, delta, invert, loading, sub }: { icon: string; label: string; value: string; delta: number | null; invert?: boolean; loading: boolean; sub?: string }) {
  const good = delta === null ? null : invert ? delta < 0 : delta > 0;
  const tone = delta === null || delta === 0 ? 'flat' : good ? 'up' : 'down';
  const arrow = delta === null || delta === 0 ? '·' : delta > 0 ? '↑' : '↓';
  return (
    <div className="rest-kpi">
      <div className="rest-kpi-icon" aria-hidden="true">{icon}</div>
      <div>
        <div className="rest-kpi-value">{loading && value === '—' ? '…' : value}</div>
        <div className="rest-kpi-label">{label}</div>
        <div className={`rest-kpi-delta rest-kpi-delta-${tone}`}><i aria-hidden="true">{arrow}</i>{sub ?? formatDelta(delta)}</div>
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

function Widget({ id, role, title, subtitle, tools, children }: { id: RestaurantWidgetId; role: RestaurantRole | undefined; title: string; subtitle: string; tools?: ReactNode; children: ReactNode }) {
  const meta = widgetsFor(role).find((w) => w.id === id);
  return (
    <section id={id} className={`card chart-card rest-widget${meta?.wide ? ' rest-widget-wide' : ''}`} aria-labelledby={`rest-${id}-title`}>
      <div className="rest-widget-head">
        <div>
          <p className="chart-title" id={`rest-${id}-title`}>{title}</p>
          <p className="chart-subtitle">{subtitle}</p>
        </div>
        {tools && <div className="rest-widget-tools">{tools}</div>}
      </div>
      {children}
    </section>
  );
}

function MenuTable({ overview, active, onSelect, currency, finance, loading }: { overview?: RestaurantOverview; active: string; onSelect: (id: string) => void; currency: string; finance: boolean; loading: boolean }) {
  const rows = overview?.byMenu ?? [];
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="rest-empty">No orders in this range.</div>;
  const max = Math.max(1, ...rows.map((r) => r.orders));
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            <th>Menu type</th>
            <th>Orders</th>
            <th>Prep vs target</th>
            <th>On time</th>
            {finance && <th style={{ textAlign: 'right' }}>Revenue</th>}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const over = r.avgPrepMinutes != null && r.avgPrepMinutes > r.prepTargetMinutes;
            return (
              <tr key={r.bookingTypeId} className={`rest-row-click${active === r.bookingTypeId ? ' is-active' : ''}`} onClick={() => onSelect(r.bookingTypeId)} tabIndex={0}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(r.bookingTypeId); } }} aria-pressed={active === r.bookingTypeId}>
                <td>
                  <span className="rest-menu-chip"><i style={{ background: r.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{r.name}</span>
                  <span className="rest-order-sub">{r.serviceMode} · {r.completed} completed</span>
                </td>
                <td style={{ whiteSpace: 'nowrap' }}><span className="rest-inline-track"><span className="rest-inline-fill" style={{ width: `${(r.orders / max) * 100}%` }} /></span>{r.orders}</td>
                <td style={{ color: over ? 'var(--color-critical)' : undefined, whiteSpace: 'nowrap' }}>{formatMinutes(r.avgPrepMinutes)} <span className="rest-order-sub" style={{ display: 'inline' }}>/ {r.prepTargetMinutes} min</span></td>
                <td>{formatPercent(r.onTimeRate)}</td>
                {finance && <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{formatMoney(r.revenue, currency)}</td>}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

const KIND_LABEL: Record<string, string> = { station: 'Station', table: 'Table', rider: 'Rider', staff: 'Staff', other: 'Resource' };

function StationTable({ overview, active, onSelect, currency, finance, loading }: { overview?: RestaurantOverview; active: string; onSelect: (id: string) => void; currency: string; finance: boolean; loading: boolean }) {
  const rows = overview?.byStation ?? [];
  if (loading && rows.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (rows.length === 0) return <div className="rest-empty">No orders in this range.</div>;
  const max = Math.max(1, ...rows.map((r) => r.orders));
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            <th>Station / table</th>
            <th>Orders</th>
            <th>Completed</th>
            <th>Covers</th>
            <th>Avg prep</th>
            <th>Delayed</th>
            {finance && <th style={{ textAlign: 'right' }}>Revenue</th>}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.resourceId} className={`rest-row-click${active === r.resourceId ? ' is-active' : ''}`} onClick={() => onSelect(r.resourceId)} tabIndex={0}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(r.resourceId); } }} aria-pressed={active === r.resourceId}>
              <td><span className="rest-strong">{r.name}</span><span className="rest-order-sub">{[KIND_LABEL[r.kind], r.branchName].filter(Boolean).join(' · ')}</span></td>
              <td style={{ whiteSpace: 'nowrap' }}><span className="rest-inline-track"><span className="rest-inline-fill" style={{ width: `${(r.orders / max) * 100}%` }} /></span>{r.orders}</td>
              <td>{r.completed}{r.cancelled > 0 && <span className="rest-order-sub">{r.cancelled} cancelled</span>}</td>
              <td>{r.covers}</td>
              <td>{formatMinutes(r.avgPrepMinutes)}</td>
              <td style={{ color: r.delayed > 0 ? 'var(--color-critical)' : undefined }}>{r.delayed}</td>
              {finance && <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{formatMoney(r.revenue, currency)}</td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CustomisePanel({ layout, role, onChange, onClose }: { layout: RestaurantLayout; role: RestaurantRole | undefined; onChange: (l: RestaurantLayout) => void; onClose: () => void }) {
  const widgets = widgetsFor(role);
  return (
    <div className="rest-customise-panel" role="dialog" aria-label="Customise dashboard panels">
      <h4>Panels — tick to show, arrows to reorder</h4>
      {layout.order.map((id, index) => {
        const meta = widgets.find((w) => w.id === id);
        if (!meta) return null;
        const shown = !layout.hidden.includes(id);
        return (
          <div key={id} className="rest-customise-row">
            <input id={`rest-widget-${id}`} type="checkbox" checked={shown} onChange={() => onChange(toggleWidget(layout, id))} />
            <label htmlFor={`rest-widget-${id}`}>{meta.label}<small>{meta.hint}</small></label>
            <span className="rest-reorder">
              <button type="button" aria-label={`Move ${meta.label} up`} disabled={index === 0} onClick={() => onChange(moveWidget(layout, id, -1))}>▲</button>
              <button type="button" aria-label={`Move ${meta.label} down`} disabled={index === layout.order.length - 1} onClick={() => onChange(moveWidget(layout, id, 1))}>▼</button>
            </span>
          </div>
        );
      })}
      <div className="rest-customise-foot">
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(defaultLayout(role))}>Reset to {role === 'Admin' ? 'owner' : role === 'Manager' ? 'floor' : 'kitchen'} default</button>
        <button type="button" className="btn btn-primary btn-sm" onClick={onClose}>Done</button>
      </div>
    </div>
  );
}
