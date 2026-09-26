import { useMemo, useState } from 'react';
import {
  useCheckInBookingMutation,
  useSendReminderMutation,
  useUpdateBookingStatusMutation,
} from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import { STATUS_COLORS, type ClinicFlow, type ClinicQueueEntry, type ClinicStage } from '../../booking/types';
import { formatMinutes } from './clinicReport';

/* Today's waiting room, check-in to discharge.
 *
 * The stage tiles are the summary a receptionist glances at; the table is
 * the queue they work. Every row carries the one action that moves the
 * patient to the next stage, so the board is where the flow is driven
 * from, not just where it is watched. The parent polls the endpoint, so a
 * check-in from the mobile scanner shows up here within the minute. */

const STAGES: { id: ClinicStage; label: string; color: string; sub: string }[] = [
  { id: 'scheduled', label: 'Scheduled', color: STATUS_COLORS.Confirmed.bg, sub: 'not yet arrived' },
  { id: 'waiting', label: 'Waiting', color: STATUS_COLORS.CheckedIn.bg, sub: 'checked in' },
  { id: 'inConsultation', label: 'In consultation', color: STATUS_COLORS.InProgress.bg, sub: 'with the doctor' },
  { id: 'completed', label: 'Discharged', color: STATUS_COLORS.Completed.bg, sub: 'visit complete' },
  { id: 'noShow', label: 'No-show', color: STATUS_COLORS.NoShow.bg, sub: 'did not arrive' },
  { id: 'cancelled', label: 'Cancelled', color: STATUS_COLORS.Cancelled.bg, sub: 'or rejected' },
];

type QueueView = 'active' | 'all' | 'waiting' | 'done';

