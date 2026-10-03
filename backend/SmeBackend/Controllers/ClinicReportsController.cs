using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The reporting half of the clinic operations dashboard: headline KPIs and
/// breakdowns (overview), today's patient flow (flow), operational alerts
/// (alerts) and the reminder / follow-up worklist (reminders).
///
/// A separate controller from ReportsController for the same reason
/// ExcursionReportsController is: ReportsController authorizes through the
/// Inventory module's policies, which say nothing about whether a
/// receptionist may see who is in the waiting room. These use the same
/// Admin/Manager/Staff role checks and the same tenantId claim as
/// BookingsController, the component they actually report on.
///
/// Everything here is derived from data the platform already records
/// (bookings, resources, customers, inventory). Nothing is fabricated: a
/// metric whose inputs do not exist yet (e.g. wait time before any booking
/// has a ConsultationStartedAt) comes back null and the clients render a
/// dash, never a zero that would read as a measurement.
[ApiController]
[Route("api/reports/clinic")]
[Authorize(Roles = "Admin,Manager,Staff")]
public class ClinicReportsController : ControllerBase
{
    private readonly AppDbContext _db;

    /// A patient who has been waiting this long is a queue alert.
    private const int LongWaitMinutes = 20;
    /// A confirmed patient this far past their slot with no check-in is
    /// flagged as a probable no-show so the desk can call them.
    private const int OverdueGraceMinutes = 15;

    public ClinicReportsController(AppDbContext db)
    {
        _db = db;
    }

    // ── Overview: KPIs + breakdowns ─────────────────────────────────────

