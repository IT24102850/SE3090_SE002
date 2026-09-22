using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The gym / fitness operations dashboard: attendance and occupancy,
/// memberships and demographics, revenue against targets, payment status,
/// equipment utilisation and maintenance, class attendance.
///
/// Same footing as the clinic and restaurant controllers: its own role
/// checks, everything derived from data the platform records, and a
/// metric with no inputs yet is null (the client draws a dash).
///
/// How a gym maps onto the platform:
///   member      = User with Role Customer (DateOfBirth / Gender feed the
///                 demographics; both optional)
///   membership  = Subscription (plan = tier, Status = lifecycle,
///                 PaymentStatus = latest billing run)
///   visit       = Booking; CheckInAt is the entry, CheckOutAt the exit,
///                 Source the method (RFID / App / Biometric / Front desk)
///   class       = BookingType of kind "class" (GymConfig); a session is
///                 one start time on one resource, its attendance the
///                 bookings on it
///   zone        = Room resource (Capacity sums to the facility capacity
///                 unless the Memberships module config sets one)
///   trainer     = Staff resource with its weekly roster
///   equipment   = EquipmentItem (CurrentStock = units on the floor);
///                 utilisation from EquipmentReservations, maintenance
///                 from EquipmentMaintenances plus a uses-since-service
///                 threshold
///
/// Hour-of-day and "today" use the viewer's local offset (`tz`, minutes
/// east of UTC), like the restaurant controller.
[ApiController]
[Route("api/reports/gym")]
[Authorize(Roles = "Admin,Manager,Staff")]
public class GymReportsController : ControllerBase
{
    private readonly AppDbContext _db;

    private const int RenewalWindowDays = 30;
    private const int RenewalUrgentDays = 7;
    private const int MaintenanceSoonDays = 14;
    private const double HighOccupancyPercent = 90;

    private static readonly string[] AgeBands = { "Under 18", "18-24", "25-34", "35-44", "45-54", "55+", "Not stated" };

    public GymReportsController(AppDbContext db)
    {
        _db = db;
    }

    // ── Overview ────────────────────────────────────────────────────────

