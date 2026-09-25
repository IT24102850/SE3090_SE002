import { useEffect, useMemo, useState } from 'react';
import { useGetSchoolGradebookQuery, useGradeSchoolAssessmentMutation } from '../../../api/bookingApi';
import { apiErrorMessage, useToast } from '../../../shared/components/Toast';
import { formatDateTime } from '../../../shared/dateUtils';
import type { SchoolAssessment, SchoolGradebookRow } from '../../booking/types';
import { formatPercent } from './schoolReport';

/* The gradebook: every exam and assignment in the range on the left, the
 * selected one's per-student marks on the right, entered inline. A score
 * is saved on blur or Enter; feedback is a short note beside it. The
 * letter comes from the tenant's grade scale so a report card and this
 * screen agree. */

export default function SchoolGradebook({ from, to, tz, branchId, bookingTypeId, grade, canGrade }: { from: string; to: string; tz: number; branchId?: string; bookingTypeId?: string; grade?: string; canGrade: boolean }) {
  const { data, isLoading } = useGetSchoolGradebookQuery({ from, to, tz, branchId, bookingTypeId, grade });
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [gradeIt] = useGradeSchoolAssessmentMutation();
  const toast = useToast();
  const [busyId, setBusyId] = useState<string | null>(null);

  const assessments = data?.assessments ?? [];
  useEffect(() => {
    if (selectedKey && assessments.some((a) => a.key === selectedKey)) return;
    setSelectedKey((assessments.find((a) => a.isOverdue) ?? assessments[0])?.key ?? null);
  }, [assessments, selectedKey]);
  const selected = useMemo(() => assessments.find((a) => a.key === selectedKey), [assessments, selectedKey]);

  async function save(row: SchoolGradebookRow, score: number | null, feedback: string | null) {
    setBusyId(row.bookingId);
    try {
      await gradeIt({ bookingId: row.bookingId, score, maxScore: row.maxScore, feedback }).unwrap();
    } catch (error) {
      toast.show(apiErrorMessage(error, 'Could not save the grade.'), 'error');
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="school-gradebook">
      <div>
        <p className="school-subhead">Assessments</p>
        {isLoading ? (
          <div className="loading-row"><span className="spinner spinner-dark" /> Loading the gradebook…</div>
        ) : assessments.length === 0 ? (
          <div className="school-empty">No exams or assignments in this range. Create a booking type of kind "exam" or "assignment" and book each student on it.</div>
        ) : (
          <div className="school-sessions">
            {assessments.map((a) => (
              <button key={a.key} type="button" className={`school-session${a.key === selectedKey ? ' is-active' : ''}${a.isOverdue ? ' school-session-flag' : ''}`} onClick={() => setSelectedKey(a.key)} aria-pressed={a.key === selectedKey}>
                <span className="school-session-time">{a.date.slice(5, 10)}<small>{a.kind}</small></span>
                <span className="school-session-main">
                  <strong><i style={{ background: a.colorHex ?? 'var(--color-primary)' }} aria-hidden="true" />{a.name}</strong>
                  <span>{[a.grade, `due ${a.dueAt.slice(0, 10)}`, `weight ${a.weight}`].join(' · ')}</span>
                </span>
                <span className="school-session-marks">
                  <b className="mark-present">{a.graded}</b><small>/ {a.students} graded{a.avgPercent != null ? ` · avg ${a.avgPercent}%` : ''}</small>
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
      <div>
        {selected ? (
          <>
            <div className="school-subhead"><span>{selected.name} · out of {selected.maxScore}</span><span style={{ textTransform: 'none', letterSpacing: 0 }}>{selected.submitted} submitted · {selected.graded} graded</span></div>
            <div className="table-wrap" style={{ maxHeight: 420, overflow: 'auto' }}>
              <table className="data-table school-grade-table">
                <thead><tr><th>Student</th><th>Submitted</th><th>Score</th><th>%</th><th>Grade</th><th>Feedback</th></tr></thead>
                <tbody>
                  {selected.rows.map((r) => <GradeRow key={r.bookingId} row={r} assessment={selected} busy={busyId === r.bookingId} canGrade={canGrade} onSave={save} />)}
                </tbody>
              </table>
            </div>
            <p className="school-note">Type a score and press Enter or move on; leave it blank to clear. Percent and letter follow the tenant's grade scale{data?.scale.length ? ` (${data.scale.map((s) => `${s.grade} ≥ ${s.min}`).join(', ')})` : ''}.</p>
          </>
        ) : (
          <div className="school-empty">Pick an assessment to enter marks.</div>
        )}
      </div>
    </div>
  );
}

function GradeRow({ row, assessment, busy, canGrade, onSave }: { row: SchoolGradebookRow; assessment: SchoolAssessment; busy: boolean; canGrade: boolean; onSave: (row: SchoolGradebookRow, score: number | null, feedback: string | null) => Promise<void> }) {
  const [score, setScore] = useState(row.score == null ? '' : String(row.score));
  const [feedback, setFeedback] = useState(row.feedback ?? '');
  useEffect(() => { setScore(row.score == null ? '' : String(row.score)); setFeedback(row.feedback ?? ''); }, [row.score, row.feedback]);

  const commit = () => {
    const trimmed = score.trim();
    const value = trimmed === '' ? null : Number(trimmed);
    if (value !== null && (!Number.isFinite(value) || value < 0 || value > assessment.maxScore)) return;
    if (value === row.score && (feedback.trim() || null) === (row.feedback ?? null)) return;
    void onSave(row, value, feedback.trim() || null);
  };

  const late = row.submittedAt && new Date(row.submittedAt) > new Date(assessment.dueAt);
  return (
    <tr className={row.percent != null && row.percent < 50 ? 'school-row-low' : undefined}>
      <td><span className="school-strong">{row.studentName}</span></td>
      <td style={{ whiteSpace: 'nowrap' }}>{row.submittedAt ? <>{formatDateTime(row.submittedAt).replace(/,.*$/, '')}{late && <span className="school-pill school-pill-warn">late</span>}</> : <span className="school-muted">not yet</span>}</td>
      <td><input className="input school-score" type="number" min={0} max={assessment.maxScore} step="0.5" value={score} disabled={!canGrade || busy} onChange={(e) => setScore(e.target.value)} onBlur={commit} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); (e.target as HTMLInputElement).blur(); } }} aria-label={`Score for ${row.studentName}`} /></td>
      <td style={{ fontVariantNumeric: 'tabular-nums' }}>{formatPercent(row.percent)}</td>
      <td>{row.letter ? <span className={`badge badge-${row.percent != null && row.percent >= 65 ? 'good' : row.percent != null && row.percent >= 40 ? 'warning' : 'critical'}`}>{row.letter}</span> : <span className="school-muted">—</span>}</td>
      <td><input className="input school-feedback" value={feedback} disabled={!canGrade || busy} placeholder="Feedback…" onChange={(e) => setFeedback(e.target.value)} onBlur={commit} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); (e.target as HTMLInputElement).blur(); } }} aria-label={`Feedback for ${row.studentName}`} /></td>
    </tr>
  );
}
