import type { AttendanceMark, SchoolOverview } from '../../booking/types';
import {
  deltaPercent,
  downloadCsv,
  formatCount,
  formatDelta,
  formatMinutes,
  formatMoney,
  formatPercent,
  presetRange,
  tzOffsetMinutes,
  type RestaurantRange as SchoolRange,
  type RestaurantRangePreset as SchoolRangePreset,
} from '../restaurant/restaurantReport';

/* Reporting helpers for the school dashboard: presets, deltas and the
 * formatters are shared with the restaurant and gym; the attendance
 * vocabulary and the CSV shape live here. */

export { deltaPercent, downloadCsv, formatCount, formatDelta, formatMinutes, formatMoney, formatPercent, presetRange, tzOffsetMinutes };
export type { SchoolRange, SchoolRangePreset };

export const MARK_LABEL: Record<AttendanceMark, string> = { present: 'Present', late: 'Late', absent: 'Absent', excused: 'Excused' };
export const MARK_SHORT: Record<AttendanceMark, string> = { present: 'P', late: 'L', absent: 'A', excused: 'E' };
export const MARK_TONE: Record<AttendanceMark, 'good' | 'warning' | 'critical' | 'neutral'> = { present: 'good', late: 'warning', absent: 'critical', excused: 'neutral' };

/** Points change on one register row: -1 incident, +1 commendation. */
export function pointsLabel(points: number): string {
  if (points > 0) return `+${points}`;
  if (points < 0) return String(points);
  return '';
}

