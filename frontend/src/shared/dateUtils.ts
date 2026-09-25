export function startOfDay(d: Date): Date {
  const r = new Date(d);
  r.setHours(0, 0, 0, 0);
  return r;
}

export function addDays(d: Date, days: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + days);
  return r;
}

export function isSameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export function toISODate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Monday-first start of the calendar week containing `d`.
export function startOfWeek(d: Date): Date {
  const r = startOfDay(d);
  const day = (r.getDay() + 6) % 7; // 0 = Monday
  return addDays(r, -day);
}

export function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

// 6-week (42-day) month grid starting on the Monday on/before the 1st.
export function buildMonthGrid(monthAnchor: Date): Date[] {
  const first = startOfMonth(monthAnchor);
  const gridStart = startOfWeek(first);
  return Array.from({ length: 42 }, (_, i) => addDays(gridStart, i));
}

export function buildWeekGrid(weekAnchor: Date): Date[] {
  const start = startOfWeek(weekAnchor);
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}

export function formatMonthYear(d: Date): string {
  return d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
}

export function formatDayLabel(d: Date): string {
  return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });
}

export const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// Combine a calendar day with an existing time-of-day, producing a UTC-suffixed
// ISO string the backend (Npgsql/timestamptz) will accept unambiguously.
export function combineDateWithTimeOfDay(day: Date, timeSourceIso: string): string {
  const t = new Date(timeSourceIso);
  const combined = new Date(day);
  combined.setHours(t.getHours(), t.getMinutes(), t.getSeconds(), 0);
  return combined.toISOString();
}