export default function ClinicFlowBoard({ flow, loading }: { flow?: ClinicFlow; loading: boolean }) {
  const [view, setView] = useState<QueueView>('active');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [checkIn] = useCheckInBookingMutation();
  const [updateStatus] = useUpdateBookingStatusMutation();
  const [sendReminder] = useSendReminderMutation();
  const toast = useToast();

  const rows = useMemo(() => {
    const queue = flow?.queue ?? [];
    switch (view) {
      case 'waiting':
        return queue.filter((q) => q.stage === 'waiting' || q.stage === 'inConsultation');
      case 'done':
        return queue.filter((q) => q.stage === 'completed' || q.stage === 'noShow' || q.stage === 'cancelled');
      case 'all':
        return queue;
      default:
        return queue.filter((q) => q.stage === 'scheduled' || q.stage === 'waiting' || q.stage === 'inConsultation');
    }
  }, [flow, view]);

  async function run(entry: ClinicQueueEntry, action: () => Promise<unknown>, done: string, failed: string) {
    setBusyId(entry.bookingId);
    try {
      await action();
      toast.show(done, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, failed), 'error');
    } finally {
      setBusyId(null);
    }
  }

  const actionsFor = (entry: ClinicQueueEntry) => {
    const busy = busyId === entry.bookingId;
    switch (entry.stage) {
      case 'scheduled':
        return (
          <>
            <button type="button" className="btn btn-primary" disabled={busy}
              onClick={() => run(entry, () => checkIn(entry.bookingId).unwrap(), `${entry.patientName} checked in.`, 'Could not check the patient in.')}>
              Check in
            </button>
            {entry.isOverdue && (
              <button type="button" className="btn btn-danger" disabled={busy}
                onClick={() => run(entry, () => updateStatus({ id: entry.bookingId, status: 'NoShow' }).unwrap(), 'Marked as a no-show.', 'Could not update the appointment.')}>
                No-show
              </button>
            )}
            {!entry.reminderSent && !entry.isOverdue && (
              <button type="button" className="btn btn-secondary" disabled={busy}
                onClick={() => run(entry, () => sendReminder({ id: entry.bookingId, channel: 'Email' }).unwrap(), 'Reminder sent.', 'Could not send the reminder.')}>
                Remind
              </button>
            )}
          </>
        );
      case 'waiting':
        return (
          <button type="button" className="btn btn-primary" disabled={busy}
            onClick={() => run(entry, () => updateStatus({ id: entry.bookingId, status: 'InProgress' }).unwrap(), `${entry.patientName} is with ${entry.doctorName}.`, 'Could not start the consultation.')}>
            Start consult
          </button>
        );
      case 'inConsultation':
        return (
          <button type="button" className="btn btn-primary" disabled={busy}
            onClick={() => run(entry, () => updateStatus({ id: entry.bookingId, status: 'Completed' }).unwrap(), 'Visit completed.', 'Could not complete the visit.')}>
            Complete
          </button>
        );
      default:
        return null;
    }
  };

  const stages = flow?.stages;

  return (
    <div>
      <div className="clinic-stages">
        {STAGES.map((s) => {
          const value = stages?.[s.id];
          const alert = s.id === 'waiting' && (flow?.longestWaitMinutes ?? 0) >= 20;
          return (
            <div key={s.id} className={`clinic-stage${alert ? ' clinic-stage-alert' : ''}`}>
              <div className="clinic-stage-label"><i style={{ background: s.color }} aria-hidden="true" />{s.label}</div>
              <div className="clinic-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
              <div className="clinic-stage-sub">
                {s.id === 'waiting' && flow?.longestWaitMinutes != null
                  ? `longest ${formatMinutes(flow.longestWaitMinutes)}`
                  : s.sub}
              </div>
            </div>
          );
        })}
      </div>

      {flow && (
        <div className="clinic-flow-meta">
          <span>Doctors on duty <b>{flow.doctorsOnDuty}</b>{flow.doctorsInConsultation > 0 && <> · <b>{flow.doctorsInConsultation}</b> in consultation</>}</span>
          <span>Patients today <b>{flow.patientsToday}</b></span>
          <span>Patients per doctor <b>{flow.patientsPerDoctor ?? '—'}</b></span>
          <span>Avg wait today <b>{formatMinutes(flow.avgWaitMinutesToday)}</b></span>
          {flow.rooms.total > 0 && (
            <span>Rooms in use <b>{flow.rooms.occupied}/{flow.rooms.total}</b>{flow.rooms.occupancyPercent != null && <> ({flow.rooms.occupancyPercent}%)</>}</span>
          )}
          {flow.overdue > 0 && <span className="clinic-overdue">{flow.overdue} past their slot without check-in</span>}
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, marginBottom: 10, flexWrap: 'wrap' }}>
        <div className="clinic-queue-filter" role="tablist" aria-label="Queue view">
          {([['active', 'Active'], ['waiting', 'In clinic'], ['done', 'Done'], ['all', 'All']] as [QueueView, string][]).map(([id, label]) => (
            <button key={id} type="button" role="tab" aria-selected={view === id} className={view === id ? 'active' : ''} onClick={() => setView(id)}>{label}</button>
          ))}
        </div>
        <span className="clinic-note" style={{ margin: 0 }}>{rows.length} of {flow?.queue.length ?? 0} appointments</span>
      </div>

      {loading && !flow ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading today's patients…</div>
      ) : rows.length === 0 ? (
        <div className="clinic-empty">
          {flow && flow.queue.length === 0 ? 'No appointments today.' : 'Nothing in this view.'}
        </div>
      ) : (
        <div className="table-wrap">
          <table className="data-table clinic-queue-table">
            <thead>
              <tr>
                <th>Time</th>
                <th>Patient</th>
                <th>Doctor</th>
                <th>Treatment</th>
                <th>Status</th>
                <th>Wait</th>
                <th style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((entry) => {
                const status = STATUS_COLORS[entry.status];
                const done = entry.stage === 'completed' || entry.stage === 'noShow' || entry.stage === 'cancelled';
                return (
                  <tr key={entry.bookingId} className={done ? 'clinic-queue-row-done' : undefined}>
                    <td style={{ whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>
                      {formatTime(entry.startTime)}
                      {entry.isOverdue && <div className="clinic-overdue">overdue</div>}
                    </td>
                    <td>
                      <div className="clinic-queue-patient">
                        <strong>{entry.patientName}</strong>
                        <span>{[entry.patientPhone, entry.insuranceProvider].filter(Boolean).join(' · ') || (entry.priority !== 'Normal' ? `${entry.priority} priority` : '')}</span>
                      </div>
                    </td>
                    <td>{entry.doctorName}</td>
                    <td>
                      <span className="clinic-queue-treatment">
                        <i style={{ background: entry.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{entry.treatment}
                      </span>
                    </td>
                    <td>
                      <span className={`badge badge-${status?.tone ?? 'neutral'}`}>
                        <span className="badge-dot" />{entry.status === 'CheckedIn' ? 'Waiting' : entry.status === 'InProgress' ? 'In consult' : entry.status}
                      </span>
                    </td>
                    <td>
                      {entry.waitingMinutes != null ? (
                        <span className={`clinic-wait${entry.isLongWait ? ' clinic-wait-long' : ''}`}>{formatMinutes(entry.waitingMinutes)}</span>
                      ) : entry.checkInAt && entry.consultationStartedAt ? (
                        <span className="clinic-wait" title="Waited before consultation">
                          {formatMinutes((new Date(entry.consultationStartedAt).getTime() - new Date(entry.checkInAt).getTime()) / 60000)}
                        </span>
                      ) : (
                        <span style={{ color: 'var(--color-text-muted)' }}>—</span>
                      )}
                    </td>
                    <td>
                      <div className="clinic-queue-actions">{actionsFor(entry)}</div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