function cell(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = Array.isArray(value) ? value.join('; ') : String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function section(title: string, header: string[], rows: unknown[][]): string[] {
  return [title, header.map(cell).join(','), ...rows.map((r) => r.map(cell).join(',')), ''];
}

/** One CSV per report: attendance, academics, students and - for the
 *  owner / head - enrolment, tuition and the P&L. A teacher's export
 *  carries no money and no billing. */
export function overviewToCsv(overview: SchoolOverview, finance = true, payroll = true): string {
  const k = overview.kpis;
  const summary: unknown[][] = [
    ['Active students', k.students],
    ['Enrolled (tuition current)', k.enrolled],
    ['New students in range', k.newStudents],
    ['Lapsed in range', k.lapsed],
    ['Retention rate %', k.retentionRate],
    ['Sessions timetabled', k.sessions],
    ['Sessions held', k.sessionsHeld],
    ['Attendance rate %', k.attendanceRate],
    ['Present', k.present], ['Late', k.late], ['Absent', k.absent], ['Excused', k.excused], ['Unmarked', k.unmarked],
    ['Assessments', k.assessments],
    ['Graded entries', k.gradedEntries],
    ['Overdue ungraded', k.ungradedOverdue],
    ['Average score %', k.avgScore],
    ['Pass rate %', k.passRate],
    ['At-risk students', k.atRisk],
    ['Incidents', k.incidents], ['Commendations', k.commendations],
    ['Timetable clashes', k.conflicts],
    ['Pending approvals', k.pendingApprovals],
  ];
  if (finance) {
    summary.push(
      [`Tuition paid (${k.currency})`, k.tuitionPaid],
      [`Tutoring fees (${k.currency})`, k.tutoringFees],
      ['Outstanding invoices', k.outstandingCount],
      [`Outstanding amount (${k.currency})`, k.outstandingAmount],
      [`Monthly recurring (${k.currency})`, k.monthlyRecurring],
    );
  }
  if (payroll) {
    summary.push(
      [`Payroll estimate (${k.currency})`, k.payrollCost],
      ['Payroll hours', k.payrollHours],
      [`Purchases (${k.currency})`, k.purchases],
      [`Income (${k.currency})`, k.income],
      [`Costs (${k.currency})`, k.costs],
      [`Net (${k.currency})`, k.net],
    );
  }

  const lines: string[] = [
    `School report,${cell(overview.from.slice(0, 10))} to ${cell(overview.to.slice(0, 10))},grouped by ${overview.groupBy}`,
    '',
    ...section('Summary', ['Metric', 'Value'], summary),
    ...section('Trend', finance ? ['Period', 'Sessions', 'Attendance %', 'Absences', 'Average %', 'New students', 'Tuition paid'] : ['Period', 'Sessions', 'Attendance %', 'Absences', 'Average %', 'New students'],
      overview.trend.map((t) => finance ? [t.label, t.sessions, t.attendanceRate, t.absences, t.avgScore, t.newStudents, t.tuitionPaid] : [t.label, t.sessions, t.attendanceRate, t.absences, t.avgScore, t.newStudents])),
    ...section('Attendance mix', ['Mark', 'Count'], overview.attendanceMix.map((m) => [MARK_LABEL[m.mark], m.count])),
    ...section('Grade distribution', ['Grade', 'Minimum %', 'Students'], overview.distribution.map((d) => [d.grade, d.min, d.count])),
    ...section('Subjects', ['Subject', 'Grade', 'Kind', 'Teacher', 'Sessions', 'Students', 'Attendance %', 'Assessments', 'Graded', 'Average %', 'Weight'],
      overview.bySubject.map((s) => [s.name, s.grade, s.kind, s.teacher, s.sessions, s.students, s.attendanceRate, s.assessments, s.graded, s.avgScore, s.weight])),
    ...section('By year group', ['Grade', 'Students', 'Sessions', 'Attendance %', 'Average %', 'At risk'],
      overview.byGrade.map((g) => [g.grade, g.students, g.sessions, g.attendanceRate, g.avgScore, g.atRisk])),
    ...section('Students', ['Student', 'Grade', 'Sessions marked', 'Attended', 'Late', 'Absent', 'Excused', 'Attendance %', 'Average %', 'Points', 'Incidents', 'Commendations', 'At risk', 'Reasons', 'Tuition'],
      overview.students.map((s) => [s.name, s.grade, s.sessionsMarked, s.attended, s.late, s.absent, s.excused, s.attendanceRate, s.avgScore, s.points, s.incidents, s.commendations, s.atRisk, s.reasons, s.tuitionStatus])),
  ];
  if (finance) {
    lines.push(
      ...section('Teachers', payroll ? ['Teacher', 'Specialty', 'Sessions', 'Hours', 'Students', 'Attendance %', 'Registers outstanding', 'Pay estimate'] : ['Teacher', 'Specialty', 'Sessions', 'Hours', 'Students', 'Attendance %', 'Registers outstanding'],
        overview.byTeacher.map((t) => payroll ? [t.name, t.specialty, t.sessions, t.hoursTaught, t.students, t.attendanceRate, t.unmarkedSessions, t.payEstimate] : [t.name, t.specialty, t.sessions, t.hoursTaught, t.students, t.attendanceRate, t.unmarkedSessions])),
      ...section('Classrooms', ['Room', 'Capacity', 'Sessions', 'Hours booked', 'Utilisation %'], overview.byRoom.map((r) => [r.name, r.capacity, r.sessions, r.hoursBooked, r.utilisationPercent])),
      ...section('Enrolment by year group', ['Grade', 'Students'], overview.byGradeEnrolment.map((g) => [g.grade, g.students])),
      ...section('Tuition status', ['Status', 'Students', 'Amount'], overview.payment.map((p) => [p.status, p.students, p.amount])),
      ...section('Outstanding invoices', ['Student', 'Plan', 'Amount', 'Status', 'Next billing', 'Last payment'],
        overview.outstanding.map((o) => [o.studentName, o.plan, o.amount, o.paymentStatus, o.nextBillingAt?.slice(0, 10), o.lastPaymentAt?.slice(0, 10)])),
    );
  }
  lines.push(
    ...section('Term calendar', ['Term', 'From', 'To', 'Current'], overview.calendar.terms.map((t) => [t.name, t.from.slice(0, 10), t.to.slice(0, 10), t.isCurrent])),
    ...section('Timetable clashes', ['Resource', 'First', 'Second', 'Start', 'Overlap (min)'], overview.conflicts.map((c) => [c.resource, c.first, c.second, c.startTime, c.overlapMinutes])),
  );
  return lines.join('\n');
}
