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
import { STATUS_COLORS, type BookingStatus, type ClinicTrendBucket } from '../../booking/types';

/* The clinic dashboard's charts.
 *
 * Each has one axis and one job. The trend plots two series - appointments
 * and completions - in the two validated series colours; no-shows are not a
 * third line because red next to green fails the colour-vision check, so
 * they get their own single-hue bars in the status panel and the CSV.
 * Clickable bar lists are how the dashboard cross-filters: a doctor, a
 * treatment, a branch or an insurer is one click from becoming the filter
 * every other panel obeys. */

/* recharts writes fill/stroke as SVG attributes, so the series colours are
 * read from the CSS tokens as literal strings, and re-read when the theme
 * flips - the same reason shared/useChartTheme.ts exists. */
function useSeriesColors() {
  const read = () => {
    const css = getComputedStyle(document.documentElement);
    return {
      a: css.getPropertyValue('--clinic-chart-a').trim() || '#3366E8',
      b: css.getPropertyValue('--clinic-chart-b').trim() || '#15803D',
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

export function TrendChart({ data, loading }: { data: ClinicTrendBucket[]; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();

  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (data.length === 0 || data.every((d) => d.appointments === 0)) {
    return <div className="clinic-empty">No appointments in this range.</div>;
  }

  // Thin out the tick labels on long ranges so they never overlap.
  const interval = data.length > 20 ? Math.ceil(data.length / 10) - 1 : 0;

  return (
    <div>
      <ResponsiveContainer width="100%" height={240}>
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
          <defs>
            <linearGradient id="clinic-trend-a" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={series.a} stopOpacity={0.22} />
              <stop offset="100%" stopColor={series.a} stopOpacity={0} />
            </linearGradient>
            <linearGradient id="clinic-trend-b" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={series.b} stopOpacity={0.18} />
              <stop offset="100%" stopColor={series.b} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={interval} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={40} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} />
          <Area type="monotone" dataKey="appointments" name="Appointments" stroke={series.a} strokeWidth={2} fill="url(#clinic-trend-a)" dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: theme.tooltip.background }} />
          <Area type="monotone" dataKey="completed" name="Completed" stroke={series.b} strokeWidth={2} fill="url(#clinic-trend-b)" dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: theme.tooltip.background }} />
        </AreaChart>
      </ResponsiveContainer>
      <div className="clinic-legend" aria-label="Series">
        <span><i style={{ background: series.a }} aria-hidden="true" />Appointments</span>
        <span><i style={{ background: series.b }} aria-hidden="true" />Completed</span>
      </div>
    </div>
  );
}

export function HourChart({ data, loading }: { data: { hour: number; appointments: number }[]; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();

  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const total = data.reduce((sum, d) => sum + d.appointments, 0);
  if (total === 0) return <div className="clinic-empty">No appointments in this range.</div>;

  // Trim the silent overnight hours so the working day fills the chart.
  const first = Math.max(0, data.findIndex((d) => d.appointments > 0) - 1);
  const lastIndex = data.length - 1 - [...data].reverse().findIndex((d) => d.appointments > 0);
  const last = Math.min(23, lastIndex + 1);
  const rows = data.slice(first, last + 1).map((d) => ({ ...d, label: `${String(d.hour).padStart(2, '0')}:00` }));
  const peak = rows.reduce((best, d) => (d.appointments > best.appointments ? d : best), rows[0]);

  return (
    <div>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={rows} margin={{ top: 8, right: 8, left: -18, bottom: 0 }} barCategoryGap={2}>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={rows.length > 12 ? 1 : 0} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={40} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} />
          <Bar dataKey="appointments" name="Appointments" fill={series.a} radius={[4, 4, 0, 0]} maxBarSize={28} />
        </BarChart>
      </ResponsiveContainer>
      <p className="clinic-note">Busiest hour: <b>{peak.label}</b> with {peak.appointments} appointment{peak.appointments === 1 ? '' : 's'}.</p>
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

/** A clickable bar list. `active` marks the row that is the current
 *  filter; clicking it again clears. Values are direct-labelled and the
 *  text stays in text tokens - the bar carries the identity colour. */
export function BarList({
  data,
  active,
  onSelect,
  format = (v) => v.toLocaleString(),
  emptyText = 'Nothing in this range.',
  hint,
}: {
  data: BarDatum[];
  active?: string | null;
  onSelect?: (key: string) => void;
  format?: (value: number) => string;
  emptyText?: string;
  hint?: string;
}) {
  if (data.length === 0) return <div className="clinic-empty">{emptyText}</div>;
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div>
      <div className="clinic-bars">
        {data.map((d) => {
          const pct = Math.max((d.value / max) * 100, d.value > 0 ? 2 : 0);
          const isActive = active === d.key;
          return (
            <button
              key={d.key}
              type="button"
              className={`clinic-bar${isActive ? ' is-active' : ''}`}
              disabled={!onSelect}
              onClick={onSelect ? () => onSelect(d.key) : undefined}
              aria-pressed={onSelect ? isActive : undefined}
              title={onSelect ? (isActive ? 'Clear this filter' : `Filter the dashboard by ${d.label}`) : undefined}
            >
              <span className="clinic-bar-label">{d.label}{d.sub && <span style={{ fontWeight: 500, color: 'var(--color-text-muted)' }}> · {d.sub}</span>}</span>
              <span className="clinic-bar-value">{format(d.value)}</span>
              <span className="clinic-bar-track"><span className="clinic-bar-fill" style={{ width: `${pct}%`, background: d.color }} /></span>
            </button>
          );
        })}
      </div>
      {hint && onSelect && <p className="clinic-bar-hint">{hint}</p>}
    </div>
  );
}

const STATUS_ORDER: BookingStatus[] = ['Confirmed', 'Pending', 'CheckedIn', 'InProgress', 'Completed', 'NoShow', 'Cancelled', 'Rejected', 'WeatherCancelled'];
const STATUS_LABEL: Partial<Record<BookingStatus, string>> = { CheckedIn: 'Checked in', InProgress: 'In consultation', NoShow: 'No-show', WeatherCancelled: 'Weather-cancelled' };

/** Status uses the console's reserved status palette, with a label on
 *  every row, so the mix is never colour-alone. */
export function StatusMix({ mix, loading }: { mix: { status: BookingStatus; count: number }[]; loading: boolean }) {
  if (loading && mix.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const total = mix.reduce((sum, m) => sum + m.count, 0);
  if (total === 0) return <div className="clinic-empty">No appointments in this range.</div>;
  const rows = [...mix]
    .sort((a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status))
    .map<BarDatum>((m) => ({
      key: m.status,
      label: STATUS_LABEL[m.status] ?? m.status,
      value: m.count,
      sub: `${Math.round((m.count / total) * 100)}%`,
      color: STATUS_COLORS[m.status]?.bg,
    }));
  return <BarList data={rows} />;
}
