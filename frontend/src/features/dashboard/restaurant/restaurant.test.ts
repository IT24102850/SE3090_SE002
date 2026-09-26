import { describe, expect, it } from 'vitest';
import type { RestaurantOverview } from '../../booking/types';
import { canSeeFinance, defaultLayout, loadLayout, moveWidget, saveLayout, toggleWidget, widgetsFor } from './restaurantLayout';
import { deltaPercent, formatDelta, overviewToCsv, presetRange } from './restaurantReport';

describe('presetRange', () => {
  const today = new Date(2026, 8, 18); // 18 Sep 2026

  it('groups a single day by hour so the shift view is hour-by-hour', () => {
    expect(presetRange('today', today)).toEqual({ from: '2026-09-18', to: '2026-09-18', groupBy: 'hour' });
    expect(presetRange('yesterday', today)).toEqual({ from: '2026-09-17', to: '2026-09-17', groupBy: 'hour' });
  });

  it('maps the report presets onto the grouping the export uses', () => {
    expect(presetRange('daily', today)).toEqual({ from: '2026-09-05', to: '2026-09-18', groupBy: 'day' });
    expect(presetRange('weekly', today)).toEqual({ from: '2026-06-27', to: '2026-09-18', groupBy: 'week' });
    expect(presetRange('monthly', today)).toEqual({ from: '2025-10-01', to: '2026-09-18', groupBy: 'month' });
    expect(presetRange('month', today).from).toBe('2026-09-01');
    expect(presetRange('7d', today).from).toBe('2026-09-12');
  });
});

describe('deltaPercent', () => {
  it('is null when there is no previous period to compare against', () => {
    expect(deltaPercent(120, 0)).toBeNull();
    expect(formatDelta(null)).toBe('no previous period');
  });
  it('reports the change to one decimal with its sign', () => {
    expect(deltaPercent(103, 100)).toBe(3);
    expect(deltaPercent(88, 100)).toBe(-12);
    expect(deltaPercent(1, 3)).toBe(-66.7);
    expect(formatDelta(3)).toBe('+3.0% vs previous period');
    expect(formatDelta(-12)).toBe('-12.0% vs previous period');
  });
});

describe('role-based layouts', () => {
  it('shows money only to owners and floor managers', () => {
    expect(canSeeFinance('Admin')).toBe(true);
    expect(canSeeFinance('Manager')).toBe(true);
    expect(canSeeFinance('Staff')).toBe(false);
    expect(canSeeFinance(undefined)).toBe(false);
  });

  it('never offers a chef a financial panel', () => {
    const chef = widgetsFor('Staff');
    expect(chef.some((w) => w.finance)).toBe(false);
    expect(chef.map((w) => w.id)).not.toContain('sales');
    expect(chef.map((w) => w.id)).not.toContain('staff');
    expect(chef.map((w) => w.id)).toContain('kitchen');
    expect(chef.map((w) => w.id)).toContain('inventory');
  });

  it('opens each role on the panel they work from', () => {
    expect(defaultLayout('Admin').order[0]).toBe('sales');
    expect(defaultLayout('Manager').order[0]).toBe('feed');
    expect(defaultLayout('Staff').order[0]).toBe('kitchen');
    expect(defaultLayout('Customer').order).toEqual([]);
  });

  it('includes every allowed widget exactly once in a default layout', () => {
    for (const role of ['Admin', 'Manager', 'Staff'] as const) {
      const order = defaultLayout(role).order;
      expect(new Set(order).size).toBe(order.length);
      expect(order.sort()).toEqual(widgetsFor(role).map((w) => w.id).sort());
    }
  });
});

describe('layout persistence', () => {
  const store = new Map<string, string>();
  const localStorageMock = {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => { store.set(k, v); },
    removeItem: (k: string) => { store.delete(k); },
    clear: () => store.clear(),
    key: () => null,
    length: 0,
  };
  Object.defineProperty(globalThis, 'localStorage', { value: localStorageMock, configurable: true });

  it('round-trips and is keyed by role so a promotion starts fresh', () => {
    const base = defaultLayout('Manager');
    const moved = moveWidget(base, 'stations', -1);
    expect(moved.order[0]).toBe('stations');
    const hidden = toggleWidget(moved, 'status');
    saveLayout('t1', 'u1', 'Manager', hidden);
    expect(loadLayout('t1', 'u1', 'Manager')).toEqual(hidden);
    expect(loadLayout('t1', 'u1', 'Admin')).toEqual(defaultLayout('Admin'));
  });

  it('drops widgets the role may not see and appends new ones', () => {
    store.set('restaurant-dashboard-layout:t1:u2:Staff', JSON.stringify({ order: ['sales', 'feed', 'bogus'], hidden: ['staff', 'menu'] }));
    const layout = loadLayout('t1', 'u2', 'Staff');
    expect(layout.order[0]).toBe('feed');
    expect(layout.order).not.toContain('sales');
    expect(layout.order).not.toContain('bogus');
    expect(layout.hidden).toEqual(['menu']);
    expect(layout.order.length).toBe(widgetsFor('Staff').length);
  });

  it('leaves the order alone when a move would run off either end', () => {
    const base = defaultLayout('Admin');
    expect(moveWidget(base, base.order[0], -1)).toBe(base);
    expect(moveWidget(base, base.order[base.order.length - 1], 1)).toBe(base);
  });
});

