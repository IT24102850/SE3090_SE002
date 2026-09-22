using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The school / tuition-centre dashboard: today's timetable and attendance
/// marking, the gradebook, student performance and at-risk flags,
/// enrolment and retention, tuition billing, a simple P&L, the term
/// calendar, pending approvals and timetable conflicts.
///
/// Same footing as the clinic / restaurant / gym controllers: its own role
/// checks, everything derived from data the platform records, and a
/// metric with no inputs yet is null. What the platform does not record
/// (backups, third-party integrations, access-log audits, parent
/// accounts) is not reported and not faked.
///
/// How a school maps onto the platform (SchoolConfig has the JSON shapes):
///   student      = User with Role Customer; MedicalNotes carries medical
///                  alerts / accommodations; IsApproved = registration
///                  approved
///   teacher      = Staff resource with its weekly roster and HourlyRate
///   classroom    = Room resource
///   subject      = BookingType of kind "lesson" / "tutoring" (ConfigJson
///                  subject + grade); a session is one start time on one
///                  resource, its roster the bookings on it
///   attendance   = the student's booking on a session; the mark and the
///                  behaviour points sit in FormData; CheckInAt is the
///                  time they arrived
///   assessment   = BookingType of kind "exam" / "assignment"; one booking
///                  per student with score / maxScore / feedback in
///                  FormData; the type's weight is its share of the final
///   tuition      = Subscription (plan = the fee package; PaymentStatus =
///                  the latest invoice run)
///   payroll      = teachers' rostered hours x HourlyRate
///   terms        = the Scheduling module's config; thresholds and the
///                  grade scale = the Attendance module's config
[ApiController]
[Route("api/reports/school")]
[Authorize(Roles = "Admin,Manager,Staff")]
public class SchoolReportsController : ControllerBase
{
    private readonly AppDbContext _db;

    private const int AssignmentHorizonDays = 7;
    private const int UnmarkedGraceMinutes = 30;

    public SchoolReportsController(AppDbContext db)
    {
        _db = db;
    }

    // ── Overview ────────────────────────────────────────────────────────

