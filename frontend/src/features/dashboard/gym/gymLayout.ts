/* The gym dashboard's widget registry and per-user layout - the same
 * arrangement as the restaurant's: each widget names the roles that may
 * see it and whether it shows money, the default order differs per role,
 * and the stored layout is keyed by role as well as user.
 *
 *   Admin   (owner)      - everything, opens on revenue and members
 *   Manager (ops)        - everything, opens on the live floor
 *   Staff   (front desk / trainer) - the floor, the log, classes and
 *                          equipment; never a revenue or billing panel */

export type GymRole = 'Admin' | 'Manager' | 'Staff' | 'Customer';

export type GymWidgetId =
  | 'live'
  | 'heatmap'
  | 'attendance'
  | 'members'
  | 'demographics'
  | 'revenue'
  | 'payments'
  | 'sales'
  | 'classes'
  | 'trainers'
  | 'zones'
  | 'equipment'
  | 'methods'
  | 'branches';

export interface GymWidgetMeta {
  id: GymWidgetId;
  label: string;
  hint: string;
  wide?: boolean;
  roles: GymRole[];
  finance?: boolean;
}

const ALL: GymRole[] = ['Admin', 'Manager', 'Staff'];
const OWNERS: GymRole[] = ['Admin', 'Manager'];

export const GYM_WIDGETS: GymWidgetMeta[] = [
  { id: 'live', label: 'Live check-in monitor', hint: 'Who is inside now, entries and exits, occupancy against capacity', wide: true, roles: ALL },
  { id: 'heatmap', label: 'Peak hours heatmap', hint: 'Check-ins by hour and day of the week', roles: ALL },
  { id: 'members', label: 'Membership overview', hint: 'Active, frozen, expired; renewals coming up', roles: ALL },
  { id: 'attendance', label: 'Attendance log', hint: 'Searchable check-in records with method and duration', wide: true, roles: ALL },
  { id: 'revenue', label: 'Revenue vs target', hint: 'Month- and year-to-date against targets, with the trend', wide: true, roles: OWNERS, finance: true },
  { id: 'payments', label: 'Payment status', hint: 'Paid, pending, failed and overdue billings', roles: OWNERS, finance: true },
  { id: 'sales', label: 'Sales & plans', hint: 'Popular plans, sign-ups and drop-in revenue', roles: OWNERS, finance: true },
  { id: 'demographics', label: 'Demographics', hint: 'Active members by age band, gender and tier', roles: ALL },
  { id: 'classes', label: 'Class attendance', hint: 'Sessions, bookings and fill rate per class', wide: true, roles: ALL },
  { id: 'trainers', label: 'Trainer load', hint: 'Sessions and bookings per trainer', roles: ALL },
  { id: 'zones', label: 'Zone utilisation', hint: 'Booked hours against opening hours per training zone', roles: ALL },
  { id: 'equipment', label: 'Equipment & maintenance', hint: 'Usage per machine and what is due for service', wide: true, roles: ALL },
  { id: 'methods', label: 'Check-in methods', hint: 'RFID, app, biometric, front desk', roles: ALL },
  { id: 'branches', label: 'Branch comparison', hint: 'Visits and members per branch', roles: OWNERS, finance: true },
];

export interface GymLayout {
  order: GymWidgetId[];
  hidden: GymWidgetId[];
}

export function canSeeFinance(role: GymRole | undefined): boolean {
  return role === 'Admin' || role === 'Manager';
}

export function widgetsFor(role: GymRole | undefined): GymWidgetMeta[] {
  return GYM_WIDGETS.filter((w) => role !== undefined && w.roles.includes(role));
}

const ROLE_ORDER: Record<GymRole, GymWidgetId[]> = {
  Admin: ['revenue', 'members', 'live', 'payments', 'sales', 'heatmap', 'demographics', 'classes', 'attendance', 'equipment', 'trainers', 'zones', 'methods', 'branches'],
  Manager: ['live', 'members', 'heatmap', 'classes', 'attendance', 'equipment', 'revenue', 'payments', 'sales', 'trainers', 'zones', 'demographics', 'methods', 'branches'],
  Staff: ['live', 'attendance', 'classes', 'members', 'heatmap', 'equipment', 'trainers', 'zones', 'demographics', 'methods'],
  Customer: [],
};

export function defaultLayout(role: GymRole | undefined): GymLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (role ? ROLE_ORDER[role] : []).filter((id) => allowed.has(id));
  for (const w of widgetsFor(role)) if (!order.includes(w.id)) order.push(w.id);
  return { order, hidden: [] };
}

const KEY = (tenantId: string, userId: string, role: string) => `gym-dashboard-layout:${tenantId}:${userId}:${role}`;

function normalise(raw: Partial<GymLayout> | null | undefined, role: GymRole | undefined): GymLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (raw?.order ?? []).filter((id): id is GymWidgetId => allowed.has(id as GymWidgetId));
  for (const id of defaultLayout(role).order) if (!order.includes(id)) order.push(id);
  const hidden = (raw?.hidden ?? []).filter((id): id is GymWidgetId => allowed.has(id as GymWidgetId));
  return { order, hidden };
}

export function loadLayout(tenantId: string, userId: string, role: GymRole | undefined): GymLayout {
  try {
    const stored = localStorage.getItem(KEY(tenantId, userId, role ?? 'none'));
    return stored ? normalise(JSON.parse(stored), role) : defaultLayout(role);
  } catch {
    return defaultLayout(role);
  }
}

export function saveLayout(tenantId: string, userId: string, role: GymRole | undefined, layout: GymLayout): void {
  try {
    localStorage.setItem(KEY(tenantId, userId, role ?? 'none'), JSON.stringify(layout));
  } catch {
    // Private mode or a full store: the layout just does not persist.
  }
}

export function moveWidget(layout: GymLayout, id: GymWidgetId, direction: -1 | 1): GymLayout {
  const index = layout.order.indexOf(id);
  const target = index + direction;
  if (index < 0 || target < 0 || target >= layout.order.length) return layout;
  const order = [...layout.order];
  [order[index], order[target]] = [order[target], order[index]];
  return { ...layout, order };
}

export function toggleWidget(layout: GymLayout, id: GymWidgetId): GymLayout {
  const hidden = layout.hidden.includes(id) ? layout.hidden.filter((h) => h !== id) : [...layout.hidden, id];
  return { ...layout, hidden };
}
