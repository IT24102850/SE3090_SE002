import { describe, expect, it } from 'vitest';
import type { GymOverview } from '../../booking/types';
import { canSeeFinance, defaultLayout, loadLayout, widgetsFor } from './gymLayout';
import { hourLabel, overviewToCsv } from './gymReport';

describe('role-based layouts', () => {
  it('keeps money away from the front desk', () => {
    expect(canSeeFinance('Admin')).toBe(true);
    expect(canSeeFinance('Manager')).toBe(true);
    expect(canSeeFinance('Staff')).toBe(false);
    const floor = widgetsFor('Staff').map((w) => w.id);
    expect(floor).not.toContain('revenue');
    expect(floor).not.toContain('payments');
    expect(floor).not.toContain('sales');
    expect(floor).toContain('live');
    expect(floor).toContain('attendance');
    expect(floor).toContain('equipment');
  });

  it('opens each role on the panel they work from', () => {
    expect(defaultLayout('Admin').order[0]).toBe('revenue');
    expect(defaultLayout('Manager').order[0]).toBe('live');
    expect(defaultLayout('Staff').order[0]).toBe('live');
  });

  it('drops forbidden widgets from a stored layout', () => {
    const store = new Map<string, string>();
    Object.defineProperty(globalThis, 'localStorage', {
      value: { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => { store.set(k, v); }, removeItem: () => {}, clear: () => {}, key: () => null, length: 0 },
      configurable: true,
    });
    store.set('gym-dashboard-layout:t:u:Staff', JSON.stringify({ order: ['revenue', 'classes'], hidden: ['payments', 'heatmap'] }));
    const layout = loadLayout('t', 'u', 'Staff');
    expect(layout.order[0]).toBe('classes');
    expect(layout.order).not.toContain('revenue');
    expect(layout.hidden).toEqual(['heatmap']);
    expect(layout.order.length).toBe(widgetsFor('Staff').length);
  });
});

describe('hourLabel', () => {
  it('pads and dashes', () => {
    expect(hourLabel(6)).toBe('06:00');
    expect(hourLabel(18)).toBe('18:00');
    expect(hourLabel(null)).toBe('—');
  });
});

describe('overviewToCsv', () => {
  const overview: GymOverview = {
    from: '2026-08-20', to: '2026-09-18', groupBy: 'day', asOf: '2026-09-18T09:00:00Z', tz: 330, filters: {},
    targets: { facilityCapacity: 120, monthlyRevenueTarget: 180000, yearlyRevenueTarget: 2160000, monthTargetToDate: 108000, openHoursPerDay: 15, maintenanceEveryUses: 200 },
    kpis: {
      currency: 'LKR', visits: 630, uniqueVisitors: 24, visitsPerDay: 21, avgVisitMinutes: 61.5, visitSamples: 600, peakHour: 6, peakHourCheckIns: 80,
      totalMembers: 24, activeMembers: 19, frozenMembers: 1, expiredMembers: 3, cancelledMembers: 1, withoutMembership: 1, newMembers: 3, signUps: 9, lapsed: 2, churnRate: 8.3,
      renewalsDue30: 16, renewalsDue7: 3, overduePayments: 3, overdueAmount: 16500, revenue: 146000, membershipRevenue: 128000, dropInRevenue: 18000, revenueMtd: 87500, revenueYtd: 500000,
      monthlyRecurring: 150000, classSessions: 30, classBookings: 400, classFillRate: 79.1, equipmentItems: 7, equipmentUtilisation: 2.1, maintenanceDue: 4, zones: 5, trainers: 5,
    },
    previous: { visits: 600, uniqueVisitors: 22, signUps: 6, revenue: 140000 },
    renewals: [{ subscriptionId: 's1', memberId: 'm1', memberName: 'Ishani Silva', plan: 'Standard', amount: 7500, endDate: '2026-09-23T18:29:00Z', daysLeft: 5, autoRenew: false, paymentStatus: 'Paid' }],
    outstanding: [{ subscriptionId: 's2', memberId: 'm2', memberName: 'Kasun Fernando', plan: 'Basic', amount: 4500, paymentStatus: 'Pending' }],
    payment: [{ status: 'Paid', memberships: 17, amount: 362000 }, { status: 'Pending', memberships: 1, amount: 4500 }],
    statusMix: [], trend: [{ bucket: '2026-09-18T00:00', label: '18 Sep', visits: 26, uniqueMembers: 20, classBookings: 14, signUps: 1, revenue: 3000 }],
    heatmap: [{ dayOfWeek: 0, label: 'Sun', hours: Array(24).fill(0) }], byHour: [{ hour: 6, checkIns: 80 }], byMethod: [{ method: 'RFID', checkIns: 200 }],
    byClass: [{ bookingTypeId: 'c1', name: 'Spin, "evening"', sessions: 8, bookings: 100, attended: 90, capacityPerSession: 14, fillRate: 89.3, avgPerSession: 12.5, noShows: 4, revenue: 0 }],
    byTrainer: [], byZone: [], byEquipment: [], byPlan: [{ plan: 'Standard', members: 6, monthlyValue: 45000, signUpsInRange: 2 }],
    byAge: [{ band: '25-34', members: 9 }], byGender: [{ gender: 'Female', members: 10 }], byBranch: [],
    filterOptions: { branches: [], zones: [], trainers: [], classes: [], bookingTypes: [], plans: [] },
  };

  it('writes one sheet with a section per breakdown and quotes awkward cells', () => {
    const csv = overviewToCsv(overview, true);
    expect(csv.startsWith('Gym operations report,2026-08-20 to 2026-09-18,grouped by day')).toBe(true);
    expect(csv).toContain('Revenue MTD (LKR),87500');
    expect(csv).toContain('Monthly target (LKR),180000');
    expect(csv).toContain('"Spin, ""evening""",8,100,90,14,89.3,4,0');
    expect(csv).toContain('Payment status');
    expect(csv).toContain('Ishani Silva,Standard,2026-09-23,5,false,7500,Paid');
  });

  it('strips money and billing for the front desk', () => {
    const csv = overviewToCsv(overview, false);
    expect(csv).not.toContain('Revenue');
    expect(csv).not.toContain('Payment status');
    expect(csv).not.toContain('Outstanding');
    expect(csv).toContain('Ishani Silva,Standard,2026-09-23,5,false\n');
    expect(csv).toContain('Peak hour,06:00');
  });
});