describe('overviewToCsv', () => {
  const overview: RestaurantOverview = {
    from: '2026-09-11T00:00:00',
    to: '2026-09-18T00:00:00',
    groupBy: 'day',
    asOf: '2026-09-18T09:00:00Z',
    tz: 330,
    filters: {},
    kpis: {
      currency: 'LKR', orders: 40, completed: 32, cancelled: 3, noShows: 1, pending: 2, open: 2,
      completionRate: 88.9, cancellationRate: 8.3, revenue: 160000, revenueBooked: 12000, averageOrderValue: 5000,
      covers: 96, revenuePerCover: 1666.67, revenuePerDay: 20000, ordersPerDay: 5, avgPrepMinutes: 14.2, avgTicketMinutes: 41,
      prepSamples: 30, onTimeRate: 90, delayed: 3, prepTargetMinutes: 20, tables: 8, tableTurnover: 0.5,
      staffRostered: 4, staffHeadcount: 5, laborHours: 160, laborCost: 48000, laborPercent: 30, laborRated: 4,
      wasteUnits: 12, wasteCost: 2400, wastePercent: 1.5, wasteEntries: 3, consumptionMovements: 20, consumptionCost: 15000,
      lowStockItems: 2, ordersToday: 6, revenueToday: 21000, coversToday: 14,
    },
    previous: { from: '2026-09-04', to: '2026-09-10', orders: 36, completed: 30, cancelled: 2, revenue: 150000, covers: 90, averageOrderValue: 5000 },
    statusMix: [{ status: 'Completed', count: 32 }],
    trend: [{ bucket: '2026-09-11T00:00', label: '11 Sep', orders: 5, completed: 4, cancelled: 0, revenue: 20000, covers: 12, dineIn: 3, offPremise: 2 }],
    byHour: [{ hour: 12, orders: 10, revenue: 50000 }],
    byShift: [{ shift: 'lunch', label: 'Lunch', hours: '11:00–16:00', orders: 20, completed: 18, revenue: 90000, covers: 50 }],
    byChannel: [{ channel: 'POS', orders: 25, completed: 22, cancelled: 1, revenue: 110000, covers: 70 }],
    byServiceMode: [{ mode: 'Dine-in', orders: 30, completed: 26, revenue: 130000, covers: 90, avgPrepMinutes: 15 }],
    byMenu: [{ bookingTypeId: 'm1', name: 'Dinner, "family" table', serviceMode: 'Dine-in', orders: 12, completed: 10, revenue: 60000, avgPrepMinutes: 18, prepTargetMinutes: 20, onTimeRate: 80 }],
    byStation: [{ resourceId: 'r1', name: 'Garden Terrace', kind: 'table', branchName: 'Main', orders: 12, completed: 10, cancelled: 1, revenue: 60000, covers: 40, avgPrepMinutes: 16, delayed: 1 }],
    byBranch: [{ branchId: 'b1', name: 'Main', orders: 40, completed: 32, revenue: 160000, covers: 96 }],
    waste: { byItem: [{ inventoryItemId: 'i1', name: 'Prawns', units: 2, cost: 5600 }], byReason: [{ reason: 'Spoiled', entries: 1, units: 2, cost: 5600 }] },
    filterOptions: { branches: [], stations: [], menu: [], channels: [], serviceModes: [], shifts: [] },
  };

  it('writes one sheet with a section per breakdown and quotes awkward cells', () => {
    const csv = overviewToCsv(overview, true);
    expect(csv.startsWith('Restaurant operations report,2026-09-11 to 2026-09-18,grouped by day')).toBe(true);
    expect(csv).toContain('Revenue (LKR),160000');
    expect(csv).toContain('Labor % of sales,30');
    expect(csv).toContain('By menu type');
    expect(csv).toContain('"Dinner, ""family"" table",Dine-in,12,10,18,20,80,60000');
    expect(csv).toContain('Waste by reason');
    expect(csv).toContain('Spoiled,1,2,5600');
  });

  it('strips every money column for a chef', () => {
    const csv = overviewToCsv(overview, false);
    expect(csv).not.toContain('Revenue');
    expect(csv).not.toContain('Labor cost');
    expect(csv).not.toContain('Waste by item');
    expect(csv).toContain('Average prep time (min),14.2');
    expect(csv).toContain('Garden Terrace,table,Main,12,10,1,40,16,1\n');
  });
});
