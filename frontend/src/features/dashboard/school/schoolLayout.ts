/* The school dashboard's widget registry and per-user layout - the same
 * arrangement as the restaurant and gym: each widget names the roles that
 * may see it and whether it is financial or administrative, the default
 * order differs per role, and the stored layout is keyed by role.
 *
 *   Admin   (owner / principal) - everything: finance, approvals, payroll
 *   Manager (academic head)     - academics and operations plus tuition
 *                                 status, no payroll or P&L
 *   Staff   (teacher)           - the timetable and registers, gradebook,
 *                                 assignments, students; never money or
 *                                 user administration */

export type SchoolRole = 'Admin' | 'Manager' | 'Staff' | 'Customer';

export type SchoolWidgetId =
  | 'timetable'
  | 'attendance'
  | 'students'
  | 'gradebook'
  | 'assignments'
  | 'subjects'
  | 'grades'
  | 'teachers'
  | 'rooms'
  | 'enrolment'
  | 'tuition'
  | 'finance'
  | 'calendar'
  | 'approvals'
  | 'behaviour';

export interface SchoolWidgetMeta {
  id: SchoolWidgetId;
  label: string;
  hint: string;
  wide?: boolean;
  roles: SchoolRole[];
  finance?: boolean;
  admin?: boolean;
}

const ALL: SchoolRole[] = ['Admin', 'Manager', 'Staff'];
const HEADS: SchoolRole[] = ['Admin', 'Manager'];
const OWNER: SchoolRole[] = ['Admin'];

export const SCHOOL_WIDGETS: SchoolWidgetMeta[] = [
  { id: 'timetable', label: "Today's timetable & registers", hint: 'Sessions today, mark attendance, medical alerts on the roster', wide: true, roles: ALL },
  { id: 'attendance', label: 'Attendance', hint: 'Present / late / absent / excused mix and the trend', roles: ALL },
  { id: 'behaviour', label: 'Behaviour & participation', hint: 'Incidents and commendations logged on registers', roles: ALL },
  { id: 'students', label: 'Student performance', hint: 'Every student with attendance, average and at-risk flags; open one for charts', wide: true, roles: ALL },
  { id: 'gradebook', label: 'Gradebook', hint: 'Exams and assignments with per-student marks and feedback', wide: true, roles: ALL },
  { id: 'assignments', label: 'Assignments due', hint: 'Work due this week, submissions and grading progress', roles: ALL },
  { id: 'subjects', label: 'Subjects & courses', hint: 'Attendance and averages per subject, with the teacher', wide: true, roles: ALL },
  { id: 'grades', label: 'Performance by grade', hint: 'Attendance, average and at-risk count per year group', roles: ALL },
  { id: 'teachers', label: 'Teachers', hint: 'Sessions, hours, registers outstanding, pay estimate', roles: HEADS },
  { id: 'rooms', label: 'Classrooms', hint: 'Booked hours and utilisation per room', roles: HEADS },
  { id: 'enrolment', label: 'Enrolment & retention', hint: 'New students, lapsed enrolments, retention, by year group', roles: HEADS },
  { id: 'tuition', label: 'Tuition & payments', hint: 'Invoice status and who to chase', roles: HEADS, finance: true },
  { id: 'finance', label: 'Income & costs', hint: 'Tuition and fees against payroll and purchases - a simple P&L', wide: true, roles: OWNER, finance: true },
  { id: 'calendar', label: 'Term calendar', hint: 'Current term, holidays, timetable clashes', roles: ALL },
  { id: 'approvals', label: 'Registrations to approve', hint: 'New students and staff waiting for approval', roles: HEADS, admin: true },
];

export interface SchoolLayout {
  order: SchoolWidgetId[];
  hidden: SchoolWidgetId[];
}

export function canSeeFinance(role: SchoolRole | undefined): boolean {
  return role === 'Admin' || role === 'Manager';
}

export function canSeePayroll(role: SchoolRole | undefined): boolean {
  return role === 'Admin';
}

export function widgetsFor(role: SchoolRole | undefined): SchoolWidgetMeta[] {
  return SCHOOL_WIDGETS.filter((w) => role !== undefined && w.roles.includes(role));
}

const ROLE_ORDER: Record<SchoolRole, SchoolWidgetId[]> = {
  Admin: ['finance', 'enrolment', 'tuition', 'approvals', 'students', 'attendance', 'subjects', 'grades', 'timetable', 'gradebook', 'teachers', 'rooms', 'calendar', 'assignments', 'behaviour'],
  Manager: ['timetable', 'students', 'attendance', 'subjects', 'grades', 'gradebook', 'teachers', 'approvals', 'enrolment', 'tuition', 'calendar', 'rooms', 'assignments', 'behaviour'],
  Staff: ['timetable', 'gradebook', 'assignments', 'students', 'attendance', 'subjects', 'behaviour', 'grades', 'calendar'],
  Customer: [],
};

export function defaultLayout(role: SchoolRole | undefined): SchoolLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (role ? ROLE_ORDER[role] : []).filter((id) => allowed.has(id));
  for (const w of widgetsFor(role)) if (!order.includes(w.id)) order.push(w.id);
  return { order, hidden: [] };
}

const KEY = (tenantId: string, userId: string, role: string) => `school-dashboard-layout:${tenantId}:${userId}:${role}`;

function normalise(raw: Partial<SchoolLayout> | null | undefined, role: SchoolRole | undefined): SchoolLayout {
  const allowed = new Set(widgetsFor(role).map((w) => w.id));
  const order = (raw?.order ?? []).filter((id): id is SchoolWidgetId => allowed.has(id as SchoolWidgetId));
  for (const id of defaultLayout(role).order) if (!order.includes(id)) order.push(id);
  const hidden = (raw?.hidden ?? []).filter((id): id is SchoolWidgetId => allowed.has(id as SchoolWidgetId));
  return { order, hidden };
}

export function loadLayout(tenantId: string, userId: string, role: SchoolRole | undefined): SchoolLayout {
  try {
    const stored = localStorage.getItem(KEY(tenantId, userId, role ?? 'none'));
    return stored ? normalise(JSON.parse(stored), role) : defaultLayout(role);
  } catch {
    return defaultLayout(role);
  }
}

export function saveLayout(tenantId: string, userId: string, role: SchoolRole | undefined, layout: SchoolLayout): void {
  try {
    localStorage.setItem(KEY(tenantId, userId, role ?? 'none'), JSON.stringify(layout));
  } catch {
    // Private mode or a full store: the layout just does not persist.
  }
}

export function moveWidget(layout: SchoolLayout, id: SchoolWidgetId, direction: -1 | 1): SchoolLayout {
  const index = layout.order.indexOf(id);
  const target = index + direction;
  if (index < 0 || target < 0 || target >= layout.order.length) return layout;
  const order = [...layout.order];
  [order[index], order[target]] = [order[target], order[index]];
  return { ...layout, order };
}

export function toggleWidget(layout: SchoolLayout, id: SchoolWidgetId): SchoolLayout {
  const hidden = layout.hidden.includes(id) ? layout.hidden.filter((h) => h !== id) : [...layout.hidden, id];
  return { ...layout, hidden };
}
