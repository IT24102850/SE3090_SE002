import { Link } from 'react-router-dom';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useChartTheme } from '../../shared/useChartTheme';
import PlatformLayout from './PlatformLayout';
import { useOverviewQuery, type PlatformOverview } from './platformApi';

const n = (v: number) => v.toLocaleString();
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '—');
const ago = (iso: string) => {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
};
const uptime = (secs: number) => {
  const d = Math.floor(secs / 86400), h = Math.floor((secs % 86400) / 3600), m = Math.floor((secs % 3600) / 60);
  return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
};

function chartColor() {
  return getComputedStyle(document.documentElement).getPropertyValue('--pf-chart-a').trim() || '#2563EB';
}

function Kpi({ label, value, sub, icon }: { label: string; value: string; sub?: React.ReactNode; icon: string }) {
  return (
    <div className="pf-card pf-kpi">
      <span className="pf-kpi-icon" aria-hidden="true">{icon}</span>
      <div className="pf-kpi-label">{label}</div>
      <div className="pf-kpi-value">{value}</div>
      {sub && <div className="pf-kpi-sub">{sub}</div>}
    </div>
  );
}

function Delta({ now, before }: { now: number; before: number }) {
  if (before === 0) return <b>{now > 0 ? 'new' : 'no change'}</b>;
  const pct = Math.round(((now - before) / before) * 100);
  return <b className={pct >= 0 ? 'up' : 'down'}>{pct >= 0 ? '▲' : '▼'} {Math.abs(pct)}%</b>;
}

function Bars({ rows, total }: { rows: { label: string; value: number; hint?: string }[]; total: number }) {
  if (rows.length === 0) return <div className="pf-empty">Nothing yet.</div>;
  return (
    <div className="pf-bars">
      {rows.map((r) => (
        <div className="pf-bar" key={r.label} title={r.hint}>
          <span>{r.label}</span>
          <div className="pf-bar-track"><i style={{ width: `${total ? Math.max(2, (r.value / total) * 100) : 0}%` }} /></div>
          <b>{n(r.value)}</b>
        </div>
      ))}
    </div>
  );
}

function SecurityPanel({ s }: { s: PlatformOverview['security'] }) {
  const items: { tone: 'good' | 'warn' | 'bad'; title: string; body: string }[] = [];
  items.push(s.mfaEnabledAt
    ? { tone: 'good', title: 'Two-factor sign-in is on', body: `Enrolled ${when(s.mfaEnabledAt)}.` }
    : { tone: 'bad', title: 'Two-factor sign-in is not enrolled', body: 'Sign out and back in to enrol an authenticator app.' });
  items.push(s.failedLogins24h > 0
    ? { tone: s.failedLogins24h >= 3 ? 'bad' : 'warn', title: `${s.failedLogins24h} failed sign-in attempt${s.failedLogins24h === 1 ? '' : 's'} in the last 24 h`, body: 'See the audit log for the addresses involved.' }
    : { tone: 'good', title: 'No failed sign-ins in the last 24 h', body: 'Nobody has tried the owner account with a wrong password or code.' });
  if (s.lockedUntil) items.push({ tone: 'warn', title: 'Account is in lockout', body: `Locked until ${when(s.lockedUntil)} after repeated failures.` });
  items.push(s.liveSessions > 1
    ? { tone: 'warn', title: `${s.liveSessions} consoles are open right now`, body: 'If that is not you, revoke the others under Security.' }
    : { tone: 'good', title: 'This is the only open console', body: `Last sign-in ${when(s.lastLoginAt)} from ${s.lastLoginIp ?? 'unknown'}.` });
  const pwAge = s.passwordChangedAt ? (Date.now() - new Date(s.passwordChangedAt).getTime()) / 86400000 : null;
  if (pwAge !== null && pwAge > 90) items.push({ tone: 'warn', title: `Password is ${Math.floor(pwAge)} days old`, body: 'Rotate it under Security.' });
  return (
    <div className="pf-grid" style={{ gap: 10 }}>
      {items.map((i) => (
        <div key={i.title} className={`pf-alert pf-alert-${i.tone}`}><div><b>{i.title}</b>{i.body}</div></div>
      ))}
    </div>
  );
}

