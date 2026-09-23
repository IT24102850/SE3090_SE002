import { humanize, statusTone } from '../format';

export default function StatusBadge({ status, label }: { status: string; label?: string }) {
  return <span className={`bl-badge bl-badge-${statusTone(status)}`}>{label ?? humanize(status)}</span>;
}
