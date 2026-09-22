import { useMemo, useState } from 'react';
import { useGetSchoolStudentQuery } from '../../../api/bookingApi';
import { formatDateTime } from '../../../shared/dateUtils';
import type { SchoolStudentRow } from '../../booking/types';
import { ScoreLine, SubjectBars } from './SchoolCharts';
import { formatPercent, MARK_LABEL, MARK_TONE, pointsLabel } from './schoolReport';

/* Student performance: the whole cohort in one searchable table, at-risk
 * first, and a drawer for one student with the charts - attendance and
 * average per subject, scores over time - plus the assessment list with
 * feedback, the attendance history and the behaviour log. The at-risk
 * flag is the tenant's own thresholds (Attendance module config). */

export default function SchoolStudents({ rows, loading, thresholds, from, to, tz, finance }: {
  rows: SchoolStudentRow[]; loading: boolean; thresholds?: { atRiskAttendancePercent: number; atRiskGradePercent: number }; from: string; to: string; tz: number; finance: boolean;
}) {
  const [search, setSearch] = useState('');
  const [view, setView] = useState<'all' | 'risk' | 'medical'>('all');
  const [openId, setOpenId] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return rows
      .filter((r) => (view === 'risk' ? r.atRisk : view === 'medical' ? r.medicalAlert : true))
      .filter((r) => !q || r.name.toLowerCase().includes(q) || (r.grade ?? '').toLowerCase().includes(q) || (r.phone ?? '').includes(q))
      .sort((a, b) => Number(b.atRisk) - Number(a.atRisk) || (a.attendanceRate ?? 101) - (b.attendanceRate ?? 101));
  }, [rows, search, view]);

  return (
    <div>
      <div className="school-log-tools">
        <input className="input" placeholder="Search student, grade, phone…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search students" />
        <div className="school-queue-filter" role="tablist" aria-label="Student view">
          <button type="button" role="tab" aria-selected={view === 'all'} className={view === 'all' ? 'active' : ''} onClick={() => setView('all')}>All ({rows.length})</button>
          <button type="button" role="tab" aria-selected={view === 'risk'} className={view === 'risk' ? 'active' : ''} onClick={() => setView('risk')}>At risk ({rows.filter((r) => r.atRisk).length})</button>
          <button type="button" role="tab" aria-selected={view === 'medical'} className={view === 'medical' ? 'active' : ''} onClick={() => setView('medical')}>Medical alerts ({rows.filter((r) => r.medicalAlert).length})</button>
        </div>
        {thresholds && <span className="school-note" style={{ margin: 0 }}>At risk = attendance under {thresholds.atRiskAttendancePercent}% or average under {thresholds.atRiskGradePercent}%, or 3+ incidents.</span>}
      </div>

      {loading && rows.length === 0 ? (
        <div className="loading-row"><span className="spinner spinner-dark" /> Loading students…</div>
      ) : filtered.length === 0 ? (
        <div className="school-empty">{rows.length === 0 ? 'No student activity in this range.' : 'No students match.'}</div>
      ) : (
        <div className="table-wrap" style={{ maxHeight: 440, overflow: 'auto' }}>
          <table className="data-table">
            <thead><tr><th>Student</th><th>Attendance</th><th>Average</th><th>Points</th><th>Last seen</th>{finance && <th>Tuition</th>}<th>Flags</th></tr></thead>
            <tbody>
              {filtered.map((r) => (
                <tr key={r.studentId} className={`school-row-click${r.atRisk ? ' school-row-risk' : ''}`} onClick={() => setOpenId(r.studentId)} tabIndex={0}
                  onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOpenId(r.studentId); } }}>
                  <td><span className="school-strong">{r.name}</span><span className="school-sub">{[r.grade, r.phone].filter(Boolean).join(' · ')}</span></td>
                  <td style={{ whiteSpace: 'nowrap' }}>
                    <span className="school-inline-track"><span className="school-inline-fill" style={{ width: `${r.attendanceRate ?? 0}%`, background: r.attendanceRate != null && thresholds && r.attendanceRate < thresholds.atRiskAttendancePercent ? 'var(--color-critical)' : undefined }} /></span>
                    {formatPercent(r.attendanceRate)}<span className="school-sub">{r.attended}/{r.sessionsMarked} · {r.late} late · {r.absent} absent</span>
                  </td>
                  <td style={{ fontVariantNumeric: 'tabular-nums', color: r.avgScore != null && thresholds && r.avgScore < thresholds.atRiskGradePercent ? 'var(--color-critical)' : undefined }}>{formatPercent(r.avgScore)}<span className="school-sub">{r.graded} graded</span></td>
                  <td><span className={r.points > 0 ? 'school-good' : r.points < 0 ? 'school-bad' : undefined}>{pointsLabel(r.points) || '0'}</span><span className="school-sub">{r.commendations} ↑ · {r.incidents} ↓</span></td>
                  <td style={{ whiteSpace: 'nowrap' }}>{r.lastSeen ? formatDateTime(r.lastSeen).replace(/,.*$/, '') : '—'}</td>
                  {finance && <td><span className={`badge badge-${r.tuitionStatus === 'Paid' ? 'good' : r.tuitionStatus === 'Pending' ? 'warning' : r.tuitionStatus === 'none' ? 'neutral' : 'critical'}`}>{r.tuitionStatus}</span></td>}
                  <td>
                    {r.atRisk && <span className="school-pill school-pill-risk" title={r.reasons.join(', ')}>at risk</span>}
                    {r.medicalAlert && <span className="school-pill school-pill-warn">⚕ medical</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {openId && <StudentDrawer id={openId} from={from} to={to} tz={tz} finance={finance} threshold={thresholds?.atRiskGradePercent ?? 50} onClose={() => setOpenId(null)} />}
    </div>
  );
}

function StudentDrawer({ id, from, to, tz, finance, threshold, onClose }: { id: string; from: string; to: string; tz: number; finance: boolean; threshold: number; onClose: () => void }) {
  const { data, isLoading } = useGetSchoolStudentQuery({ id, from, to, tz });
  const [tab, setTab] = useState<'progress' | 'assessments' | 'attendance' | 'behaviour'>('progress');
  return (
    <>
      <button type="button" className="school-scrim" aria-label="Close" onClick={onClose} />
      <aside className="school-drawer" role="dialog" aria-label="Student progress">
        {isLoading || !data ? (
          <div className="loading-row"><span className="spinner spinner-dark" /> Loading…</div>
        ) : (
          <>
            <div className="school-drawer-head">
              <div>
                <h3>{data.student.fullName}</h3>
                <p>{[data.student.phone, data.student.email, data.tuition?.plan].filter(Boolean).join(' · ')}</p>
                {data.student.medicalNotes && <p className="school-medical">⚕ {data.student.medicalNotes}</p>}
              </div>
              <button type="button" className="btn btn-ghost btn-sm" onClick={onClose}>Close</button>
            </div>
            <div className="school-stages" style={{ gridTemplateColumns: 'repeat(4, minmax(0, 1fr))' }}>
              <Tile label="Attendance" value={formatPercent(data.summary?.attendanceRate)} sub={data.summary ? `${data.summary.attended}/${data.summary.sessionsMarked} sessions` : ''} alert={!!data.summary?.reasons.some((r) => r.startsWith('attendance'))} />
              <Tile label="Average" value={data.summary?.avgScore != null ? `${formatPercent(data.summary.avgScore)}${data.summary.letter ? ` · ${data.summary.letter}` : ''}` : '—'} sub={`${data.assessments.filter((a) => a.score != null).length} graded`} alert={!!data.summary?.reasons.some((r) => r.startsWith('average'))} />
              <Tile label="Points" value={data.summary ? (pointsLabel(data.summary.points) || '0') : '—'} sub={data.summary ? `${data.summary.commendations} ↑ · ${data.summary.incidents} ↓` : ''} alert={(data.summary?.incidents ?? 0) >= 3} />
              <Tile label={finance ? 'Tuition' : 'Status'} value={finance ? (data.tuition ? data.tuition.paymentStatus : 'none') : data.summary?.atRisk ? 'At risk' : 'On track'} sub={finance && data.tuition ? `${data.tuition.status} · to ${data.tuition.endDate.slice(0, 10)}` : (data.summary?.reasons.join(', ') || '')} alert={finance ? data.tuition?.paymentStatus !== 'Paid' && !!data.tuition : !!data.summary?.atRisk} />
            </div>
            <div className="school-queue-filter" role="tablist" aria-label="Student detail" style={{ marginBottom: 12 }}>
              {(['progress', 'assessments', 'attendance', 'behaviour'] as const).map((t) => (
                <button key={t} type="button" role="tab" aria-selected={tab === t} className={tab === t ? 'active' : ''} onClick={() => setTab(t)}>{t[0].toUpperCase() + t.slice(1)}</button>
              ))}
            </div>
            {tab === 'progress' && (
              <>
                <p className="school-subhead">Per subject</p>
                <SubjectBars data={data.perSubject.map((s) => ({ name: s.name, attendanceRate: s.attendanceRate, avgScore: s.avgScore }))} />
                <p className="school-subhead" style={{ marginTop: 14 }}>Scores over time</p>
                <ScoreLine data={data.assessments.map((a) => ({ label: a.date.slice(5, 10), percent: a.percent, name: a.name }))} threshold={threshold} />
              </>
            )}
            {tab === 'assessments' && (
              <div className="school-list">
                {data.assessments.length === 0 && <div className="school-empty">No assessments in this range.</div>}
                {data.assessments.map((a) => (
                  <div key={a.bookingId} className="school-list-row">
                    <div className="school-list-main"><strong><i style={{ background: a.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{a.name}</strong><span>{a.kind} · {a.date.slice(0, 10)} · weight {a.weight}{a.feedback ? ` · “${a.feedback}”` : ''}</span></div>
                    <div className="school-list-side"><b>{a.score != null ? `${a.score}/${a.maxScore}` : a.submittedAt ? 'submitted' : 'pending'}</b><small>{a.percent != null ? `${a.percent}% · ${a.letter}` : ''}</small></div>
                  </div>
                ))}
              </div>
            )}
            {tab === 'attendance' && (
              <div className="school-list">
                {data.attendance.length === 0 && <div className="school-empty">No sessions in this range.</div>}
                {[...data.attendance].reverse().map((a) => (
                  <div key={a.bookingId} className="school-list-row">
                    <div className="school-list-main"><strong>{a.name}</strong><span>{formatDateTime(a.date)} · {a.teacher}</span></div>
                    <div className="school-list-side">{a.mark ? <span className={`badge badge-${MARK_TONE[a.mark]}`}>{MARK_LABEL[a.mark]}</span> : <span className="school-muted">unmarked</span>}</div>
                  </div>
                ))}
              </div>
            )}
            {tab === 'behaviour' && (
              <div className="school-list">
                {data.behaviour.length === 0 && <div className="school-empty">No incidents or commendations logged.</div>}
                {data.behaviour.map((b) => (
                  <div key={b.bookingId} className="school-list-row">
                    <div className="school-list-main"><strong>{b.note || (b.points > 0 ? 'Commendation' : 'Incident')}</strong><span>{formatDateTime(b.date)} · {b.name} · {b.teacher}</span></div>
                    <div className="school-list-side"><b className={b.points > 0 ? 'school-good' : 'school-bad'}>{pointsLabel(b.points)}</b></div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </aside>
    </>
  );
}

function Tile({ label, value, sub, alert }: { label: string; value: string | number | undefined; sub: string; alert?: boolean }) {
  return (
    <div className={`school-stage${alert ? ' school-stage-alert' : ''}`}>
      <div className="school-stage-label">{label}</div>
      <div className="school-stage-value" style={{ fontSize: '1.2rem' }}>{value ?? '—'}</div>
      <div className="school-stage-sub">{sub}</div>
    </div>
  );
}
