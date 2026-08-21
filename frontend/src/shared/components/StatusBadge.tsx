import { STATUS_COLORS, type BookingStatus } from '../../features/booking/types';

export default function StatusBadge({ status }: { status: BookingStatus }) {
  const meta = STATUS_COLORS[status] ?? STATUS_COLORS.Pending;
  return (
    <span className={`badge badge-${meta.tone}`}>
      <span className="badge-dot" />
      {status}
    </span>
  );
}