export default function PlatformOverviewPage() {
  const { data, isLoading, isError, refetch } = useOverviewQuery(undefined, { pollingInterval: 60_000 });
  const theme = useChartTheme();
  const series = chartColor();

  return (
    <PlatformLayout title="Overview">
      <div className="pf-head">
        <div>
          <div className="pf-eyebrow">Platform owner</div>
          <h1>Everything on Unify, in one place</h1>
          <p>Every tenant, every user, every booking on the platform - refreshed each minute. {data && <>Generated {ago(data.generatedAt)}.</>}</p>
        </div>
        <button type="button" className="pf-btn" onClick={() => refetch()}>↻ Refresh</button>
      </div>

      {isError && <div className="pf-alert pf-alert-bad"><div><b>Could not load the overview.</b>Your session may have ended; try refreshing.</div></div>}
      {isLoading && !data && <div className="pf-empty">Loading platform figures…</div>}

      {data && (
        <>
          <div className="pf-grid pf-grid-4">
            <Kpi icon="🏢" label="Tenants" value={n(data.tenants.total)} sub={<><b>{n(data.tenants.active)}</b> active · <b>{n(data.tenants.suspended)}</b> suspended · <b>+{n(data.tenants.new30d)}</b> this month</>} />
            <Kpi icon="👥" label="Users" value={n(data.users.total)} sub={<><b>+{n(data.users.new30d)}</b> joined in the last 30 days</>} />
            <Kpi icon="📅" label="Bookings · 30 days" value={n(data.bookings.last30d)} sub={<><Delta now={data.bookings.last30d} before={data.bookings.previous30d} /> vs previous 30 · <b>{n(data.bookings.today)}</b> today</>} />
            <Kpi icon="⏭" label="Upcoming bookings" value={n(data.bookings.upcoming)} sub={<><b>{n(data.bookings.total)}</b> all time</>} />
          </div>

          <div className="pf-grid pf-grid-21">
            <div className="pf-card">
              <div className="pf-card-head"><h2>Bookings created per day</h2><span>Last 30 days, all tenants</span></div>
              <div className="pf-chart">
                <ResponsiveContainer>
                  <AreaChart data={data.bookings.perDay} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
                    <defs>
                      <linearGradient id="pf-area" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={series} stopOpacity={0.28} />
                        <stop offset="100%" stopColor={series} stopOpacity={0.02} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid stroke={theme.grid} vertical={false} />
                    <XAxis dataKey="date" tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(d: string) => d.slice(5)} interval={6} />
                    <YAxis tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} allowDecimals={false} width={40} />
                    <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} formatter={(v) => [n(Number(v ?? 0)), 'Bookings']} />
                    <Area type="monotone" dataKey="count" stroke={series} strokeWidth={2} fill="url(#pf-area)" dot={false} activeDot={{ r: 5, strokeWidth: 2, stroke: theme.tooltip.background }} />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            </div>
            <div className="pf-card">
              <div className="pf-card-head"><h2>Security posture</h2><Link to="/platform/security" style={{ fontSize: '.74rem' }}>Manage →</Link></div>
              <SecurityPanel s={data.security} />
            </div>
          </div>

          <div className="pf-grid pf-grid-3">
            <div className="pf-card">
              <div className="pf-card-head"><h2>New tenants per week</h2><span>Last 12 weeks</span></div>
              <div className="pf-chart" style={{ height: 180 }}>
                <ResponsiveContainer>
                  <BarChart data={data.tenants.perWeek} margin={{ top: 8, right: 8, left: -18, bottom: 0 }} barCategoryGap="30%">
                    <CartesianGrid stroke={theme.grid} vertical={false} />
                    <XAxis dataKey="weekStart" tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(d: string) => d.slice(5)} interval={2} />
                    <YAxis tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} allowDecimals={false} width={40} />
                    <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} formatter={(v) => [n(Number(v ?? 0)), 'Tenants']} labelFormatter={(d) => `Week of ${d}`} />
                    <Bar dataKey="count" fill={series} radius={[4, 4, 0, 0]} maxBarSize={28} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
            <div className="pf-card">
              <div className="pf-card-head"><h2>Tenants by business type</h2><span>{data.tenants.byType.length} types</span></div>
              <Bars total={data.tenants.total} rows={data.tenants.byType.map((t) => ({ label: t.businessType || '(unset)', value: t.count, hint: `${t.active} active` }))} />
            </div>
            <div className="pf-card">
              <div className="pf-card-head"><h2>Users by role</h2><span>Across all tenants</span></div>
              <Bars total={data.users.total} rows={[...data.users.byRole].sort((a, b) => b.count - a.count).map((r) => ({ label: r.role, value: r.count }))} />
            </div>
          </div>

          <div className="pf-grid pf-grid-2">
            <div className="pf-card">
              <div className="pf-card-head"><h2>Busiest tenants</h2><span>Bookings in the last 30 days</span></div>
              {data.topTenants.length === 0 ? <div className="pf-empty">No bookings in the last 30 days.</div> : (
                <ul className="pf-list">
                  {data.topTenants.map((t, i) => (
                    <li key={t.id}>
                      <span>
                        <Link to={`/platform/tenants?open=${t.id}`} style={{ fontWeight: 700, color: 'inherit', textDecoration: 'none' }}>{i + 1}. {t.name}</Link>
                        <small>{t.businessType}{!t.isActive && ' · suspended'}</small>
                      </span>
                      <b>{n(t.bookings30d)}</b>
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <div className="pf-card">
              <div className="pf-card-head"><h2>Recent console activity</h2><Link to="/platform/audit" style={{ fontSize: '.74rem' }}>Full log →</Link></div>
              {data.recentAudit.length === 0 ? <div className="pf-empty">No activity recorded yet.</div> : data.recentAudit.map((a) => (
                <div key={a.id} className={`pf-audit-row${a.succeeded ? '' : ' failed'}`}>
                  <i aria-hidden="true" />
                  <span>
                    <span className="pf-mono">{a.action}</span>{a.targetLabel && <> · {a.targetLabel}</>}
                    <small>{a.actorEmail} · {a.ipAddress}{a.detail && <> · {a.detail}</>}</small>
                  </span>
                  <time dateTime={a.createdAt}>{ago(a.createdAt)}</time>
                </div>
              ))}
            </div>
          </div>

          <div className="pf-card">
            <div className="pf-card-head"><h2>System</h2><span>Backend process</span></div>
            <div className="pf-grid pf-grid-4">
              <div><div className="pf-kpi-label">Environment</div><div style={{ fontWeight: 700 }}>{data.system.environment}</div></div>
              <div><div className="pf-kpi-label">Uptime</div><div style={{ fontWeight: 700 }}>{uptime(data.system.uptimeSeconds)} <small className="pf-count">since {when(data.system.startedAt)}</small></div></div>
              <div><div className="pf-kpi-label">Migrations</div><div style={{ fontWeight: 700 }}>{data.system.appliedMigrations} applied{data.system.pendingMigrations > 0 && <span className="pf-pill pf-pill-warn" style={{ marginLeft: 8 }}>{data.system.pendingMigrations} pending</span>}</div></div>
              <div><div className="pf-kpi-label">Runtime</div><div style={{ fontWeight: 700 }}>.NET {data.system.runtime}</div></div>
            </div>
          </div>
        </>
      )}
    </PlatformLayout>
  );
}
