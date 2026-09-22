import type { ClinicGroupBy, ClinicOverview } from '../../booking/types';
import { addDays, startOfMonth, toISODate } from '../../../shared/dateUtils';

/* Reporting helpers: the date presets the filter bar offers and the CSV
 * export. Kept apart from the components so the CSV shape can be tested
 * and reused by the mobile app's share sheet if it ever grows one. */

export type ClinicRangePreset = 'today' | '7d' | '30d' | 'month' | 'daily' | 'weekly' | 'monthly' | 'custom';

export interface ClinicRange {
  from: string;
  to: string;
  groupBy: ClinicGroupBy;
}

/** Operational presets look back a fixed window; the three report presets
 *  match the exportable daily / weekly / monthly operational reports. */
export function presetRange(preset: ClinicRangePreset, today = new Date()): ClinicRange {
  const to = toISODate(today);
  switch (preset) {
    case 'today':
      return { from: to, to, groupBy: 'day' };
    case '7d':
      return { from: toISODate(addDays(today, -6)), to, groupBy: 'day' };
    case 'month':
      return { from: toISODate(startOfMonth(today)), to, groupBy: 'day' };
    case 'daily':
      return { from: toISODate(addDays(today, -13)), to, groupBy: 'day' };
    case 'weekly':
      return { from: toISODate(addDays(today, -7 * 12 + 1)), to, groupBy: 'week' };
    case 'monthly': {
      const start = new Date(today.getFullYear(), today.getMonth() - 11, 1);
      return { from: toISODate(start), to, groupBy: 'month' };
    }
    case '30d':
    default:
      return { from: toISODate(addDays(today, -29)), to, groupBy: 'day' };
  }
}

function cell(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = typeof value === 'number' ? String(value) : String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function section(title: string, header: string[], rows: unknown[][]): string[] {
  return [title, header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(',')), ''];
}

/** One CSV with a section per breakdown, so the whole report opens as a
 *  single sheet rather than six downloads. */
export function overviewToCsv(overview: ClinicOverview): string {
  const k = overview.kpis;
  const lines: string[] = [
    `Clinic operations report,${cell(overview.from.slice(0, 10))} to ${cell(overview.to.slice(0, 10))},grouped by ${overview.groupBy}`,
    '',
    ...section('Summary', ['Metric', 'Value'], [
      ['Total patients', k.totalPatients],
      ['New patients in range', k.newPatients],
      ['Patients seen in range', k.activePatients],
      ['Doctors', k.totalDoctors],
      ['Appointments', k.totalAppointments],
      ['Completed', k.completed],
      ['No-shows', k.noShows],
      ['Cancelled', k.cancelled],
      ['Completion rate %', k.completionRate],
      ['No-show rate %', k.noShowRate],
      ['Cancellation rate %', k.cancellationRate],
      [`Revenue realised (${k.currency})`, k.revenueRealised],
      [`Revenue booked (${k.currency})`, k.revenueBooked],
      ['Average wait (min)', k.avgWaitMinutes],
      ['Average visit (min)', k.avgVisitMinutes],
    ]),
    ...section('Trend', ['Period', 'Appointments', 'Completed', 'No-shows', 'Cancelled', 'Revenue'],
      overview.trend.map((t) => [t.label, t.appointments, t.completed, t.noShows, t.cancelled, t.revenue])),
    ...section('By doctor', ['Doctor', 'Specialty', 'Branch', 'Appointments', 'Completed', 'No-shows', 'Revenue', 'Avg wait (min)'],
      overview.byDoctor.map((d) => [d.name, d.specialty, d.branchName, d.appointments, d.completed, d.noShows, d.revenue, d.avgWaitMinutes])),
    ...section('By treatment', ['Treatment', 'Appointments', 'Completed', 'Revenue'],
      overview.byTreatment.map((t) => [t.name, t.appointments, t.completed, t.revenue])),
    ...section('By branch', ['Branch', 'Appointments', 'Patients', 'Revenue', 'Completion rate %'],
      overview.byBranch.map((b) => [b.name, b.appointments, b.patients, b.revenue, b.completionRate])),
    ...section('By insurance provider', ['Provider', 'Patients', 'Appointments', 'Revenue'],
      overview.byInsurance.map((i) => [i.provider, i.patients, i.appointments, i.revenue])),
    ...section('By booking channel', ['Channel', 'Appointments'],
      overview.bySource.map((s) => [s.source, s.appointments])),
    ...section('By hour of day', ['Hour', 'Appointments'],
      overview.byHour.map((h) => [`${String(h.hour).padStart(2, '0')}:00`, h.appointments])),
  ];
  return lines.join('\n');
}

export function downloadCsv(filename: string, csv: string): void {
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export function formatMinutes(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  if (value < 60) return `${Math.round(value)} min`;
  const h = Math.floor(value / 60);
  const m = Math.round(value % 60);
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

export function formatMoney(value: number | null | undefined, currency = 'LKR'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  return `${currency} ${Math.round(value).toLocaleString()}`;
}

export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  return `${value.toFixed(1)}%`;
}
