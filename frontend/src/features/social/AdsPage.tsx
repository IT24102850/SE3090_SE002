import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import { Link } from 'react-router-dom';
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import type { RootState } from '../../store/store';
import { useToast } from '../../shared/components/Toast';
import { useChartTheme } from '../../shared/useChartTheme';
import { errorMessage } from '../billing/billingApi';
import { useAsync } from '../billing/useAsync';
import { socialApi, type MarketingSettings, type UpdateMarketingSettings } from './socialApi';
import { PlatformMark, SoBadge, dateTime, relativeTime } from './components';
import '../billing/billing.css';
import './social.css';

/* Channel colours follow the channel, never its rank: the dataviz reference
 * categorical order, validated (scripts/validate_palette.js) for both modes.
 * Light-mode contrast is below 3:1 for three slots, so the chart is always
 * paired with the channel table beneath it. */
const CHANNEL_ORDER = ['Facebook', 'Instagram', 'TikTok', 'Website', 'Direct / in-app', 'Other'] as const;
const CHANNEL_COLORS: Record<'light' | 'dark', string[]> = {
  light: ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300'],
  dark: ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#0ca30c'],
};
const channelKey = (c: string) => ((CHANNEL_ORDER as readonly string[]).includes(c) ? c : 'Other');

function isDark() {
  const attr = document.documentElement.getAttribute('data-theme');
  if (attr === 'dark') return true;
  if (attr === 'light') return false;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
}

const money = (n: number | null | undefined) => (n == null ? '—' : n.toLocaleString(undefined, { maximumFractionDigits: 0 }));
const pct = (n: number | null | undefined, digits = 1) => (n == null ? '—' : `${(n * 100).toFixed(digits)}%`);
const isoDay = (d: Date) => d.toISOString().slice(0, 10);

type Tab = 'performance' | 'tracking' | 'events';

export default function AdsPage() {
  const [tab, setTab] = useState<Tab>('performance');
  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Ads &amp; attribution</h1>
          <p className="page-subtitle">Which channels and ads bring bookings and revenue — and server-side conversion tracking so Meta and TikTok optimise for real bookings, not clicks.</p>
        </div>
      </div>
      <div className="bl-tabs" role="tablist">
        {([['performance', 'Performance'], ['tracking', 'Conversion tracking'], ['events', 'Event log']] as [Tab, string][]).map(([id, label]) => (
          <button key={id} role="tab" aria-selected={tab === id} className={`bl-tab${tab === id ? ' bl-tab-active' : ''}`} onClick={() => setTab(id)}>{label}</button>
        ))}
      </div>
      {tab === 'performance' && <Performance />}
      {tab === 'tracking' && <Tracking />}
      {tab === 'events' && <EventLog />}
    </div>
  );
}

// ── Performance ────────────────────────────────────────────────────────────

