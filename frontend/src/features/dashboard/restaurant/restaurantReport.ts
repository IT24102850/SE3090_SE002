import type { RestaurantGroupBy, RestaurantOverview, RestaurantInventory } from '../../booking/types';
import { addDays, startOfMonth, toISODate } from '../../../shared/dateUtils';
import { downloadCsv, formatMinutes, formatMoney, formatPercent } from '../clinic/clinicReport';

/* Reporting helpers for the restaurant dashboard: the date presets the
 * filter bar offers, the "vs previous period" delta, and the CSV export.
 * The formatters and the download are the clinic's - they are not clinic
 * specific and one implementation is enough. */

export { downloadCsv, formatMinutes, formatMoney, formatPercent };

export type RestaurantRangePreset = 'today' | 'yesterday' | '7d' | '30d' | 'month' | 'daily' | 'weekly' | 'monthly' | 'custom';

export interface RestaurantRange {
  from: string;
  to: string;
  groupBy: RestaurantGroupBy;
}

/** The viewer's UTC offset in minutes east, the way the API wants it. */
export function tzOffsetMinutes(now = new Date()): number {
  return -now.getTimezoneOffset();
}

/** A single day groups by hour - the shift-by-shift view - and everything
 *  longer by day; the three report presets match the exportable daily /
 *  weekly / monthly operational reports. */