    /// <summary>Clinic KPIs and breakdowns (by doctor, treatment, branch, insurer, channel, hour) for a date range, with optional cross-filters.</summary>
    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? branchId,
        [FromQuery] Guid? resourceId,
        [FromQuery] Guid? bookingTypeId,
        [FromQuery] string? insuranceProvider,
        [FromQuery] string groupBy = "day")
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);

        var (start, endExclusive) = Range(from, to);
        var grouping = NormalizeGroupBy(groupBy);
        var now = DateTime.UtcNow;
        var today = now.Date;

        var resources = await _db.Resources.AsNoTracking()
            .Include(r => r.Branch)
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null)
            .ToListAsync();
        var branches = await _db.Branches.AsNoTracking()
            .Where(b => b.TenantId == tenantId)
            .OrderBy(b => b.Name)
            .ToListAsync();
        var bookingTypes = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.DeletedAt == null && bt.Status != BookingTypeStatus.Archived)
            .OrderBy(bt => bt.Name)
            .ToListAsync();

        var customersQuery = _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && u.Role == UserRole.Customer);
        if (branchId.HasValue) customersQuery = customersQuery.Where(u => u.BranchId == branchId.Value);
        var customers = await customersQuery
            .Select(u => new PatientRow(u.Id, u.FullName, u.InsuranceProvider, u.CreatedAt))
            .ToListAsync();
        var patientsById = customers.ToDictionary(p => p.Id);

        var bookingsQuery = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.StartTime >= start && b.StartTime < endExclusive);
        if (branchId.HasValue) bookingsQuery = bookingsQuery.Where(b => b.Resource.BranchId == branchId.Value);
        if (resourceId.HasValue) bookingsQuery = bookingsQuery.Where(b => b.ResourceId == resourceId.Value);
        if (bookingTypeId.HasValue) bookingsQuery = bookingsQuery.Where(b => b.BookingTypeId == bookingTypeId.Value);
        var bookings = await bookingsQuery.ToListAsync();

        // Insurance is a property of the patient, not the booking, so the
        // filter is applied after the patient lookup. "Uninsured" is a real
        // bucket the desk asks about, so blank providers group under it
        // rather than disappearing.
        string ProviderOf(Booking b)
        {
            var patientId = b.BookedFor ?? b.BookedBy;
            return patientsById.TryGetValue(patientId, out var p) ? NormalizeProvider(p.InsuranceProvider) : UninsuredLabel;
        }
        if (!string.IsNullOrWhiteSpace(insuranceProvider))
        {
            var wanted = insuranceProvider.Trim();
            bookings = bookings.Where(b => string.Equals(ProviderOf(b), wanted, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        var live = bookings.Where(b => IsLive(b.Status)).ToList();
        var completed = bookings.Where(b => b.Status == BookingStatus.Completed).ToList();
        var noShows = bookings.Count(b => b.Status == BookingStatus.NoShow);
        var cancelled = bookings.Count(b => b.Status == BookingStatus.Cancelled || b.Status == BookingStatus.WeatherCancelled);
        // Outcome rates use only appointments whose outcome is known: a
        // booking still in the future cannot have been completed or missed,
        // and counting it as "not completed" would drag every rate down at
        // the start of a month.
        var decided = bookings.Count(b => b.Status == BookingStatus.Completed || b.Status == BookingStatus.NoShow
            || b.Status == BookingStatus.Cancelled || b.Status == BookingStatus.WeatherCancelled || b.Status == BookingStatus.Rejected);

        var waits = bookings
            .Where(b => b.CheckInAt != null && b.ConsultationStartedAt != null && b.ConsultationStartedAt >= b.CheckInAt)
            .Select(b => (b.ConsultationStartedAt!.Value - b.CheckInAt!.Value).TotalMinutes)
            .ToList();
        var visits = bookings
            .Where(b => b.CheckInAt != null && b.CheckOutAt != null && b.CheckOutAt >= b.CheckInAt)
            .Select(b => (b.CheckOutAt!.Value - b.CheckInAt!.Value).TotalMinutes)
            .ToList();

        var doctors = DoctorsOf(resources);
        if (branchId.HasValue) doctors = doctors.Where(r => r.BranchId == branchId.Value).ToList();
        var rooms = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived
            && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();

        // Staffing today is independent of the selected range: the ratio a
        // manager wants is "how thin are we spread right now".
        var todayBookings = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.StartTime >= today && b.StartTime < today.AddDays(1)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .Select(b => new { b.ResourceId, b.Status, b.BookedFor, b.BookedBy })
            .ToListAsync();
        var liveToday = todayBookings.Where(b => IsLive(b.Status)).ToList();
        var doctorsOnDuty = liveToday.Select(b => b.ResourceId).Distinct().Count(id => doctors.Any(d => d.Id == id));
        var patientsToday = liveToday.Select(b => b.BookedFor ?? b.BookedBy).Distinct().Count();

        var activePatients = live.Select(b => b.BookedFor ?? b.BookedBy).Distinct().Count();
        var newPatients = customers.Count(p => p.CreatedAt >= start && p.CreatedAt < endExclusive);

        var trend = BuildTrend(bookings, start, endExclusive, grouping);

        var byDoctor = bookings
            .GroupBy(b => b.ResourceId)
            .Select(g =>
            {
                var resource = g.First().Resource;
                var doctorWaits = g.Where(b => b.CheckInAt != null && b.ConsultationStartedAt != null && b.ConsultationStartedAt >= b.CheckInAt)
                    .Select(b => (b.ConsultationStartedAt!.Value - b.CheckInAt!.Value).TotalMinutes).ToList();
                return new
                {
                    resourceId = g.Key,
                    name = resource.Name,
                    specialty = resource.Specialty,
                    branchName = resource.Branch?.Name,
                    appointments = g.Count(),
                    completed = g.Count(b => b.Status == BookingStatus.Completed),
                    noShows = g.Count(b => b.Status == BookingStatus.NoShow),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    avgWaitMinutes = doctorWaits.Count > 0 ? Math.Round(doctorWaits.Average(), 1) : (double?)null,
                };
            })
            .OrderByDescending(x => x.appointments)
            .ToList();

        var byTreatment = bookings
            .GroupBy(b => b.BookingTypeId)
            .Select(g => new
            {
                bookingTypeId = g.Key,
                name = g.First().BookingType.Name,
                colorHex = g.First().BookingType.ColorHex,
                appointments = g.Count(),
                completed = g.Count(b => b.Status == BookingStatus.Completed),
                revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            })
            .OrderByDescending(x => x.appointments)
            .ToList();

        var byBranch = bookings
            .GroupBy(b => b.Resource.BranchId)
            .Select(g =>
            {
                var branch = g.Key.HasValue ? branches.FirstOrDefault(br => br.Id == g.Key.Value) : null;
                var branchDecided = g.Count(b => b.Status == BookingStatus.Completed || b.Status == BookingStatus.NoShow
                    || b.Status == BookingStatus.Cancelled || b.Status == BookingStatus.WeatherCancelled || b.Status == BookingStatus.Rejected);
                var branchCompleted = g.Count(b => b.Status == BookingStatus.Completed);
                return new
                {
                    branchId = g.Key,
                    name = branch?.Name ?? "Unassigned",
                    appointments = g.Count(),
                    patients = g.Select(b => b.BookedFor ?? b.BookedBy).Distinct().Count(),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    completionRate = branchDecided > 0 ? Math.Round(branchCompleted / (double)branchDecided * 100, 1) : (double?)null,
                };
            })
            .OrderByDescending(x => x.revenue)
            .ThenByDescending(x => x.appointments)
            .ToList();

        // Patient distribution by insurer is over the whole register, the
        // appointment/revenue split over the selected range - both are the
        // question "which insurers do we actually serve".
        var appointmentsByProvider = bookings
            .GroupBy(ProviderOf)
            .ToDictionary(g => g.Key, g => new
            {
                appointments = g.Count(),
                revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            }, StringComparer.OrdinalIgnoreCase);
        var byInsurance = customers
            .GroupBy(p => NormalizeProvider(p.InsuranceProvider), StringComparer.OrdinalIgnoreCase)
            .Select(g => new
            {
                provider = g.Key,
                patients = g.Count(),
                appointments = appointmentsByProvider.TryGetValue(g.Key, out var a) ? a.appointments : 0,
                revenue = appointmentsByProvider.TryGetValue(g.Key, out var r) ? r.revenue : 0m,
            })
            .OrderByDescending(x => x.patients)
            .ToList();

        var bySource = bookings
            .GroupBy(b => string.IsNullOrWhiteSpace(b.Source) ? "Front desk" : b.Source!.Trim())
            .Select(g => new { source = g.Key, appointments = g.Count() })
            .OrderByDescending(x => x.appointments)
            .ToList();

        var byHour = Enumerable.Range(0, 24)
            .Select(h => new { hour = h, appointments = bookings.Count(b => b.StartTime.Hour == h) })
            .ToList();

        var statusMix = bookings
            .GroupBy(b => b.Status)
            .Select(g => new { status = g.Key.ToString(), count = g.Count() })
            .OrderByDescending(x => x.count)
            .ToList();

        return Ok(new
        {
            from = start,
            to = endExclusive.AddDays(-1),
            groupBy = grouping,
            asOf = now,
            filters = new { branchId, resourceId, bookingTypeId, insuranceProvider },
            kpis = new
            {
                totalPatients = customers.Count,
                newPatients,
                activePatients,
                totalDoctors = doctors.Count,
                doctorsOnDutyToday = doctorsOnDuty,
                rooms = rooms.Count,
                totalAppointments = bookings.Count,
                completed = completed.Count,
                noShows,
                cancelled,
                pending = bookings.Count(b => b.Status == BookingStatus.Pending),
                confirmed = bookings.Count(b => b.Status == BookingStatus.Confirmed),
                completionRate = decided > 0 ? Math.Round(completed.Count / (double)decided * 100, 1) : (double?)null,
                noShowRate = decided > 0 ? Math.Round(noShows / (double)decided * 100, 1) : (double?)null,
                cancellationRate = decided > 0 ? Math.Round(cancelled / (double)decided * 100, 1) : (double?)null,
                revenueRealised = completed.Sum(b => b.TotalCost ?? 0m),
                revenueBooked = live.Sum(b => b.TotalCost ?? 0m),
                currency = "LKR",
                avgWaitMinutes = waits.Count > 0 ? Math.Round(waits.Average(), 1) : (double?)null,
                avgVisitMinutes = visits.Count > 0 ? Math.Round(visits.Average(), 1) : (double?)null,
                waitSamples = waits.Count,
                appointmentsToday = liveToday.Count,
                patientsToday,
                patientsPerDoctorToday = doctorsOnDuty > 0 ? Math.Round(patientsToday / (double)doctorsOnDuty, 1) : (double?)null,
            },
            statusMix,
            trend,
            byDoctor,
            byTreatment,
            byBranch,
            byInsurance,
            bySource,
            byHour,
            filterOptions = new
            {
                branches = branches.Select(b => new { id = b.Id, name = b.Name }),
                doctors = DoctorsOf(resources).OrderBy(r => r.Name).Select(r => new { id = r.Id, name = r.Name, specialty = r.Specialty, branchId = r.BranchId }),
                treatments = bookingTypes.Select(bt => new { id = bt.Id, name = bt.Name, colorHex = bt.ColorHex }),
                insuranceProviders = customers.Select(p => NormalizeProvider(p.InsuranceProvider))
                    .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p => p == UninsuredLabel ? 1 : 0).ThenBy(p => p),
            },
        });
    }

    // ── Flow: today's waiting room ──────────────────────────────────────

    /// <summary>Today's patient flow: every appointment with its stage (scheduled, waiting, in consultation, done), live waiting times and staffing ratios.</summary>
    [HttpGet("flow")]
    public async Task<IActionResult> GetFlow([FromQuery] DateTime? on, [FromQuery] Guid? branchId, [FromQuery] Guid? resourceId)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);

        var now = DateTime.UtcNow;
        var day = DateTimeUtil.AsUtc(on ?? now).Date;
        var next = day.AddDays(1);

        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null && b.StartTime >= day && b.StartTime < next);
        if (branchId.HasValue) query = query.Where(b => b.Resource.BranchId == branchId.Value);
        if (resourceId.HasValue) query = query.Where(b => b.ResourceId == resourceId.Value);
        var bookings = await query.OrderBy(b => b.StartTime).ToListAsync();

        var patients = await PatientsFor(tenantId, bookings);

        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && (!branchId.HasValue || r.BranchId == branchId.Value))
            .ToListAsync();
        var doctors = DoctorsOf(resources);
        var rooms = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived).ToList();

        var queue = bookings.Select(b =>
        {
            patients.TryGetValue(b.BookedFor ?? b.BookedBy, out var patient);
            var waiting = b.Status == BookingStatus.CheckedIn && b.CheckInAt != null
                ? (int)Math.Max(0, Math.Round((now - b.CheckInAt.Value).TotalMinutes))
                : (int?)null;
            var overdue = (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Pending)
                && b.CheckInAt == null && b.StartTime.AddMinutes(OverdueGraceMinutes) < now;
            return new
            {
                bookingId = b.Id,
                patientId = b.BookedFor ?? b.BookedBy,
                patientName = patient?.FullName ?? b.Title ?? "Patient",
                patientPhone = patient?.Phone,
                insuranceProvider = patient?.InsuranceProvider,
                resourceId = b.ResourceId,
                doctorName = b.Resource.Name,
                treatment = b.BookingType.Name,
                colorHex = b.BookingType.ColorHex,
                startTime = b.StartTime,
                endTime = b.EndTime,
                status = b.Status.ToString(),
                priority = b.Priority.ToString(),
                stage = StageOf(b.Status),
                checkInAt = b.CheckInAt,
                consultationStartedAt = b.ConsultationStartedAt,
                checkOutAt = b.CheckOutAt,
                waitingMinutes = waiting,
                isLongWait = waiting.HasValue && waiting.Value >= LongWaitMinutes,
                isOverdue = overdue,
                reminderSent = b.ReminderSent,
            };
        }).ToList();

        var waitingNow = queue.Where(q => q.waitingMinutes.HasValue).OrderByDescending(q => q.waitingMinutes).ToList();
        var waitsToday = bookings
            .Where(b => b.CheckInAt != null && b.ConsultationStartedAt != null && b.ConsultationStartedAt >= b.CheckInAt)
            .Select(b => (b.ConsultationStartedAt!.Value - b.CheckInAt!.Value).TotalMinutes)
            .ToList();

        var live = bookings.Where(b => IsLive(b.Status)).ToList();
        var doctorsOnDuty = live.Select(b => b.ResourceId).Distinct().Count(id => doctors.Any(d => d.Id == id));
        var patientsToday = live.Select(b => b.BookedFor ?? b.BookedBy).Distinct().Count();
        var occupiedRooms = bookings
            .Where(b => b.Status == BookingStatus.InProgress && rooms.Any(r => r.Id == b.ResourceId))
            .Select(b => b.ResourceId).Distinct().Count();
        var busyDoctors = bookings
            .Where(b => b.Status == BookingStatus.InProgress && doctors.Any(d => d.Id == b.ResourceId))
            .Select(b => b.ResourceId).Distinct().Count();

        return Ok(new
        {
            asOf = now,
            date = day,
            stages = new
            {
                scheduled = queue.Count(q => q.stage == "scheduled"),
                waiting = queue.Count(q => q.stage == "waiting"),
                inConsultation = queue.Count(q => q.stage == "inConsultation"),
                completed = queue.Count(q => q.stage == "completed"),
                noShow = queue.Count(q => q.stage == "noShow"),
                cancelled = queue.Count(q => q.stage == "cancelled"),
            },
            waitingNow,
            longestWaitMinutes = waitingNow.Count > 0 ? waitingNow.Max(q => q.waitingMinutes) : null,
            avgWaitMinutesToday = waitsToday.Count > 0 ? Math.Round(waitsToday.Average(), 1) : (double?)null,
            overdue = queue.Count(q => q.isOverdue),
            doctorsOnDuty,
            doctorsInConsultation = busyDoctors,
            patientsToday,
            patientsPerDoctor = doctorsOnDuty > 0 ? Math.Round(patientsToday / (double)doctorsOnDuty * 1.0, 1) : (double?)null,
            rooms = new
            {
                total = rooms.Count,
                occupied = occupiedRooms,
                occupancyPercent = rooms.Count > 0 ? Math.Round(occupiedRooms / (double)rooms.Count * 100, 1) : (double?)null,
            },
            queue,
        });
    }

    // ── Alerts ──────────────────────────────────────────────────────────

    /// <summary>Operational alerts: long waits, overdue arrivals, ageing approvals, unsent reminders, low stock, unavailable doctors.</summary>
    [HttpGet("alerts")]
    public async Task<IActionResult> GetAlerts([FromQuery] Guid? branchId)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);

        var now = DateTime.UtcNow;
        var today = now.Date;
        var alerts = new List<object>();

        var todays = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.StartTime >= today && b.StartTime < today.AddDays(1)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .ToListAsync();

        var longWaits = todays.Where(b => b.Status == BookingStatus.CheckedIn && b.CheckInAt != null
            && (now - b.CheckInAt.Value).TotalMinutes >= LongWaitMinutes).ToList();
        if (longWaits.Count > 0)
        {
            var longest = (int)Math.Round(longWaits.Max(b => (now - b.CheckInAt!.Value).TotalMinutes));
            alerts.Add(Alert("queue-long-wait", "critical", "queue",
                $"{longWaits.Count} patient{(longWaits.Count == 1 ? "" : "s")} waiting over {LongWaitMinutes} min",
                $"Longest wait is {longest} min. Check which consultation rooms are free.", longWaits.Count, "/dashboard#flow"));
        }

        var waiting = todays.Count(b => b.Status == BookingStatus.CheckedIn);
        if (waiting >= 5)
        {
            alerts.Add(Alert("queue-depth", "warning", "queue",
                $"{waiting} patients in the waiting room",
                "The queue is deep. Consider opening another room or calling the next doctor in.", waiting, "/dashboard#flow"));
        }

        var overdue = todays.Where(b => (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Pending)
            && b.CheckInAt == null && b.StartTime.AddMinutes(OverdueGraceMinutes) < now).ToList();
        if (overdue.Count > 0)
        {
            alerts.Add(Alert("arrivals-overdue", "warning", "arrivals",
                $"{overdue.Count} appointment{(overdue.Count == 1 ? "" : "s")} past their slot with no check-in",
                "Call the patient or mark the appointment as a no-show so the slot can be reused.", overdue.Count, "/dashboard#flow"));
        }

        var stalePending = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.Status == BookingStatus.Pending
                && b.StartTime > now
                && b.CreatedAt < now.AddHours(-24)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .CountAsync();
        if (stalePending > 0)
        {
            alerts.Add(Alert("approvals-stale", "warning", "approvals",
                $"{stalePending} appointment request{(stalePending == 1 ? "" : "s")} unconfirmed for over 24h",
                "Patients are waiting on a confirmation. Approve or decline them from Bookings.", stalePending, "/bookings"));
        }

        var unremindedTomorrow = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && !b.ReminderSent
                && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed)
                && b.StartTime > now && b.StartTime <= now.AddHours(24)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .CountAsync();
        if (unremindedTomorrow > 0)
        {
            alerts.Add(Alert("reminders-unsent", "info", "reminders",
                $"{unremindedTomorrow} appointment{(unremindedTomorrow == 1 ? "" : "s")} in the next 24h without a reminder",
                "The scheduler sends these automatically every few minutes; send now if a patient needs an early nudge.", unremindedTomorrow, "/dashboard#reminders"));
        }

        var lowStock = await _db.InventoryItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && i.IsActive && i.Quantity <= i.ReorderLevel
                && (!branchId.HasValue || i.BranchId == branchId.Value))
            .OrderBy(i => i.Quantity - i.ReorderLevel)
            .Select(i => new { i.Name, i.Quantity, i.ReorderLevel })
            .ToListAsync();
        if (lowStock.Count > 0)
        {
            var outOfStock = lowStock.Count(i => i.Quantity <= 0);
            var preview = string.Join(", ", lowStock.Take(3).Select(i => $"{i.Name} ({i.Quantity:0.#}/{i.ReorderLevel:0.#})"));
            alerts.Add(Alert("inventory-low", outOfStock > 0 ? "critical" : "warning", "inventory",
                $"{lowStock.Count} medical supply item{(lowStock.Count == 1 ? "" : "s")} at or below reorder level",
                (outOfStock > 0 ? $"{outOfStock} out of stock. " : "") + preview, lowStock.Count, "/inventory"));
        }

        var unavailableDoctors = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null
                && r.Status == ResourceStatus.UnderMaintenance
                && (!branchId.HasValue || r.BranchId == branchId.Value))
            .Select(r => r.Name)
            .ToListAsync();
        if (unavailableDoctors.Count > 0)
        {
            alerts.Add(Alert("resources-unavailable", "info", "resources",
                $"{unavailableDoctors.Count} doctor/room{(unavailableDoctors.Count == 1 ? "" : "s")} marked unavailable",
                string.Join(", ", unavailableDoctors.Take(4)), unavailableDoctors.Count, "/resources"));
        }

        var noShowsToday = todays.Count(b => b.Status == BookingStatus.NoShow);
        if (todays.Count >= 4 && noShowsToday >= Math.Max(2, todays.Count / 4))
        {
            alerts.Add(Alert("no-shows-today", "warning", "outcomes",
                $"{noShowsToday} no-shows today ({Math.Round(noShowsToday / (double)todays.Count * 100)}% of the day's list)",
                "Well above a normal day. Reminder timing or a doctor running late may be the cause.", noShowsToday, "/reports"));
        }

        return Ok(new { asOf = now, alerts });
    }

    // ── Reminders and follow-ups ────────────────────────────────────────

    /// <summary>The reminder worklist: upcoming appointments and whether they have been reminded, plus recently seen patients with no follow-up booked.</summary>
    [HttpGet("reminders")]
    public async Task<IActionResult> GetReminders([FromQuery] Guid? branchId, [FromQuery] int withinHours = 48)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        withinHours = Math.Clamp(withinHours, 1, 24 * 14);

        var now = DateTime.UtcNow;
        var horizon = now.AddHours(withinHours);

        var upcoming = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed)
                && b.StartTime > now && b.StartTime <= horizon
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .OrderBy(b => b.StartTime)
            .ToListAsync();

        var upcomingIds = upcoming.Select(b => b.Id).ToList();
        var lastReminders = await _db.BookingReminders.AsNoTracking()
            .Where(r => r.BookingId != null && upcomingIds.Contains(r.BookingId.Value))
            .GroupBy(r => r.BookingId!.Value)
            .Select(g => new { BookingId = g.Key, SentAt = g.Max(r => r.SentAt), Channel = g.OrderByDescending(r => r.SentAt).Select(r => r.Channel).FirstOrDefault() })
            .ToListAsync();
        var reminderByBooking = lastReminders.ToDictionary(r => r.BookingId);

        var patients = await PatientsFor(tenantId, upcoming);

        var items = upcoming.Select(b =>
        {
            patients.TryGetValue(b.BookedFor ?? b.BookedBy, out var patient);
            reminderByBooking.TryGetValue(b.Id, out var last);
            return new
            {
                bookingId = b.Id,
                patientName = patient?.FullName ?? b.Title ?? "Patient",
                patientPhone = patient?.Phone,
                patientEmail = patient?.Email,
                doctorName = b.Resource.Name,
                treatment = b.BookingType.Name,
                startTime = b.StartTime,
                status = b.Status.ToString(),
                reminderSent = b.ReminderSent,
                lastReminderAt = last?.SentAt,
                lastChannel = last?.Channel,
            };
        }).ToList();

        // Follow-up candidates: seen in the last 30 days, nothing booked
        // ahead. The clinic decides who actually needs one; this is the
        // list to work through, not a diagnosis.
        var since = now.AddDays(-30);
        var recentCompleted = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.Status == BookingStatus.Completed
                && b.StartTime >= since && b.StartTime <= now
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .OrderByDescending(b => b.StartTime)
            .ToListAsync();
        var recentPatientIds = recentCompleted.Select(b => b.BookedFor ?? b.BookedBy).Distinct().ToList();
        var withFuture = await _db.Bookings.AsNoTracking()
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.StartTime > now
                && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed
                    || b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress)
                && recentPatientIds.Contains(b.BookedFor ?? b.BookedBy))
            .Select(b => b.BookedFor ?? b.BookedBy)
            .Distinct()
            .ToListAsync();
        var withFutureSet = withFuture.ToHashSet();
        var followPatients = await PatientsFor(tenantId, recentCompleted);

        var followUps = recentCompleted
            .Where(b => !withFutureSet.Contains(b.BookedFor ?? b.BookedBy))
            .GroupBy(b => b.BookedFor ?? b.BookedBy)
            .Select(g =>
            {
                var last = g.First();
                followPatients.TryGetValue(g.Key, out var patient);
                return new
                {
                    patientId = g.Key,
                    patientName = patient?.FullName ?? last.Title ?? "Patient",
                    patientPhone = patient?.Phone,
                    lastVisit = last.StartTime,
                    doctorName = last.Resource.Name,
                    treatment = last.BookingType.Name,
                    daysSince = (int)Math.Floor((now - last.StartTime).TotalDays),
                };
            })
            .OrderBy(x => x.lastVisit)
            .Take(25)
            .ToList();

        return Ok(new
        {
            asOf = now,
            withinHours,
            unsent = items.Count(i => !i.reminderSent),
            items,
            followUps,
        });
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private const string UninsuredLabel = "Uninsured / self-pay";

    private sealed record PatientRow(Guid Id, string FullName, string? InsuranceProvider, DateTime CreatedAt);

    private sealed record PatientContact(Guid Id, string FullName, string Phone, string Email, string? InsuranceProvider);

    private async Task<Dictionary<Guid, PatientContact>> PatientsFor(Guid tenantId, IEnumerable<Booking> bookings)
    {
        var ids = bookings.Select(b => b.BookedFor ?? b.BookedBy).Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, PatientContact>();
        return await _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && ids.Contains(u.Id))
            .Select(u => new PatientContact(u.Id, u.FullName, u.Phone, u.Email, u.InsuranceProvider))
            .ToDictionaryAsync(p => p.Id);
    }

    /// Doctors are the Staff-category resources. A clinic that categorised
    /// its doctors as "Other" (the default) would otherwise show zero
    /// doctors while clearly running consultations, so fall back to every
    /// non-room, non-equipment resource when no Staff ones exist.
    private static List<Resource> DoctorsOf(IEnumerable<Resource> resources)
    {
        var active = resources.Where(r => r.Status != ResourceStatus.Archived).ToList();
        var staff = active.Where(r => r.Category == ResourceCategory.Staff).ToList();
        if (staff.Count > 0) return staff;
        return active.Where(r => r.Category != ResourceCategory.Room && r.Category != ResourceCategory.Equipment).ToList();
    }

    private static string StageOf(BookingStatus status) => status switch
    {
        BookingStatus.Pending or BookingStatus.Confirmed => "scheduled",
        BookingStatus.CheckedIn => "waiting",
        BookingStatus.InProgress => "inConsultation",
        BookingStatus.Completed => "completed",
        BookingStatus.NoShow => "noShow",
        _ => "cancelled",
    };

    private static bool IsLive(BookingStatus status) =>
        status != BookingStatus.Cancelled && status != BookingStatus.WeatherCancelled
        && status != BookingStatus.Rejected && status != BookingStatus.NoShow;

    private static string NormalizeProvider(string? provider) =>
        string.IsNullOrWhiteSpace(provider) ? UninsuredLabel : provider.Trim();

    private static object Alert(string id, string severity, string category, string title, string detail, int count, string href) =>
        new { id, severity, category, title, detail, count, href };

    private static (DateTime start, DateTime endExclusive) Range(DateTime? from, DateTime? to)
    {
        var today = DateTime.UtcNow.Date;
        var start = DateTimeUtil.AsUtc(from ?? today.AddDays(-29)).Date;
        var end = DateTimeUtil.AsUtc(to ?? today).Date;
        if (end < start) (start, end) = (end, start);
        // Cap at two years so a mistyped year cannot pull the whole table.
        if ((end - start).TotalDays > 731) start = end.AddDays(-731);
        return (start, end.AddDays(1));
    }

    private static string NormalizeGroupBy(string? groupBy) => (groupBy ?? "day").Trim().ToLowerInvariant() switch
    {
        "week" or "weekly" => "week",
        "month" or "monthly" => "month",
        _ => "day",
    };

    private static List<object> BuildTrend(List<Booking> bookings, DateTime start, DateTime endExclusive, string grouping)
    {
        static DateTime BucketStart(DateTime d, string g) => g switch
        {
            "week" => d.Date.AddDays(-(((int)d.DayOfWeek + 6) % 7)), // Monday
            "month" => new DateTime(d.Year, d.Month, 1, 0, 0, 0, DateTimeKind.Utc),
            _ => d.Date,
        };
        static DateTime NextBucket(DateTime d, string g) => g switch
        {
            "week" => d.AddDays(7),
            "month" => d.AddMonths(1),
            _ => d.AddDays(1),
        };
        static string Label(DateTime d, string g) => g switch
        {
            "week" => "Wk of " + d.ToString("dd MMM", CultureInfo.InvariantCulture),
            "month" => d.ToString("MMM yyyy", CultureInfo.InvariantCulture),
            _ => d.ToString("dd MMM", CultureInfo.InvariantCulture),
        };

        var grouped = bookings
            .GroupBy(b => BucketStart(b.StartTime, grouping))
            .ToDictionary(g => g.Key, g => g.ToList());

        var result = new List<object>();
        for (var cursor = BucketStart(start, grouping); cursor < endExclusive; cursor = NextBucket(cursor, grouping))
        {
            grouped.TryGetValue(cursor, out var inBucket);
            inBucket ??= new List<Booking>();
            result.Add(new
            {
                bucket = cursor.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                label = Label(cursor, grouping),
                appointments = inBucket.Count,
                completed = inBucket.Count(b => b.Status == BookingStatus.Completed),
                noShows = inBucket.Count(b => b.Status == BookingStatus.NoShow),
                cancelled = inBucket.Count(b => b.Status == BookingStatus.Cancelled || b.Status == BookingStatus.WeatherCancelled),
                revenue = inBucket.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            });
        }
        return result;
    }

    private bool TryTenant(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    // Same rule as ReportsController: an Admin sees the whole tenant unless
    // they pick a branch; a Manager/Staff defaults to their own branch but
    // may still ask for another one explicitly.
    private Guid? ResolveBranchScope(Guid? requested)
    {
        if (User.IsInRole(UserRole.Admin.ToString()) || requested.HasValue) return requested;
        return Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId) ? branchId : null;
    }
}
