/* The clinic dashboard's widget registry and the per-user layout that
 * customises it.
 *
 * Every panel on the dashboard is one of these ids. The order and the
 * hidden set are stored per user + tenant in localStorage: a receptionist
 * who only ever needs the waiting room and the reminders can drop the
 * charts, and a manager can lead with branch comparison, without either
 * choice leaking into the other's console. */

export type ClinicWidgetId =
  | 'flow'
  | 'trend'
  | 'status'
  | 'treatments'
  | 'doctors'
  | 'branches'
  | 'insurance'
  | 'hours'
  | 'sources'
  | 'reminders';

export interface ClinicWidgetMeta {
  id: ClinicWidgetId;
  label: string;
  hint: string;
  /** Wide widgets take the full row; the rest sit two-up. */
  wide?: boolean;
}

export const CLINIC_WIDGETS: ClinicWidgetMeta[] = [
  { id: 'flow', label: 'Patient flow', hint: "Today's waiting room, from check-in to discharge", wide: true },
  { id: 'trend', label: 'Appointment trend', hint: 'Appointments and completions over the selected range', wide: true },
  { id: 'status', label: 'Appointment status', hint: 'Scheduled, completed, cancelled and no-show mix' },
  { id: 'treatments', label: 'Treatment demand', hint: 'Appointments by treatment type' },
  { id: 'doctors', label: 'Doctor performance', hint: 'Load, completion, no-shows and wait per doctor', wide: true },
  { id: 'branches', label: 'Branch comparison', hint: 'Patients and revenue per branch' },
  { id: 'insurance', label: 'Insurance providers', hint: 'Patient distribution by insurer' },
  { id: 'hours', label: 'Peak hours', hint: 'When appointments land through the day' },
  { id: 'sources', label: 'Booking channels', hint: 'Where appointments come from' },
  { id: 'reminders', label: 'Reminders & follow-ups', hint: 'Upcoming appointments to remind, patients due a follow-up', wide: true },
];

export interface ClinicLayout {
  order: ClinicWidgetId[];
  hidden: ClinicWidgetId[];
}

export const DEFAULT_LAYOUT: ClinicLayout = {
  order: CLINIC_WIDGETS.map((w) => w.id),
  hidden: [],
};

const KEY = (tenantId: string, userId: string) => `clinic-dashboard-layout:${tenantId}:${userId}`;

const KNOWN = new Set<string>(CLINIC_WIDGETS.map((w) => w.id));

/* Unknown ids (a widget that was removed) are dropped and missing ones
 * (a widget added since the layout was saved) are appended, so a stale
 * layout never hides a new panel or crashes the page. */
function normalise(raw: Partial<ClinicLayout> | null | undefined): ClinicLayout {
  const order = (raw?.order ?? []).filter((id): id is ClinicWidgetId => KNOWN.has(id));
  for (const w of CLINIC_WIDGETS) if (!order.includes(w.id)) order.push(w.id);
  const hidden = (raw?.hidden ?? []).filter((id): id is ClinicWidgetId => KNOWN.has(id));
  return { order, hidden };
}

export function loadLayout(tenantId: string, userId: string): ClinicLayout {
  try {
    const stored = localStorage.getItem(KEY(tenantId, userId));
    return stored ? normalise(JSON.parse(stored)) : DEFAULT_LAYOUT;
  } catch {
    return DEFAULT_LAYOUT;
  }
}

export function saveLayout(tenantId: string, userId: string, layout: ClinicLayout): void {
  try {
    localStorage.setItem(KEY(tenantId, userId), JSON.stringify(layout));
  } catch {
    // Private mode or a full store: the layout just does not persist.
  }
}

export function moveWidget(layout: ClinicLayout, id: ClinicWidgetId, direction: -1 | 1): ClinicLayout {
  const index = layout.order.indexOf(id);
  const target = index + direction;
  if (index < 0 || target < 0 || target >= layout.order.length) return layout;
  const order = [...layout.order];
  [order[index], order[target]] = [order[target], order[index]];
  return { ...layout, order };
}

export function toggleWidget(layout: ClinicLayout, id: ClinicWidgetId): ClinicLayout {
  const hidden = layout.hidden.includes(id)
    ? layout.hidden.filter((h) => h !== id)
    : [...layout.hidden, id];
  return { ...layout, hidden };
}
