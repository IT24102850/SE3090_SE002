import { useEffect, useState } from 'react';
import { useGetGymAttendanceQuery } from '../../../api/bookingApi';
import { formatDateTime, formatTime } from '../../../shared/dateUtils';
import type { GymAttendanceRow } from '../../booking/types';
import { formatMinutes } from './gymReport';

/* The daily attendance log: every check-in in the selected range, newest
 * first, searchable by member name / phone / email / activity and
 * filterable by method (RFID keycard, app scan, biometric, front desk).
 * Paged on the server so a busy month never lands in one request. */

const MEMBERSHIP_TONE: Record<GymAttendanceRow['membershipStatus'], 'good' | 'warning' | 'critical' | 'neutral'> = { active: 'good', frozen: 'warning', expired: 'critical', cancelled: 'critical', none: 'neutral' };

export default function GymAttendanceLog({ from, to, tz, branchId, resourceId }: { from: string; to: string; tz: number; branchId?: string; resourceId?: string }) {
  const [search, setSearch] = useState('');
  const [debounced, setDebounced] = useState('');
  const [method, setMethod] = useState('');
  const [page, setPage] = useState(1);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => { setPage(1); }, [debounced, method, from, to, branchId, resourceId]);

  const { data, isLoading, isFetching } = useGetGymAttendanceQuery({ from, to, tz, branchId, resourceId, search: debounced || undefined, method: method || undefined, page, pageSize: 25 });
  const pages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1;

  return (
    <div>
      <div className="gym-log-tools">
        <input className="input" placeholder="Search member, phone, email, activity…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search attendance" />
        <select className="input" value={method} onChange={(e) => setMethod(e.target.value)} aria-label="Check-in method">
          <option value="">All methods</option>
          {(data?.methods ?? []).map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
        <span className="gym-note" style={{ margin: 0 }}>{data ? `${data.total.toLocaleString()} check-in${data.total === 1 ? '' : 's'}` : ''}{isFetching && !isLoading ? ' · updating…' : ''}</span>
      </div>

      {isLoading ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading the log…</div>
      ) : !data || data.rows.length === 0 ? (
        <div className="gym-empty">{debounced || method ? 'No check-ins match.' : 'No check-ins in this range.'}</div>
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>In</th>
                <th>Out</th>
                <th>Member</th>
                <th>Membership</th>
                <th>Method</th>
                <th>Activity</th>
                <th>Duration</th>
              </tr>
            </thead>
            <tbody>
              {data.rows.map((r) => (
                <tr key={r.bookingId}>
                  <td style={{ whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{formatDateTime(r.checkInAt)}</td>
                  <td style={{ whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{r.checkOutAt ? formatTime(r.checkOutAt) : <span className="gym-inside-pill">inside</span>}</td>
                  <td><span className="gym-strong">{r.memberName}</span>{r.phone && <span className="gym-sub">{r.phone}</span>}</td>
                  <td><span className={`badge badge-${MEMBERSHIP_TONE[r.membershipStatus]}`}><span className="badge-dot" />{r.plan ?? (r.membershipStatus === 'none' ? 'None' : r.membershipStatus)}</span></td>
                  <td>{r.method}</td>
                  <td>{r.activity}<span className="gym-sub">{r.zone}</span></td>
                  <td>{formatMinutes(r.minutes)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {pages > 1 && (
        <div className="gym-pager">
          <button type="button" className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>‹ Newer</button>
          <span>Page {page} of {pages}</span>
          <button type="button" className="btn btn-ghost btn-sm" disabled={page >= pages} onClick={() => setPage((p) => p + 1)}>Older ›</button>
        </div>
      )}
    </div>
  );
}
