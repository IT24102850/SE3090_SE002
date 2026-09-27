import { describe, expect, it } from 'vitest';
import type { SchoolOverview } from '../../booking/types';
import { canSeeFinance, canSeePayroll, defaultLayout, loadLayout, widgetsFor } from './schoolLayout';
import { MARK_SHORT, overviewToCsv, pointsLabel } from './schoolReport';

describe('role-based layouts', () => {
  it('keeps money and user administration away from teachers', () => {
    expect(canSeeFinance('Admin')).toBe(true);
    expect(canSeeFinance('Manager')).toBe(true);
    expect(canSeeFinance('Staff')).toBe(false);
    expect(canSeePayroll('Manager')).toBe(false);
    const teacher = widgetsFor('Staff').map((w) => w.id);
    expect(teacher).not.toContain('tuition');
    expect(teacher).not.toContain('finance');
    expect(teacher).not.toContain('approvals');
    expect(teacher).not.toContain('teachers');
    expect(teacher).toContain('timetable');
    expect(teacher).toContain('gradebook');
    expect(teacher).toContain('students');
  });

  it('gives the P&L to the owner only', () => {
    expect(widgetsFor('Admin').map((w) => w.id)).toContain('finance');
    expect(widgetsFor('Manager').map((w) => w.id)).not.toContain('finance');
    expect(widgetsFor('Manager').map((w) => w.id)).toContain('tuition');
  });

  it('opens each role on the panel they work from', () => {
    expect(defaultLayout('Admin').order[0]).toBe('finance');
    expect(defaultLayout('Manager').order[0]).toBe('timetable');
    expect(defaultLayout('Staff').order[0]).toBe('timetable');
  });

  it('drops forbidden widgets from a stored layout', () => {
    const store = new Map<string, string>();
    Object.defineProperty(globalThis, 'localStorage', {
      value: { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => { store.set(k, v); }, removeItem: () => {}, clear: () => {}, key: () => null, length: 0 },
      configurable: true,
    });
    store.set('school-dashboard-layout:t:u:Staff', JSON.stringify({ order: ['finance', 'gradebook'], hidden: ['approvals', 'grades'] }));
    const layout = loadLayout('t', 'u', 'Staff');
    expect(layout.order[0]).toBe('gradebook');
    expect(layout.order).not.toContain('finance');
    expect(layout.hidden).toEqual(['grades']);
  });
});

describe('register helpers', () => {
  it('has one letter per mark and signed points', () => {
    expect(MARK_SHORT).toEqual({ present: 'P', late: 'L', absent: 'A', excused: 'E' });
    expect(pointsLabel(2)).toBe('+2');
    expect(pointsLabel(-1)).toBe('-1');
    expect(pointsLabel(0)).toBe('');
  });
});