    /// <summary>Membership, attendance, revenue, class and equipment KPIs with breakdowns for a date range. Hours use the viewer's `tz` offset.</summary>
    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? branchId,
        [FromQuery] Guid? resourceId,
        [FromQuery] Guid? bookingTypeId,
        [FromQuery] string? plan,
        [FromQuery] string groupBy = "day",
        [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var grouping = NormalizeGroupBy(groupBy);
        var now = DateTime.UtcNow;
        var days = Math.Max(1, (int)Math.Round((endExclusive - start).TotalDays));
        var localNow = clock.Local(now);

        var targets = GymConfig.TargetsOf(await ModuleConfigAsync(tenantId));

        var resources = await _db.Resources.AsNoTracking().Include(r => r.Branch)
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null).ToListAsync();
        var branches = await _db.Branches.AsNoTracking().Where(b => b.TenantId == tenantId).OrderBy(b => b.Name).ToListAsync();
        var types = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.DeletedAt == null && bt.Status != BookingTypeStatus.Archived)
            .OrderBy(bt => bt.Name).ToListAsync();

        var members = await _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && u.Role == UserRole.Customer && (!branchId.HasValue || u.BranchId == branchId.Value))
            .Select(u => new MemberRow(u.Id, u.FullName, u.Phone, u.Email, u.DateOfBirth, u.Gender, u.CreatedAt, u.IsActive))
            .ToListAsync();
        var membersById = members.ToDictionary(m => m.Id);

        var subs = await _db.Subscriptions.AsNoTracking()
            .Where(s => s.TenantId == tenantId && (!branchId.HasValue || s.BranchId == branchId.Value || s.BranchId == null))
            .ToListAsync();
        if (!string.IsNullOrWhiteSpace(plan))
        {
            var wanted = plan.Trim();
            subs = subs.Where(s => string.Equals(s.PlanName, wanted, StringComparison.OrdinalIgnoreCase)).ToList();
        }
        // The membership that counts for a member is their latest one.
        var currentSub = subs.GroupBy(s => s.CustomerId).ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.EndDate).First());
        var memberFilter = string.IsNullOrWhiteSpace(plan) ? null : currentSub.Keys.ToHashSet();

        var bookings = await LoadBookingsAsync(tenantId, start, endExclusive, branchId, resourceId, bookingTypeId);
        if (memberFilter != null) bookings = bookings.Where(b => memberFilter.Contains(b.BookedFor ?? b.BookedBy)).ToList();
        var previous = await LoadBookingsAsync(tenantId, start - (endExclusive - start), start, branchId, resourceId, bookingTypeId);
        if (memberFilter != null) previous = previous.Where(b => memberFilter.Contains(b.BookedFor ?? b.BookedBy)).ToList();

        // ── Attendance ──────────────────────────────────────────────────
        var visits = bookings.Where(IsVisit).ToList();
        var prevVisits = previous.Where(IsVisit).ToList();
        var uniqueVisitors = visits.Select(MemberOf).Distinct().Count();
        var durations = visits.Where(b => b.CheckOutAt != null && b.CheckOutAt >= b.CheckInAt)
            .Select(b => (b.CheckOutAt!.Value - b.CheckInAt!.Value).TotalMinutes).ToList();

        var heatmap = Enumerable.Range(0, 7).Select(dow => new
        {
            dayOfWeek = dow,
            label = CultureInfo.InvariantCulture.DateTimeFormat.GetAbbreviatedDayName((DayOfWeek)dow),
            hours = Enumerable.Range(0, 24).Select(h => visits.Count(v =>
            {
                var l = clock.Local(v.CheckInAt!.Value);
                return (int)l.DayOfWeek == dow && l.Hour == h;
            })).ToList(),
        }).ToList();
        var byHour = Enumerable.Range(0, 24).Select(h => new { hour = h, checkIns = visits.Count(v => clock.Local(v.CheckInAt!.Value).Hour == h) }).ToList();
        var peak = byHour.OrderByDescending(x => x.checkIns).First();
        var byMethod = visits.GroupBy(MethodOf, StringComparer.OrdinalIgnoreCase)
            .Select(g => new { method = g.Key, checkIns = g.Count() }).OrderByDescending(x => x.checkIns).ToList();

        // ── Memberships ─────────────────────────────────────────────────
        var active = currentSub.Values.Where(s => IsActiveSub(s, now)).ToList();
        var frozen = currentSub.Values.Count(s => s.Status.Equals("Frozen", StringComparison.OrdinalIgnoreCase));
        var expired = currentSub.Values.Count(s => IsExpired(s, now));
        var cancelled = currentSub.Values.Count(s => s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase));
        var noMembership = members.Count(m => !currentSub.ContainsKey(m.Id));
        var renewalsDue = active.Where(s => s.EndDate <= now.AddDays(RenewalWindowDays)).OrderBy(s => s.EndDate).ToList();
        var signUps = subs.Count(s => s.StartDate >= start && s.StartDate < endExclusive);
        var prevSignUps = subs.Count(s => s.StartDate >= start - (endExclusive - start) && s.StartDate < start);
        var lapsedInRange = currentSub.Values.Count(s => IsExpired(s, now) && s.EndDate >= start && s.EndDate < endExclusive);
        var newMembers = members.Count(m => m.CreatedAt >= start && m.CreatedAt < endExclusive);
        var activeAtStart = subs.Count(s => s.StartDate < start && s.EndDate >= start && !s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase));
        var churnRate = activeAtStart > 0 ? Math.Round(lapsedInRange / (double)activeAtStart * 100, 1) : (double?)null;

        var payment = currentSub.Values.Where(s => !IsExpired(s, now) && !s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))
            .GroupBy(s => NormalizePayment(s.PaymentStatus))
            .Select(g => new { status = g.Key, memberships = g.Count(), amount = g.Sum(s => s.Amount) })
            .OrderBy(x => PaymentOrder(x.status)).ToList();
        var outstanding = currentSub.Values.Where(s => !IsExpired(s, now) && IsUnpaid(s)).ToList();

        // ── Revenue ─────────────────────────────────────────────────────
        decimal MembershipRevenue(DateTime s, DateTime e) => subs.Where(x => NormalizePayment(x.PaymentStatus) == "Paid" && PaidAt(x) >= s && PaidAt(x) < e).Sum(x => x.Amount);
        decimal DropInRevenue(IEnumerable<Booking> bs) => bs.Where(b => b.Status == BookingStatus.Completed && KindOf(b) != GymConfig.Access && KindOf(b) != GymConfig.Class).Sum(b => b.TotalCost ?? 0m);
        var membershipRevenue = MembershipRevenue(start, endExclusive);
        var dropInRevenue = DropInRevenue(bookings);
        var prevRevenue = MembershipRevenue(start - (endExclusive - start), start) + DropInRevenue(previous);

        var monthStart = clock.Utc(new DateTime(localNow.Year, localNow.Month, 1));
        var yearStart = clock.Utc(new DateTime(localNow.Year, 1, 1));
        var mtdBookings = await LoadBookingsAsync(tenantId, monthStart, now, branchId, null, null);
        var ytdBookings = await LoadBookingsAsync(tenantId, yearStart, now, branchId, null, null);
        var mtd = MembershipRevenue(monthStart, now) + DropInRevenue(mtdBookings);
        var ytd = MembershipRevenue(yearStart, now) + DropInRevenue(ytdBookings);
        var daysInMonth = DateTime.DaysInMonth(localNow.Year, localNow.Month);
        var monthPace = targets.MonthlyRevenueTarget.HasValue ? Math.Round(targets.MonthlyRevenueTarget.Value * localNow.Day / daysInMonth, 2) : (decimal?)null;

        // ── Classes ─────────────────────────────────────────────────────
        var classBookings = bookings.Where(b => KindOf(b) == GymConfig.Class && IsLive(b.Status)).ToList();
        var byClass = classBookings.GroupBy(b => b.BookingTypeId).Select(g =>
        {
            var type = g.First().BookingType;
            var sessions = g.GroupBy(b => new { b.ResourceId, b.StartTime }).ToList();
            var capacity = (type.MaxParticipants ?? 0) * sessions.Count;
            var attended = g.Count(b => b.Status == BookingStatus.Completed || b.CheckInAt != null);
            return new
            {
                bookingTypeId = g.Key,
                name = type.Name,
                colorHex = type.ColorHex,
                sessions = sessions.Count,
                bookings = g.Sum(b => Math.Max(1, b.AttendeeCount ?? 1)),
                attended,
                capacityPerSession = type.MaxParticipants,
                fillRate = capacity > 0 ? Math.Round(g.Sum(b => Math.Max(1, b.AttendeeCount ?? 1)) / (double)capacity * 100, 1) : (double?)null,
                avgPerSession = sessions.Count > 0 ? Math.Round(g.Count() / (double)sessions.Count, 1) : (double?)null,
                noShows = g.Count(b => b.Status == BookingStatus.NoShow),
                revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            };
        }).OrderByDescending(x => x.bookings).ToList();

        var byTrainer = bookings.Where(b => b.Resource.Category == ResourceCategory.Staff && IsLive(b.Status))
            .GroupBy(b => b.ResourceId).Select(g => new
            {
                resourceId = g.Key,
                name = g.First().Resource.Name,
                specialty = g.First().Resource.Specialty,
                sessions = g.GroupBy(b => b.StartTime).Count(),
                bookings = g.Count(),
                completed = g.Count(b => b.Status == BookingStatus.Completed),
                revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            }).OrderByDescending(x => x.bookings).ToList();

        var zones = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();
        var openHours = (double)targets.OpenHoursPerDay * days;
        var byZone = zones.Select(z =>
        {
            var inZone = bookings.Where(b => b.ResourceId == z.Id && IsLive(b.Status)).ToList();
            var hours = inZone.Sum(b => Math.Max(0, (b.EndTime - b.StartTime).TotalHours));
            return new
            {
                resourceId = z.Id,
                name = z.Name,
                capacity = z.Capacity,
                visits = inZone.Count,
                hoursBooked = Math.Round(hours, 1),
                utilisationPercent = openHours > 0 ? Math.Round(hours / openHours * 100, 1) : (double?)null,
            };
        }).OrderByDescending(x => x.visits).ToList();

        // ── Equipment ───────────────────────────────────────────────────
        var equipment = await _db.EquipmentItems.AsNoTracking()
            .Where(e => e.TenantId == tenantId && e.IsActive && (!branchId.HasValue || e.BranchId == branchId.Value))
            .OrderBy(e => e.Name).ToListAsync();
        var equipmentIds = equipment.Select(e => e.Id).ToList();
        var reservations = await _db.EquipmentReservations.AsNoTracking().Include(r => r.Booking)
            .Where(r => r.TenantId == tenantId && equipmentIds.Contains(r.EquipmentItemId)
                && r.Booking != null && r.Booking.DeletedAt == null && r.Booking.StartTime >= start && r.Booking.StartTime < endExclusive)
            .ToListAsync();
        var maintenance = await _db.EquipmentMaintenances.AsNoTracking()
            .Where(m => m.EquipmentItemId != null && equipmentIds.Contains(m.EquipmentItemId.Value))
            .ToListAsync();
        var allReservations = await _db.EquipmentReservations.AsNoTracking().Include(r => r.Booking)
            .Where(r => r.TenantId == tenantId && equipmentIds.Contains(r.EquipmentItemId) && r.Booking != null && r.Booking.DeletedAt == null)
            .Select(r => new { r.EquipmentItemId, r.Booking!.StartTime, r.Quantity })
            .ToListAsync();

        var byEquipment = equipment.Select(e =>
        {
            var uses = reservations.Where(r => r.EquipmentItemId == e.Id).ToList();
            var hours = uses.Sum(r => (double)r.Quantity * Math.Max(0, (r.Booking!.EndTime - r.Booking.StartTime).TotalHours));
            var available = (double)Math.Max(1m, e.CurrentStock) * openHours;
            var lastService = maintenance.Where(m => m.EquipmentItemId == e.Id && m.Status.Equals("Completed", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(m => m.MaintenanceDate).FirstOrDefault();
            var nextDue = maintenance.Where(m => m.EquipmentItemId == e.Id && !m.Status.Equals("Completed", StringComparison.OrdinalIgnoreCase))
                .OrderBy(m => m.NextDueDate).FirstOrDefault();
            var usesSinceService = allReservations.Count(r => r.EquipmentItemId == e.Id && (lastService == null || r.StartTime > lastService.MaintenanceDate));
            var maintenanceStatus = nextDue == null ? "none"
                : nextDue.Status.Equals("InProgress", StringComparison.OrdinalIgnoreCase) ? "inService"
                : nextDue.NextDueDate < now ? "overdue"
                : nextDue.NextDueDate <= now.AddDays(MaintenanceSoonDays) ? "dueSoon"
                : "scheduled";
            if (maintenanceStatus is "none" or "scheduled" && usesSinceService >= targets.MaintenanceEveryUses) maintenanceStatus = "usageDue";
            return new
            {
                equipmentItemId = e.Id,
                name = e.Name,
                category = e.Category,
                units = e.CurrentStock,
                uses = uses.Sum(r => (int)r.Quantity),
                hoursUsed = Math.Round(hours, 1),
                utilisationPercent = available > 0 ? Math.Round(hours / available * 100, 1) : (double?)null,
                lastServicedAt = lastService?.MaintenanceDate,
                nextDueAt = nextDue?.NextDueDate,
                usesSinceService,
                maintenanceEveryUses = targets.MaintenanceEveryUses,
                maintenanceStatus,
                maintenanceNotes = nextDue?.Notes,
            };
        }).OrderByDescending(x => x.hoursUsed).ToList();

        // ── Demographics (active members) ───────────────────────────────
        var activeMembers = active.Select(s => s.CustomerId).Where(membersById.ContainsKey).Select(id => membersById[id]).ToList();
        var byAge = AgeBands.Select(band => new { band, members = activeMembers.Count(m => AgeBandOf(m.DateOfBirth, localNow) == band) }).ToList();
        var byGender = activeMembers.GroupBy(m => string.IsNullOrWhiteSpace(m.Gender) ? "Not stated" : m.Gender!.Trim(), StringComparer.OrdinalIgnoreCase)
            .Select(g => new { gender = g.Key, members = g.Count() }).OrderByDescending(x => x.members).ToList();
        var byPlan = active.GroupBy(s => s.PlanName, StringComparer.OrdinalIgnoreCase)
            .Select(g => new { plan = g.Key, members = g.Count(), monthlyValue = g.Sum(s => MonthlyValue(s)), signUpsInRange = subs.Count(s => s.PlanName.Equals(g.Key, StringComparison.OrdinalIgnoreCase) && s.StartDate >= start && s.StartDate < endExclusive) })
            .OrderByDescending(x => x.members).ToList();

        var trend = BuildTrend(bookings, subs, clock, start, endExclusive, grouping);

        var statusMix = bookings.GroupBy(b => b.Status).Select(g => new { status = g.Key.ToString(), count = g.Count() }).OrderByDescending(x => x.count).ToList();

        var byBranch = bookings.Where(IsVisit).GroupBy(b => b.Resource.BranchId).Select(g =>
        {
            var branch = g.Key.HasValue ? branches.FirstOrDefault(br => br.Id == g.Key.Value) : null;
            return new { branchId = g.Key, name = branch?.Name ?? "Unassigned", visits = g.Count(), members = g.Select(MemberOf).Distinct().Count() };
        }).OrderByDescending(x => x.visits).ToList();

        return Ok(new
        {
            from = clock.Local(start).Date,
            to = clock.Local(endExclusive).Date.AddDays(-1),
            groupBy = grouping,
            asOf = now,
            tz,
            filters = new { branchId, resourceId, bookingTypeId, plan },
            targets = new
            {
                facilityCapacity = targets.FacilityCapacity ?? (zones.Sum(z => z.Capacity ?? 0) > 0 ? zones.Sum(z => z.Capacity ?? 0) : (int?)null),
                monthlyRevenueTarget = targets.MonthlyRevenueTarget,
                yearlyRevenueTarget = targets.YearlyRevenueTarget,
                monthTargetToDate = monthPace,
                openHoursPerDay = targets.OpenHoursPerDay,
                maintenanceEveryUses = targets.MaintenanceEveryUses,
            },
            kpis = new
            {
                currency = "LKR",
                visits = visits.Count,
                uniqueVisitors,
                visitsPerDay = Math.Round(visits.Count / (double)days, 1),
                avgVisitMinutes = durations.Count > 0 ? Math.Round(durations.Average(), 1) : (double?)null,
                visitSamples = durations.Count,
                peakHour = peak.checkIns > 0 ? peak.hour : (int?)null,
                peakHourCheckIns = peak.checkIns,
                totalMembers = members.Count,
                activeMembers = active.Count,
                frozenMembers = frozen,
                expiredMembers = expired,
                cancelledMembers = cancelled,
                withoutMembership = noMembership,
                newMembers,
                signUps,
                lapsed = lapsedInRange,
                churnRate,
                renewalsDue30 = renewalsDue.Count,
                renewalsDue7 = renewalsDue.Count(s => s.EndDate <= now.AddDays(RenewalUrgentDays)),
                overduePayments = outstanding.Count,
                overdueAmount = outstanding.Sum(s => s.Amount),
                revenue = membershipRevenue + dropInRevenue,
                membershipRevenue,
                dropInRevenue,
                revenueMtd = mtd,
                revenueYtd = ytd,
                monthlyRecurring = active.Sum(s => MonthlyValue(s)),
                classSessions = byClass.Sum(c => c.sessions),
                classBookings = byClass.Sum(c => c.bookings),
                classFillRate = byClass.Any(c => c.fillRate.HasValue) ? Math.Round(byClass.Where(c => c.fillRate.HasValue).Average(c => c.fillRate!.Value), 1) : (double?)null,
                equipmentItems = equipment.Count,
                equipmentUtilisation = byEquipment.Any(e => e.utilisationPercent.HasValue) ? Math.Round(byEquipment.Where(e => e.utilisationPercent.HasValue).Average(e => e.utilisationPercent!.Value), 1) : (double?)null,
                maintenanceDue = byEquipment.Count(e => e.maintenanceStatus is "overdue" or "dueSoon" or "usageDue" or "inService"),
                zones = zones.Count,
                trainers = resources.Count(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived && (!branchId.HasValue || r.BranchId == branchId.Value)),
            },
            previous = new
            {
                visits = prevVisits.Count,
                uniqueVisitors = prevVisits.Select(MemberOf).Distinct().Count(),
                signUps = prevSignUps,
                revenue = prevRevenue,
            },
            renewals = renewalsDue.Take(30).Select(s =>
            {
                membersById.TryGetValue(s.CustomerId, out var m);
                return new { subscriptionId = s.Id, memberId = s.CustomerId, memberName = m?.FullName ?? "Member", phone = m?.Phone, email = m?.Email, plan = s.PlanName, amount = s.Amount, endDate = s.EndDate, daysLeft = (int)Math.Ceiling((s.EndDate - now).TotalDays), autoRenew = s.AutoRenew, paymentStatus = NormalizePayment(s.PaymentStatus) };
            }),
            outstanding = outstanding.OrderBy(s => s.NextBillingAt ?? s.EndDate).Take(30).Select(s =>
            {
                membersById.TryGetValue(s.CustomerId, out var m);
                return new { subscriptionId = s.Id, memberId = s.CustomerId, memberName = m?.FullName ?? "Member", phone = m?.Phone, plan = s.PlanName, amount = s.Amount, paymentStatus = NormalizePayment(s.PaymentStatus), nextBillingAt = s.NextBillingAt, lastPaymentAt = s.LastPaymentAt };
            }),
            payment,
            statusMix,
            trend,
            heatmap,
            byHour,
            byMethod,
            byClass,
            byTrainer,
            byZone,
            byEquipment,
            byPlan,
            byAge,
            byGender,
            byBranch,
            filterOptions = new
            {
                branches = branches.Select(b => new { id = b.Id, name = b.Name }),
                zones = zones.Select(z => new { id = z.Id, name = z.Name, capacity = z.Capacity }),
                trainers = resources.Where(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived).OrderBy(r => r.Name).Select(r => new { id = r.Id, name = r.Name, specialty = r.Specialty }),
                classes = types.Where(t => GymConfig.KindOf(t) == GymConfig.Class).Select(t => new { id = t.Id, name = t.Name, colorHex = t.ColorHex, capacity = t.MaxParticipants }),
                bookingTypes = types.Select(t => new { id = t.Id, name = t.Name, kind = GymConfig.KindOf(t) }),
                plans = subs.Select(s => s.PlanName).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p => p).ToList(),
            },
        });
    }

    // ── Live: who is inside right now ───────────────────────────────────

    /// <summary>Live occupancy: members inside now against capacity, today's entries and exits by hour, the latest check-ins, today's classes and the trainers rostered now.</summary>
    [HttpGet("live")]
    public async Task<IActionResult> GetLive([FromQuery] Guid? branchId, [FromQuery] Guid? resourceId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(now);
        var localNow = clock.Local(now);

        var targets = GymConfig.TargetsOf(await ModuleConfigAsync(tenantId));
        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && (!branchId.HasValue || r.BranchId == branchId.Value)).ToListAsync();
        var zones = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived).ToList();
        var capacity = targets.FacilityCapacity ?? (zones.Sum(z => z.Capacity ?? 0) > 0 ? zones.Sum(z => z.Capacity ?? 0) : (int?)null);

        var todays = await LoadBookingsAsync(tenantId, dayStart, dayEnd, branchId, resourceId, null);
        var members = await MembersFor(tenantId, todays);
        var subs = await CurrentSubsFor(tenantId, members.Keys);

        var inside = todays.Where(IsInside).OrderByDescending(b => b.CheckInAt).ToList();
        var entries = todays.Where(b => b.CheckInAt != null).ToList();
        var exits = todays.Where(b => b.CheckOutAt != null).ToList();

        object Row(Booking b)
        {
            members.TryGetValue(MemberOf(b), out var m);
            subs.TryGetValue(MemberOf(b), out var s);
            var minutes = b.CheckInAt != null ? (int)Math.Max(0, Math.Round(((b.CheckOutAt ?? now) - b.CheckInAt.Value).TotalMinutes)) : (int?)null;
            return new
            {
                bookingId = b.Id,
                memberId = MemberOf(b),
                memberName = m?.FullName ?? b.Title ?? "Member",
                plan = s?.PlanName,
                membershipStatus = s == null ? "none" : IsExpired(s, now) ? "expired" : NormalizeStatus(s.Status),
                paymentStatus = s == null ? null : NormalizePayment(s.PaymentStatus),
                kind = KindOf(b),
                activity = b.BookingType.Name,
                colorHex = b.BookingType.ColorHex,
                zone = b.Resource.Name,
                method = MethodOf(b),
                status = b.Status.ToString(),
                startTime = b.StartTime,
                checkInAt = b.CheckInAt,
                checkOutAt = b.CheckOutAt,
                minutesInside = minutes,
                isInside = IsInside(b),
            };
        }

        var byHour = Enumerable.Range(0, 24).Select(h => new
        {
            hour = h,
            entries = entries.Count(b => clock.Local(b.CheckInAt!.Value).Hour == h),
            exits = exits.Count(b => clock.Local(b.CheckOutAt!.Value).Hour == h),
        }).ToList();

        var classesToday = todays.Where(b => KindOf(b) == GymConfig.Class && IsLive(b.Status))
            .GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime })
            .Select(g =>
            {
                var first = g.First();
                var booked = g.Sum(b => Math.Max(1, b.AttendeeCount ?? 1));
                var cap = first.BookingType.MaxParticipants;
                return new
                {
                    bookingTypeId = g.Key.BookingTypeId,
                    name = first.BookingType.Name,
                    colorHex = first.BookingType.ColorHex,
                    resourceName = first.Resource.Name,
                    startTime = g.Key.StartTime,
                    endTime = first.EndTime,
                    booked,
                    checkedIn = g.Count(b => b.CheckInAt != null),
                    capacity = cap,
                    fillPercent = cap > 0 ? Math.Round(booked / (double)cap * 100) : (double?)null,
                    isFull = cap > 0 && booked >= cap,
                    state = g.Key.StartTime > now ? "upcoming" : first.EndTime > now ? "inProgress" : "done",
                };
            }).OrderBy(c => c.startTime).ToList();

        var trainers = resources.Where(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived).ToList();
        var trainerIds = trainers.Select(t => t.Id).ToList();
        var dow = (int)localNow.DayOfWeek;
        var roster = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId != null && trainerIds.Contains(s.ResourceId.Value) && s.IsAvailable && s.DayOfWeek == dow).ToListAsync();
        var trainersNow = roster.Select(s =>
        {
            var t = trainers.First(x => x.Id == s.ResourceId);
            var onFloor = s.StartTime <= localNow.TimeOfDay && localNow.TimeOfDay < s.EndTime;
            return new
            {
                resourceId = t.Id,
                name = t.Name,
                specialty = t.Specialty,
                shiftStart = s.StartTime.ToString(@"hh\:mm"),
                shiftEnd = s.EndTime.ToString(@"hh\:mm"),
                onFloor,
                busy = todays.Any(b => b.ResourceId == t.Id && (b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress)),
                sessionsToday = todays.Count(b => b.ResourceId == t.Id && IsLive(b.Status)),
            };
        }).OrderByDescending(t => t.onFloor).ThenBy(t => t.shiftStart).ToList();

        return Ok(new
        {
            asOf = now,
            date = clock.Local(dayStart).Date,
            insideNow = inside.Count,
            capacity,
            occupancyPercent = capacity > 0 ? Math.Round(inside.Count / (double)capacity * 100, 1) : (double?)null,
            entriesToday = entries.Count,
            exitsToday = exits.Count,
            uniqueToday = entries.Select(MemberOf).Distinct().Count(),
            expiredInsideToday = entries.Count(b => subs.TryGetValue(MemberOf(b), out var s) ? IsExpired(s, now) : !subs.ContainsKey(MemberOf(b)) && KindOf(b) == GymConfig.Access),
            byHour,
            inside = inside.Select(Row),
            recent = entries.OrderByDescending(b => b.CheckInAt).Take(20).Select(Row),
            classesToday,
            trainers = new { rostered = trainersNow.Count, onFloor = trainersNow.Count(t => t.onFloor), list = trainersNow },
        });
    }

    // ── Attendance log ──────────────────────────────────────────────────

    /// <summary>Searchable check-in log: member, method, time in / out, duration, activity and zone, newest first.</summary>
    [HttpGet("attendance")]
    public async Task<IActionResult> GetAttendance(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? branchId, [FromQuery] Guid? resourceId,
        [FromQuery] string? search, [FromQuery] string? method, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var now = DateTime.UtcNow;
        pageSize = Math.Clamp(pageSize, 10, 200);
        page = Math.Max(1, page);

        var visits = (await LoadBookingsAsync(tenantId, start, endExclusive, branchId, resourceId, null)).Where(IsVisit).ToList();
        var members = await MembersFor(tenantId, visits);
        var subs = await CurrentSubsFor(tenantId, members.Keys);

        if (!string.IsNullOrWhiteSpace(method))
            visits = visits.Where(b => string.Equals(MethodOf(b), method.Trim(), StringComparison.OrdinalIgnoreCase)).ToList();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var q = search.Trim();
            visits = visits.Where(b =>
                (members.TryGetValue(MemberOf(b), out var m) && (m.FullName.Contains(q, StringComparison.OrdinalIgnoreCase) || m.Phone.Contains(q, StringComparison.OrdinalIgnoreCase) || m.Email.Contains(q, StringComparison.OrdinalIgnoreCase)))
                || (b.Title ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
                || b.BookingType.Name.Contains(q, StringComparison.OrdinalIgnoreCase)
                || b.Resource.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        var ordered = visits.OrderByDescending(b => b.CheckInAt).ToList();
        var pageRows = ordered.Skip((page - 1) * pageSize).Take(pageSize).Select(b =>
        {
            members.TryGetValue(MemberOf(b), out var m);
            subs.TryGetValue(MemberOf(b), out var s);
            return new
            {
                bookingId = b.Id,
                memberId = MemberOf(b),
                memberName = m?.FullName ?? b.Title ?? "Member",
                phone = m?.Phone,
                plan = s?.PlanName,
                membershipStatus = s == null ? "none" : IsExpired(s, now) ? "expired" : NormalizeStatus(s.Status),
                method = MethodOf(b),
                kind = KindOf(b),
                activity = b.BookingType.Name,
                zone = b.Resource.Name,
                checkInAt = b.CheckInAt,
                checkOutAt = b.CheckOutAt,
                minutes = b.CheckOutAt != null ? (int)Math.Max(0, Math.Round((b.CheckOutAt.Value - b.CheckInAt!.Value).TotalMinutes)) : (int?)null,
                status = b.Status.ToString(),
            };
        }).ToList();

        return Ok(new
        {
            asOf = now,
            from = clock.Local(start).Date,
            to = clock.Local(endExclusive).Date.AddDays(-1),
            total = ordered.Count,
            page,
            pageSize,
            methods = visits.Select(MethodOf).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x).ToList(),
            rows = pageRows,
        });
    }

    // ── Alerts ──────────────────────────────────────────────────────────

    /// <summary>Operational alerts: near capacity, renewals due, failed / overdue billing, lapsed members checking in, maintenance due, full classes, no trainer rostered, low stock.</summary>
    [HttpGet("alerts")]
    public async Task<IActionResult> GetAlerts([FromQuery] Guid? branchId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(now);
        var alerts = new List<object>();

        var targets = GymConfig.TargetsOf(await ModuleConfigAsync(tenantId));
        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && (!branchId.HasValue || r.BranchId == branchId.Value)).ToListAsync();
        var zones = resources.Where(r => r.Category == ResourceCategory.Room && r.Status != ResourceStatus.Archived).ToList();
        var capacity = targets.FacilityCapacity ?? (zones.Sum(z => z.Capacity ?? 0) > 0 ? zones.Sum(z => z.Capacity ?? 0) : (int?)null);

        var todays = await LoadBookingsAsync(tenantId, dayStart, dayEnd, branchId, null, null);
        var inside = todays.Count(IsInside);
        if (capacity > 0 && inside / (double)capacity * 100 >= HighOccupancyPercent)
        {
            alerts.Add(Alert("occupancy-high", inside >= capacity ? "critical" : "warning", "occupancy",
                inside >= capacity ? $"At capacity: {inside} of {capacity} inside" : $"{inside} of {capacity} inside ({Math.Round(inside / (double)capacity * 100)}%)",
                "Hold walk-ins at the desk until the floor clears, or open another zone.", inside, "/dashboard#live"));
        }

        var subs = await _db.Subscriptions.AsNoTracking()
            .Where(s => s.TenantId == tenantId && (!branchId.HasValue || s.BranchId == branchId.Value || s.BranchId == null)).ToListAsync();
        var current = subs.GroupBy(s => s.CustomerId).Select(g => g.OrderByDescending(s => s.EndDate).First()).ToList();

        var due7 = current.Where(s => IsActiveSub(s, now) && s.EndDate <= now.AddDays(RenewalUrgentDays)).ToList();
        if (due7.Count > 0)
        {
            alerts.Add(Alert("renewals-due", "warning", "memberships",
                $"{due7.Count} membership{(due7.Count == 1 ? "" : "s")} expire{(due7.Count == 1 ? "s" : "")} within {RenewalUrgentDays} days",
                $"{due7.Count(s => !s.AutoRenew)} without auto-renew. Call or message them from the renewals list.", due7.Count, "/dashboard#members"));
        }

        var unpaid = current.Where(s => !IsExpired(s, now) && IsUnpaid(s)).ToList();
        if (unpaid.Count > 0)
        {
            var failed = unpaid.Count(s => NormalizePayment(s.PaymentStatus) is "Failed" or "Overdue");
            alerts.Add(Alert("payments-unpaid", failed > 0 ? "critical" : "warning", "billing",
                $"{unpaid.Count} membership billing{(unpaid.Count == 1 ? "" : "s")} not settled",
                $"{failed} failed or overdue, LKR {unpaid.Sum(s => s.Amount):N0} outstanding. Retry the card or take payment at the desk.", unpaid.Count, "/dashboard#payments"));
        }

        var subByMember = current.ToDictionary(s => s.CustomerId);
        var lapsedInside = todays.Where(b => b.CheckInAt != null && KindOf(b) == GymConfig.Access
            && (!subByMember.TryGetValue(MemberOf(b), out var s) || IsExpired(s, now) || s.Status.Equals("Cancelled", StringComparison.OrdinalIgnoreCase))).ToList();
        if (lapsedInside.Count > 0)
        {
            alerts.Add(Alert("lapsed-checkins", "warning", "memberships",
                $"{lapsedInside.Count} check-in{(lapsedInside.Count == 1 ? "" : "s")} today by members without a valid membership",
                "Expired, cancelled or no membership on file. Renew them at the desk or restrict the keycard.", lapsedInside.Count, "/dashboard#attendance"));
        }

        var equipment = await _db.EquipmentItems.AsNoTracking()
            .Where(e => e.TenantId == tenantId && e.IsActive && (!branchId.HasValue || e.BranchId == branchId.Value)).ToListAsync();
        var equipmentIds = equipment.Select(e => e.Id).ToList();
        var maintenance = await _db.EquipmentMaintenances.AsNoTracking()
            .Where(m => m.EquipmentItemId != null && equipmentIds.Contains(m.EquipmentItemId.Value) && m.Status != "Completed").ToListAsync();
        var overdue = maintenance.Where(m => m.NextDueDate < now && m.Status != "InProgress").ToList();
        var soon = maintenance.Where(m => m.NextDueDate >= now && m.NextDueDate <= now.AddDays(MaintenanceSoonDays)).ToList();
        if (overdue.Count > 0 || soon.Count > 0)
        {
            string NameOf(EquipmentMaintenance m) => equipment.FirstOrDefault(e => e.Id == m.EquipmentItemId)?.Name ?? "Equipment";
            alerts.Add(Alert("maintenance-due", overdue.Count > 0 ? "critical" : "warning", "equipment",
                overdue.Count > 0 ? $"{overdue.Count} machine{(overdue.Count == 1 ? "" : "s")} overdue for service" : $"{soon.Count} machine{(soon.Count == 1 ? "" : "s")} due for service within {MaintenanceSoonDays} days",
                string.Join(", ", overdue.Concat(soon).OrderBy(m => m.NextDueDate).Take(4).Select(m => $"{NameOf(m)} ({m.NextDueDate:dd MMM})")), overdue.Count + soon.Count, "/dashboard#equipment"));
        }
        var inService = maintenance.Count(m => m.Status == "InProgress");
        if (inService > 0)
        {
            alerts.Add(Alert("equipment-out", "info", "equipment",
                $"{inService} machine{(inService == 1 ? "" : "s")} out of service",
                "Under maintenance right now. Update the record when it is back on the floor.", inService, "/dashboard#equipment"));
        }

        var fullClasses = todays.Where(b => KindOf(b) == GymConfig.Class && IsLive(b.Status) && b.StartTime > now)
            .GroupBy(b => new { b.BookingTypeId, b.ResourceId, b.StartTime })
            .Where(g => g.First().BookingType.MaxParticipants > 0 && g.Sum(b => Math.Max(1, b.AttendeeCount ?? 1)) >= g.First().BookingType.MaxParticipants)
            .ToList();
        if (fullClasses.Count > 0)
        {
            alerts.Add(Alert("classes-full", "info", "classes",
                $"{fullClasses.Count} class{(fullClasses.Count == 1 ? "" : "es")} today already full",
                string.Join(", ", fullClasses.Take(3).Select(g => $"{g.First().BookingType.Name} {clock.Local(g.Key.StartTime):HH:mm}")) + ". Consider a second session.", fullClasses.Count, "/dashboard#classes"));
        }

        var trainers = resources.Where(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived).Select(r => r.Id).ToList();
        if (inside > 0 && trainers.Count > 0)
        {
            var localNow = clock.Local(now);
            var onFloor = await _db.ResourceSchedules.AsNoTracking()
                .CountAsync(s => s.ResourceId != null && trainers.Contains(s.ResourceId.Value) && s.IsAvailable && s.DayOfWeek == (int)localNow.DayOfWeek
                    && s.StartTime <= localNow.TimeOfDay && localNow.TimeOfDay < s.EndTime);
            if (onFloor == 0)
            {
                alerts.Add(Alert("trainers-none", "info", "staff",
                    "Members are on the floor but no trainer is rostered right now",
                    "The roster (Resources > staff schedules) has no shift covering this hour.", inside, "/resources"));
            }
        }

        var lowStock = await _db.InventoryItems.AsNoTracking()
            .CountAsync(i => i.TenantId == tenantId && i.IsActive && i.Quantity <= i.ReorderLevel && (!branchId.HasValue || i.BranchId == branchId.Value));
        if (lowStock > 0)
        {
            alerts.Add(Alert("inventory-low", "info", "inventory",
                $"{lowStock} stock item{(lowStock == 1 ? "" : "s")} at or below reorder level",
                "Supplements, towels and consumables - see Inventory.", lowStock, "/inventory"));
        }

        return Ok(new { asOf = now, alerts });
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private sealed record MemberRow(Guid Id, string FullName, string Phone, string Email, DateTime? DateOfBirth, string? Gender, DateTime CreatedAt, bool IsActive);

    private async Task<string?> ModuleConfigAsync(Guid tenantId) =>
        await _db.TenantModules.AsNoTracking()
            .Where(m => m.TenantId == tenantId && m.ModuleName == GymConfig.MembershipsModule)
            .Select(m => m.ConfigJson).FirstOrDefaultAsync();

    private async Task<List<Booking>> LoadBookingsAsync(Guid tenantId, DateTime start, DateTime endExclusive, Guid? branchId, Guid? resourceId, Guid? bookingTypeId)
    {
        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource).ThenInclude(r => r.Branch)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null && b.StartTime >= start && b.StartTime < endExclusive);
        if (branchId.HasValue) query = query.Where(b => b.Resource.BranchId == branchId.Value);
        if (resourceId.HasValue) query = query.Where(b => b.ResourceId == resourceId.Value);
        if (bookingTypeId.HasValue) query = query.Where(b => b.BookingTypeId == bookingTypeId.Value);
        return await query.ToListAsync();
    }

    private async Task<Dictionary<Guid, MemberRow>> MembersFor(Guid tenantId, IEnumerable<Booking> bookings)
    {
        var ids = bookings.Select(MemberOf).Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, MemberRow>();
        return await _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && ids.Contains(u.Id))
            .Select(u => new MemberRow(u.Id, u.FullName, u.Phone, u.Email, u.DateOfBirth, u.Gender, u.CreatedAt, u.IsActive))
            .ToDictionaryAsync(m => m.Id);
    }

    private async Task<Dictionary<Guid, Subscription>> CurrentSubsFor(Guid tenantId, IEnumerable<Guid> memberIds)
    {
        var ids = memberIds.Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, Subscription>();
        var subs = await _db.Subscriptions.AsNoTracking().Where(s => s.TenantId == tenantId && ids.Contains(s.CustomerId)).ToListAsync();
        return subs.GroupBy(s => s.CustomerId).ToDictionary(g => g.Key, g => g.OrderByDescending(s => s.EndDate).First());
    }

    private static Guid MemberOf(Booking b) => b.BookedFor ?? b.BookedBy;
    private static string KindOf(Booking b) => GymConfig.KindOf(b.BookingType);
    private static string MethodOf(Booking b) => string.IsNullOrWhiteSpace(b.Source) ? "Front desk" : b.Source.Trim();
    private static bool IsVisit(Booking b) => b.CheckInAt != null && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected;
    private static bool IsInside(Booking b) => b.CheckInAt != null && b.CheckOutAt == null && (b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress);
    private static bool IsLive(BookingStatus s) => s != BookingStatus.Cancelled && s != BookingStatus.WeatherCancelled && s != BookingStatus.Rejected && s != BookingStatus.NoShow;

    private static bool IsExpired(Subscription s, DateTime now) => s.EndDate < now || s.Status.Equals("Expired", StringComparison.OrdinalIgnoreCase);
    private static bool IsActiveSub(Subscription s, DateTime now) => !IsExpired(s, now) && NormalizeStatus(s.Status) == "active";
    private static bool IsUnpaid(Subscription s) => NormalizePayment(s.PaymentStatus) != "Paid";
    private static string NormalizeStatus(string status) => status.Trim().ToLowerInvariant() switch { "frozen" or "paused" or "on hold" => "frozen", "cancelled" or "canceled" => "cancelled", "expired" => "expired", _ => "active" };
    private static string NormalizePayment(string? status) => (status ?? "Paid").Trim().ToLowerInvariant() switch { "pending" => "Pending", "failed" or "declined" => "Failed", "overdue" or "unpaid" => "Overdue", _ => "Paid" };
    private static int PaymentOrder(string s) => s switch { "Paid" => 0, "Pending" => 1, "Failed" => 2, _ => 3 };
    private static DateTime PaidAt(Subscription s) => s.LastPaymentAt ?? s.StartDate;

    private static decimal MonthlyValue(Subscription s) => s.BillingCycle.Trim().ToLowerInvariant() switch
    {
        "yearly" or "annual" or "annually" => Math.Round(s.Amount / 12, 2),
        "quarterly" => Math.Round(s.Amount / 3, 2),
        "weekly" => Math.Round(s.Amount * 52 / 12, 2),
        "oneoff" or "one-off" or "once" => 0m,
        _ => s.Amount,
    };

    private static string AgeBandOf(DateTime? dob, DateTime localNow)
    {
        if (dob == null) return "Not stated";
        var age = localNow.Year - dob.Value.Year;
        if (dob.Value.Date > localNow.AddYears(-age).Date) age--;
        return age < 18 ? "Under 18" : age <= 24 ? "18-24" : age <= 34 ? "25-34" : age <= 44 ? "35-44" : age <= 54 ? "45-54" : "55+";
    }

    private static object Alert(string id, string severity, string category, string title, string detail, int count, string href) =>
        new { id, severity, category, title, detail, count, href };

    private static string NormalizeGroupBy(string? groupBy) => (groupBy ?? "day").Trim().ToLowerInvariant() switch
    {
        "hour" or "hourly" => "hour",
        "week" or "weekly" => "week",
        "month" or "monthly" => "month",
        _ => "day",
    };

    private static List<object> BuildTrend(List<Booking> bookings, List<Subscription> subs, LocalClock clock, DateTime start, DateTime endExclusive, string grouping)
    {
        static DateTime BucketStart(DateTime local, string g) => g switch
        {
            "hour" => new DateTime(local.Year, local.Month, local.Day, local.Hour, 0, 0),
            "week" => local.Date.AddDays(-(((int)local.DayOfWeek + 6) % 7)),
            "month" => new DateTime(local.Year, local.Month, 1),
            _ => local.Date,
        };
        static DateTime NextBucket(DateTime d, string g) => g switch { "hour" => d.AddHours(1), "week" => d.AddDays(7), "month" => d.AddMonths(1), _ => d.AddDays(1) };
        static string Label(DateTime d, string g) => g switch
        {
            "hour" => d.ToString("HH:mm", CultureInfo.InvariantCulture),
            "week" => "Wk of " + d.ToString("dd MMM", CultureInfo.InvariantCulture),
            "month" => d.ToString("MMM yyyy", CultureInfo.InvariantCulture),
            _ => d.ToString("dd MMM", CultureInfo.InvariantCulture),
        };

        var visits = bookings.Where(IsVisit).GroupBy(b => BucketStart(clock.Local(b.CheckInAt!.Value), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var classes = bookings.Where(b => KindOf(b) == GymConfig.Class && IsLive(b.Status)).GroupBy(b => BucketStart(clock.Local(b.StartTime), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var paid = subs.Where(s => NormalizePayment(s.PaymentStatus) == "Paid").GroupBy(s => BucketStart(clock.Local(PaidAt(s)), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var starts = subs.GroupBy(s => BucketStart(clock.Local(s.StartDate), grouping)).ToDictionary(g => g.Key, g => g.ToList());
        var dropIns = bookings.Where(b => b.Status == BookingStatus.Completed && KindOf(b) != GymConfig.Access && KindOf(b) != GymConfig.Class)
            .GroupBy(b => BucketStart(clock.Local(b.StartTime), grouping)).ToDictionary(g => g.Key, g => g.ToList());

        var localStart = clock.Local(start);
        var localEnd = clock.Local(endExclusive);
        var result = new List<object>();
        var limit = grouping == "hour" ? 24 * 3 : 800;
        for (var cursor = BucketStart(localStart, grouping); cursor < localEnd && result.Count < limit; cursor = NextBucket(cursor, grouping))
        {
            visits.TryGetValue(cursor, out var v); v ??= new List<Booking>();
            classes.TryGetValue(cursor, out var c); c ??= new List<Booking>();
            paid.TryGetValue(cursor, out var p); p ??= new List<Subscription>();
            starts.TryGetValue(cursor, out var s); s ??= new List<Subscription>();
            dropIns.TryGetValue(cursor, out var d); d ??= new List<Booking>();
            result.Add(new
            {
                bucket = cursor.ToString("yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture),
                label = Label(cursor, grouping),
                visits = v.Count,
                uniqueMembers = v.Select(MemberOf).Distinct().Count(),
                classBookings = c.Count,
                signUps = s.Count,
                revenue = p.Sum(x => x.Amount) + d.Sum(x => x.TotalCost ?? 0m),
            });
        }
        return result;
    }

    /// Local-time arithmetic for one request (`tz` = minutes east of UTC).
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

    private bool TryTenant(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private Guid? ResolveBranchScope(Guid? requested)
    {
        if (User.IsInRole(UserRole.Admin.ToString()) || requested.HasValue) return requested;
        return Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId) ? branchId : null;
    }
}
