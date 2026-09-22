import { describe, expect, it } from 'vitest';
import type { ClinicOverview } from '../../booking/types';
import { DEFAULT_LAYOUT, loadLayout, moveWidget, saveLayout, toggleWidget } from './clinicLayout';
import { formatMinutes, overviewToCsv, presetRange } from './clinicReport';

describe('presetRange', () => {
  const today = new Date(2026, 8, 18); // 18 Sep 2026

  it('maps the report presets onto the grouping the export uses', () => {
    expect(presetRange('daily', today)).toEqual({ from: '2026-09-05', to: '2026-09-18', groupBy: 'day' });
    expect(presetRange('weekly', today)).toEqual({ from: '2026-06-27', to: '2026-09-18', groupBy: 'week' });
    expect(presetRange('monthly', today)).toEqual({ from: '2025-10-01', to: '2026-09-18', groupBy: 'month' });
  });

  it('keeps the operational presets on a daily grouping', () => {
    expect(presetRange('today', today)).toEqual({ from: '2026-09-18', to: '2026-09-18', groupBy: 'day' });
    expect(presetRange('month', today).from).toBe('2026-09-01');
    expect(presetRange('7d', today).from).toBe('2026-09-12');
  });
});

describe('formatMinutes', () => {
  it('renders a dash for a metric with nothing to measure', () => {
    expect(formatMinutes(null)).toBe('—');
    expect(formatMinutes(undefined)).toBe('—');
  });
  it('rolls minutes into hours past sixty', () => {
    expect(formatMinutes(12.4)).toBe('12 min');
    expect(formatMinutes(60)).toBe('1 h');
    expect(formatMinutes(95)).toBe('1 h 35 min');
  });
});

describe('overviewToCsv', () => {
  const overview: ClinicOverview = {
    from: '2026-09-01T00:00:00Z',
    to: '2026-09-18T00:00:00Z',
    groupBy: 'day',
    asOf: '2026-09-18T09:00:00Z',
    filters: {},
    kpis: {
      totalPatients: 120, newPatients: 4, activePatients: 60, totalDoctors: 5, doctorsOnDutyToday: 3, rooms: 2,
      totalAppointments: 80, completed: 60, noShows: 5, cancelled: 3, pending: 2, confirmed: 10,
      completionRate: 88.2, noShowRate: 7.4, cancellationRate: 4.4, revenueRealised: 240000, revenueBooked: 300000,
      currency: 'LKR', avgWaitMinutes: null, avgVisitMinutes: 32, waitSamples: 0, appointmentsToday: 9, patientsToday: 9, patientsPerDoctorToday: 3,
    },
    statusMix: [],
    trend: [{ bucket: '2026-09-01', label: '01 Sep', appointments: 4, completed: 3, noShows: 1, cancelled: 0, revenue: 12000 }],
    byDoctor: [{ resourceId: 'r1', name: 'Dr. Perera, "Ravi"', specialty: 'GP', branchName: null, appointments: 40, completed: 30, noShows: 2, revenue: 120000, avgWaitMinutes: 11.5 }],
    byTreatment: [],
    byBranch: [],
    byInsurance: [{ provider: 'Uninsured / self-pay', patients: 70, appointments: 50, revenue: 150000 }],
    bySource: [],
    byHour: [],
    filterOptions: { branches: [], doctors: [], treatments: [], insuranceProviders: [] },
  };

  it('writes one section per breakdown and escapes quoted names', () => {
    const csv = overviewToCsv(overview);
    expect(csv).toContain('Summary\nMetric,Value\nTotal patients,120');
    expect(csv).toContain('Trend\nPeriod,Appointments,Completed,No-shows,Cancelled,Revenue\n01 Sep,4,3,1,0,12000');
    expect(csv).toContain('"Dr. Perera, ""Ravi""",GP,,40,30,2,120000,11.5');
    expect(csv).toContain('Uninsured / self-pay,70,50,150000');
  });

  it('leaves an unmeasured metric blank rather than writing 0', () => {
    const line = overviewToCsv(overview).split('\n').find((l) => l.startsWith('Average wait (min)'));
    expect(line).toBe('Average wait (min),');
  });
});

describe('clinic layout', () => {
  it('reorders and hides widgets without losing any', () => {
    const moved = moveWidget(DEFAULT_LAYOUT, 'trend', -1);
    expect(moved.order.slice(0, 2)).toEqual(['trend', 'flow']);
    expect(moveWidget(DEFAULT_LAYOUT, 'flow', -1)).toBe(DEFAULT_LAYOUT);

    const hidden = toggleWidget(DEFAULT_LAYOUT, 'hours');
    expect(hidden.hidden).toEqual(['hours']);
    expect(toggleWidget(hidden, 'hours').hidden).toEqual([]);
  });

  it('round-trips through storage and repairs a stale layout', () => {
    saveLayout('t1', 'u1', { order: ['reminders', 'flow', 'retired-widget' as never], hidden: ['bogus' as never, 'hours'] });
    const loaded = loadLayout('t1', 'u1');
    expect(loaded.order.slice(0, 2)).toEqual(['reminders', 'flow']);
    expect(loaded.order).toHaveLength(DEFAULT_LAYOUT.order.length);
    expect(loaded.hidden).toEqual(['hours']);
    expect(loadLayout('t1', 'someone-else')).toEqual(DEFAULT_LAYOUT);
  });
});
