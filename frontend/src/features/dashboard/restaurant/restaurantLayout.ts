/* The restaurant dashboard's widget registry and the per-user layout.
 *
 * Every panel is one of these ids. Two things differ from the clinic
 * registry:
 *
 *   - Role-based views. Each widget says which roles may see it and
 *     whether it is financial. An owner (Admin) gets the money; a floor
 *     manager (Manager) gets the service - orders, tables, staff - plus
 *     the day's sales; a head chef (Staff) gets the kitchen and the stock,
 *     and never a revenue figure. The default order also differs per role
 *     so each opens on the panel they actually work from.
 *   - The stored layout is keyed by role as well as user, so a manager
 *     promoted to admin starts from the owner default rather than a
 *     layout that never had the finance panels in it. */

export type RestaurantRole = 'Admin' | 'Manager' | 'Staff' | 'Customer';

export type RestaurantWidgetId =
  | 'feed'
  | 'kitchen'
  | 'sales'
  | 'flow'
  | 'hours'
  | 'channels'
  | 'menu'
  | 'stations'
  | 'shifts'
  | 'staff'
  | 'inventory'
  | 'waste'
  | 'status'
  | 'branches'
  | 'upcoming';

export interface RestaurantWidgetMeta {
  id: RestaurantWidgetId;
  label: string;
  hint: string;
  /** Wide widgets take the full row; the rest sit two-up. */
  wide?: boolean;
  /** Roles that may see the panel at all. */
  roles: RestaurantRole[];
  /** Shows money - hidden from anyone without the finance view. */
  finance?: boolean;
}

const ALL: RestaurantRole[] = ['Admin', 'Manager', 'Staff'];
const OWNERS: RestaurantRole[] = ['Admin', 'Manager'];

export const RESTAURANT_WIDGETS: RestaurantWidgetMeta[] = [
  { id: 'feed', label: 'Live order feed', hint: "Today's orders by stage, with the next action on each", wide: true, roles: ALL },
  { id: 'kitchen', label: 'Kitchen performance', hint: 'Ticket times against target and station throughput', wide: true, roles: ALL },
  { id: 'sales', label: 'Sales trend', hint: 'Revenue, orders or covers over the selected range', wide: true, roles: OWNERS, finance: true },
  { id: 'flow', label: 'Customer flow', hint: 'Dine-in versus takeaway / delivery per period', roles: ALL },
  { id: 'hours', label: 'Peak hours', hint: 'Orders and revenue by hour of day', roles: ALL },
  { id: 'channels', label: 'Channels & service modes', hint: 'POS, online, delivery apps; dine-in, takeaway, delivery', roles: ALL },
  { id: 'menu', label: 'Menu performance', hint: 'Orders, revenue and prep time per menu type', roles: ALL },
  { id: 'stations', label: 'Stations & tables', hint: 'Throughput, revenue and delays per station, table or rider', wide: true, roles: ALL },
  { id: 'shifts', label: 'Shift comparison', hint: 'Breakfast, lunch, dinner and late night side by side', roles: ALL },
  { id: 'staff', label: 'Staff & labor', hint: 'Who is rostered now and labor as a share of sales', wide: true, roles: OWNERS, finance: true },
  { id: 'inventory', label: 'Stock levels', hint: 'Ingredients against reorder level, with a waste log', wide: true, roles: ALL },
  { id: 'waste', label: 'Waste & variance', hint: 'What was written off, by item and reason', roles: OWNERS, finance: true },
  { id: 'status', label: 'Order status', hint: 'Completed, cancelled and no-show mix', roles: ALL },
  { id: 'branches', label: 'Branch comparison', hint: 'Orders and revenue per branch', roles: OWNERS, finance: true },
  { id: 'upcoming', label: 'Upcoming orders', hint: 'Reservations and pre-orders due in the next 24 hours', roles: ALL },
];

