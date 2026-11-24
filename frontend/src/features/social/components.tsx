import type { Platform, PostStatus, TargetStatus } from './socialApi';

const LETTER: Record<Platform, string> = { Facebook: 'f', Instagram: 'IG', TikTok: '♪' };

export function PlatformMark({ platform, small }: { platform: Platform | string; small?: boolean }) {
  const p = platform as Platform;
  return (
    <span className={`so-platform so-platform-${p}${small ? ' so-platform-sm' : ''}`} aria-label={platform} title={platform}>
      {LETTER[p] ?? '?'}
    </span>
  );
}

const TONE: Record<string, string> = {
  Published: 'bl-badge-good',
  Simulated: 'bl-badge-primary',
  Sent: 'bl-badge-good',
  Connected: 'bl-badge-good',
  Scheduled: 'bl-badge-primary',
  Pending: 'bl-badge-primary',
  Processing: 'bl-badge-warning',
  Publishing: 'bl-badge-warning',
  PartiallyPublished: 'bl-badge-warning',
  NeedsReconnect: 'bl-badge-critical',
  Failed: 'bl-badge-critical',
  Skipped: '',
  Cancelled: '',
  Draft: '',
};

const LABEL: Record<string, string> = {
  PartiallyPublished: 'Partly published',
  NeedsReconnect: 'Needs reconnecting',
  Simulated: 'Sandbox',
};

export function SoBadge({ status }: { status: PostStatus | TargetStatus | string }) {
  return <span className={`bl-badge ${TONE[status] ?? ''}`}>{LABEL[status] ?? status}</span>;
}

export function relativeTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const then = new Date(iso).getTime();
  const diff = Date.now() - then;
  const abs = Math.abs(diff);
  const future = diff < 0;
  const fmt = (n: number, unit: string) => `${future ? 'in ' : ''}${n} ${unit}${n === 1 ? '' : 's'}${future ? '' : ' ago'}`;
  if (abs < 60_000) return future ? 'in a moment' : 'just now';
  if (abs < 3_600_000) return fmt(Math.round(abs / 60_000), 'min');
  if (abs < 86_400_000) return fmt(Math.round(abs / 3_600_000), 'hour');
  if (abs < 7 * 86_400_000) return fmt(Math.round(abs / 86_400_000), 'day');
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

export async function copyText(text: string, show: (m: string, k?: 'success' | 'error') => void, what = 'Copied.') {
  try {
    await navigator.clipboard.writeText(text);
    show(what, 'success');
  } catch {
    show('Could not copy automatically — select the text and copy it.', 'error');
  }
}