describe('overviewToCsv', () => {
  const overview: SchoolOverview = {
    from: '2026-08-20', to: '2026-09-19', groupBy: 'day', asOf: '2026-09-19T09:00:00Z', tz: 330, filters: {},
    thresholds: { atRiskAttendancePercent: 75, atRiskGradePercent: 50, lateAfterMinutes: 10, scale: [{ grade: 'A', min: 75 }, { grade: 'F', min: 0 }] },
    calendar: { terms: [{ name: 'Term 3', from: '2026-08-25', to: '2026-12-05', isCurrent: true }], currentTerm: { name: 'Term 3', from: '2026-08-25', to: '2026-12-05', daysLeft: 77, progressPercent: 25 }, holidays: [], nextHoliday: null },
    kpis: {
      currency: 'LKR', students: 24, enrolled: 22, newStudents: 1, lapsed: 1, retentionRate: 92.9, pendingApprovals: 3, pendingStudents: 2, pendingStaff: 1,
      sessions: 60, sessionsHeld: 54, attendanceRate: 91, present: 500, late: 40, absent: 40, excused: 14, unmarked: 20, unmarkedSessions: 2,
      assessments: 7, gradedEntries: 76, ungradedOverdue: 8, avgScore: 67.5, passRate: 87.5, atRisk: 4, behaviourPoints: -10, incidents: 27, commendations: 17,
      teachers: 4, rooms: 3, conflicts: 0, tuitionPaid: 280500, tutoringFees: 15000, income: 295500, payrollHours: 500, payrollCost: 255000, purchases: 68200, costs: 323200, net: -27700,
      outstandingCount: 4, outstandingAmount: 61500, monthlyRecurring: 342000,
    },
    previous: { attendanceRate: 89, avgScore: 65, newStudents: 2, income: 250000, sessions: 50 },
    attendanceMix: [{ mark: 'present', count: 500 }, { mark: 'late', count: 40 }, { mark: 'absent', count: 40 }, { mark: 'excused', count: 14 }],
    distribution: [{ grade: 'A', min: 75, count: 20 }, { grade: 'F', min: 0, count: 3 }],
    trend: [{ bucket: '2026-09-19', label: '19 Sep', sessions: 3, attendanceRate: null, absences: 0, avgScore: null, newStudents: 0, tuitionPaid: 0 }],
    bySubject: [{ bookingTypeId: 's1', name: 'Mathematics - Grade 10', subject: 'Mathematics', grade: 'Grade 10', kind: 'lesson', teacher: 'Mr. Dilshan Ekanayake - Mathematics', sessions: 12, students: 14, attendanceRate: 90, assessments: 2, graded: 28, avgScore: 66.5, weight: 1 }],
    byGrade: [{ grade: 'Grade 10', students: 14, sessions: 30, attendanceRate: 90, avgScore: 67, atRisk: 3 }],
    byGradeEnrolment: [{ grade: 'Grade 10', students: 13 }],
    byTeacher: [{ resourceId: 't1', name: 'Mr. Dilshan Ekanayake - Mathematics', specialty: 'Mathematics', sessions: 20, hoursTaught: 30, students: 24, attendanceRate: 90, unmarkedSessions: 1, payEstimate: 16500 }],
    byRoom: [{ resourceId: 'r1', name: 'Classroom A', capacity: 20, sessions: 20, hoursBooked: 30, utilisationPercent: 15.8 }],
    atRisk: [], students: [{ studentId: 'u7', name: 'Ravindu, "Ravi" Wijesinghe', grade: 'Grade 10', sessionsMarked: 33, attended: 15, late: 2, absent: 16, excused: 2, attendanceRate: 45.5, avgScore: 79.5, graded: 4, points: 1, incidents: 1, commendations: 2, lastSeen: '2026-09-18T09:00:00Z', atRisk: true, reasons: ['attendance 45.5%'], medicalAlert: false, tuitionStatus: 'Overdue' }],
    payment: [{ status: 'Paid', students: 18, amount: 280500 }], outstanding: [], pendingApprovals: [], conflicts: [],
    filterOptions: { branches: [], teachers: [], rooms: [], subjects: [], grades: [] },
  };

  it('writes one sheet with a section per report and quotes awkward cells', () => {
    const csv = overviewToCsv(overview, true, true);
    expect(csv.startsWith('School report,2026-08-20 to 2026-09-19,grouped by day')).toBe(true);
    expect(csv).toContain('Attendance rate %,91');
    expect(csv).toContain('Net (LKR),-27700');
    expect(csv).toContain('"Ravindu, ""Ravi"" Wijesinghe",Grade 10,33,15,2,16,2,45.5,79.5,1,1,2,true,attendance 45.5%,Overdue');
    expect(csv).toContain('Mr. Dilshan Ekanayake - Mathematics,Mathematics,20,30,24,90,1,16500');
  });

  it('strips money for a teacher and payroll for the academic head', () => {
    const teacher = overviewToCsv(overview, false, false);
    expect(teacher).not.toContain('Tuition paid');
    expect(teacher).not.toContain('Payroll');
    expect(teacher).not.toContain('Teachers');
    expect(teacher).toContain('At-risk students,4');
    const head = overviewToCsv(overview, true, false);
    expect(head).toContain('Tuition paid (LKR),280500');
    expect(head).not.toContain('Payroll estimate');
    expect(head).toContain('Mr. Dilshan Ekanayake - Mathematics,Mathematics,20,30,24,90,1\n');
  });
});
