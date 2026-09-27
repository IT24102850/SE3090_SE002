/* Display helpers shared by the billing screens. */

export function money(amount: number | null | undefined, currency = 'LKR'): string {
  const value = Number(amount ?? 0);
  return `${currency} ${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function compactMoney(amount: number, currency = 'LKR'): string {
  const abs = Math.abs(amount);
  const short = abs >= 1_000_000 ? `${(amount / 1_000_000).toFixed(1)}M` : abs >= 10_000 ? `${(amount / 1000).toFixed(0)}k` : amount.toFixed(0);
  return `${currency} ${short}`;
}

export function date(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

export function dateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

/** yyyy-mm-dd in local time, for <input type="date">. */
export function isoDay(d: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function addDays(d: Date, days: number): Date {
  const copy = new Date(d);
  copy.setDate(copy.getDate() + days);
  return copy;
}

export type Tone = 'good' | 'warning' | 'critical' | 'neutral' | 'primary';

/** One mapping from every billing status to a badge tone. */
export function statusTone(status: string): Tone {
  switch (status) {
    case 'Paid':
    case 'Succeeded':
    case 'Approved':
    case 'Active':
    case 'Completed':
      return 'good';
    case 'PartiallyPaid':
    case 'Pending':
    case 'UnderReview':
    case 'PendingCancel':
    case 'AwaitingApproval':
    case 'Frozen':
      return 'warning';
    case 'Overdue':
    case 'Failed':
    case 'Rejected':
    case 'critical':
    case 'high':
      return 'critical';
    case 'Issued':
    case 'Submitted':
      return 'primary';
    default:
      return 'neutral';
  }
}

/** "PartiallyPaid" -> "Partially paid", "UnderReview" -> "Under review". */
export function humanize(value: string): string {
  const spaced = value.replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2');
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
}

export function downloadBlob(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
