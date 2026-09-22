import { useEffect, useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { useChartTheme } from '../../../shared/useChartTheme';
import type { SchoolTrendBucket } from '../../booking/types';
import { formatMoney } from './schoolReport';

/* The school dashboard's charts: one metric per chart, the two validated
 * series colours, clickable bar lists for cross-filtering, and a small
 * score-over-time line for one student's assessments. */

function useSeriesColors() {
  const read = () => {
    const css = getComputedStyle(document.documentElement);
    return {
      a: css.getPropertyValue('--school-chart-a').trim() || '#3366E8',
      b: css.getPropertyValue('--school-chart-b').trim() || '#15803D',
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

export type TrendMetric = 'attendanceRate' | 'avgScore' | 'sessions' | 'absences' | 'newStudents' | 'tuitionPaid';
export const TREND_LABEL: Record<TrendMetric, string> = {
  attendanceRate: 'Attendance %', avgScore: 'Average %', sessions: 'Sessions', absences: 'Absences', newStudents: 'New students', tuitionPaid: 'Tuition paid',
};

function compact(value: number): string {
  if (Math.abs(value) >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (Math.abs(value) >= 1_000) return `${(value / 1_000).toFixed(value >= 10_000 ? 0 : 1)}k`;
  return String(Math.round(value));
}

export function TrendChart({ data, metric, currency, loading }: { data: SchoolTrendBucket[]; metric: TrendMetric; currency: string; loading: boolean }) {
  const theme = useChartTheme();
  const series = useSeriesColors();
  if (loading && data.length === 0) return <div className="loading-row"><span className="spinner spinner-dark" /></div>;
  const rows = data.map((d) => ({ ...d, value: d[metric] }));
  if (rows.length === 0 || rows.every((d) => d.value === null || d.value === 0)) return <div className="school-empty">Nothing in this range.</div>;

  const isPercent = metric === 'attendanceRate' || metric === 'avgScore';
  const format = (v: number) => (metric === 'tuitionPaid' ? formatMoney(v, currency) : isPercent ? `${v.toFixed(1)}%` : v.toLocaleString());
  const interval = rows.length > 20 ? Math.ceil(rows.length / 10) - 1 : 0;
  const present = rows.filter((r) => r.value !== null) as (SchoolTrendBucket & { value: number })[];
  const best = present.reduce((b, d) => (d.value > b.value ? d : b), present[0]);
  const worst = present.reduce((b, d) => (d.value < b.value ? d : b), present[0]);

  return (
    <div>
      <ResponsiveContainer width="100%" height={220}>
        <AreaChart data={rows} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
          <defs>
            <linearGradient id="school-trend-a" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={series.a} stopOpacity={0.22} />
              <stop offset="100%" stopColor={series.a} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={interval} />
          <YAxis domain={isPercent ? [0, 100] : undefined} allowDecimals={false} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={48} tickFormatter={compact} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} formatter={(v) => (v === null ? '—' : format(Number(v)))} />
          <Area type="monotone" dataKey="value" name={TREND_LABEL[metric]} stroke={series.a} strokeWidth={2} fill="url(#school-trend-a)" dot={false} connectNulls activeDot={{ r: 4, strokeWidth: 2, stroke: theme.tooltip.background }} />
        </AreaChart>
      </ResponsiveContainer>
      <p className="school-note">
        {isPercent
          ? <>Best <b>{best.label}</b> ({format(best.value)}) · lowest <b>{worst.label}</b> ({format(worst.value)}).</>
          : <>{TREND_LABEL[metric]} in range: <b>{format(present.reduce((s, d) => s + d.value, 0))}</b> · peak <b>{best.label}</b> with {format(best.value)}.</>}
      </p>
    </div>
  );
}

/** One student's assessment scores over time, as a percentage. */
export function ScoreLine({ data, threshold }: { data: { label: string; percent: number | null; name: string }[]; threshold: number }) {
  const theme = useChartTheme();
  const series = useSeriesColors();
  const rows = data.filter((d) => d.percent !== null);
  if (rows.length === 0) return <div className="school-empty">No graded work in this range.</div>;
  return (
    <div>
      <ResponsiveContainer width="100%" height={180}>
        <LineChart data={rows} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
          <CartesianGrid stroke={theme.grid} vertical={false} />
          <XAxis dataKey="label" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} interval={rows.length > 8 ? 1 : 0} />
          <YAxis domain={[0, 100]} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={40} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ stroke: theme.grid }} formatter={(v, _n, p) => [`${Number(v).toFixed(1)}%`, (p.payload as { name: string }).name]} />
          <Line type="monotone" dataKey="percent" name="Score" stroke={series.a} strokeWidth={2} dot={{ r: 4, fill: series.a, strokeWidth: 2, stroke: theme.tooltip.background }} />
        </LineChart>
      </ResponsiveContainer>
      <p className="school-note">Pass line at <b>{threshold}%</b>; each point is one exam or assignment.</p>
    </div>
  );
}

/** Attendance % per subject for one student - a horizontal bar per subject
 *  is clearer than a radar for six or fewer subjects. */
export function SubjectBars({ data }: { data: { name: string; attendanceRate: number | null; avgScore: number | null }[] }) {
  const theme = useChartTheme();
  const series = useSeriesColors();
  const rows = data.filter((d) => d.attendanceRate !== null || d.avgScore !== null);
  if (rows.length === 0) return <div className="school-empty">No subjects in this range.</div>;
  return (
    <div>
      <ResponsiveContainer width="100%" height={Math.max(120, rows.length * 34)}>
        <BarChart data={rows} layout="vertical" margin={{ top: 4, right: 8, left: 8, bottom: 0 }} barGap={2} barCategoryGap="30%">
          <CartesianGrid stroke={theme.grid} horizontal={false} />
          <XAxis type="number" domain={[0, 100]} tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} />
          <YAxis type="category" dataKey="name" tick={{ fill: theme.tick, fontSize: 11 }} axisLine={false} tickLine={false} width={110} />
          <Tooltip contentStyle={theme.tooltip} itemStyle={theme.tooltipItem} labelStyle={theme.tooltipItem} cursor={{ fill: theme.grid }} formatter={(v) => (v === null ? '—' : `${Number(v).toFixed(1)}%`)} />
          <Bar dataKey="attendanceRate" name="Attendance" fill={series.a} radius={[0, 4, 4, 0]} maxBarSize={12} />
          <Bar dataKey="avgScore" name="Average" fill={series.b} radius={[0, 4, 4, 0]} maxBarSize={12} />
        </BarChart>
      </ResponsiveContainer>
      <div className="school-legend" aria-label="Series">
        <span><i style={{ background: series.a }} aria-hidden="true" />Attendance %</span>
        <span><i style={{ background: series.b }} aria-hidden="true" />Average %</span>
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
  data, active, onSelect, format = (v) => v.toLocaleString(), emptyText = 'Nothing in this range.', hint, max: maxOverride,
}: {
  data: BarDatum[]; active?: string | null; onSelect?: (key: string) => void; format?: (value: number) => string; emptyText?: string; hint?: string; max?: number;
}) {
  if (data.length === 0) return <div className="school-empty">{emptyText}</div>;
  const max = maxOverride ?? Math.max(1, ...data.map((d) => d.value));
  return (
    <div>
      <div className="school-bars">
        {data.map((d) => {
          const pct = Math.max((d.value / max) * 100, d.value > 0 ? 2 : 0);
          const isActive = active === d.key;
          return (
            <button key={d.key} type="button" className={`school-bar${isActive ? ' is-active' : ''}`} disabled={!onSelect}
              onClick={onSelect ? () => onSelect(d.key) : undefined} aria-pressed={onSelect ? isActive : undefined}
              title={onSelect ? (isActive ? 'Clear this filter' : `Filter the dashboard by ${d.label}`) : undefined}>
              <span className="school-bar-label">{d.label}{d.sub && <span className="school-bar-sub"> · {d.sub}</span>}</span>
              <span className="school-bar-value">{format(d.value)}</span>
              <span className="school-bar-track"><span className="school-bar-fill" style={{ width: `${Math.min(100, pct)}%`, background: d.color }} /></span>
            </button>
          );
        })}
      </div>
      {hint && onSelect && <p className="school-bar-hint">{hint}</p>}
    </div>
  );
}
