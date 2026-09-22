import type { GymOverview } from '../../booking/types';
import {
  deltaPercent,
  downloadCsv,
  formatCount,
  formatDelta,
  formatMinutes,
  formatMoney,
  formatPercent,
  presetRange,
  tzOffsetMinutes,
  type RestaurantRange as GymRange,
  type RestaurantRangePreset as GymRangePreset,
} from '../restaurant/restaurantReport';

/* Reporting helpers for the gym dashboard. The presets, deltas and
 * formatters are the restaurant's - none of them is restaurant-specific -
 * so only the CSV shape lives here. */

export { deltaPercent, downloadCsv, formatCount, formatDelta, formatMinutes, formatMoney, formatPercent, presetRange, tzOffsetMinutes };
export type { GymRange, GymRangePreset };

export function hourLabel(hour: number | null | undefined): string {
  if (hour === null || hour === undefined) return '—';
  return `${String(hour).padStart(2, '0')}:00`;
}

function cell(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function section(title: string, header: string[], rows: unknown[][]): string[] {
  return [title, header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(',')), ''];
}

/** One CSV with a section per breakdown; `finance` false strips every
 *  money column and the billing sections. */
export function overviewToCsv(overview: GymOverview, finance = true): string {
  const k = overview.kpis;
  const summary: unknown[][] = [
    ['Visits', k.visits],
    ['Unique visitors', k.uniqueVisitors],
    ['Visits per day', k.visitsPerDay],
    ['Average visit (min)', k.avgVisitMinutes],
    ['Peak hour', hourLabel(k.peakHour)],
    ['Members (total)', k.totalMembers],
    ['Active memberships', k.activeMembers],
    ['Frozen', k.frozenMembers],
    ['Expired', k.expiredMembers],
    ['Cancelled', k.cancelledMembers],
    ['Without a membership', k.withoutMembership],
    ['New members in range', k.newMembers],
    ['Sign-ups in range', k.signUps],
    ['Lapsed in range', k.lapsed],
    ['Churn rate %', k.churnRate],
    ['Renewals due (30 days)', k.renewalsDue30],
    ['Class sessions', k.classSessions],
    ['Class bookings', k.classBookings],
    ['Class fill rate %', k.classFillRate],
    ['Equipment items', k.equipmentItems],
    ['Equipment utilisation %', k.equipmentUtilisation],
    ['Maintenance due', k.maintenanceDue],
  ];
  if (finance) {
    summary.push(
      [`Revenue in range (${k.currency})`, k.revenue],
      [`Membership revenue (${k.currency})`, k.membershipRevenue],
      [`Drop-in / PT revenue (${k.currency})`, k.dropInRevenue],
      [`Revenue MTD (${k.currency})`, k.revenueMtd],
      [`Revenue YTD (${k.currency})`, k.revenueYtd],
      [`Monthly target (${k.currency})`, overview.targets.monthlyRevenueTarget],
      [`Yearly target (${k.currency})`, overview.targets.yearlyRevenueTarget],
      [`Monthly recurring (${k.currency})`, k.monthlyRecurring],
      ['Overdue billings', k.overduePayments],
      [`Outstanding (${k.currency})`, k.overdueAmount],
    );
  }

  const lines: string[] = [
    `Gym operations report,${cell(overview.from.slice(0, 10))} to ${cell(overview.to.slice(0, 10))},grouped by ${overview.groupBy}`,
    '',
    ...section('Summary', ['Metric', 'Value'], summary),
    ...section('Trend', finance ? ['Period', 'Visits', 'Unique members', 'Class bookings', 'Sign-ups', 'Revenue'] : ['Period', 'Visits', 'Unique members', 'Class bookings', 'Sign-ups'],
      overview.trend.map((t) => finance ? [t.label, t.visits, t.uniqueMembers, t.classBookings, t.signUps, t.revenue] : [t.label, t.visits, t.uniqueMembers, t.classBookings, t.signUps])),
    ...section('Check-ins by hour', ['Hour', 'Check-ins'], overview.byHour.map((h) => [hourLabel(h.hour), h.checkIns])),
    ...section('Heatmap (check-ins by day and hour)', ['Day', ...Array.from({ length: 24 }, (_, h) => hourLabel(h))],
      overview.heatmap.map((d) => [d.label, ...d.hours])),
    ...section('Check-in methods', ['Method', 'Check-ins'], overview.byMethod.map((m) => [m.method, m.checkIns])),
    ...section('Classes', finance ? ['Class', 'Sessions', 'Bookings', 'Attended', 'Capacity per session', 'Fill rate %', 'No-shows', 'Revenue'] : ['Class', 'Sessions', 'Bookings', 'Attended', 'Capacity per session', 'Fill rate %', 'No-shows'],
      overview.byClass.map((c) => finance ? [c.name, c.sessions, c.bookings, c.attended, c.capacityPerSession, c.fillRate, c.noShows, c.revenue] : [c.name, c.sessions, c.bookings, c.attended, c.capacityPerSession, c.fillRate, c.noShows])),
    ...section('Trainers', finance ? ['Trainer', 'Specialty', 'Sessions', 'Bookings', 'Completed', 'Revenue'] : ['Trainer', 'Specialty', 'Sessions', 'Bookings', 'Completed'],
      overview.byTrainer.map((t) => finance ? [t.name, t.specialty, t.sessions, t.bookings, t.completed, t.revenue] : [t.name, t.specialty, t.sessions, t.bookings, t.completed])),
    ...section('Zones', ['Zone', 'Capacity', 'Visits', 'Hours booked', 'Utilisation %'], overview.byZone.map((z) => [z.name, z.capacity, z.visits, z.hoursBooked, z.utilisationPercent])),
    ...section('Equipment', ['Machine', 'Category', 'Units', 'Uses', 'Hours used', 'Utilisation %', 'Last serviced', 'Next due', 'Uses since service', 'Maintenance'],
      overview.byEquipment.map((e) => [e.name, e.category, e.units, e.uses, e.hoursUsed, e.utilisationPercent, e.lastServicedAt?.slice(0, 10), e.nextDueAt?.slice(0, 10), e.usesSinceService, e.maintenanceStatus])),
    ...section('Members by age', ['Age band', 'Members'], overview.byAge.map((a) => [a.band, a.members])),
    ...section('Members by gender', ['Gender', 'Members'], overview.byGender.map((g) => [g.gender, g.members])),
    ...section('Members by plan', finance ? ['Plan', 'Active members', 'Monthly value', 'Sign-ups in range'] : ['Plan', 'Active members', 'Sign-ups in range'],
      overview.byPlan.map((p) => finance ? [p.plan, p.members, p.monthlyValue, p.signUpsInRange] : [p.plan, p.members, p.signUpsInRange])),
    ...section('Renewals due', finance ? ['Member', 'Plan', 'Ends', 'Days left', 'Auto-renew', 'Amount', 'Payment'] : ['Member', 'Plan', 'Ends', 'Days left', 'Auto-renew'],
      overview.renewals.map((r) => finance ? [r.memberName, r.plan, r.endDate.slice(0, 10), r.daysLeft, r.autoRenew, r.amount, r.paymentStatus] : [r.memberName, r.plan, r.endDate.slice(0, 10), r.daysLeft, r.autoRenew])),
  ];
  if (finance) {
    lines.push(
      ...section('Payment status', ['Status', 'Memberships', 'Amount'], overview.payment.map((p) => [p.status, p.memberships, p.amount])),
      ...section('Outstanding billings', ['Member', 'Plan', 'Amount', 'Status', 'Next billing', 'Last payment'],
        overview.outstanding.map((o) => [o.memberName, o.plan, o.amount, o.paymentStatus, o.nextBillingAt?.slice(0, 10), o.lastPaymentAt?.slice(0, 10)])),
      ...section('By branch', ['Branch', 'Visits', 'Members'], overview.byBranch.map((b) => [b.name, b.visits, b.members])),
    );
  }
  return lines.join('\n');
}
