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
import { STATUS_COLORS, type BookingStatus, type RestaurantTrendBucket } from '../../booking/types';
import { formatMoney } from './restaurantReport';

/* The restaurant dashboard's charts.
 *
 * One axis per chart, one job per chart. Revenue and orders are different
 * scales, so the sales trend shows one metric at a time (a toggle, never
 * a second y-axis). The customer-flow chart is the one two-series panel -
 * dine-in against off-premise - in the two validated series colours, with
 * a legend and a gap between the bars so the pair is never colour-alone.
 * Clickable bar lists are how the dashboard cross-filters. */

/* recharts writes fill/stroke as SVG attributes, so the series colours
 * are read from the CSS tokens as literal strings and re-read when the
 * theme flips - the same reason shared/useChartTheme.ts exists. */
function useSeriesColors() {
  const read = () => {
    const css = getComputedStyle(document.documentElement);
    return {
      a: css.getPropertyValue('--rest-chart-a').trim() || '#3366E8',
      b: css.getPropertyValue('--rest-chart-b').trim() || '#15803D',
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

export type SalesMetric = 'revenue' | 'orders' | 'covers';

const METRIC_LABEL: Record<SalesMetric, string> = { revenue: 'Revenue', orders: 'Orders', covers: 'Covers' };

function compact(value: number): string {
  if (Math.abs(value) >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (Math.abs(value) >= 1_000) return `${(value / 1_000).toFixed(value >= 10_000 ? 0 : 1)}k`;
  return String(Math.round(value));
}

export function SalesTrendChart({ data, metric, currency, loading }: { data: RestaurantTrendBucket[]; metric: SalesMetric; currency: string; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();

  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (data.length === 0 || data.every((d) => d.orders === 0)) {
    return <div className="rest-empty">No orders in this range.</div>;
  }

  const interval = data.length > 20 ? Math.ceil(data.length / 10) - 1 : 0;
  const format = (v: number) => (metric === 'revenue' ? formatMoney(v, currency) : v.toLocaleString());
  const peak = data.reduce((best, d) => (d[metric] > best[metric] ? d : best), data[0]);
  const total = data.reduce((sum, d) => sum + d[metric], 0);

  return (
    <div>
      <ResponsiveContainer width="100%" height={240}>
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
          <defs>
            <linearGradient id="rest-trend-a" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={series.a} stopOpacity={0.22} />
              <stop offset="100%" stopColor={series.a} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={interval} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={48} tickFormatter={compact} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} formatter={(v) => format(Number(v))} />
          <Area type="monotone" dataKey={metric} name={METRIC_LABEL[metric]} stroke={series.a} strokeWidth={2} fill="url(#rest-trend-a)" dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: theme.tooltip.background }} />
        </AreaChart>
      </ResponsiveContainer>
      <p className="rest-note">
        {METRIC_LABEL[metric]} in range: <b>{format(total)}</b> · best period <b>{peak.label}</b> with {format(peak[metric])}.
      </p>
    </div>
  );
}

/** Dine-in against off-premise (takeaway + delivery + drive-thru), the
 *  restaurant's "in restaurant vs online" split, per period. */
export function FlowChart({ data, loading }: { data: RestaurantTrendBucket[]; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();

  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  if (data.length === 0 || data.every((d) => d.dineIn === 0 && d.offPremise === 0)) {
    return <div className="rest-empty">No orders in this range.</div>;
  }

  // A long range as grouped bars would be a comb; fold into ten bars.
  const rows = data.length > 14 ? fold(data, 10) : data;
  const dineIn = data.reduce((s, d) => s + d.dineIn, 0);
  const off = data.reduce((s, d) => s + d.offPremise, 0);
  const total = dineIn + off;

  return (
    <div>
      <div className="rest-flow-heads">
        <div><b>{dineIn.toLocaleString()}</b><span>Dine-in{total > 0 && ` · ${Math.round((dineIn / total) * 100)}%`}</span></div>
        <div><b>{off.toLocaleString()}</b><span>Takeaway / delivery{total > 0 && ` · ${Math.round((off / total) * 100)}%`}</span></div>
      </div>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={rows} margin={{ top: 8, right: 8, left: -18, bottom: 0 }} barGap={2} barCategoryGap="28%">
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={0} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={40} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} />
          <Bar dataKey="dineIn" name="Dine-in" fill={series.a} radius={[4, 4, 0, 0]} maxBarSize={22} />
          <Bar dataKey="offPremise" name="Takeaway / delivery" fill={series.b} radius={[4, 4, 0, 0]} maxBarSize={22} />
        </BarChart>
      </ResponsiveContainer>
      <div className="rest-legend" aria-label="Series">
        <span><i style={{ background: series.a }} aria-hidden="true" />Dine-in</span>
        <span><i style={{ background: series.b }} aria-hidden="true" />Takeaway / delivery</span>
      </div>
    </div>
  );
}

function fold(data: RestaurantTrendBucket[], buckets: number): RestaurantTrendBucket[] {
  const size = Math.ceil(data.length / buckets);
  const out: RestaurantTrendBucket[] = [];
  for (let i = 0; i < data.length; i += size) {
    const chunk = data.slice(i, i + size);
    const first = chunk[0];
    const last = chunk[chunk.length - 1];
    out.push({
      ...first,
      label: chunk.length > 1 ? `${first.label}–${last.label}` : first.label,
      orders: chunk.reduce((s, d) => s + d.orders, 0),
      completed: chunk.reduce((s, d) => s + d.completed, 0),
      cancelled: chunk.reduce((s, d) => s + d.cancelled, 0),
      revenue: chunk.reduce((s, d) => s + d.revenue, 0),
      covers: chunk.reduce((s, d) => s + d.covers, 0),
      dineIn: chunk.reduce((s, d) => s + d.dineIn, 0),
      offPremise: chunk.reduce((s, d) => s + d.offPremise, 0),
    });
  }
  return out;
}

export function HourChart({ data, metric, currency, loading }: { data: { hour: number; orders: number; revenue: number }[]; metric: 'orders' | 'revenue'; currency: string; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();

  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const total = data.reduce((sum, d) => sum + d.orders, 0);
  if (total === 0) return <div className="rest-empty">No orders in this range.</div>;

  // Trim the silent overnight hours so the service day fills the chart.
  const first = Math.max(0, data.findIndex((d) => d.orders > 0) - 1);
  const lastIndex = data.length - 1 - [...data].reverse().findIndex((d) => d.orders > 0);
  const last = Math.min(23, lastIndex + 1);
  const rows = data.slice(first, last + 1).map((d) => ({ ...d, label: `${String(d.hour).padStart(2, '0')}:00` }));
  const peak = rows.reduce((best, d) => (d[metric] > best[metric] ? d : best), rows[0]);
  const format = (v: number) => (metric === 'revenue' ? formatMoney(v, currency) : `${v.toLocaleString()} order${v === 1 ? '' : 's'}`);

  return (
    <div>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={rows} margin={{ top: 8, right: 8, left: -10, bottom: 0 }} barCategoryGap={2}>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={rows.length > 12 ? 1 : 0} />
          <YAxis allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={48} tickFormatter={compact} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} formatter={(v) => format(Number(v))} />
          <Bar dataKey={metric} name={metric === 'revenue' ? 'Revenue' : 'Orders'} fill={series.a} radius={[4, 4, 0, 0]} maxBarSize={28} />
        </BarChart>
      </ResponsiveContainer>
      <p className="rest-note">Busiest hour: <b>{peak.label}</b> with {format(peak[metric])}.</p>
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
  if (data.length === 0) return <div className="rest-empty">{emptyText}</div>;
  const max = Math.max(1, ...data.map((d) => d.value));
  return (
    <div>
      <div className="rest-bars">
        {data.map((d) => {
          const pct = Math.max((d.value / max) * 100, d.value > 0 ? 2 : 0);
          const isActive = active === d.key;
          return (
            <button
              key={d.key}
              type="button"
              className={`rest-bar${isActive ? ' is-active' : ''}`}
              disabled={!onSelect}
              onClick={onSelect ? () => onSelect(d.key) : undefined}
              aria-pressed={onSelect ? isActive : undefined}
              title={onSelect ? (isActive ? 'Clear this filter' : `Filter the dashboard by ${d.label}`) : undefined}
            >
              <span className="rest-bar-label">{d.label}{d.sub && <span className="rest-bar-sub"> · {d.sub}</span>}</span>
              <span className="rest-bar-value">{format(d.value)}</span>
              <span className="rest-bar-track"><span className="rest-bar-fill" style={{ width: `${pct}%`, background: d.color }} /></span>
            </button>
          );
        })}
      </div>
      {hint && onSelect && <p className="rest-bar-hint">{hint}</p>}
    </div>
  );
}

const STATUS_ORDER: BookingStatus[] = ['Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'Rejected', 'NoShow', 'WeatherCancelled'];
/** Restaurant words for the booking statuses. */
export const STATUS_LABEL: Partial<Record<BookingStatus, string>> = {
  Pending: 'New',
  Confirmed: 'Accepted',
  CheckedIn: 'Preparing',
  InProgress: 'Ready / serving',
  Completed: 'Completed',
  NoShow: 'No-show',
  WeatherCancelled: 'Weather-cancelled',
};

/** Status uses the console's reserved status palette, with a label on
 *  every row, so the mix is never colour-alone. */
export function StatusMix({ mix, loading }: { mix: { status: BookingStatus; count: number }[]; loading: boolean }) {
  if (loading && mix.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const total = mix.reduce((sum, m) => sum + m.count, 0);
  if (total === 0) return <div className="rest-empty">No orders in this range.</div>;
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
