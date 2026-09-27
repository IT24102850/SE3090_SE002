import { useEffect, useMemo, useState } from 'react';
import { useMarkSchoolAttendanceMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatTime } from '../../../shared/dateUtils';
import type { AttendanceMark, SchoolRosterRow, SchoolSession, SchoolToday } from '../../booking/types';
import { MARK_LABEL, MARK_SHORT, pointsLabel } from './schoolReport';

/* Today's timetable and the register for the selected session.
 *
 * Left: every session today in order, with its attendance state and a
 * "needs marking" flag once it has started and nobody has been marked.
 * Right: the roster of the selected session - one row per student with
 * the four marks, a +/- for participation and incidents, and the medical
 * alert or accommodation from the student's profile where there is one,
 * because the teacher needs to see it before the lesson, not after. */

const MARKS: AttendanceMark[] = ['present', 'late', 'absent', 'excused'];

export default function SchoolTimetable({ today, loading, canMark }: { today?: SchoolToday; loading: boolean; canMark: boolean }) {
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [mark] = useMarkSchoolAttendanceMutation();
  const toast = useToast();

  const sessions = today?.sessions ?? [];
  // Default to the session that most needs attention: in progress, then
  // the first that needs marking, then the next upcoming one.
  useEffect(() => {
    if (selectedKey && sessions.some((s) => s.sessionKey === selectedKey)) return;
    const pick = sessions.find((s) => s.state === 'inProgress') ?? sessions.find((s) => s.needsMarking) ?? sessions.find((s) => s.state === 'upcoming') ?? sessions[0];
    setSelectedKey(pick?.sessionKey ?? null);
  }, [sessions, selectedKey]);

  const selected = useMemo(() => sessions.find((s) => s.sessionKey === selectedKey), [sessions, selectedKey]);

  async function setMark(row: SchoolRosterRow, value: AttendanceMark, points?: number) {
    setBusyId(row.bookingId);
    try {
      await mark({ bookingId: row.bookingId, mark: value, points: points ?? row.points, note: row.note ?? undefined }).unwrap();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not save the mark.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  async function markAll(session: SchoolSession, value: AttendanceMark) {
    const targets = session.roster.filter((r) => r.mark === null);
    if (targets.length === 0) return;
    setBusyId('all');
    try {
      await Promise.all(targets.map((r) => mark({ bookingId: r.bookingId, mark: value, points: r.points }).unwrap()));
      toast.show(`${targets.length} marked ${MARK_LABEL[value].toLowerCase()}.`, 'success');
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not mark the register.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  async function adjustPoints(row: SchoolRosterRow, delta: number) {
    const note = window.prompt(delta > 0 ? 'Commendation note (optional)' : 'Incident note (optional)', row.note ?? '') ?? undefined;
    setBusyId(row.bookingId);
    try {
      await mark({ bookingId: row.bookingId, mark: row.mark ?? 'present', points: row.points + delta, note: note?.trim() || row.note || undefined }).unwrap();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not save the points.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  const summary = today?.summary;

  return (
    <div>
      <div className="school-stages">
        <Tile label="Sessions today" value={summary?.sessions} sub={summary ? `${summary.done} done · ${summary.inProgress} running · ${summary.upcoming} to come` : ''} loading={loading} />
        <Tile label="Registers to mark" value={summary?.needsMarking} sub="started, nobody marked yet" loading={loading} alert={(summary?.needsMarking ?? 0) > 0} />
        <Tile label="Present so far" value={summary?.presentSoFar} sub={summary ? `${summary.absentSoFar} absent · ${summary.studentsExpected} expected` : ''} loading={loading} />
        <Tile label="Medical alerts" value={summary?.medicalAlerts} sub="students on today's registers" loading={loading} alert={(summary?.medicalAlerts ?? 0) > 0} />
        <Tile label="Teachers on duty" value={today?.teachers.onDuty} sub={today ? `${today.teachers.rostered} rostered today` : ''} loading={loading} />
      </div>

      {today?.holiday && <div className="school-holiday">Today is a holiday: <b>{today.holiday}</b>{sessions.length > 0 && ` - ${sessions.length} session${sessions.length === 1 ? '' : 's'} still timetabled.`}</div>}

      <div className="school-timetable">
        <div>
          <p className="school-subhead">Timetable{today?.term ? ` · ${today.term}` : ''}</p>
          {loading && !today ? (
            <div className="loading-row"><span className="spinner spinner-dark" /> Loading today…</div>
          ) : sessions.length === 0 ? (
            <div className="school-empty">No sessions timetabled today.</div>
          ) : (
            <div className="school-sessions">
              {sessions.map((s) => (
                <button key={s.sessionKey} type="button" className={`school-session${s.sessionKey === selectedKey ? ' is-active' : ''}${s.needsMarking ? ' school-session-flag' : ''}`} onClick={() => setSelectedKey(s.sessionKey)} aria-pressed={s.sessionKey === selectedKey}>
                  <span className="school-session-time">{formatTime(s.startTime)}<small>{s.state === 'done' ? 'done' : s.state === 'inProgress' ? 'now' : 'next'}</small></span>
                  <span className="school-session-main">
                    <strong><i style={{ background: s.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{s.name}</strong>
                    <span>{[s.grade, s.resourceName].filter(Boolean).join(' · ')} · {s.students} students</span>
                  </span>
                  <span className="school-session-marks" aria-label={`${s.present} present, ${s.late} late, ${s.absent} absent, ${s.excused} excused, ${s.unmarked} unmarked`}>
                    <b className="mark-present">{s.present}</b><b className="mark-late">{s.late}</b><b className="mark-absent">{s.absent}</b><b className="mark-excused">{s.excused}</b>
                    {s.unmarked > 0 && <small>{s.unmarked} unmarked</small>}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>

        <div>
          {selected ? (
            <>
              <div className="school-subhead" style={{ alignItems: 'flex-start' }}>
                <span>Register · {selected.name} · {formatTime(selected.startTime)}–{formatTime(selected.endTime)}</span>
                {canMark && selected.unmarked > 0 && (
                  <span className="school-register-tools">
                    <button type="button" className="btn btn-secondary btn-sm" disabled={busyId === 'all'} onClick={() => markAll(selected, 'present')}>Mark rest present</button>
                  </span>
                )}
              </div>
              <div className="school-roster">
                {selected.roster.map((r) => {
                  const busy = busyId === r.bookingId || busyId === 'all';
                  return (
                    <div key={r.bookingId} className={`school-roster-row${r.medicalAlert ? ' school-roster-row-alert' : ''}`}>
                      <div className="school-roster-main">
                        <strong>{r.studentName}{r.tuitionStatus === 'lapsed' && <span className="school-pill school-pill-warn">tuition lapsed</span>}{r.tuitionStatus === 'Overdue' && <span className="school-pill school-pill-warn">fees overdue</span>}</strong>
                        <span>
                          {r.arrivedAt ? `arrived ${formatTime(r.arrivedAt)}` : r.mark ? MARK_LABEL[r.mark] : 'not marked'}
                          {r.points !== 0 && <> · <b className={r.points > 0 ? 'school-good' : 'school-bad'}>{pointsLabel(r.points)}</b></>}
                          {r.note && <> · {r.note}</>}
                        </span>
                        {r.medicalAlert && <span className="school-medical">⚕ {r.medicalAlert}</span>}
                      </div>
                      <div className="school-marks" role="group" aria-label={`Attendance for ${r.studentName}`}>
                        {MARKS.map((m) => (
                          <button key={m} type="button" className={`school-mark school-mark-${m}${r.mark === m ? ' is-active' : ''}`} disabled={!canMark || busy} onClick={() => setMark(r, m)} title={MARK_LABEL[m]} aria-pressed={r.mark === m}>{MARK_SHORT[m]}</button>
                        ))}
                        {canMark && (
                          <>
                            <button type="button" className="school-mark school-mark-plus" disabled={busy} onClick={() => adjustPoints(r, +1)} title="Commendation (+1)">+</button>
                            <button type="button" className="school-mark school-mark-minus" disabled={busy} onClick={() => adjustPoints(r, -1)} title="Incident (−1)">−</button>
                          </>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
              <p className="school-note">P present · L late · A absent · E excused. A student arriving after the late threshold is shown as late automatically; a mark set here overrides it.</p>
            </>
          ) : (
            <div className="school-empty">Pick a session to open its register.</div>
          )}
        </div>
      </div>
    </div>
  );
}

function Tile({ label, value, sub, loading, alert }: { label: string; value: string | number | undefined; sub: string; loading: boolean; alert?: boolean }) {
  return (
    <div className={`school-stage${alert ? ' school-stage-alert' : ''}`}>
      <div className="school-stage-label">{label}</div>
      <div className="school-stage-value">{loading && value === undefined ? '…' : (value ?? '—')}</div>
      <div className="school-stage-sub">{sub}</div>
    </div>
  );
}