    /// <summary>Attendance, academic, enrolment, tuition and payroll KPIs with breakdowns for a date range. Hours use the viewer's `tz` offset.</summary>
    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? branchId, [FromQuery] Guid? resourceId,
        [FromQuery] Guid? bookingTypeId, [FromQuery] string? grade, [FromQuery] string groupBy = "day", [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var grouping = NormalizeGroupBy(groupBy);
        var now = DateTime.UtcNow;
        var days = Math.Max(1, (int)Math.Round((endExclusive - start).TotalDays));
        var localNow = clock.Local(now);

        var calendar = SchoolConfig.CalendarOf(await ModuleConfigAsync(tenantId, SchoolConfig.SchedulingModule));
        var thresholds = SchoolConfig.ThresholdsOf(await ModuleConfigAsync(tenantId, SchoolConfig.AttendanceModule));

        var resources = await _db.Resources.AsNoTracking().Include(r => r.Branch)
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null).ToListAsync();
        var branches = await _db.Branches.AsNoTracking().Where(b => b.TenantId == tenantId).OrderBy(b => b.Name).ToListAsync();
        var types = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.DeletedAt == null && bt.Status != BookingTypeStatus.Archived).OrderBy(bt => bt.Name).ToListAsync();

        var students = await _db.Users.AsNoTracking().IgnoreQueryFilters()
            .Where(u => u.TenantId == tenantId && u.Role == UserRole.Customer && (!branchId.HasValue || u.BranchId == branchId.Value))
            .Select(u => new StudentRow(u.Id, u.FullName, u.Phone, u.Email, u.CreatedAt, u.IsActive, u.IsApproved, u.MedicalNotes))
            .ToListAsync();
        var studentsById = students.ToDictionary(s => s.Id);
        var pendingStudents = students.Where(s => !s.IsApproved).ToList();
        var pendingStaff = await _db.Users.AsNoTracking().IgnoreQueryFilters()
            .CountAsync(u => u.TenantId == tenantId && !u.IsApproved && u.Role != UserRole.Customer);

        var subs = await _db.Subscriptions.AsNoTracking()
            .Where(s => s.TenantId == tenantId && (!branchId.HasValue || s.BranchId == branchId.Value || s.BranchId == null)).ToListAsync();
        var currentSub = subs.GroupBy(s => s.CustomerId).ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.EndDate).First());

        var allBookings = await LoadBookingsAsync(tenantId, start, endExclusive, branchId, resourceId, bookingTypeId);
        var wantedGrade = string.IsNullOrWhiteSpace(grade) ? null : grade.Trim();
        if (wantedGrade != null) allBookings = allBookings.Where(b => string.Equals(SchoolConfig.GradeOf(b.BookingType), wantedGrade, StringComparison.OrdinalIgnoreCase)).ToList();
        // A session booked on a classroom by a teacher (the "room hold") is
        // timetable, not a register row: it counts for room utilisation and
        // clashes, never for attendance or a student's record.
        var studentIds = studentsById.Keys.ToHashSet();
        var bookings = allBookings.Where(b => studentIds.Contains(MemberOf(b))).ToList();
        var previous = (await LoadBookingsAsync(tenantId, start - (endExclusive - start), start, branchId, resourceId, bookingTypeId))
            .Where(b => studentIds.Contains(MemberOf(b))).ToList();
        if (wantedGrade != null) previous = previous.Where(b => string.Equals(SchoolConfig.GradeOf(b.BookingType), wantedGrade, StringComparison.OrdinalIgnoreCase)).ToList();

        // ── Attendance ──────────────────────────────────────────────────
        var lessons = bookings.Where(b => IsLesson(b) && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected).ToList();
        var pastLessons = lessons.Where(b => b.StartTime <= now).ToList();
        var marks = pastLessons.Select(b => MarkOf(b, thresholds)).ToList();
        var marked = marks.Count(m => m != null);
        int Count(string mark) => marks.Count(m => m == mark);
        var attended = Count("present") + Count("late");
        var attendanceRate = marked > 0 ? Math.Round(attended / (double)marked * 100, 1) : (double?)null;
        var prevPast = previous.Where(b => IsLesson(b) && b.StartTime <= now && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected).ToList();
        var prevMarks = prevPast.Select(b => MarkOf(b, thresholds)).Where(m => m != null).ToList();
        var prevAttendance = prevMarks.Count > 0 ? Math.Round(prevMarks.Count(m => m is "present" or "late") / (double)prevMarks.Count * 100, 1) : (double?)null;
        var sessions = lessons.GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime }).ToList();
        var unmarkedSessions = sessions.Count(s => s.Key.StartTime.AddMinutes(UnmarkedGraceMinutes) < now && s.Any(b => MarkOf(b, thresholds) == null));

        // ── Academics ───────────────────────────────────────────────────
        var assessments = bookings.Where(b => IsAssessment(b) && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected).ToList();
        var graded = assessments.Select(b => (b, a: SchoolConfig.AssessmentOf(b.FormData))).Where(x => x.a.Score.HasValue).ToList();
        double Pct((Booking b, SchoolConfig.Assessment a) x) => x.a.Score!.Value / x.a.MaxScore * 100;
        var avgScore = graded.Count > 0 ? Math.Round(graded.Average(Pct), 1) : (double?)null;
        var prevGraded = previous.Where(IsAssessment).Select(b => (b, a: SchoolConfig.AssessmentOf(b.FormData))).Where(x => x.a.Score.HasValue).ToList();
        var prevAvg = prevGraded.Count > 0 ? Math.Round(prevGraded.Average(Pct), 1) : (double?)null;
        var passRate = graded.Count > 0 ? Math.Round(graded.Count(x => Pct(x) >= thresholds.AtRiskGradePercent) / (double)graded.Count * 100, 1) : (double?)null;
        var ungraded = assessments.Count(b => SchoolConfig.AssessmentOf(b.FormData).Score == null && (SchoolConfig.AssessmentOf(b.FormData).DueAt ?? b.EndTime) < now);
        var distribution = thresholds.Scale.Select(band => new { grade = band.Grade, min = band.Min, count = graded.Count(x => SchoolConfig.LetterOf(Pct(x), thresholds.Scale) == band.Grade) }).ToList();

        // ── Per-student performance and at-risk flags ───────────────────
        var studentStats = StudentStats(bookings, thresholds, now);
        var atRisk = studentStats.Values.Where(s => s.AtRisk).OrderBy(s => s.AttendanceRate ?? 0).ThenBy(s => s.AvgScore ?? 0).ToList();

        // ── Enrolment & retention ───────────────────────────────────────
        var activeStudents = students.Where(s => s.IsApproved && s.IsActive).ToList();
        var newStudents = students.Count(s => s.CreatedAt >= start && s.CreatedAt < endExclusive && s.IsApproved);
        var prevNew = students.Count(s => s.CreatedAt >= start - (endExclusive - start) && s.CreatedAt < start && s.IsApproved);
        var enrolledAtStart = subs.Where(s => s.StartDate < start && s.EndDate >= start && !s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase)).Select(s => s.CustomerId).Distinct().ToList();
        var stillEnrolled = enrolledAtStart.Count(id => currentSub.TryGetValue(id, out var s) && !IsLapsed(s, now));
        var retention = enrolledAtStart.Count > 0 ? Math.Round(stillEnrolled / (double)enrolledAtStart.Count * 100, 1) : (double?)null;
        var enrolledNow = currentSub.Values.Count(s => !IsLapsed(s, now));
        var lapsed = currentSub.Values.Count(s => IsLapsed(s, now) && s.EndDate >= start && s.EndDate < endExclusive);
        var byGradeEnrolment = currentSub.Values.Where(s => !IsLapsed(s, now)).GroupBy(s => GradeFromPlan(s.PlanName) ?? "Unassigned")
            .Select(g => new { grade = g.Key, students = g.Count() }).OrderBy(x => x.grade).ToList();

        // ── Tuition, payroll, P&L ───────────────────────────────────────
        var payment = currentSub.Values.Where(s => !IsLapsed(s, now)).GroupBy(s => NormalizePayment(s.PaymentStatus))
            .Select(g => new { status = g.Key, students = g.Count(), amount = g.Sum(s => s.Amount) }).OrderBy(x => PaymentOrder(x.status)).ToList();
        var outstanding = currentSub.Values.Where(s => !IsLapsed(s, now) && NormalizePayment(s.PaymentStatus) != "Paid").ToList();
        var tuitionPaid = subs.Where(s => NormalizePayment(s.PaymentStatus) == "Paid" && PaidAt(s) >= start && PaidAt(s) < endExclusive).Sum(s => s.Amount);
        var tutoringFees = bookings.Where(b => b.Status == BookingStatus.Completed && SchoolConfig.KindOf(b.BookingType) == SchoolConfig.Tutoring).Sum(b => b.TotalCost ?? 0m);
        var prevIncome = subs.Where(s => NormalizePayment(s.PaymentStatus) == "Paid" && PaidAt(s) >= start - (endExclusive - start) && PaidAt(s) < start).Sum(s => s.Amount)
            + previous.Where(b => b.Status == BookingStatus.Completed && SchoolConfig.KindOf(b.BookingType) == SchoolConfig.Tutoring).Sum(b => b.TotalCost ?? 0m);

        var teachers = resources.Where(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();
        var teacherIds = teachers.Select(t => t.Id).ToList();
        var roster = await _db.ResourceSchedules.AsNoTracking().Where(s => s.ResourceId != null && teacherIds.Contains(s.ResourceId.Value) && s.IsAvailable).ToListAsync();
        var (payrollHours, payrollCost) = PayrollOver(teachers, roster, clock.Local(start).Date, days);
        var purchases = await _db.StockMovements.AsNoTracking()
            .Where(m => m.TenantId == tenantId && m.MovementType == "Receive" && m.OccurredAt >= start && m.OccurredAt < endExclusive && (!branchId.HasValue || m.BranchId == branchId.Value))
            .Select(m => m.Quantity * (m.UnitCost ?? 0m)).SumAsync();
        var income = tuitionPaid + tutoringFees;
        var costs = payrollCost + purchases;

        // ── Breakdowns ──────────────────────────────────────────────────
        var bySubject = lessons.Concat(assessments).GroupBy(b => b.BookingTypeId).Select(g =>
        {
            var type = g.First().BookingType;
            var kind = SchoolConfig.KindOf(type);
            var past = g.Where(b => IsLesson(b) && b.StartTime <= now).ToList();
            var pm = past.Select(b => MarkOf(b, thresholds)).Where(m => m != null).ToList();
            var gr = g.Where(IsAssessment).Select(b => SchoolConfig.AssessmentOf(b.FormData)).Where(a => a.Score.HasValue).ToList();
            return new
            {
                bookingTypeId = g.Key,
                name = type.Name,
                subject = SchoolConfig.SubjectOf(type),
                grade = SchoolConfig.GradeOf(type),
                kind,
                colorHex = type.ColorHex,
                teacher = g.Where(b => b.Resource.Category == ResourceCategory.Staff).GroupBy(b => b.Resource.Name).OrderByDescending(x => x.Count()).Select(x => x.Key).FirstOrDefault(),
                sessions = g.Where(IsLesson).GroupBy(b => new { b.ResourceId, b.StartTime }).Count(),
                students = g.Select(MemberOf).Distinct().Count(),
                attendanceRate = pm.Count > 0 ? Math.Round(pm.Count(m => m is "present" or "late") / (double)pm.Count * 100, 1) : (double?)null,
                assessments = g.Count(IsAssessment),
                graded = gr.Count,
                avgScore = gr.Count > 0 ? Math.Round(gr.Average(a => a.Score!.Value / a.MaxScore * 100), 1) : (double?)null,
                weight = SchoolConfig.WeightOf(type),
            };
        }).OrderBy(x => x.grade).ThenBy(x => x.name).ToList();

        var byGrade = lessons.Concat(assessments).GroupBy(b => SchoolConfig.GradeOf(b.BookingType) ?? "Unassigned").Select(g =>
        {
            var pm = g.Where(b => IsLesson(b) && b.StartTime <= now).Select(b => MarkOf(b, thresholds)).Where(m => m != null).ToList();
            var gr = g.Where(IsAssessment).Select(b => SchoolConfig.AssessmentOf(b.FormData)).Where(a => a.Score.HasValue).ToList();
            var ids = g.Select(MemberOf).Distinct().ToList();
            return new
            {
                grade = g.Key,
                students = ids.Count,
                sessions = g.Where(IsLesson).GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime }).Count(),
                attendanceRate = pm.Count > 0 ? Math.Round(pm.Count(m => m is "present" or "late") / (double)pm.Count * 100, 1) : (double?)null,
                avgScore = gr.Count > 0 ? Math.Round(gr.Average(a => a.Score!.Value / a.MaxScore * 100), 1) : (double?)null,
                atRisk = ids.Count(id => studentStats.TryGetValue(id, out var s) && s.AtRisk),
            };
        }).OrderBy(x => x.grade).ToList();

        var byTeacher = lessons.Where(b => b.Resource.Category == ResourceCategory.Staff).GroupBy(b => b.ResourceId).Select(g =>
        {
            var r = g.First().Resource;
            var sess = g.GroupBy(b => new { b.BookingTypeId, b.StartTime }).ToList();
            var pm = g.Where(b => b.StartTime <= now).Select(b => MarkOf(b, thresholds)).Where(m => m != null).ToList();
            var hours = sess.Sum(s => Math.Max(0, (s.First().EndTime - s.First().StartTime).TotalHours));
            return new
            {
                resourceId = g.Key,
                name = r.Name,
                specialty = r.Specialty,
                sessions = sess.Count,
                hoursTaught = Math.Round(hours, 1),
                students = g.Select(MemberOf).Distinct().Count(),
                attendanceRate = pm.Count > 0 ? Math.Round(pm.Count(m => m is "present" or "late") / (double)pm.Count * 100, 1) : (double?)null,
                unmarkedSessions = sess.Count(s => s.Key.StartTime.AddMinutes(UnmarkedGraceMinutes) < now && s.Any(b => MarkOf(b, thresholds) == null)),
                payEstimate = r.HourlyRate.HasValue ? Math.Round((decimal)hours * r.HourlyRate.Value, 2) : (decimal?)null,
            };
        }).OrderByDescending(x => x.sessions).ToList();

        var rooms = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();
        var roomLessons = allBookings.Where(b => IsLesson(b) && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected).ToList();
        var byRoom = rooms.Select(room =>
        {
            var sess = roomLessons.Where(b => b.ResourceId == room.Id).GroupBy(b => new { b.BookingTypeId, b.StartTime }).ToList();
            var hours = sess.Sum(s => Math.Max(0, (s.First().EndTime - s.First().StartTime).TotalHours));
            return new { resourceId = room.Id, name = room.Name, capacity = room.Capacity, sessions = sess.Count, hoursBooked = Math.Round(hours, 1), utilisationPercent = days > 0 ? Math.Round(hours / (days * 8.0) * 100, 1) : (double?)null };
        }).OrderByDescending(x => x.hoursBooked).ToList();

        // Conflicts: the same teacher or room on two different sessions
        // that overlap. This is the timetable's own double-booking check,
        // independent of the Bookings conflicts report.
        var conflicts = roomLessons.GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime })
            .Select(s => new { s.Key.ResourceId, s.Key.BookingTypeId, s.Key.StartTime, EndTime = s.First().EndTime, Name = s.First().BookingType.Name, Resource = s.First().Resource.Name })
            .OrderBy(s => s.StartTime).ToList();
        var conflictRows = new List<object>();
        for (var i = 0; i < conflicts.Count; i++)
            for (var j = i + 1; j < conflicts.Count; j++)
            {
                var a = conflicts[i]; var b = conflicts[j];
                if (a.ResourceId != b.ResourceId || b.StartTime >= a.EndTime) continue;
                conflictRows.Add(new { resource = a.Resource, first = a.Name, second = b.Name, startTime = b.StartTime, overlapMinutes = (int)Math.Round((a.EndTime - b.StartTime).TotalMinutes) });
            }

        var behaviour = pastLessons.Select(b => SchoolConfig.AttendanceOf(b.FormData)).ToList();
        var trend = BuildTrend(bookings, subs, students, clock, start, endExclusive, grouping, thresholds, now);

        var currentTerm = calendar.Terms.FirstOrDefault(t => t.From <= now && now <= t.To.AddDays(1));
        var nextHoliday = calendar.Holidays.FirstOrDefault(h => h.Date >= localNow.Date);

        return Ok(new
        {
            from = clock.Local(start).Date,
            to = clock.Local(endExclusive).Date.AddDays(-1),
            groupBy = grouping,
            asOf = now,
            tz,
            filters = new { branchId, resourceId, bookingTypeId, grade = wantedGrade },
            thresholds = new { thresholds.AtRiskAttendancePercent, thresholds.AtRiskGradePercent, thresholds.LateAfterMinutes, scale = thresholds.Scale.Select(s => new { s.Grade, s.Min }) },
            calendar = new
            {
                terms = calendar.Terms.Select(t => new { t.Name, from = t.From, to = t.To, isCurrent = currentTerm != null && t.Name == currentTerm.Name }),
                currentTerm = currentTerm == null ? null : new { currentTerm.Name, from = currentTerm.From, to = currentTerm.To, daysLeft = (int)Math.Ceiling((currentTerm.To - now).TotalDays), progressPercent = Math.Round((now - currentTerm.From).TotalDays / Math.Max(1, (currentTerm.To - currentTerm.From).TotalDays) * 100, 1) },
                holidays = calendar.Holidays.Where(h => h.Date >= localNow.Date.AddDays(-7)).Take(12).Select(h => new { h.Name, date = h.Date, daysAway = (int)Math.Round((h.Date - localNow.Date).TotalDays) }),
                nextHoliday = nextHoliday == null ? null : new { nextHoliday.Name, date = nextHoliday.Date, daysAway = (int)Math.Round((nextHoliday.Date - localNow.Date).TotalDays) },
            },
            kpis = new
            {
                currency = "LKR",
                students = activeStudents.Count,
                enrolled = enrolledNow,
                newStudents,
                lapsed,
                retentionRate = retention,
                pendingApprovals = pendingStudents.Count + pendingStaff,
                pendingStudents = pendingStudents.Count,
                pendingStaff,
                sessions = sessions.Count,
                sessionsHeld = sessions.Count(s => s.Key.StartTime <= now),
                attendanceRate,
                present = Count("present"),
                late = Count("late"),
                absent = Count("absent"),
                excused = Count("excused"),
                unmarked = marks.Count(m => m == null),
                unmarkedSessions,
                assessments = assessments.GroupBy(b => new { b.BookingTypeId, b.StartTime }).Count(),
                gradedEntries = graded.Count,
                ungradedOverdue = ungraded,
                avgScore,
                passRate,
                atRisk = atRisk.Count,
                behaviourPoints = behaviour.Sum(a => a.Points),
                incidents = behaviour.Count(a => a.Points < 0),
                commendations = behaviour.Count(a => a.Points > 0),
                teachers = teachers.Count,
                rooms = rooms.Count,
                conflicts = conflictRows.Count,
                tuitionPaid,
                tutoringFees,
                income,
                payrollHours = Math.Round(payrollHours, 1),
                payrollCost = Math.Round(payrollCost, 2),
                purchases,
                costs,
                net = income - costs,
                outstandingCount = outstanding.Count,
                outstandingAmount = outstanding.Sum(s => s.Amount),
                monthlyRecurring = currentSub.Values.Where(s => !IsLapsed(s, now)).Sum(MonthlyValue),
            },
            previous = new { attendanceRate = prevAttendance, avgScore = prevAvg, newStudents = prevNew, income = prevIncome, sessions = prevPast.GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime }).Count() },
            attendanceMix = new[] { "present", "late", "absent", "excused" }.Select(m => new { mark = m, count = Count(m) }).ToList(),
            distribution,
            trend,
            bySubject,
            byGrade,
            byGradeEnrolment,
            byTeacher,
            byRoom,
            atRisk = atRisk.Take(40).Select(s => Project(s, studentsById, currentSub, now)),
            students = studentStats.Values.OrderBy(s => s.Name).Select(s => Project(s, studentsById, currentSub, now)),
            payment,
            outstanding = outstanding.OrderBy(s => s.NextBillingAt ?? s.EndDate).Take(30).Select(s =>
            {
                studentsById.TryGetValue(s.CustomerId, out var st);
                return new { subscriptionId = s.Id, studentId = s.CustomerId, studentName = st?.FullName ?? "Student", phone = st?.Phone, plan = s.PlanName, amount = s.Amount, paymentStatus = NormalizePayment(s.PaymentStatus), nextBillingAt = s.NextBillingAt, lastPaymentAt = s.LastPaymentAt };
            }),
            pendingApprovals = pendingStudents.Take(20).Select(s => new { s.Id, s.FullName, s.Email, s.Phone, s.CreatedAt, role = "Customer" }),
            conflicts = conflictRows.Take(20),
            filterOptions = new
            {
                branches = branches.Select(b => new { id = b.Id, name = b.Name }),
                teachers = teachers.OrderBy(t => t.Name).Select(t => new { id = t.Id, name = t.Name, specialty = t.Specialty }),
                rooms = rooms.OrderBy(r => r.Name).Select(r => new { id = r.Id, name = r.Name, capacity = r.Capacity }),
                subjects = types.Select(t => new { id = t.Id, name = t.Name, kind = SchoolConfig.KindOf(t), subject = SchoolConfig.SubjectOf(t), grade = SchoolConfig.GradeOf(t) }),
                grades = types.Select(SchoolConfig.GradeOf).Where(g => g != null).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(g => g).ToList(),
            },
        });
    }

    // ── Today ───────────────────────────────────────────────────────────

    /// <summary>Today's timetable with per-session attendance state and roster (medical alerts flagged), teachers on duty, assignments due this week, pending approvals.</summary>
    [HttpGet("today")]
    public async Task<IActionResult> GetToday([FromQuery] DateTime? on, [FromQuery] Guid? branchId, [FromQuery] Guid? resourceId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(on.HasValue ? DateTimeUtil.AsUtc(on.Value) : now);
        var localNow = clock.Local(now);
        var thresholds = SchoolConfig.ThresholdsOf(await ModuleConfigAsync(tenantId, SchoolConfig.AttendanceModule));
        var calendar = SchoolConfig.CalendarOf(await ModuleConfigAsync(tenantId, SchoolConfig.SchedulingModule));

        var allToday = await LoadBookingsAsync(tenantId, dayStart, dayEnd, branchId, resourceId, null);
        var students = await StudentsFor(tenantId, allToday);
        var subs = await CurrentSubsFor(tenantId, students.Keys);
        // Room holds (booked by a teacher on a classroom) are not registers.
        var todays = allToday.Where(b => students.ContainsKey(MemberOf(b))).ToList();

        var sessions = todays.Where(b => IsLesson(b) && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected)
            .GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime })
            .Select(g =>
            {
                var first = g.First();
                var ms = g.Select(b => MarkOf(b, thresholds)).ToList();
                return new
                {
                    sessionKey = $"{g.Key.BookingTypeId:N}-{g.Key.ResourceId:N}-{g.Key.StartTime:O}",
                    bookingTypeId = g.Key.BookingTypeId,
                    name = first.BookingType.Name,
                    subject = SchoolConfig.SubjectOf(first.BookingType),
                    grade = SchoolConfig.GradeOf(first.BookingType),
                    colorHex = first.BookingType.ColorHex,
                    resourceId = g.Key.ResourceId,
                    resourceName = first.Resource.Name,
                    resourceKind = first.Resource.Category == ResourceCategory.Staff ? "teacher" : "room",
                    startTime = g.Key.StartTime,
                    endTime = first.EndTime,
                    state = g.Key.StartTime > now ? "upcoming" : first.EndTime > now ? "inProgress" : "done",
                    students = g.Count(),
                    present = ms.Count(m => m == "present"),
                    late = ms.Count(m => m == "late"),
                    absent = ms.Count(m => m == "absent"),
                    excused = ms.Count(m => m == "excused"),
                    unmarked = ms.Count(m => m == null),
                    needsMarking = g.Key.StartTime.AddMinutes(UnmarkedGraceMinutes) < now && ms.Any(m => m == null),
                    roster = g.OrderBy(b => students.TryGetValue(MemberOf(b), out var s) ? s.FullName : b.Title).Select(b =>
                    {
                        students.TryGetValue(MemberOf(b), out var st);
                        subs.TryGetValue(MemberOf(b), out var sub);
                        var att = SchoolConfig.AttendanceOf(b.FormData);
                        return new
                        {
                            bookingId = b.Id,
                            studentId = MemberOf(b),
                            studentName = st?.FullName ?? b.Title ?? "Student",
                            phone = st?.Phone,
                            mark = MarkOf(b, thresholds),
                            arrivedAt = b.CheckInAt,
                            points = att.Points,
                            note = att.Note,
                            medicalAlert = string.IsNullOrWhiteSpace(st?.MedicalNotes) ? null : st!.MedicalNotes,
                            tuitionStatus = sub == null ? "none" : IsLapsed(sub, now) ? "lapsed" : NormalizePayment(sub.PaymentStatus),
                        };
                    }),
                };
            })
            .OrderBy(s => s.startTime).ToList();

        var teachers = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value))
            .ToListAsync();
        var teacherIds = teachers.Select(t => t.Id).ToList();
        var dow = (int)clock.Local(dayStart).DayOfWeek;
        var roster = await _db.ResourceSchedules.AsNoTracking().Where(s => s.ResourceId != null && teacherIds.Contains(s.ResourceId.Value) && s.IsAvailable && s.DayOfWeek == dow).ToListAsync();
        var teachersToday = roster.Select(s =>
        {
            var t = teachers.First(x => x.Id == s.ResourceId);
            return new
            {
                resourceId = t.Id, name = t.Name, specialty = t.Specialty,
                shiftStart = s.StartTime.ToString(@"hh\:mm"), shiftEnd = s.EndTime.ToString(@"hh\:mm"),
                onDuty = s.StartTime <= localNow.TimeOfDay && localNow.TimeOfDay < s.EndTime,
                sessionsToday = sessions.Count(x => x.resourceId == t.Id),
            };
        }).OrderByDescending(t => t.onDuty).ThenBy(t => t.shiftStart).ToList();

        var horizon = now.AddDays(AssignmentHorizonDays);
        var dueSoon = await _db.Bookings.AsNoTracking().Include(b => b.BookingType).Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null && b.EndTime >= now.AddDays(-14) && b.StartTime <= horizon
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .ToListAsync();
        var assignments = dueSoon.Where(b => SchoolConfig.KindOf(b.BookingType) == SchoolConfig.Assignment)
            .GroupBy(b => new { b.BookingTypeId, b.StartTime })
            .Select(g =>
            {
                var first = g.First();
                var items = g.Select(b => SchoolConfig.AssessmentOf(b.FormData)).ToList();
                var due = items.Select(a => a.DueAt).FirstOrDefault(d => d != null) ?? first.EndTime;
                return new
                {
                    bookingTypeId = g.Key.BookingTypeId,
                    name = first.BookingType.Name,
                    subject = SchoolConfig.SubjectOf(first.BookingType),
                    grade = SchoolConfig.GradeOf(first.BookingType),
                    dueAt = due,
                    isOverdue = due < now,
                    students = g.Count(),
                    submitted = items.Count(a => a.SubmittedAt != null),
                    graded = items.Count(a => a.Score != null),
                };
            })
            .Where(a => a.dueAt >= now.AddDays(-14))
            .OrderBy(a => a.dueAt).ToList();

        var pending = await _db.Users.AsNoTracking().IgnoreQueryFilters()
            .Where(u => u.TenantId == tenantId && !u.IsApproved)
            .OrderBy(u => u.CreatedAt)
            .Select(u => new { u.Id, u.FullName, u.Email, u.Phone, role = u.Role.ToString(), u.CreatedAt })
            .Take(20).ToListAsync();

        var localDay = clock.Local(dayStart).Date;
        var holiday = calendar.Holidays.FirstOrDefault(h => h.Date.Date == localDay);

        return Ok(new
        {
            asOf = now,
            date = localDay,
            holiday = holiday == null ? null : holiday.Name,
            term = calendar.Terms.FirstOrDefault(t => t.From <= now && now <= t.To.AddDays(1))?.Name,
            summary = new
            {
                sessions = sessions.Count,
                done = sessions.Count(s => s.state == "done"),
                inProgress = sessions.Count(s => s.state == "inProgress"),
                upcoming = sessions.Count(s => s.state == "upcoming"),
                needsMarking = sessions.Count(s => s.needsMarking),
                studentsExpected = todays.Where(IsLesson).Select(MemberOf).Distinct().Count(),
                presentSoFar = sessions.Sum(s => s.present + s.late),
                absentSoFar = sessions.Sum(s => s.absent),
                medicalAlerts = sessions.SelectMany(s => s.roster).Where(r => r.medicalAlert != null).Select(r => r.studentId).Distinct().Count(),
            },
            sessions,
            teachers = new { rostered = teachersToday.Count, onDuty = teachersToday.Count(t => t.onDuty), list = teachersToday },
            assignments,
            pendingApprovals = pending,
        });
    }

    // ── Students ────────────────────────────────────────────────────────

    /// <summary>One student's progress: per-subject attendance and average, every assessment with its score, attendance history and behaviour notes.</summary>
    [HttpGet("students/{id:guid}")]
    public async Task<IActionResult> GetStudent(Guid id, [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var now = DateTime.UtcNow;
        var thresholds = SchoolConfig.ThresholdsOf(await ModuleConfigAsync(tenantId, SchoolConfig.AttendanceModule));

        var student = await _db.Users.AsNoTracking().IgnoreQueryFilters()
            .Where(u => u.TenantId == tenantId && u.Id == id && u.Role == UserRole.Customer)
            .Select(u => new { u.Id, u.FullName, u.Email, u.Phone, u.Address, u.MedicalNotes, u.CreatedAt, u.IsApproved, u.DateOfBirth })
            .FirstOrDefaultAsync();
        if (student == null) return NotFound();

        var bookings = (await _db.Bookings.AsNoTracking().Include(b => b.Resource).Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null && b.StartTime >= start && b.StartTime < endExclusive && (b.BookedFor == id || (b.BookedFor == null && b.BookedBy == id)))
            .OrderBy(b => b.StartTime).ToListAsync());
        var stats = StudentStats(bookings, thresholds, now).Values.FirstOrDefault();
        var sub = (await _db.Subscriptions.AsNoTracking().Where(s => s.TenantId == tenantId && s.CustomerId == id).ToListAsync()).OrderByDescending(s => s.EndDate).FirstOrDefault();

        var perSubject = bookings.GroupBy(b => b.BookingTypeId).Select(g =>
        {
            var type = g.First().BookingType;
            var pm = g.Where(b => IsLesson(b) && b.StartTime <= now).Select(b => MarkOf(b, thresholds)).Where(m => m != null).ToList();
            var gr = g.Where(IsAssessment).Select(b => SchoolConfig.AssessmentOf(b.FormData)).Where(a => a.Score.HasValue).ToList();
            return new
            {
                bookingTypeId = g.Key, name = type.Name, subject = SchoolConfig.SubjectOf(type), grade = SchoolConfig.GradeOf(type), kind = SchoolConfig.KindOf(type), colorHex = type.ColorHex,
                sessions = g.Count(IsLesson), attended = pm.Count(m => m is "present" or "late"), marked = pm.Count,
                attendanceRate = pm.Count > 0 ? Math.Round(pm.Count(m => m is "present" or "late") / (double)pm.Count * 100, 1) : (double?)null,
                avgScore = gr.Count > 0 ? Math.Round(gr.Average(a => a.Score!.Value / a.MaxScore * 100), 1) : (double?)null,
                letter = gr.Count > 0 ? SchoolConfig.LetterOf(gr.Average(a => a.Score!.Value / a.MaxScore * 100), thresholds.Scale) : null,
            };
        }).OrderBy(x => x.name).ToList();

        var assessments = bookings.Where(IsAssessment).Select(b =>
        {
            var a = SchoolConfig.AssessmentOf(b.FormData);
            return new
            {
                bookingId = b.Id, name = b.BookingType.Name, subject = SchoolConfig.SubjectOf(b.BookingType), kind = SchoolConfig.KindOf(b.BookingType), colorHex = b.BookingType.ColorHex,
                date = b.StartTime, dueAt = a.DueAt ?? b.EndTime, submittedAt = a.SubmittedAt, score = a.Score, maxScore = a.MaxScore,
                percent = a.Score.HasValue ? Math.Round(a.Score.Value / a.MaxScore * 100, 1) : (double?)null,
                letter = a.Score.HasValue ? SchoolConfig.LetterOf(a.Score.Value / a.MaxScore * 100, thresholds.Scale) : null,
                weight = SchoolConfig.WeightOf(b.BookingType), feedback = a.Feedback,
            };
        }).ToList();

        var attendance = bookings.Where(b => IsLesson(b) && b.StartTime <= now).Select(b =>
        {
            var att = SchoolConfig.AttendanceOf(b.FormData);
            return new { bookingId = b.Id, date = b.StartTime, name = b.BookingType.Name, teacher = b.Resource.Name, mark = MarkOf(b, thresholds), arrivedAt = b.CheckInAt, points = att.Points, note = att.Note };
        }).ToList();

        return Ok(new
        {
            asOf = now,
            student = new { student.Id, student.FullName, student.Email, student.Phone, student.Address, medicalNotes = student.MedicalNotes, joinedAt = student.CreatedAt, student.IsApproved, student.DateOfBirth },
            tuition = sub == null ? null : new { plan = sub.PlanName, amount = sub.Amount, status = IsLapsed(sub, now) ? "lapsed" : NormalizeStatus(sub.Status), paymentStatus = NormalizePayment(sub.PaymentStatus), endDate = sub.EndDate },
            summary = stats == null ? null : new { stats.AttendanceRate, stats.AvgScore, letter = stats.AvgScore.HasValue ? SchoolConfig.LetterOf(stats.AvgScore.Value, thresholds.Scale) : null, stats.Points, stats.Incidents, stats.Commendations, stats.AtRisk, stats.Reasons, stats.SessionsMarked, stats.Attended },
            perSubject,
            assessments,
            attendance,
            behaviour = attendance.Where(a => a.points != 0 || !string.IsNullOrWhiteSpace(a.note)).OrderByDescending(a => a.date).ToList(),
        });
    }

    // ── Gradebook ───────────────────────────────────────────────────────

    /// <summary>The gradebook: every exam / assignment in the range with one row per student (score, submission, feedback), newest first.</summary>
    [HttpGet("gradebook")]
    public async Task<IActionResult> GetGradebook([FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? branchId, [FromQuery] Guid? bookingTypeId, [FromQuery] string? grade, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var now = DateTime.UtcNow;
        var thresholds = SchoolConfig.ThresholdsOf(await ModuleConfigAsync(tenantId, SchoolConfig.AttendanceModule));

        // Assignments are keyed by their due date, which can sit after the
        // range's end while the work was set inside it - widen the load.
        var bookings = (await LoadBookingsAsync(tenantId, start.AddDays(-30), endExclusive.AddDays(30), branchId, null, bookingTypeId))
            .Where(b => IsAssessment(b) && b.Status != BookingStatus.Rejected && b.Status != BookingStatus.Cancelled).ToList();
        if (!string.IsNullOrWhiteSpace(grade)) bookings = bookings.Where(b => string.Equals(SchoolConfig.GradeOf(b.BookingType), grade.Trim(), StringComparison.OrdinalIgnoreCase)).ToList();
        var students = await StudentsFor(tenantId, bookings);
        bookings = bookings.Where(b => students.ContainsKey(MemberOf(b))).ToList();

        var assessments = bookings.GroupBy(b => new { b.BookingTypeId, b.StartTime })
            .Select(g =>
            {
                var first = g.First();
                var rows = g.Select(b =>
                {
                    var a = SchoolConfig.AssessmentOf(b.FormData);
                    students.TryGetValue(MemberOf(b), out var st);
                    return new
                    {
                        bookingId = b.Id, studentId = MemberOf(b), studentName = st?.FullName ?? b.Title ?? "Student",
                        score = a.Score, maxScore = a.MaxScore, percent = a.Score.HasValue ? Math.Round(a.Score.Value / a.MaxScore * 100, 1) : (double?)null,
                        letter = a.Score.HasValue ? SchoolConfig.LetterOf(a.Score.Value / a.MaxScore * 100, thresholds.Scale) : null,
                        submittedAt = a.SubmittedAt, feedback = a.Feedback,
                    };
                }).OrderBy(r => r.studentName).ToList();
                var due = g.Select(b => SchoolConfig.AssessmentOf(b.FormData).DueAt).FirstOrDefault(d => d != null) ?? first.EndTime;
                var scored = rows.Where(r => r.percent.HasValue).Select(r => r.percent!.Value).ToList();
                return new
                {
                    key = $"{g.Key.BookingTypeId:N}-{g.Key.StartTime:O}",
                    bookingTypeId = g.Key.BookingTypeId,
                    name = first.BookingType.Name,
                    subject = SchoolConfig.SubjectOf(first.BookingType),
                    grade = SchoolConfig.GradeOf(first.BookingType),
                    kind = SchoolConfig.KindOf(first.BookingType),
                    colorHex = first.BookingType.ColorHex,
                    weight = SchoolConfig.WeightOf(first.BookingType),
                    date = g.Key.StartTime,
                    dueAt = due,
                    isOverdue = due < now && rows.Any(r => r.score == null),
                    students = rows.Count,
                    submitted = rows.Count(r => r.submittedAt != null),
                    graded = scored.Count,
                    avgPercent = scored.Count > 0 ? Math.Round(scored.Average(), 1) : (double?)null,
                    maxScore = rows.Select(r => r.maxScore).DefaultIfEmpty(100).Max(),
                    rows,
                };
            })
            .Where(a => a.date >= start && a.date < endExclusive || (a.dueAt >= start && a.dueAt < endExclusive))
            .OrderByDescending(a => a.date).ToList();

        return Ok(new { asOf = now, from = clock.Local(start).Date, to = clock.Local(endExclusive).Date.AddDays(-1), scale = thresholds.Scale.Select(x => new { x.Grade, x.Min }), assessments });
    }

    // ── Alerts ──────────────────────────────────────────────────────────

    /// <summary>Operational alerts: at-risk students, sessions not yet marked, overdue ungraded work, unpaid tuition, pending approvals, timetable conflicts, no teacher on duty, holiday tomorrow.</summary>
    [HttpGet("alerts")]
    public async Task<IActionResult> GetAlerts([FromQuery] Guid? branchId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(now);
        var localNow = clock.Local(now);
        var thresholds = SchoolConfig.ThresholdsOf(await ModuleConfigAsync(tenantId, SchoolConfig.AttendanceModule));
        var calendar = SchoolConfig.CalendarOf(await ModuleConfigAsync(tenantId, SchoolConfig.SchedulingModule));
        var alerts = new List<object>();

        var customerIds = (await _db.Users.AsNoTracking().IgnoreQueryFilters().Where(u => u.TenantId == tenantId && u.Role == UserRole.Customer).Select(u => u.Id).ToListAsync()).ToHashSet();
        var last30All = await LoadBookingsAsync(tenantId, now.AddDays(-30), now.AddDays(1), branchId, null, null);
        var last30 = last30All.Where(b => customerIds.Contains(MemberOf(b))).ToList();
        var stats = StudentStats(last30, thresholds, now).Values.Where(s => s.AtRisk).ToList();
        if (stats.Count > 0)
        {
            alerts.Add(Alert("students-at-risk", stats.Count >= 5 ? "critical" : "warning", "students",
                $"{stats.Count} student{(stats.Count == 1 ? "" : "s")} below the at-risk thresholds (last 30 days)",
                $"Attendance under {thresholds.AtRiskAttendancePercent}% or average under {thresholds.AtRiskGradePercent}%: {string.Join(", ", stats.Take(3).Select(s => s.Name))}{(stats.Count > 3 ? "…" : "")}", stats.Count, "/dashboard#students"));
        }

        var todays = last30.Where(b => b.StartTime >= dayStart && b.StartTime < dayEnd).ToList();
        var unmarked = todays.Where(b => IsLesson(b) && b.Status != BookingStatus.Cancelled && b.StartTime.AddMinutes(UnmarkedGraceMinutes) < now && MarkOf(b, thresholds) == null)
            .GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime }).ToList();
        if (unmarked.Count > 0)
        {
            alerts.Add(Alert("attendance-unmarked", "warning", "attendance",
                $"{unmarked.Count} session{(unmarked.Count == 1 ? "" : "s")} today without attendance marked",
                string.Join(", ", unmarked.Take(3).Select(g => $"{g.First().BookingType.Name} {clock.Local(g.Key.StartTime):HH:mm}")) + ". Mark the register from the timetable.", unmarked.Count, "/dashboard#timetable"));
        }

        var ungraded = last30.Where(b => IsAssessment(b) && b.Status != BookingStatus.Cancelled)
            .Select(b => (b, a: SchoolConfig.AssessmentOf(b.FormData)))
            .Where(x => x.a.Score == null && (x.a.DueAt ?? x.b.EndTime) < now.AddDays(-2))
            .GroupBy(x => new { x.b.BookingTypeId, x.b.StartTime }).ToList();
        if (ungraded.Count > 0)
        {
            var entries = ungraded.Sum(g => g.Count());
            alerts.Add(Alert("grading-overdue", "warning", "gradebook",
                $"{entries} submission{(entries == 1 ? "" : "s")} across {ungraded.Count} assessment{(ungraded.Count == 1 ? "" : "s")} waiting over 2 days for a grade",
                string.Join(", ", ungraded.Take(3).Select(g => g.First().b.BookingType.Name)) + ". Enter marks in the gradebook.", entries, "/dashboard#gradebook"));
        }

        var subs = await _db.Subscriptions.AsNoTracking().Where(s => s.TenantId == tenantId && (!branchId.HasValue || s.BranchId == branchId.Value || s.BranchId == null)).ToListAsync();
        var current = subs.GroupBy(s => s.CustomerId).Select(g => g.OrderByDescending(s => s.EndDate).First()).ToList();
        var unpaid = current.Where(s => !IsLapsed(s, now) && NormalizePayment(s.PaymentStatus) != "Paid").ToList();
        if (unpaid.Count > 0)
        {
            var overdue = unpaid.Count(s => NormalizePayment(s.PaymentStatus) is "Overdue" or "Failed");
            alerts.Add(Alert("tuition-unpaid", overdue > 0 ? "critical" : "warning", "billing",
                $"{unpaid.Count} tuition invoice{(unpaid.Count == 1 ? "" : "s")} not settled",
                $"{overdue} overdue or failed, LKR {unpaid.Sum(s => s.Amount):N0} outstanding. Send reminders from the tuition panel.", unpaid.Count, "/dashboard#tuition"));
        }
        var lapsedAttending = todays.Where(b => IsLesson(b)).Select(MemberOf).Distinct()
            .Count(id => current.FirstOrDefault(s => s.CustomerId == id) is { } s && IsLapsed(s, now));
        if (lapsedAttending > 0)
        {
            alerts.Add(Alert("tuition-lapsed", "info", "billing",
                $"{lapsedAttending} student{(lapsedAttending == 1 ? "" : "s")} on today's registers with lapsed tuition",
                "Enrolment has ended but they are still timetabled. Renew or remove them from the class.", lapsedAttending, "/dashboard#tuition"));
        }

        var pending = await _db.Users.AsNoTracking().IgnoreQueryFilters().CountAsync(u => u.TenantId == tenantId && !u.IsApproved);
        if (pending > 0)
        {
            alerts.Add(Alert("approvals-pending", "info", "users",
                $"{pending} registration{(pending == 1 ? "" : "s")} waiting for approval",
                "New students or staff cannot sign in until approved. Review them under Users.", pending, "/dashboard#approvals"));
        }

        var week = await LoadBookingsAsync(tenantId, dayStart, dayStart.AddDays(7), branchId, null, null);
        // Clashes are checked on every resource - teachers and rooms alike.
        var sessions = week.Where(b => IsLesson(b) && b.Status != BookingStatus.Cancelled).GroupBy(b => new { b.ResourceId, b.BookingTypeId, b.StartTime })
            .Select(g => new { g.Key.ResourceId, g.Key.StartTime, EndTime = g.First().EndTime, Name = g.First().BookingType.Name, Resource = g.First().Resource.Name }).OrderBy(s => s.StartTime).ToList();
        var conflicts = 0; string? example = null;
        for (var i = 0; i < sessions.Count; i++)
            for (var j = i + 1; j < sessions.Count; j++)
                if (sessions[i].ResourceId == sessions[j].ResourceId && sessions[j].StartTime < sessions[i].EndTime)
                {
                    conflicts++;
                    example ??= $"{sessions[i].Resource}: {sessions[i].Name} and {sessions[j].Name} at {clock.Local(sessions[j].StartTime):ddd HH:mm}";
                }
        if (conflicts > 0)
        {
            alerts.Add(Alert("timetable-conflicts", "critical", "scheduling",
                $"{conflicts} timetable clash{(conflicts == 1 ? "" : "es")} in the next 7 days",
                $"{example}. Move one of the sessions to another room or teacher.", conflicts, "/dashboard#calendar"));
        }

        var teachers = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value))
            .Select(r => r.Id).ToListAsync();
        var inProgress = todays.Count(b => IsLesson(b) && b.StartTime <= now && b.EndTime > now);
        if (inProgress > 0 && teachers.Count > 0)
        {
            var onDuty = await _db.ResourceSchedules.AsNoTracking().CountAsync(s => s.ResourceId != null && teachers.Contains(s.ResourceId.Value) && s.IsAvailable
                && s.DayOfWeek == (int)localNow.DayOfWeek && s.StartTime <= localNow.TimeOfDay && localNow.TimeOfDay < s.EndTime);
            if (onDuty == 0)
                alerts.Add(Alert("teachers-none", "info", "staff", "Classes are running but no teacher is rostered right now", "The roster (Resources > staff schedules) has no shift covering this hour.", inProgress, "/resources"));
        }

        var tomorrow = calendar.Holidays.FirstOrDefault(h => h.Date.Date == localNow.Date.AddDays(1));
        if (tomorrow != null)
        {
            var scheduled = week.Count(b => IsLesson(b) && customerIds.Contains(MemberOf(b)) && clock.Local(b.StartTime).Date == localNow.Date.AddDays(1) && b.Status != BookingStatus.Cancelled);
            alerts.Add(Alert("holiday-tomorrow", scheduled > 0 ? "warning" : "info", "calendar",
                $"Tomorrow is a holiday: {tomorrow.Name}",
                scheduled > 0 ? $"{scheduled} student session{(scheduled == 1 ? "" : "s")} still timetabled - cancel or move them." : "Nothing timetabled.", scheduled, "/dashboard#calendar"));
        }

        return Ok(new { asOf = now, alerts });
    }

    // ── Actions: attendance and grades ──────────────────────────────────

    public sealed record MarkAttendanceDto(Guid BookingId, string Mark, int? Points, string? Note);

    /// <summary>Marks one student's attendance on a session (present / late / absent / excused), optionally with behaviour points and a note.</summary>
    [HttpPost("attendance")]
    public async Task<IActionResult> MarkAttendance([FromBody] MarkAttendanceDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var mark = dto.Mark?.Trim().ToLowerInvariant();
        if (mark is not ("present" or "late" or "absent" or "excused")) return BadRequest(new { message = "mark must be present, late, absent or excused." });

        var booking = await _db.Bookings.FirstOrDefaultAsync(b => b.Id == dto.BookingId && b.TenantId == tenantId && b.DeletedAt == null);
        if (booking == null) return NotFound();

        var now = DateTime.UtcNow;
        booking.FormData = SchoolConfig.Merge(booking.FormData, new Dictionary<string, object?>
        {
            ["attendance"] = mark,
            ["points"] = dto.Points,
            ["note"] = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim(),
            ["markedAt"] = now,
        });
        switch (mark)
        {
            case "present" or "late":
                booking.Status = booking.EndTime <= now ? BookingStatus.Completed : BookingStatus.CheckedIn;
                booking.CheckInAt ??= now;
                break;
            case "absent":
                booking.Status = BookingStatus.NoShow;
                break;
            case "excused":
                booking.Status = BookingStatus.Cancelled;
                booking.CancellationReason ??= "Excused absence";
                break;
        }
        booking.UpdatedAt = now;
        await _db.SaveChangesAsync();
        return Ok(new { booking.Id, mark, booking.Status, booking.CheckInAt });
    }

    public sealed record GradeDto(Guid BookingId, double? Score, double? MaxScore, string? Feedback, DateTime? SubmittedAt);

    /// <summary>Enters or clears a score (and feedback) on a student's exam / assignment booking.</summary>
    [HttpPost("grade")]
    public async Task<IActionResult> Grade([FromBody] GradeDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var booking = await _db.Bookings.Include(b => b.BookingType).FirstOrDefaultAsync(b => b.Id == dto.BookingId && b.TenantId == tenantId && b.DeletedAt == null);
        if (booking == null) return NotFound();
        if (!IsAssessment(booking)) return BadRequest(new { message = "Only exam / assignment bookings take a grade." });
        var max = dto.MaxScore is > 0 ? dto.MaxScore.Value : SchoolConfig.AssessmentOf(booking.FormData).MaxScore;
        if (dto.Score is < 0 || dto.Score > max) return BadRequest(new { message = $"score must be between 0 and {max}." });

        var now = DateTime.UtcNow;
        booking.FormData = SchoolConfig.Merge(booking.FormData, new Dictionary<string, object?>
        {
            ["score"] = dto.Score,
            ["maxScore"] = max,
            ["feedback"] = string.IsNullOrWhiteSpace(dto.Feedback) ? null : dto.Feedback.Trim(),
            ["submittedAt"] = dto.SubmittedAt ?? SchoolConfig.AssessmentOf(booking.FormData).SubmittedAt ?? (dto.Score.HasValue ? now : null),
            ["gradedAt"] = dto.Score.HasValue ? now : null,
        });
        if (dto.Score.HasValue && booking.Status != BookingStatus.Completed) { booking.Status = BookingStatus.Completed; booking.CheckOutAt ??= now; }
        booking.UpdatedAt = now;
        await _db.SaveChangesAsync();
        return Ok(new { booking.Id, score = dto.Score, maxScore = max, percent = dto.Score.HasValue ? Math.Round(dto.Score.Value / max * 100, 1) : (double?)null });
    }

    public sealed record ApproveDto(Guid UserId, string? Role);

    /// <summary>Approves a pending registration - a student as-is, or a staff member with the role to assign. UsersController's approve is staff-only, so this covers students too.</summary>
    [HttpPost("approve")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Approve([FromBody] ApproveDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var user = await _db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(u => u.Id == dto.UserId && u.TenantId == tenantId && !u.IsApproved);
        if (user == null) return NotFound();
        if (user.Role != UserRole.Customer)
        {
            if (!User.IsInRole(UserRole.Admin.ToString())) return Forbid();
            if (!string.IsNullOrWhiteSpace(dto.Role))
            {
                if (!Enum.TryParse<UserRole>(dto.Role, true, out var role) || role == UserRole.Customer) return BadRequest(new { message = "Role must be Admin, Manager or Staff." });
                user.Role = role;
            }
        }
        user.IsApproved = true;
        user.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { user.Id, user.FullName, role = user.Role.ToString(), user.IsApproved });
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private sealed record StudentRow(Guid Id, string FullName, string Phone, string Email, DateTime CreatedAt, bool IsActive, bool IsApproved, string? MedicalNotes);

    private sealed class StudentStat
    {
        public Guid Id; public string Name = ""; public string? Grade;
        public int SessionsMarked; public int Attended; public int Late; public int Absent; public int Excused;
        public double? AttendanceRate; public double? AvgScore; public int Graded; public int Points; public int Incidents; public int Commendations;
        public DateTime? LastSeen; public bool AtRisk; public List<string> Reasons = new();
    }

    private static Dictionary<Guid, StudentStat> StudentStats(List<Booking> bookings, SchoolConfig.Thresholds t, DateTime now)
    {
        var result = new Dictionary<Guid, StudentStat>();
        foreach (var g in bookings.Where(b => b.Status != BookingStatus.Rejected).GroupBy(MemberOf))
        {
            var s = new StudentStat { Id = g.Key, Name = g.First().Title?.Split(" - ").LastOrDefault() ?? "Student" };
            var grades = g.Select(b => SchoolConfig.GradeOf(b.BookingType)).Where(x => x != null).GroupBy(x => x).OrderByDescending(x => x.Count()).FirstOrDefault();
            s.Grade = grades?.Key;
            var marks = g.Where(b => IsLesson(b) && b.StartTime <= now && b.Status != BookingStatus.Rejected).Select(b => (b, m: MarkOf(b, t))).Where(x => x.m != null).ToList();
            s.SessionsMarked = marks.Count;
            s.Attended = marks.Count(x => x.m is "present" or "late");
            s.Late = marks.Count(x => x.m == "late");
            s.Absent = marks.Count(x => x.m == "absent");
            s.Excused = marks.Count(x => x.m == "excused");
            var counted = marks.Count(x => x.m != "excused");
            s.AttendanceRate = counted > 0 ? Math.Round(marks.Count(x => x.m is "present" or "late") / (double)counted * 100, 1) : null;
            s.LastSeen = marks.Where(x => x.m is "present" or "late").Select(x => x.b.CheckInAt ?? x.b.StartTime).DefaultIfEmpty().Max();
            if (s.LastSeen == default) s.LastSeen = null;
            var graded = g.Where(IsAssessment).Select(b => SchoolConfig.AssessmentOf(b.FormData)).Where(a => a.Score.HasValue).ToList();
            s.Graded = graded.Count;
            s.AvgScore = graded.Count > 0 ? Math.Round(graded.Average(a => a.Score!.Value / a.MaxScore * 100), 1) : null;
            var att = g.Where(IsLesson).Select(b => SchoolConfig.AttendanceOf(b.FormData)).ToList();
            s.Points = att.Sum(a => a.Points);
            s.Incidents = att.Count(a => a.Points < 0);
            s.Commendations = att.Count(a => a.Points > 0);
            if (s.AttendanceRate.HasValue && counted >= 3 && s.AttendanceRate < t.AtRiskAttendancePercent) s.Reasons.Add($"attendance {s.AttendanceRate}%");
            if (s.AvgScore.HasValue && s.AvgScore < t.AtRiskGradePercent) s.Reasons.Add($"average {s.AvgScore}%");
            if (s.Incidents >= 3) s.Reasons.Add($"{s.Incidents} incidents");
            s.AtRisk = s.Reasons.Count > 0;
            result[g.Key] = s;
        }
        return result;
    }

    private static object Project(StudentStat s, Dictionary<Guid, StudentRow> students, Dictionary<Guid, Subscription> subs, DateTime now)
    {
        students.TryGetValue(s.Id, out var st);
        subs.TryGetValue(s.Id, out var sub);
        return new
        {
            studentId = s.Id, name = st?.FullName ?? s.Name, phone = st?.Phone, grade = s.Grade ?? GradeFromPlan(sub?.PlanName),
            sessionsMarked = s.SessionsMarked, attended = s.Attended, late = s.Late, absent = s.Absent, excused = s.Excused,
            attendanceRate = s.AttendanceRate, avgScore = s.AvgScore, graded = s.Graded, points = s.Points, incidents = s.Incidents, commendations = s.Commendations,
            lastSeen = s.LastSeen, atRisk = s.AtRisk, reasons = s.Reasons,
            medicalAlert = !string.IsNullOrWhiteSpace(st?.MedicalNotes),
            tuitionStatus = sub == null ? "none" : IsLapsed(sub, now) ? "lapsed" : NormalizePayment(sub.PaymentStatus),
        };
    }

    private async Task<string?> ModuleConfigAsync(Guid tenantId, string module) =>
        await _db.TenantModules.AsNoTracking().Where(m => m.TenantId == tenantId && m.ModuleName == module).Select(m => m.ConfigJson).FirstOrDefaultAsync();

    private async Task<List<Booking>> LoadBookingsAsync(Guid tenantId, DateTime start, DateTime endExclusive, Guid? branchId, Guid? resourceId, Guid? bookingTypeId)
    {
        var query = _db.Bookings.AsNoTracking().Include(b => b.Resource).ThenInclude(r => r.Branch).Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null && b.StartTime >= start && b.StartTime < endExclusive);
        if (branchId.HasValue) query = query.Where(b => b.Resource.BranchId == branchId.Value);
        if (resourceId.HasValue) query = query.Where(b => b.ResourceId == resourceId.Value);
        if (bookingTypeId.HasValue) query = query.Where(b => b.BookingTypeId == bookingTypeId.Value);
        return await query.ToListAsync();
    }

    private async Task<Dictionary<Guid, StudentRow>> StudentsFor(Guid tenantId, IEnumerable<Booking> bookings)
    {
        var ids = bookings.Select(MemberOf).Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, StudentRow>();
        return await _db.Users.AsNoTracking().IgnoreQueryFilters().Where(u => u.TenantId == tenantId && ids.Contains(u.Id) && u.Role == UserRole.Customer)
            .Select(u => new StudentRow(u.Id, u.FullName, u.Phone, u.Email, u.CreatedAt, u.IsActive, u.IsApproved, u.MedicalNotes)).ToDictionaryAsync(s => s.Id);
    }

    private async Task<Dictionary<Guid, Subscription>> CurrentSubsFor(Guid tenantId, IEnumerable<Guid> ids)
    {
        var list = ids.Distinct().ToList();
        if (list.Count == 0) return new Dictionary<Guid, Subscription>();
        var subs = await _db.Subscriptions.AsNoTracking().Where(s => s.TenantId == tenantId && list.Contains(s.CustomerId)).ToListAsync();
        return subs.GroupBy(s => s.CustomerId).ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.EndDate).First());
    }

    private static Guid MemberOf(Booking b) => b.BookedFor ?? b.BookedBy;
    private static bool IsLesson(Booking b) => SchoolConfig.KindOf(b.BookingType) is SchoolConfig.Lesson or SchoolConfig.Tutoring;
    private static bool IsAssessment(Booking b) => SchoolConfig.KindOf(b.BookingType) is SchoolConfig.Exam or SchoolConfig.Assignment;

    /// The attendance mark: explicit in FormData when marked from the
    /// dashboard, otherwise derived from the status a scanner or the
    /// mobile app left (checked in = present, and late past the grace).
    private static string? MarkOf(Booking b, SchoolConfig.Thresholds t)
    {
        var att = SchoolConfig.AttendanceOf(b.FormData);
        if (att.Mark != null) return att.Mark;
        return b.Status switch
        {
            BookingStatus.NoShow => "absent",
            BookingStatus.Cancelled or BookingStatus.WeatherCancelled => "excused",
            BookingStatus.CheckedIn or BookingStatus.InProgress or BookingStatus.Completed when b.CheckInAt != null =>
                (b.CheckInAt.Value - b.StartTime).TotalMinutes > t.LateAfterMinutes ? "late" : "present",
            BookingStatus.Completed => "present",
            _ => null,
        };
    }

    private static string? GradeFromPlan(string? plan)
    {
        if (string.IsNullOrWhiteSpace(plan)) return null;
        var m = System.Text.RegularExpressions.Regex.Match(plan, @"(Grade|Year)\s*\d+", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return m.Success ? m.Value : null;
    }

    private static bool IsLapsed(Subscription s, DateTime now) => s.EndDate < now || s.Status.Equals("Expired", StringComparison.OrdinalIgnoreCase) || s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase);
    private static string NormalizeStatus(string status) => status.Trim().ToLowerInvariant() switch { "frozen" or "paused" => "frozen", "cancelled" or "canceled" => "cancelled", "expired" => "expired", _ => "active" };
    private static string NormalizePayment(string? status) => (status ?? "Paid").Trim().ToLowerInvariant() switch { "pending" => "Pending", "failed" or "declined" => "Failed", "overdue" or "unpaid" => "Overdue", _ => "Paid" };
    private static int PaymentOrder(string s) => s switch { "Paid" => 0, "Pending" => 1, "Failed" => 2, _ => 3 };
    private static DateTime PaidAt(Subscription s) => s.LastPaymentAt ?? s.StartDate;
    private static decimal MonthlyValue(Subscription s) => s.BillingCycle.Trim().ToLowerInvariant() switch
    {
        "yearly" or "annual" => Math.Round(s.Amount / 12, 2), "quarterly" or "term" or "termly" => Math.Round(s.Amount / 3, 2), "oneoff" or "one-off" => 0m, _ => s.Amount,
    };

    private static (double hours, decimal cost) PayrollOver(List<Resource> staff, List<ResourceSchedule> roster, DateTime firstDay, int days)
    {
        double hours = 0; decimal cost = 0;
        var byStaff = roster.GroupBy(s => s.ResourceId!.Value).ToDictionary(g => g.Key, g => g.ToList());
        for (var d = 0; d < days; d++)
        {
            var dow = (int)firstDay.AddDays(d).DayOfWeek;
            foreach (var member in staff)
            {
                if (!byStaff.TryGetValue(member.Id, out var rows)) continue;
                foreach (var s in rows.Where(s => s.DayOfWeek == dow))
                {
                    var h = Math.Max(0, (s.EndTime - s.StartTime).TotalHours);
                    if (s.LunchBreakStart.HasValue && s.LunchBreakEnd.HasValue && s.LunchBreakEnd > s.LunchBreakStart) h -= (s.LunchBreakEnd.Value - s.LunchBreakStart.Value).TotalHours;
                    hours += Math.Max(0, h);
                    cost += (decimal)Math.Max(0, h) * (member.HourlyRate ?? 0m);
                }
            }
        }
        return (hours, cost);
    }

    private static object Alert(string id, string severity, string category, string title, string detail, int count, string href) =>
        new { id, severity, category, title, detail, count, href };

    private static string NormalizeGroupBy(string? groupBy) => (groupBy ?? "day").Trim().ToLowerInvariant() switch
    {
        "week" or "weekly" => "week", "month" or "monthly" => "month", _ => "day",
    };

    private static List<object> BuildTrend(List<Booking> bookings, List<Subscription> subs, List<StudentRow> students, LocalClock clock, DateTime start, DateTime endExclusive, string grouping, SchoolConfig.Thresholds t, DateTime now)
    {
        static DateTime BucketStart(DateTime local, string g) => g switch
        {
            "week" => local.Date.AddDays(-(((int)local.DayOfWeek + 6) % 7)), "month" => new DateTime(local.Year, local.Month, 1), _ => local.Date,
        };
        static DateTime NextBucket(DateTime d, string g) => g switch { "week" => d.AddDays(7), "month" => d.AddMonths(1), _ => d.AddDays(1) };
        static string Label(DateTime d, string g) => g switch
        {
            "week" => "Wk of " + d.ToString("dd MMM", CultureInfo.InvariantCulture), "month" => d.ToString("MMM yyyy", CultureInfo.InvariantCulture), _ => d.ToString("dd MMM", CultureInfo.InvariantCulture),
        };
        var lessons = bookings.Where(b => IsLesson(b) && b.StartTime <= now).GroupBy(b => BucketStart(clock.Local(b.StartTime), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var graded = bookings.Where(IsAssessment).Select(b => (b, a: SchoolConfig.AssessmentOf(b.FormData))).Where(x => x.a.Score.HasValue).GroupBy(x => BucketStart(clock.Local(x.b.StartTime), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var joined = students.Where(s => s.IsApproved).GroupBy(s => BucketStart(clock.Local(s.CreatedAt), grouping)).ToDictionary(g => g.Key, g => g.Count());
        var paid = subs.Where(s => NormalizePayment(s.PaymentStatus) == "Paid").GroupBy(s => BucketStart(clock.Local(PaidAt(s)), grouping)).ToDictionary(g => g.Key, g => g.Sum(s => s.Amount));

        var result = new List<object>();
        var localEnd = clock.Local(endExclusive);
        for (var cursor = BucketStart(clock.Local(start), grouping); cursor < localEnd && result.Count < 800; cursor = NextBucket(cursor, grouping))
        {
            lessons.TryGetValue(cursor, out var l); l ??= new List<Booking>();
            graded.TryGetValue(cursor, out var g); g ??= new List<(Booking, SchoolConfig.Assessment)>();
            var marks = l.Select(b => MarkOf(b, t)).Where(m => m != null).ToList();
            result.Add(new
            {
                bucket = cursor.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                label = Label(cursor, grouping),
                sessions = l.GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime }).Count(),
                attendanceRate = marks.Count > 0 ? Math.Round(marks.Count(m => m is "present" or "late") / (double)marks.Count * 100, 1) : (double?)null,
                absences = marks.Count(m => m == "absent"),
                avgScore = g.Count > 0 ? Math.Round(g.Average(x => x.a.Score!.Value / x.a.MaxScore * 100), 1) : (double?)null,
                newStudents = joined.TryGetValue(cursor, out var n) ? n : 0,
                tuitionPaid = paid.TryGetValue(cursor, out var p) ? p : 0m,
            });
        }
        return result;
    }

    private sealed class LocalClock
    {
        private readonly TimeSpan _offset;
        public LocalClock(int tzMinutes) { _offset = TimeSpan.FromMinutes(Math.Clamp(tzMinutes, -14 * 60, 14 * 60)); }
        public DateTime Local(DateTime utc) => DateTime.SpecifyKind(utc + _offset, DateTimeKind.Unspecified);
        public DateTime Utc(DateTime local) => DateTime.SpecifyKind(local - _offset, DateTimeKind.Utc);
        public (DateTime start, DateTime endExclusive) Day(DateTime utc) { var day = Local(utc).Date; return (Utc(day), Utc(day.AddDays(1))); }
        public (DateTime start, DateTime endExclusive) Range(DateTime? from, DateTime? to)
        {
            var today = Local(DateTime.UtcNow).Date;
            var start = (from ?? today.AddDays(-29)).Date;
            var end = (to ?? today).Date;
            if (end < start) (start, end) = (end, start);
            if ((end - start).TotalDays > 731) start = end.AddDays(-731);
            return (Utc(start), Utc(end.AddDays(1)));
        }
    }

    private bool TryTenant(out Guid tenantId) => Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private Guid? ResolveBranchScope(Guid? requested)
    {
        if (User.IsInRole(UserRole.Admin.ToString()) || requested.HasValue) return requested;
        return Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId) ? branchId : null;
    }
}