export interface RestaurantLayout {
  order: RestaurantWidgetId[];
  hidden: RestaurantWidgetId[];
}

/** Whether this role sees money on the dashboard at all. */
export function canSeeFinance(role: RestaurantRole | undefined): boolean {
  return role === 'Admin' || role === 'Manager';
}

/** The widgets a role may show; anything else never renders for them. */
export function widgetsFor(role: RestaurantRole | undefined): RestaurantWidgetMeta[] {
  return RESTAURANT_WIDGETS.filter((w) => role !== undefined && w.roles.includes(role));
}

/* Each role opens on the panel it works from: the owner on sales, the
 * floor manager on the feed and the room, the chef on the kitchen. */
const ROLE_ORDER: Record<RestaurantRole, RestaurantWidgetId[]> = {
  Admin: ['sales', 'feed', 'kitchen', 'flow', 'channels', 'menu', 'hours', 'shifts', 'stations', 'staff', 'inventory', 'waste', 'status', 'branches', 'upcoming'],
  Manager: ['feed', 'stations', 'upcoming', 'kitchen', 'staff', 'sales', 'flow', 'hours', 'channels', 'menu', 'shifts', 'inventory', 'waste', 'status', 'branches'],
  Staff: ['kitchen', 'feed', 'stations', 'inventory', 'upcoming', 'menu', 'hours', 'flow', 'channels', 'shifts', 'status'],
  Customer: [],
};

export function defaultLayout(role: RestaurantRole | undefined): RestaurantLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (role ? ROLE_ORDER[role] : []).filter((id) => allowed.has(id));
  for (const w of widgetsFor(role)) if (!order.includes(w.id)) order.push(w.id);
  return { order, hidden: [] };
}

const KEY = (tenantId: string, userId: string, role: string) => `restaurant-dashboard-layout:${tenantId}:${userId}:${role}`;

/* Unknown ids (a widget that was removed, or one this role may not see)
 * are dropped and missing ones (a widget added since the layout was
 * saved) are appended, so a stale layout never hides a new panel, shows
 * a forbidden one, or crashes the page. */
function normalise(raw: Partial<RestaurantLayout> | null | undefined, role: RestaurantRole | undefined): RestaurantLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (raw?.order ?? []).filter((id): id is RestaurantWidgetId => allowed.has(id as RestaurantWidgetId));
  for (const id of defaultLayout(role).order) if (!order.includes(id)) order.push(id);
  const hidden = (raw?.hidden ?? []).filter((id): id is RestaurantWidgetId => allowed.has(id as RestaurantWidgetId));
  return { order, hidden };
}

export function loadLayout(tenantId: string, userId: string, role: RestaurantRole | undefined): RestaurantLayout {
  try {
    const stored = localStorage.getItem(KEY(tenantId, userId, role ?? 'none'));
    return stored ? normalise(JSON.parse(stored), role) : defaultLayout(role);
  } catch {
    return defaultLayout(role);
  }
}

export function saveLayout(tenantId: string, userId: string, role: RestaurantRole | undefined, layout: RestaurantLayout): void {
  try {
    localStorage.setItem(KEY(tenantId, userId, role ?? 'none'), JSON.stringify(layout));
  } catch {
    // Private mode or a full store: the layout just does not persist.
  }
}

export function moveWidget(layout: RestaurantLayout, id: RestaurantWidgetId, direction: -1 | 1): RestaurantLayout {
  const index = layout.order.indexOf(id);
  const target = index + direction;
  if (index < 0 || target < 0 || target >= layout.order.length) return layout;
  const order = [...layout.order];
  [order[index], order[target]] = [order[target], order[index]];
  return { ...layout, order };
}

export function toggleWidget(layout: RestaurantLayout, id: RestaurantWidgetId): RestaurantLayout {
  const hidden = layout.hidden.includes(id)
    ? layout.hidden.filter((h) => h !== id)
    : [...layout.hidden, id];
  return { ...layout, hidden };
}