function Performance() {
  const theme = useChartTheme();
  const [days, setDays] = useState(30);
  const to = isoDay(new Date());
  const from = isoDay(new Date(Date.now() - (days - 1) * 86_400_000));
  const attribution = useAsync(() => socialApi.attribution(from, to), [from, to]);
  const campaigns = useAsync(() => socialApi.campaigns(from, to), [from, to]);
  const palette = CHANNEL_COLORS[isDark() ? 'dark' : 'light'];

  const { series, rows } = useMemo(() => {
    const daily = attribution.data?.daily ?? [];
    const present = new Set(daily.map((d) => channelKey(d.channel)));
    const seriesKeys = CHANNEL_ORDER.filter((c) => present.has(c));
    const byDate = new Map<string, Record<string, number | string>>();
    for (let i = 0; i < days; i++) {
      const d = isoDay(new Date(Date.parse(from) + i * 86_400_000));
      byDate.set(d, { date: d });
    }
    for (const d of daily) {
      const row = byDate.get(d.date);
      if (!row) continue;
      const k = channelKey(d.channel);
      row[k] = ((row[k] as number) ?? 0) + d.bookings;
    }
    return { series: seriesKeys, rows: [...byDate.values()] };
  }, [attribution.data, days, from]);

  const a = attribution.data;
  const c = campaigns.data;
  const socialShare = a && a.totalBookings > 0 ? a.socialBookings / a.totalBookings : null;
  const maxShare = Math.max(0.0001, ...(a?.channels.map((ch) => ch.revenueShare) ?? [0]));

  return (
    <div className="bl-stack" style={{ gap: 20 }}>
      <div className="bl-row">
        {[7, 30, 90].map((d) => (
          <button key={d} className={`btn btn-sm ${days === d ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setDays(d)}>Last {d} days</button>
        ))}
      </div>

      {(attribution.error || campaigns.error) && <div className="bl-notice bl-notice-critical">{attribution.error ?? campaigns.error}</div>}

      <div className="bl-kpis">
        <Kpi label="Bookings" value={a ? a.totalBookings.toLocaleString() : '…'} sub={a ? `${money(a.totalRevenue)} revenue` : undefined} />
        <Kpi label="From social" value={a ? a.socialBookings.toLocaleString() : '…'} sub={socialShare != null ? `${pct(socialShare, 0)} of bookings` : undefined} />
        <Kpi label="Social revenue" value={a ? money(a.socialRevenue) : '…'} />
        <Kpi label="Ad spend" value={c ? money(c.totalSpend) : '…'} sub={c && c.totalSpend > 0 ? `${c.attributedBookings} attributed bookings` : 'connect an ad account'} />
        <Kpi label="Return on ad spend" value={c?.blendedRoas != null ? `${c.blendedRoas.toFixed(2)}×` : '—'}
          sub={c?.blendedRoas != null ? (c.blendedRoas >= 1 ? '▲ ads earn more than they cost' : '▼ ads cost more than they earn') : undefined} />
      </div>

      <section className="card" style={{ padding: 16 }}>
        <h2 style={{ margin: '0 0 12px', fontSize: '1rem' }}>Bookings per day, by channel</h2>
        {a && a.totalBookings === 0 ? (
          <div className="bl-notice">No bookings in this period. Share a <Link to="/social">tracked booking link</Link> to start seeing where bookings come from.</div>
        ) : (
          <div style={{ width: '100%', height: 260 }}>
            <ResponsiveContainer>
              <BarChart data={rows} margin={{ top: 4, right: 8, left: -12, bottom: 0 }}>
                <CartesianGrid vertical={false} stroke={theme.grid} />
                <XAxis dataKey="date" tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false}
                  tickFormatter={(d: string) => new Date(d).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })} minTickGap={24} />
                <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} tickLine={false} axisLine={false} width={40} />
                <Tooltip cursor={{ fill: theme.grid }} contentStyle={theme.tooltip} itemStyle={theme.tooltipItem}
                  labelFormatter={(d) => new Date(String(d)).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })} />
                <Legend wrapperStyle={{ fontSize: 12, color: theme.tick }} iconType="circle" iconSize={8} />
                {series.map((s, i) => (
                  <Bar key={s} dataKey={s} stackId="c" fill={palette[CHANNEL_ORDER.indexOf(s)]} maxBarSize={28}
                    stroke={theme.tooltip.background} strokeWidth={2}
                    radius={i === series.length - 1 ? [4, 4, 0, 0] : 0} />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </section>

      <section className="bl-stack">
        <h2 style={{ margin: 0, fontSize: '1rem' }}>Channels</h2>
        <div className="bl-table-wrap">
          <table className="bl-table">
            <thead>
              <tr><th>Channel</th><th className="bl-num">Bookings</th><th className="bl-num">Confirmed / done</th><th className="bl-num">Lost</th><th className="bl-num">Revenue</th><th style={{ width: '22%' }}>Share of revenue</th></tr>
            </thead>
            <tbody>
              {a?.channels.map((ch) => (
                <tr key={ch.channel}>
                  <td>
                    <span className="bl-row" style={{ gap: 8 }}>
                      <span aria-hidden style={{ width: 10, height: 10, borderRadius: 3, background: palette[CHANNEL_ORDER.indexOf(channelKey(ch.channel) as typeof CHANNEL_ORDER[number])] }} />
                      {ch.channel}
                    </span>
                  </td>
                  <td className="bl-num">{ch.bookings}</td>
                  <td className="bl-num">{ch.converted}</td>
                  <td className="bl-num">{ch.lost}</td>
                  <td className="bl-num">{money(ch.revenue)}</td>
                  <td>
                    <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                      <div className="so-bar" style={{ flex: 1 }}><span style={{ width: `${(ch.revenueShare / maxShare) * 100}%` }} /></div>
                      <span className="bl-small" style={{ width: 44, textAlign: 'right' }}>{pct(ch.revenueShare, 0)}</span>
                    </div>
                  </td>
                </tr>
              ))}
              {a && a.channels.length === 0 && <tr><td colSpan={6} className="bl-muted">No bookings yet.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      <section className="bl-stack">
        <div className="bl-spread">
          <h2 style={{ margin: 0, fontSize: '1rem' }}>Campaigns</h2>
          <span className="bl-small bl-muted">Spend from your ad accounts; bookings and revenue from Unify, matched by utm_campaign.</span>
        </div>
        {c?.warnings.map((w) => <div key={w} className="bl-notice">{w}</div>)}
        <div className="bl-table-wrap">
          <table className="bl-table">
            <thead>
              <tr>
                <th>Campaign</th><th className="bl-num">Spend</th><th className="bl-num">Clicks</th><th className="bl-num">CTR</th><th className="bl-num">CPC</th>
                <th className="bl-num">Bookings</th><th className="bl-num">Revenue</th><th className="bl-num">Cost / booking</th><th className="bl-num">ROAS</th>
              </tr>
            </thead>
            <tbody>
              {c?.campaigns.map((r) => (
                <tr key={`${r.platform}-${r.campaignId ?? r.campaign}`}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{r.campaign}</div>
                    <div className="bl-small bl-muted">{r.platform}{r.matchedToAdAccount ? '' : ' · no ad spend matched'}</div>
                  </td>
                  <td className="bl-num">{money(r.spend)}</td>
                  <td className="bl-num">{r.clicks?.toLocaleString() ?? '—'}</td>
                  <td className="bl-num">{pct(r.ctr, 2)}</td>
                  <td className="bl-num">{r.cpc?.toFixed(2) ?? '—'}</td>
                  <td className="bl-num">{r.bookings}</td>
                  <td className="bl-num">{money(r.revenue)}</td>
                  <td className="bl-num">{money(r.costPerBooking)}</td>
                  <td className="bl-num">
                    {r.roas == null ? '—' : (
                      <span className={r.roas >= 1 ? 'so-roas-good' : 'so-roas-bad'}>{r.roas >= 1 ? '▲' : '▼'} {r.roas.toFixed(2)}×</span>
                    )}
                  </td>
                </tr>
              ))}
              {c && c.campaigns.length === 0 && (
                <tr><td colSpan={9} className="bl-muted">No campaign data. Add the URL parameters from <Link to="/social">Social accounts</Link> to your ads, and connect an ad account under Conversion tracking.</td></tr>
              )}
            </tbody>
          </table>
        </div>
        <span className="bl-small bl-muted">ROAS compares booking revenue with ad spend as-is, so it assumes your ad account bills in the same currency as your bookings. Lost bookings (cancelled, no-show, rejected) earn no revenue.</span>
      </section>
    </div>
  );
}

function Kpi({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="bl-kpi">
      <div className="bl-kpi-label">{label}</div>
      <div className="bl-kpi-value">{value}</div>
      {sub && <div className="bl-kpi-sub">{sub}</div>}
    </div>
  );
}

// ── Tracking settings ──────────────────────────────────────────────────────

function Tracking() {
  const toast = useToast();
  const isAdmin = useSelector((s: RootState) => s.auth.user?.role) === 'Admin';
  const settings = useAsync(() => socialApi.settings(), []);
  const [draft, setDraft] = useState<UpdateMarketingSettings>({});
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState<string | null>(null);
  const [adAccounts, setAdAccounts] = useState<{ id: string; name: string; currency: string | null }[] | null>(null);

  const s = settings.data;
  const val = (k: keyof UpdateMarketingSettings & keyof MarketingSettings) =>
    (draft[k] as string | undefined) ?? ((s?.[k] as string | null) ?? '');
  const set = (k: keyof UpdateMarketingSettings, v: string | boolean) => setDraft((d) => ({ ...d, [k]: v }));
  const dirty = Object.keys(draft).length > 0;

  const save = async () => {
    setSaving(true);
    try {
      const updated = await socialApi.updateSettings(draft);
      settings.setData(updated);
      setDraft({});
      toast.show('Tracking settings saved.', 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'Could not save.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const test = async (platform: 'meta' | 'tiktok') => {
    setTesting(platform);
    try {
      const r = await socialApi.testEvent(platform);
      toast.show(r.message, r.ok ? 'success' : 'error');
    } catch (err) {
      toast.show(errorMessage(err, 'The test failed.'), 'error');
    } finally {
      setTesting(null);
    }
  };

  const loadAdAccounts = async () => {
    try {
      setAdAccounts(await socialApi.metaAdAccounts());
    } catch (err) {
      toast.show(errorMessage(err, 'Could not list ad accounts.'), 'error');
    }
  };

  if (settings.error) return <div className="bl-notice bl-notice-critical">{settings.error}</div>;
  if (!s) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;

  const secret = (k: keyof UpdateMarketingSettings, has: boolean, hint: string | null, label: string, help: string) => (
    <div className="field" style={{ margin: 0 }}>
      <label htmlFor={`f-${k}`}>{label}</label>
      <input id={`f-${k}`} className="input" type="password" autoComplete="off" disabled={!isAdmin}
        placeholder={has ? `Saved (${hint ?? 'hidden'}) — type to replace` : 'Paste token'}
        value={(draft[k] as string | undefined) ?? ''} onChange={(e) => set(k, e.target.value)} />
      <span className="bl-small bl-muted">
        {help}
        {has && isAdmin && <> · <button type="button" className="btn btn-ghost btn-sm" style={{ padding: '0 4px' }} onClick={() => set(k, '')}>Remove</button></>}
      </span>
    </div>
  );

  const text = (k: keyof UpdateMarketingSettings & keyof MarketingSettings, label: string, help: string, placeholder = '') => (
    <div className="field" style={{ margin: 0 }}>
      <label htmlFor={`f-${k}`}>{label}</label>
      <input id={`f-${k}`} className="input" disabled={!isAdmin} placeholder={placeholder} value={val(k)} onChange={(e) => set(k, e.target.value)} />
      <span className="bl-small bl-muted">{help}</span>
    </div>
  );

  const enabled = (draft.conversionTrackingEnabled as boolean | undefined) ?? s.conversionTrackingEnabled;

  return (
    <div className="bl-stack" style={{ gap: 20 }}>
      <div className="bl-notice">
        When a booking arrives through a tracked link, Unify reports it to Meta and TikTok from the server — <strong>Schedule / PlaceAnOrder</strong> when it is booked,
        <strong> Purchase / CompletePayment</strong> when it is paid or the customer shows up. Ad-blockers and iOS tracking limits don’t stop server-side events, and the ad
        platforms then optimise for people who actually book. Email and phone are sent only as SHA-256 hashes.
        {!isAdmin && <div style={{ marginTop: 6 }}>Only an Admin can change these settings.</div>}
      </div>

      <label className="bl-row" style={{ gap: 8 }}>
        <input type="checkbox" checked={enabled} disabled={!isAdmin} onChange={(e) => set('conversionTrackingEnabled', e.target.checked)} />
        <strong>Send conversion events</strong>
      </label>

      <div className="bl-grid-2" style={{ alignItems: 'start' }}>
        <section className="card bl-stack" style={{ padding: 18 }}>
          <div className="bl-spread">
            <div className="bl-row"><PlatformMark platform="Facebook" /><PlatformMark platform="Instagram" /><strong>Meta</strong></div>
            <SoBadge status={s.metaTrackingActive ? 'Connected' : 'Pending'} />
          </div>
          {text('metaPixelId', 'Pixel (dataset) ID', 'Events Manager → Data sources → your pixel.', '1234567890')}
          {secret('metaCapiToken', s.hasMetaCapiToken, s.metaCapiTokenHint, 'Conversions API access token', 'Events Manager → pixel → Settings → Generate access token.')}
          {text('metaTestEventCode', 'Test event code (optional)', 'While set, events go to Test events only. Clear it to go live.', 'TEST12345')}
          <hr style={{ border: 0, borderTop: '1px solid var(--color-border)', width: '100%' }} />
          <div className="field" style={{ margin: 0 }}>
            <label htmlFor="f-metaAdAccountId">Ad account (for spend and ROAS)</label>
            {adAccounts ? (
              <select id="f-metaAdAccountId" className="input" disabled={!isAdmin} value={val('metaAdAccountId')} onChange={(e) => set('metaAdAccountId', e.target.value)}>
                <option value="">— none —</option>
                {adAccounts.map((acc) => <option key={acc.id} value={acc.id}>{acc.name} ({acc.id}{acc.currency ? `, ${acc.currency}` : ''})</option>)}
              </select>
            ) : (
              <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
                <input id="f-metaAdAccountId" className="input" disabled={!isAdmin} placeholder="act_1234567890" value={val('metaAdAccountId')} onChange={(e) => set('metaAdAccountId', e.target.value)} />
                {isAdmin && s.hasMetaAdsToken && <button type="button" className="btn btn-secondary btn-sm" onClick={loadAdAccounts}>Choose…</button>}
              </div>
            )}
            <span className="bl-small bl-muted">
              {s.hasMetaAdsToken
                ? `Read with the Facebook login from Social accounts${s.metaAdsTokenExpiresAt ? `, valid until ${new Date(s.metaAdsTokenExpiresAt).toLocaleDateString()}` : ''}.`
                : <>Connect Facebook on <Link to="/social">Social accounts</Link> (it includes ads_read), or paste a token below.</>}
            </span>
          </div>
          {secret('metaAdsToken', s.hasMetaAdsToken, null, 'Ads read token (optional override)', 'A system-user token with ads_read, if you prefer not to use the Facebook login.')}
          {isAdmin && <button className="btn btn-secondary btn-sm" style={{ alignSelf: 'flex-start' }} disabled={testing === 'meta' || dirty} onClick={() => test('meta')}>{testing === 'meta' ? 'Sending…' : 'Send test event'}</button>}
        </section>

        <section className="card bl-stack" style={{ padding: 18 }}>
          <div className="bl-spread">
            <div className="bl-row"><PlatformMark platform="TikTok" /><strong>TikTok</strong></div>
            <SoBadge status={s.tikTokTrackingActive ? 'Connected' : 'Pending'} />
          </div>
          {text('tikTokPixelCode', 'Pixel code', 'TikTok Ads Manager → Tools → Events → Web events.', 'C1A2B3...')}
          {secret('tikTokEventsToken', s.hasTikTokEventsToken, s.tikTokEventsTokenHint, 'Events API access token', 'Pixel → Settings → Events API → Generate access token.')}
          {text('tikTokTestEventCode', 'Test event code (optional)', 'From the pixel’s Test events tab. Clear it to go live.', 'TEST12345')}
          <hr style={{ border: 0, borderTop: '1px solid var(--color-border)', width: '100%' }} />
          {text('tikTokAdvertiserId', 'Advertiser ID (for spend and ROAS)', 'Shown at the top of TikTok Ads Manager.', '7012345678901234567')}
          {secret('tikTokAdsToken', s.hasTikTokAdsToken, null, 'Marketing API access token', 'TikTok for Business developer app → long-term access token with Reporting scope.')}
          {isAdmin && <button className="btn btn-secondary btn-sm" style={{ alignSelf: 'flex-start' }} disabled={testing === 'tiktok' || dirty} onClick={() => test('tiktok')}>{testing === 'tiktok' ? 'Sending…' : 'Send test event'}</button>}
        </section>
      </div>

      {isAdmin && (
        <div className="bl-row">
          <button className="btn btn-primary" disabled={!dirty || saving} onClick={save}>{saving ? 'Saving…' : 'Save settings'}</button>
          {dirty && <button className="btn btn-ghost" onClick={() => setDraft({})}>Discard changes</button>}
          {dirty && <span className="bl-small bl-muted">Save before sending a test event.</span>}
        </div>
      )}
    </div>
  );
}

// ── Event log ──────────────────────────────────────────────────────────────

function EventLog() {
  const toast = useToast();
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const events = useAsync(() => socialApi.events({ status: status || undefined, page }), [status, page]);
  const d = events.data;

  const counts = useMemo(() => {
    const by: Record<string, number> = {};
    d?.summary.forEach((s) => { by[s.status] = (by[s.status] ?? 0) + s.count; });
    return by;
  }, [d]);

  const retry = async (id: string) => {
    try {
      await socialApi.retryEvent(id);
      toast.show('Queued for another try.', 'success');
      void events.reload();
    } catch (err) {
      toast.show(errorMessage(err, 'Could not retry.'), 'error');
    }
  };

  return (
    <div className="bl-stack">
      <div className="bl-kpis">
        <Kpi label="Sent (30 days)" value={(counts.Sent ?? 0).toLocaleString()} />
        <Kpi label="Waiting" value={(counts.Pending ?? 0).toLocaleString()} />
        <Kpi label="Failed" value={(counts.Failed ?? 0).toLocaleString()} sub={counts.Failed ? '▼ check the error below' : undefined} />
        <Kpi label="Skipped" value={(counts.Skipped ?? 0).toLocaleString()} />
      </div>
      <div className="bl-row">
        {['', 'Sent', 'Pending', 'Failed', 'Skipped'].map((s) => (
          <button key={s} className={`btn btn-sm ${status === s ? 'btn-primary' : 'btn-ghost'}`} onClick={() => { setStatus(s); setPage(1); }}>{s || 'All'}</button>
        ))}
      </div>
      {events.error && <div className="bl-notice bl-notice-critical">{events.error}</div>}
      <div className="bl-table-wrap">
        <table className="bl-table">
          <thead>
            <tr><th>Event</th><th>Platform</th><th>Booking</th><th className="bl-num">Value</th><th>Status</th><th>When</th><th /></tr>
          </thead>
          <tbody>
            {d?.items.map((e) => (
              <tr key={e.id}>
                <td>{e.platformEventName}{e.isTest && <span className="bl-badge" style={{ marginLeft: 6 }}>test</span>}</td>
                <td><span className="bl-row" style={{ gap: 6 }}><PlatformMark platform={e.platform === 'Facebook' ? 'Facebook' : 'TikTok'} small />{e.platform === 'Facebook' ? 'Meta' : 'TikTok'}</span></td>
                <td className="bl-mono bl-small">{e.bookingId.slice(0, 8).toUpperCase()}</td>
                <td className="bl-num">{e.value != null ? `${e.currency ?? ''} ${money(e.value)}` : '—'}</td>
                <td>
                  <SoBadge status={e.status} />
                  {e.lastError && <div className="bl-small" style={{ color: e.status === 'Failed' ? 'var(--color-critical)' : 'var(--color-text-secondary)', marginTop: 4, maxWidth: 360 }}>{e.lastError}</div>}
                  {e.status === 'Pending' && e.nextAttemptAt && <div className="bl-small bl-muted">retry {relativeTime(e.nextAttemptAt)}</div>}
                </td>
                <td className="bl-small">{dateTime(e.sentAt ?? e.eventTime)}</td>
                <td>{e.status === 'Failed' && <button className="btn btn-ghost btn-sm" onClick={() => retry(e.id)}>Retry</button>}</td>
              </tr>
            ))}
            {d && d.items.length === 0 && <tr><td colSpan={7} className="bl-muted">No events yet. They appear once conversion tracking is set up and a booking comes in through a tracked link.</td></tr>}
          </tbody>
        </table>
      </div>
      {d && d.total > d.pageSize && (
        <div className="bl-row">
          <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
          <span className="bl-small bl-muted">Page {page} of {Math.ceil(d.total / d.pageSize)}</span>
          <button className="btn btn-ghost btn-sm" disabled={page * d.pageSize >= d.total} onClick={() => setPage((p) => p + 1)}>Next</button>
        </div>
      )}
    </div>
  );
}