export function presetRange(preset: RestaurantRangePreset, today = new Date()): RestaurantRange {
  const to = toISODate(today);
  switch (preset) {
    case 'today':
      return { from: to, to, groupBy: 'hour' };
    case 'yesterday': {
      const y = toISODate(addDays(today, -1));
      return { from: y, to: y, groupBy: 'hour' };
    }
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

/** Percentage change from `previous` to `current`, null when there is no
 *  base to compare against (a brand-new restaurant has no last month). */
export function deltaPercent(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous) || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

export function formatDelta(delta: number | null): string {
  if (delta === null) return 'no previous period';
  const sign = delta > 0 ? '+' : '';
  return `${sign}${delta.toFixed(1)}% vs previous period`;
}

export function formatCount(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return '—';
  return value.toLocaleString();
}

function cell(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function section(title: string, header: string[], rows: unknown[][]): string[] {
  return [title, header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(',')), ''];
}

/** One CSV with a section per breakdown. `finance` false strips every
 *  money column, so a chef's export matches what a chef's screen shows. */
export function overviewToCsv(overview: RestaurantOverview, finance = true, inventory?: RestaurantInventory): string {
  const k = overview.kpis;
  const money = (rows: unknown[][]) => rows;
  const summary: unknown[][] = [
    ['Orders', k.orders],
    ['Completed', k.completed],
    ['Cancelled', k.cancelled],
    ['No-shows', k.noShows],
    ['Completion rate %', k.completionRate],
    ['Cancellation rate %', k.cancellationRate],
    ['Covers', k.covers],
    ['Average prep time (min)', k.avgPrepMinutes],
    ['Average ticket time (min)', k.avgTicketMinutes],
    ['On-time rate %', k.onTimeRate],
    ['Delayed tickets', k.delayed],
    ['Tables', k.tables],
    ['Table turnover (per table per day)', k.tableTurnover],
    ['Staff rostered', k.staffRostered],
    ['Rostered hours', k.laborHours],
    ['Waste units', k.wasteUnits],
    ['Low-stock items', k.lowStockItems],
  ];
  if (finance) {
    summary.push(
      [`Revenue (${k.currency})`, k.revenue],
      [`Revenue booked, not yet completed (${k.currency})`, k.revenueBooked],
      [`Average order value (${k.currency})`, k.averageOrderValue],
      [`Revenue per cover (${k.currency})`, k.revenuePerCover],
      [`Labor cost (${k.currency})`, k.laborCost],
      ['Labor % of sales', k.laborPercent],
      [`Waste cost (${k.currency})`, k.wasteCost],
      ['Waste % of sales', k.wastePercent],
      [`Previous period revenue (${k.currency})`, overview.previous.revenue],
      ['Previous period orders', overview.previous.orders],
    );
  }

  const lines: string[] = [
    `Restaurant operations report,${cell(overview.from.slice(0, 10))} to ${cell(overview.to.slice(0, 10))},grouped by ${overview.groupBy}`,
    '',
    ...section('Summary', ['Metric', 'Value'], summary),
    ...section('Trend', finance ? ['Period', 'Orders', 'Completed', 'Cancelled', 'Covers', 'Dine-in', 'Off-premise', 'Revenue'] : ['Period', 'Orders', 'Completed', 'Cancelled', 'Covers', 'Dine-in', 'Off-premise'],
      overview.trend.map((t) => finance ? [t.label, t.orders, t.completed, t.cancelled, t.covers, t.dineIn, t.offPremise, t.revenue] : [t.label, t.orders, t.completed, t.cancelled, t.covers, t.dineIn, t.offPremise])),
    ...section('By hour of day', finance ? ['Hour', 'Orders', 'Revenue'] : ['Hour', 'Orders'],
      overview.byHour.map((h) => finance ? [`${String(h.hour).padStart(2, '0')}:00`, h.orders, h.revenue] : [`${String(h.hour).padStart(2, '0')}:00`, h.orders])),
    ...section('By shift', finance ? ['Shift', 'Hours', 'Orders', 'Completed', 'Covers', 'Revenue'] : ['Shift', 'Hours', 'Orders', 'Completed', 'Covers'],
      overview.byShift.map((s) => finance ? [s.label, s.hours, s.orders, s.completed, s.covers, s.revenue] : [s.label, s.hours, s.orders, s.completed, s.covers])),
    ...section('By channel', finance ? ['Channel', 'Orders', 'Completed', 'Cancelled', 'Covers', 'Revenue'] : ['Channel', 'Orders', 'Completed', 'Cancelled', 'Covers'],
      overview.byChannel.map((c) => finance ? [c.channel, c.orders, c.completed, c.cancelled, c.covers, c.revenue] : [c.channel, c.orders, c.completed, c.cancelled, c.covers])),
    ...section('By service mode', finance ? ['Mode', 'Orders', 'Completed', 'Covers', 'Avg prep (min)', 'Revenue'] : ['Mode', 'Orders', 'Completed', 'Covers', 'Avg prep (min)'],
      overview.byServiceMode.map((m) => finance ? [m.mode, m.orders, m.completed, m.covers, m.avgPrepMinutes, m.revenue] : [m.mode, m.orders, m.completed, m.covers, m.avgPrepMinutes])),
    ...section('By menu type', finance ? ['Menu type', 'Service mode', 'Orders', 'Completed', 'Avg prep (min)', 'Target (min)', 'On-time %', 'Revenue'] : ['Menu type', 'Service mode', 'Orders', 'Completed', 'Avg prep (min)', 'Target (min)', 'On-time %'],
      overview.byMenu.map((m) => finance ? [m.name, m.serviceMode, m.orders, m.completed, m.avgPrepMinutes, m.prepTargetMinutes, m.onTimeRate, m.revenue] : [m.name, m.serviceMode, m.orders, m.completed, m.avgPrepMinutes, m.prepTargetMinutes, m.onTimeRate])),
    ...section('By station / table', finance ? ['Name', 'Kind', 'Branch', 'Orders', 'Completed', 'Cancelled', 'Covers', 'Avg prep (min)', 'Delayed', 'Revenue'] : ['Name', 'Kind', 'Branch', 'Orders', 'Completed', 'Cancelled', 'Covers', 'Avg prep (min)', 'Delayed'],
      overview.byStation.map((s) => finance ? [s.name, s.kind, s.branchName, s.orders, s.completed, s.cancelled, s.covers, s.avgPrepMinutes, s.delayed, s.revenue] : [s.name, s.kind, s.branchName, s.orders, s.completed, s.cancelled, s.covers, s.avgPrepMinutes, s.delayed])),
  ];
  if (finance) {
    lines.push(
      ...section('By branch', ['Branch', 'Orders', 'Completed', 'Covers', 'Revenue'],
        money(overview.byBranch.map((b) => [b.name, b.orders, b.completed, b.covers, b.revenue]))),
      ...section('Waste by item', ['Item', 'Units', 'Cost'],
        overview.waste.byItem.map((w) => [w.name, w.units, w.cost])),
      ...section('Waste by reason', ['Reason', 'Entries', 'Units', 'Cost'],
        overview.waste.byReason.map((w) => [w.reason, w.entries, w.units, w.cost])),
    );
  }
  if (inventory) {
    lines.push(
      ...section('Stock levels', finance ? ['Item', 'SKU', 'Category', 'On hand', 'Reorder level', 'Status', 'Wasted in range', 'Consumed in range', 'Unit cost'] : ['Item', 'SKU', 'Category', 'On hand', 'Reorder level', 'Status', 'Wasted in range', 'Consumed in range'],
        inventory.items.map((i) => finance
          ? [i.name, i.sku, i.category, i.quantity, i.reorderLevel, i.status, i.wastedInRange, i.consumedInRange, i.unitCost]
          : [i.name, i.sku, i.category, i.quantity, i.reorderLevel, i.status, i.wastedInRange, i.consumedInRange])),
    );
  }
  return lines.join('\n');
}
