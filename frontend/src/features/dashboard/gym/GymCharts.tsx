import { useEffect, useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { useChartTheme } from '../../../shared/useChartTheme';
import type { GymTrendBucket } from '../../booking/types';
import { formatMoney, hourLabel } from './gymReport';

/* The gym dashboard's charts.
 *
 * Trend: one metric at a time (visits / members / class bookings / sign-ups
 * / revenue) - never a second y-axis. Entries vs exits by hour is the one
 * two-series chart, in the two validated series colours with a legend.
 * The heatmap is sequential: a single hue, light -> dark by count, with
 * the count in a tooltip and the busiest cell direct-labelled, so it is
 * never colour-alone. Clickable bar lists cross-filter. */

function useSeriesColors() {
  const read = () => {
    const css = getComputedStyle(document.documentElement);
    return {
      a: css.getPropertyValue('--gym-chart-a').trim() || '#3366E8',
      b: css.getPropertyValue('--gym-chart-b').trim() || '#15803D',
    };
  };
  const [colors, setColors] = useState(read);
  useEffect(() => {
    const observer = new MutationObserver(() => setColors(read()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const onMedia = () => setColors(read());
    media.addEventListener('change', onMedia);
    return () => {
      observer.disconnect();
      media.removeEventListener('change', onMedia);
    };
  }, []);
  return colors;
}

export type TrendMetric = 'visits' | 'uniqueMembers' | 'classBookings' | 'signUps' | 'revenue';
export const TREND_LABEL: Record<TrendMetric, string> = { visits: 'Visits', uniqueMembers: 'Unique members', classBookings: 'Class bookings', signUps: 'Sign-ups', revenue: 'Revenue' };

function compact(value: number): string {
  if (Math.abs(value) >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (Math.abs(value) >= 1_000) return `${(value / 1_000).toFixed(value >= 10_000 ? 0 : 1)}k`;
  return String(Math.round(value));
}

export function TrendChart({ data, metric, currency, loading }: { data: GymTrendBucket[]; metric: TrendMetric; currency: string; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();
  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (data.length === 0 || data.every((d) => d[metric] === 0)) return <div className="gym-empty">Nothing in this range.</div>;

  const interval = data.length > 20 ? Math.ceil(data.length / 10) - 1 : 0;
  const format = (v: number) => (metric === 'revenue' ? formatMoney(v, currency) : v.toLocaleString());
  const peak = data.reduce((best, d) => (d[metric] > best[metric] ? d : best), data[0]);
  const total = data.reduce((s, d) => s + d[metric], 0);

  return (
    <div>
      <ResponsiveContainer width="100%" height={220}>
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
          <defs>
            <linearGradient id="gym-trend-a" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={series.a} stopOpacity={0.22} />
              <stop offset="100%" stopColor={series.a} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={interval} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={48} tickFormatter={compact} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} formatter={(v) => format(Number(v))} />
          <Area type="monotone" dataKey={metric} name={TREND_LABEL[metric]} stroke={series.a} strokeWidth={2} fill="url(#gym-trend-a)" dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: theme.tooltip.background }} />
        </AreaChart>
      </ResponsiveContainer>
      <p className="gym-note">{TREND_LABEL[metric]} in range: <b>{format(total)}</b> · best period <b>{peak.label}</b> with {format(peak[metric])}.</p>
    </div>
  );
}

/** Today's entries against exits per hour - the two-series panel. */
export function FlowChart({ data, loading }: { data: { hour: number; entries: number; exits: number }[]; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();
  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const total = data.reduce((s, d) => s + d.entries + d.exits, 0);
  if (total === 0) return <div className="gym-empty">No check-ins yet today.</div>;

  const first = Math.max(0, data.findIndex((d) => d.entries + d.exits > 0) - 1);
  const lastIndex = data.length - 1 - [...data].reverse().findIndex((d) => d.entries + d.exits > 0);
  const rows = data.slice(first, Math.min(23, lastIndex + 1) + 1).map((d) => ({ ...d, label: hourLabel(d.hour) }));

  return (
    <div>
      <ResponsiveContainer width="100%" height={180}>
        <BarChart data={rows} margin={{ top: 8, right: 8, left: -18, bottom: 0 }} barGap={2} barCategoryGap="28%">
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={rows.length > 12 ? 1 : 0} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={40} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} />
          <Bar dataKey="entries" name="Entries" fill={series.a} radius={[4, 4, 0, 0]} maxBarSize={20} />
          <Bar dataKey="exits" name="Exits" fill={series.b} radius={[4, 4, 0, 0]} maxBarSize={20} />
        </BarChart>
      </ResponsiveContainer>
      <div className="gym-legend" aria-label="Series">
        <span><i style={{ background: series.a }} aria-hidden="true" />Entries</span>
        <span><i style={{ background: series.b }} aria-hidden="true" />Exits</span>
      </div>
    </div>
  );
}

/** Check-ins by day of week and hour. Sequential single-hue fill; the
 *  count sits in the cell's tooltip, the busiest cell is labelled, and
 *  the silent overnight hours are trimmed so the open day fills the grid. */
export function Heatmap({ data, loading }: { data: { dayOfWeek: number; label: string; hours: number[] }[]; loading: boolean }) {
  const series = useSeriesColors();
  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const max = Math.max(0, ...data.flatMap((d) => d.hours));
  if (max === 0) return <div className="gym-empty">No check-ins in this range.</div>;

  const busy = Array.from({ length: 24 }, (_, h) => data.some((d) => d.hours[h] > 0));
  const first = Math.max(0, busy.indexOf(true) - 1);
  const last = Math.min(23, busy.lastIndexOf(true) + 1);
  const hours = Array.from({ length: last - first + 1 }, (_, i) => first + i);
  // Monday-first, the way the roster reads.
  const rows = [...data.slice(1), data[0]];
  let peak = { day: rows[0].label, hour: 0, count: 0 };
  for (const d of rows) d.hours.forEach((c, h) => { if (c > peak.count) peak = { day: d.label, hour: h, count: c }; });

  return (
    <div>
      <div className="gym-heatmap" style={{ gridTemplateColumns: `44px repeat(${hours.length}, minmax(0, 1fr))` }} role="table" aria-label="Check-ins by day and hour">
        <span />
        {hours.map((h) => <span key={h} className="gym-heatmap-hour" role="columnheader">{h % 3 === 0 ? String(h).padStart(2, '0') : ''}</span>)}
        {rows.map((d) => (
          <div key={d.dayOfWeek} style={{ display: 'contents' }} role="row">
            <span className="gym-heatmap-day" role="rowheader">{d.label}</span>
            {hours.map((h) => {
              const count = d.hours[h];
              const alpha = count === 0 ? 0 : 0.14 + 0.86 * (count / max);
              const isPeak = count === peak.count && d.label === peak.day && h === peak.hour;
              return (
                <span
                  key={h}
                  role="cell"
                  className={`gym-heatmap-cell${isPeak ? ' is-peak' : ''}`}
                  style={{ background: count === 0 ? 'var(--color-neutral-soft)' : series.a, opacity: count === 0 ? 1 : alpha }}
                  title={`${d.label} ${hourLabel(h)}: ${count} check-in${count === 1 ? '' : 's'}`}
                >
                  {isPeak ? count : ''}
                </span>
              );
            })}
          </div>
        ))}
      </div>
      <div className="gym-heatmap-legend">
        <span>Quiet</span>
        {[0.14, 0.35, 0.57, 0.78, 1].map((a) => <i key={a} style={{ background: series.a, opacity: a }} aria-hidden="true" />)}
        <span>Busy · peak <b>{peak.day} {hourLabel(peak.hour)}</b> with {peak.count}</span>
      </div>
    </div>
  );
}

export interface BarDatum {
  key: string;
  label: string;
  value: number;
  sub?: string;
  color?: string;
}

export function BarList({
  data, active, onSelect, format = (v) => v.toLocaleString(), emptyText = 'Nothing in this range.', hint,
}: {
  data: BarDatum[]; active?: string | null; onSelect?: (key: string) => void; format?: (value: number) => string; emptyText?: string; hint?: string;
}) {
  if (data.length === 0) return <div className="gym-empty">{emptyText}</div>;
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div>
      <div className="gym-bars">
        {data.map((d) => {
          const pct = Math.max((d.value / max) * 100, d.value > 0 ? 2 : 0);
          const isActive = active === d.key;
          return (
            <button key={d.key} type="button" className={`gym-bar${isActive ? ' is-active' : ''}`} disabled={!onSelect}
              onClick={onSelect ? () => onSelect(d.key) : undefined} aria-pressed={onSelect ? isActive : undefined}
              title={onSelect ? (isActive ? 'Clear this filter' : `Filter the dashboard by ${d.label}`) : undefined}>
              <span className="gym-bar-label">{d.label}{d.sub && <span className="gym-bar-sub"> · {d.sub}</span>}</span>
              <span className="gym-bar-value">{format(d.value)}</span>
              <span className="gym-bar-track"><span className="gym-bar-fill" style={{ width: `${pct}%`, background: d.color }} /></span>
            </button>
          );
        })}
      </div>
      {hint && onSelect && <p className="gym-bar-hint">{hint}</p>}
    </div>
  );
}

/** A progress bar against a target - the MTD / YTD revenue tile. */
export function TargetBar({ label, value, target, currency, sub }: { label: string; value: number; target: number | null; currency: string; sub?: string }) {
  const pct = target && target > 0 ? Math.min(100, (value / target) * 100) : null;
  const tone = pct === null ? undefined : pct >= 100 ? 'var(--color-good)' : pct >= 70 ? undefined : 'var(--color-warning)';
  return (
    <div className="gym-target">
      <div className="gym-target-head">
        <span>{label}</span>
        <b>{formatMoney(value, currency)}</b>
      </div>
      <span className="gym-target-track"><span className="gym-target-fill" style={{ width: `${pct ?? 0}%`, background: tone }} /></span>
      <div className="gym-target-foot">
        {target && target > 0 ? <span>{Math.round((value / target) * 100)}% of {formatMoney(target, currency)}</span> : <span>No target set - add monthlyRevenueTarget to the Memberships module config</span>}
        {sub && <span>{sub}</span>}
      </div>
    </div>
  );
}
