using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The restaurant operations dashboard: sales and order KPIs with
/// breakdowns (overview), the live order feed with kitchen, table and
/// labor state (live), operational alerts (alerts) and the stock / waste
/// view (inventory).
///
/// Same shape and same reasons as ClinicReportsController: its own
/// controller so the role checks are the booking desk's, not the
/// inventory module's; everything derived from data the platform already
/// records; a metric with no inputs yet is null and the client draws a
/// dash, never a zero pretending to be a measurement.
///
/// How a restaurant maps onto the booking model (the whole vocabulary of
/// this file):
///   order        = Booking (a reservation, a table order, a takeaway or a
///                  delivery are all bookings against a resource)
///   menu type    = BookingType; its ConfigJson carries serviceMode,
///                  prepTargetMinutes and the recipe (RestaurantConfig)
///   channel      = Booking.Source ("POS" when blank)
///   service mode = dine-in / takeaway / delivery / drive-thru, from the
///                  menu type
///   station      = Resource: Equipment = kitchen station, Room/Desk =
///                  table, Vehicle = delivery rider, Staff = staff member
///   stages       = Pending "new" -> Confirmed "accepted" -> CheckedIn
///                  "preparing" (CheckInAt = kitchen start) -> InProgress
///                  "ready" (ConsultationStartedAt = ready) -> Completed
///                  "served / delivered" (CheckOutAt)
///   labor        = Staff resources' HourlyRate x their ResourceSchedules;
///                  there is no time clock, so "on shift" means "rostered
///                  now" and the client says so.
///
/// All hour-of-day logic (shifts, peak hours, "today", roster matching)
/// is done in the viewer's local time, passed as `tz` = minutes east of
/// UTC. Bookings are stored in UTC and a Colombo dinner service would
/// otherwise land in the UTC afternoon.
[ApiController]
[Route("api/reports/restaurant")]
[Authorize(Roles = "Admin,Manager,Staff")]
public class RestaurantReportsController : ControllerBase
{
    private readonly AppDbContext _db;

    /// A new (unaccepted) order this old is an alert.
    private const int StaleNewOrderMinutes = 10;
    /// An accepted order this far past its slot with no kitchen start is late.
    private const int LateStartGraceMinutes = 15;
    /// More open tickets than this and the kitchen is backed up.
    private const int DeepQueueTickets = 8;
    /// Labor as a share of sales above this is flagged.
    private const double HighLaborPercent = 35;
    /// Waste as a share of sales above this is flagged.
    private const double HighWastePercent = 5;

    private static readonly (string id, string label, int fromHour, int toHour)[] Shifts =
    {
        ("breakfast", "Breakfast", 6, 11),
        ("lunch", "Lunch", 11, 16),
        ("dinner", "Dinner", 16, 23),
        ("late", "Late night", 23, 30),
    };

    public RestaurantReportsController(AppDbContext db)
    {
        _db = db;
    }

    // ── Overview: KPIs + breakdowns ─────────────────────────────────────

    /// <summary>Sales, order, kitchen, labor and waste KPIs with breakdowns for a date range, with optional cross-filters. Hours use the viewer's `tz` offset (minutes east of UTC).</summary>
    [HttpGet("overview")]
    public async Task<IActionResult> GetOverview(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? branchId,
        [FromQuery] Guid? resourceId,
        [FromQuery] Guid? bookingTypeId,
        [FromQuery] string? channel,
        [FromQuery] string? serviceMode,
        [FromQuery] string? shift,
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

        var resources = await _db.Resources.AsNoTracking()
            .Include(r => r.Branch)
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null)
            .ToListAsync();
        var branches = await _db.Branches.AsNoTracking()
            .Where(b => b.TenantId == tenantId)
            .OrderBy(b => b.Name)
            .ToListAsync();
        var menuTypes = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.DeletedAt == null && bt.Status != BookingTypeStatus.Archived)
            .OrderBy(bt => bt.Name)
            .ToListAsync();

        var wantedMode = RestaurantConfig.NormalizeServiceMode(serviceMode);
        var wantedChannel = string.IsNullOrWhiteSpace(channel) ? null : channel.Trim();
        var wantedShift = NormalizeShift(shift);

        bool Matches(Booking b) =>
            (wantedMode == null || RestaurantConfig.ServiceModeOf(b.BookingType) == wantedMode)
            && (wantedChannel == null || string.Equals(ChannelOf(b), wantedChannel, StringComparison.OrdinalIgnoreCase))
            && (wantedShift == null || ShiftOf(clock.Local(b.StartTime).Hour) == wantedShift);

        var bookings = (await LoadBookingsAsync(tenantId, start, endExclusive, branchId, resourceId, bookingTypeId))
            .Where(Matches).ToList();
        // The same window immediately before, for the "vs previous period"
        // deltas on the KPI cards.
        var previousStart = start - (endExclusive - start);
        var previous = (await LoadBookingsAsync(tenantId, previousStart, start, branchId, resourceId, bookingTypeId))
            .Where(Matches).ToList();

        var completed = bookings.Where(b => b.Status == BookingStatus.Completed).ToList();
        var cancelledCount = bookings.Count(IsCancelled);
        var noShows = bookings.Count(b => b.Status == BookingStatus.NoShow);
        var decided = completed.Count + cancelledCount + noShows;
        var live = bookings.Where(IsLive).ToList();

        var revenue = completed.Sum(b => b.TotalCost ?? 0m);
        var covers = completed.Sum(CoversOf);
        var prep = bookings.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
        var tickets = bookings.Select(TicketMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
        var onTime = bookings.Count(b => PrepMinutes(b) is double m && m <= RestaurantConfig.PrepTargetMinutesOf(b.BookingType));
        var delayed = bookings.Count(b => PrepMinutes(b) is double m && m > RestaurantConfig.PrepTargetMinutesOf(b.BookingType));

        // ── Staffing and labor over the range (roster x hourly rate) ────
        var staff = StaffOf(resources, branchId);
        var staffIds = staff.Select(s => s.Id).ToList();
        var roster = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId != null && staffIds.Contains(s.ResourceId.Value) && s.IsAvailable)
            .ToListAsync();
        var (laborHours, laborCost, ratedStaff) = LaborOver(staff, roster, clock.Local(start).Date, days);
        var laborPercent = revenue > 0 && ratedStaff > 0 ? Math.Round((double)(laborCost / revenue) * 100, 1) : (double?)null;

        var headcount = await _db.Users.AsNoTracking()
            .CountAsync(u => u.TenantId == tenantId && u.IsActive
                && (u.Role == UserRole.Staff || u.Role == UserRole.Manager)
                && (!branchId.HasValue || u.BranchId == branchId.Value));

        // ── Tables and turnover ─────────────────────────────────────────
        var tables = resources.Where(r => KindOf(r) == "table" && r.Status != ResourceStatus.Archived
            && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();
        var dineInCompleted = completed.Count(b => RestaurantConfig.ServiceModeOf(b.BookingType) == RestaurantConfig.DineIn);
        var tableTurnover = tables.Count > 0 ? Math.Round(dineInCompleted / (double)tables.Count / days, 2) : (double?)null;

        // ── Waste, consumption and stock ────────────────────────────────
        var movements = await _db.StockMovements.AsNoTracking()
            .Where(m => m.TenantId == tenantId && m.OccurredAt >= start && m.OccurredAt < endExclusive
                && (m.MovementType == "Waste" || m.MovementType == RecipeConsumptionService.MovementType)
                && (!branchId.HasValue || m.BranchId == branchId.Value))
            .ToListAsync();
        var itemIds = movements.Select(m => m.InventoryItemId).Distinct().ToList();
        var items = await _db.InventoryItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && itemIds.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id);
        decimal CostOf(StockMovement m) => -m.Quantity * (m.UnitCost ?? (items.TryGetValue(m.InventoryItemId, out var i) ? i.UnitCost ?? 0m : 0m));
        var waste = movements.Where(m => m.MovementType == "Waste").ToList();
        var consumption = movements.Where(m => m.MovementType == RecipeConsumptionService.MovementType).ToList();
        var wasteCost = waste.Sum(CostOf);
        var wasteUnits = waste.Sum(m => -m.Quantity);
        var wastePercent = revenue > 0 ? Math.Round((double)(wasteCost / revenue) * 100, 1) : (double?)null;

        var lowStock = await _db.InventoryItems.AsNoTracking()
            .CountAsync(i => i.TenantId == tenantId && i.IsActive && i.Quantity <= i.ReorderLevel
                && (!branchId.HasValue || i.BranchId == branchId.Value));

        // ── Today, independent of the range ─────────────────────────────
        var (todayStart, todayEnd) = clock.Day(now);
        var todays = (await LoadBookingsAsync(tenantId, todayStart, todayEnd, branchId, resourceId, bookingTypeId)).Where(Matches).ToList();
        var todayCompleted = todays.Where(b => b.Status == BookingStatus.Completed).ToList();

        // ── Breakdowns ──────────────────────────────────────────────────
        var trend = BuildTrend(bookings, clock, start, endExclusive, grouping);

        var byHour = Enumerable.Range(0, 24).Select(h =>
        {
            var inHour = bookings.Where(b => clock.Local(b.StartTime).Hour == h).ToList();
            return new
            {
                hour = h,
                orders = inHour.Count,
                revenue = inHour.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            };
        }).ToList();

        var byShift = Shifts.Select(s =>
        {
            var inShift = bookings.Where(b => ShiftOf(clock.Local(b.StartTime).Hour) == s.id).ToList();
            var done = inShift.Where(b => b.Status == BookingStatus.Completed).ToList();
            return new
            {
                shift = s.id,
                label = s.label,
                hours = $"{s.fromHour:00}:00–{s.toHour % 24:00}:00",
                orders = inShift.Count,
                completed = done.Count,
                revenue = done.Sum(b => b.TotalCost ?? 0m),
                covers = done.Sum(CoversOf),
            };
        }).ToList();

        var byChannel = bookings
            .GroupBy(ChannelOf, StringComparer.OrdinalIgnoreCase)
            .Select(g => new
            {
                channel = g.Key,
                orders = g.Count(),
                completed = g.Count(b => b.Status == BookingStatus.Completed),
                cancelled = g.Count(IsCancelled),
                revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                covers = g.Where(b => b.Status == BookingStatus.Completed).Sum(CoversOf),
            })
            .OrderByDescending(x => x.orders)
            .ToList();

        var byServiceMode = bookings
            .GroupBy(b => RestaurantConfig.ServiceModeOf(b.BookingType))
            .Select(g =>
            {
                var p = g.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
                return new
                {
                    mode = g.Key,
                    orders = g.Count(),
                    completed = g.Count(b => b.Status == BookingStatus.Completed),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    covers = g.Where(b => b.Status == BookingStatus.Completed).Sum(CoversOf),
                    avgPrepMinutes = p.Count > 0 ? Math.Round(p.Average(), 1) : (double?)null,
                };
            })
            .OrderByDescending(x => x.orders)
            .ToList();

        var byMenu = bookings
            .GroupBy(b => b.BookingTypeId)
            .Select(g =>
            {
                var type = g.First().BookingType;
                var target = RestaurantConfig.PrepTargetMinutesOf(type);
                var p = g.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
                return new
                {
                    bookingTypeId = g.Key,
                    name = type.Name,
                    colorHex = type.ColorHex,
                    serviceMode = RestaurantConfig.ServiceModeOf(type),
                    orders = g.Count(),
                    completed = g.Count(b => b.Status == BookingStatus.Completed),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    avgPrepMinutes = p.Count > 0 ? Math.Round(p.Average(), 1) : (double?)null,
                    prepTargetMinutes = target,
                    onTimeRate = p.Count > 0 ? Math.Round(p.Count(m => m <= target) / (double)p.Count * 100, 1) : (double?)null,
                };
            })
            .OrderByDescending(x => x.orders)
            .ToList();

        var byStation = bookings
            .GroupBy(b => b.ResourceId)
            .Select(g =>
            {
                var r = g.First().Resource;
                var p = g.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
                return new
                {
                    resourceId = g.Key,
                    name = r.Name,
                    kind = KindOf(r),
                    branchName = r.Branch?.Name,
                    orders = g.Count(),
                    completed = g.Count(b => b.Status == BookingStatus.Completed),
                    cancelled = g.Count(IsCancelled),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    covers = g.Where(b => b.Status == BookingStatus.Completed).Sum(CoversOf),
                    avgPrepMinutes = p.Count > 0 ? Math.Round(p.Average(), 1) : (double?)null,
                    delayed = g.Count(b => PrepMinutes(b) is double m && m > RestaurantConfig.PrepTargetMinutesOf(b.BookingType)),
                };
            })
            .OrderByDescending(x => x.orders)
            .ToList();

        var byBranch = bookings
            .GroupBy(b => b.Resource.BranchId)
            .Select(g =>
            {
                var branch = g.Key.HasValue ? branches.FirstOrDefault(br => br.Id == g.Key.Value) : null;
                return new
                {
                    branchId = g.Key,
                    name = branch?.Name ?? "Unassigned",
                    orders = g.Count(),
                    completed = g.Count(b => b.Status == BookingStatus.Completed),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                    covers = g.Where(b => b.Status == BookingStatus.Completed).Sum(CoversOf),
                };
            })
            .OrderByDescending(x => x.revenue)
            .ThenByDescending(x => x.orders)
            .ToList();

        var statusMix = bookings
            .GroupBy(b => b.Status)
            .Select(g => new { status = g.Key.ToString(), count = g.Count() })
            .OrderByDescending(x => x.count)
            .ToList();

        var wasteByItem = waste
            .GroupBy(m => m.InventoryItemId)
            .Select(g => new
            {
                inventoryItemId = g.Key,
                name = items.TryGetValue(g.Key, out var i) ? i.Name : "Unknown item",
                units = g.Sum(m => -m.Quantity),
                cost = g.Sum(CostOf),
            })
            .OrderByDescending(x => x.cost)
            .Take(8)
            .ToList();
        var wasteByReason = waste
            .GroupBy(m => ReasonOf(m.Notes), StringComparer.OrdinalIgnoreCase)
            .Select(g => new { reason = g.Key, entries = g.Count(), units = g.Sum(m => -m.Quantity), cost = g.Sum(CostOf) })
            .OrderByDescending(x => x.cost)
            .ToList();

        var prevCompleted = previous.Where(b => b.Status == BookingStatus.Completed).ToList();
        var prevRevenue = prevCompleted.Sum(b => b.TotalCost ?? 0m);

        return Ok(new
        {
            from = clock.Local(start).Date,
            to = clock.Local(endExclusive).Date.AddDays(-1),
            groupBy = grouping,
            asOf = now,
            tz,
            filters = new { branchId, resourceId, bookingTypeId, channel = wantedChannel, serviceMode = wantedMode, shift = wantedShift },
            kpis = new
            {
                currency = "LKR",
                orders = bookings.Count,
                completed = completed.Count,
                cancelled = cancelledCount,
                noShows,
                pending = bookings.Count(b => b.Status == BookingStatus.Pending),
                open = bookings.Count(b => b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress),
                completionRate = decided > 0 ? Math.Round(completed.Count / (double)decided * 100, 1) : (double?)null,
                cancellationRate = decided > 0 ? Math.Round(cancelledCount / (double)decided * 100, 1) : (double?)null,
                revenue,
                revenueBooked = live.Where(b => b.Status != BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                averageOrderValue = completed.Count > 0 ? Math.Round(revenue / completed.Count, 2) : (decimal?)null,
                covers,
                revenuePerCover = covers > 0 ? Math.Round(revenue / covers, 2) : (decimal?)null,
                revenuePerDay = Math.Round(revenue / days, 2),
                ordersPerDay = Math.Round(bookings.Count / (double)days, 1),
                avgPrepMinutes = prep.Count > 0 ? Math.Round(prep.Average(), 1) : (double?)null,
                avgTicketMinutes = tickets.Count > 0 ? Math.Round(tickets.Average(), 1) : (double?)null,
                prepSamples = prep.Count,
                onTimeRate = prep.Count > 0 ? Math.Round(onTime / (double)prep.Count * 100, 1) : (double?)null,
                delayed,
                prepTargetMinutes = RestaurantConfig.DefaultPrepTargetMinutes,
                tables = tables.Count,
                tableTurnover,
                staffRostered = staff.Count,
                staffHeadcount = headcount,
                laborHours = Math.Round(laborHours, 1),
                laborCost = Math.Round(laborCost, 2),
                laborPercent,
                laborRated = ratedStaff,
                wasteUnits,
                wasteCost,
                wastePercent,
                wasteEntries = waste.Count,
                consumptionMovements = consumption.Count,
                consumptionCost = consumption.Sum(CostOf),
                lowStockItems = lowStock,
                ordersToday = todays.Count(IsLive),
                revenueToday = todayCompleted.Sum(b => b.TotalCost ?? 0m),
                coversToday = todayCompleted.Sum(CoversOf),
            },
            previous = new
            {
                from = clock.Local(previousStart).Date,
                to = clock.Local(start).Date.AddDays(-1),
                orders = previous.Count,
                completed = prevCompleted.Count,
                cancelled = previous.Count(IsCancelled),
                revenue = prevRevenue,
                covers = prevCompleted.Sum(CoversOf),
                averageOrderValue = prevCompleted.Count > 0 ? Math.Round(prevRevenue / prevCompleted.Count, 2) : (decimal?)null,
            },
            statusMix,
            trend,
            byHour,
            byShift,
            byChannel,
            byServiceMode,
            byMenu,
            byStation,
            byBranch,
            waste = new { byItem = wasteByItem, byReason = wasteByReason },
            filterOptions = new
            {
                branches = branches.Select(b => new { id = b.Id, name = b.Name }),
                stations = resources.Where(r => r.Status != ResourceStatus.Archived).OrderBy(r => r.Name)
                    .Select(r => new { id = r.Id, name = r.Name, kind = KindOf(r), branchId = r.BranchId }),
                menu = menuTypes.Select(bt => new { id = bt.Id, name = bt.Name, colorHex = bt.ColorHex, serviceMode = RestaurantConfig.ServiceModeOf(bt), prepTargetMinutes = RestaurantConfig.PrepTargetMinutesOf(bt) }),
                channels = bookings.Concat(previous).Select(ChannelOf).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(c => c).ToList(),
                serviceModes = new[] { RestaurantConfig.DineIn, RestaurantConfig.Takeaway, RestaurantConfig.Delivery, RestaurantConfig.DriveThru },
                shifts = Shifts.Select(s => new { id = s.id, label = s.label, hours = $"{s.fromHour:00}:00–{s.toHour % 24:00}:00" }),
            },
        });
    }

    // ── Live: today's order feed, kitchen, tables, labor ────────────────

    /// <summary>Today's live order feed with stage, ticket time and delay flags, plus kitchen throughput per station, table occupancy, sales so far and the rostered staff.</summary>
    [HttpGet("live")]
    public async Task<IActionResult> GetLive([FromQuery] DateTime? on, [FromQuery] Guid? branchId, [FromQuery] Guid? resourceId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);

        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(on.HasValue ? DateTimeUtil.AsUtc(on.Value) : now);
        var isToday = dayStart <= now && now < dayEnd;

        var bookings = (await LoadBookingsAsync(tenantId, dayStart, dayEnd, branchId, resourceId, null))
            .OrderBy(b => b.StartTime).ToList();
        var customers = await CustomersFor(tenantId, bookings);

        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && (!branchId.HasValue || r.BranchId == branchId.Value))
            .ToListAsync();
        var tables = resources.Where(r => KindOf(r) == "table" && r.Status != ResourceStatus.Archived).ToList();

        var feed = bookings.Select(b =>
        {
            customers.TryGetValue(b.BookedFor ?? b.BookedBy, out var customer);
            var target = RestaurantConfig.PrepTargetMinutesOf(b.BookingType);
            var stage = StageOf(b.Status);
            int? kitchenMinutes = stage switch
            {
                "preparing" when b.CheckInAt != null => (int)Math.Max(0, Math.Round((now - b.CheckInAt.Value).TotalMinutes)),
                "ready" or "completed" when PrepMinutes(b) is double m => (int)Math.Round(m),
                _ => null,
            };
            var waitingMinutes = stage == "new" ? (int)Math.Max(0, Math.Round((now - b.CreatedAt).TotalMinutes)) : (int?)null;
            var lateStart = stage == "accepted" && b.StartTime.AddMinutes(LateStartGraceMinutes) < now;
            return new
            {
                bookingId = b.Id,
                customerName = customer?.Role == UserRole.Customer ? customer.FullName : (TitleName(b.Title) ?? customer?.FullName ?? "Walk-in"),
                customerPhone = customer?.Role == UserRole.Customer ? customer.Phone : null,
                resourceId = b.ResourceId,
                resourceName = b.Resource.Name,
                resourceKind = KindOf(b.Resource),
                menuItem = b.BookingType.Name,
                colorHex = b.BookingType.ColorHex,
                serviceMode = RestaurantConfig.ServiceModeOf(b.BookingType),
                channel = ChannelOf(b),
                startTime = b.StartTime,
                endTime = b.EndTime,
                createdAt = b.CreatedAt,
                status = b.Status.ToString(),
                stage,
                priority = b.Priority.ToString(),
                covers = CoversOf(b),
                totalCost = b.TotalCost,
                notes = b.Notes,
                kitchenStartedAt = b.CheckInAt,
                readyAt = b.ConsultationStartedAt,
                servedAt = b.CheckOutAt,
                kitchenMinutes,
                prepTargetMinutes = target,
                isDelayed = stage == "preparing" && kitchenMinutes.HasValue && kitchenMinutes.Value > target,
                wasDelayed = (stage == "ready" || stage == "completed") && kitchenMinutes.HasValue && kitchenMinutes.Value > target,
                waitingMinutes,
                isStale = waitingMinutes.HasValue && waitingMinutes.Value >= StaleNewOrderMinutes,
                isLateStart = lateStart,
            };
        }).ToList();

        var open = feed.Where(f => f.stage == "preparing" || f.stage == "ready").ToList();
        var prepToday = bookings.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
        var onTimeToday = bookings.Count(b => PrepMinutes(b) is double m && m <= RestaurantConfig.PrepTargetMinutesOf(b.BookingType));

        var stations = bookings
            .GroupBy(b => b.ResourceId)
            .Select(g =>
            {
                var r = g.First().Resource;
                var rows = feed.Where(f => f.resourceId == g.Key).ToList();
                var p = g.Select(PrepMinutes).Where(m => m.HasValue).Select(m => m!.Value).ToList();
                return new
                {
                    resourceId = g.Key,
                    name = r.Name,
                    kind = KindOf(r),
                    orders = rows.Count(f => f.stage != "cancelled" && f.stage != "noShow"),
                    open = rows.Count(f => f.stage == "preparing" || f.stage == "ready"),
                    queued = rows.Count(f => f.stage == "new" || f.stage == "accepted"),
                    completed = rows.Count(f => f.stage == "completed"),
                    delayed = rows.Count(f => f.isDelayed),
                    avgPrepMinutes = p.Count > 0 ? Math.Round(p.Average(), 1) : (double?)null,
                    covers = rows.Where(f => f.stage == "completed").Sum(f => f.covers),
                    revenue = g.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                };
            })
            .OrderByDescending(x => x.open)
            .ThenByDescending(x => x.orders)
            .ToList();

        var occupiedTables = bookings
            .Where(b => (b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress) && tables.Any(t => t.Id == b.ResourceId))
            .Select(b => b.ResourceId).Distinct().Count();

        var completedToday = bookings.Where(b => b.Status == BookingStatus.Completed).ToList();
        var revenueToday = completedToday.Sum(b => b.TotalCost ?? 0m);
        var salesByHour = Enumerable.Range(0, 24).Select(h =>
        {
            var inHour = bookings.Where(b => clock.Local(b.StartTime).Hour == h).ToList();
            return new
            {
                hour = h,
                orders = inHour.Count(IsLive),
                revenue = inHour.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
            };
        }).ToList();

        // ── Roster and labor for the day ────────────────────────────────
        var staff = StaffOf(resources, branchId);
        var staffIds = staff.Select(s => s.Id).ToList();
        var localNow = clock.Local(now);
        var localDay = clock.Local(dayStart).Date;
        var dow = (int)localDay.DayOfWeek;
        var roster = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId != null && staffIds.Contains(s.ResourceId.Value) && s.IsAvailable && s.DayOfWeek == dow)
            .ToListAsync();
        var timeNow = isToday ? localNow.TimeOfDay : (localDay < localNow.Date ? TimeSpan.FromHours(24) : TimeSpan.Zero);

        var shifts = roster.Select(s =>
        {
            var member = staff.First(m => m.Id == s.ResourceId);
            var scheduled = ShiftHours(s);
            var elapsed = Math.Clamp((timeNow - s.StartTime).TotalHours, 0, Math.Max(0, (s.EndTime - s.StartTime).TotalHours));
            if (s.LunchBreakStart.HasValue && s.LunchBreakEnd.HasValue && timeNow > s.LunchBreakStart.Value)
                elapsed -= Math.Clamp((Math.Min(timeNow.TotalHours, s.LunchBreakEnd.Value.TotalHours) - s.LunchBreakStart.Value.TotalHours), 0, (s.LunchBreakEnd.Value - s.LunchBreakStart.Value).TotalHours);
            var onShift = isToday && s.StartTime <= timeNow && timeNow < s.EndTime;
            var busy = bookings.Any(b => b.ResourceId == member.Id && (b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress));
            return new
            {
                resourceId = member.Id,
                name = member.Name,
                role = member.Specialty,
                shiftStart = s.StartTime.ToString(@"hh\:mm"),
                shiftEnd = s.EndTime.ToString(@"hh\:mm"),
                scheduledHours = Math.Round(scheduled, 1),
                hoursSoFar = Math.Round(Math.Max(0, elapsed), 1),
                hourlyRate = member.HourlyRate,
                onShift,
                status = onShift ? (busy ? "busy" : "on shift") : (s.EndTime <= timeNow ? "finished" : "due later"),
                ordersHandled = bookings.Count(b => b.ResourceId == member.Id && IsLive(b.Status)),
            };
        })
        .OrderByDescending(s => s.onShift)
        .ThenBy(s => s.shiftStart)
        .ToList();

        var laborSoFar = shifts.Sum(s => (decimal)s.hoursSoFar * (s.hourlyRate ?? 0m));
        var laborScheduled = shifts.Sum(s => (decimal)s.scheduledHours * (s.hourlyRate ?? 0m));
        var rated = shifts.Count(s => s.hourlyRate.HasValue && s.hourlyRate.Value > 0);

        var upcoming = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed)
                && b.StartTime > now && b.StartTime <= now.AddHours(24)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value)
                && (!resourceId.HasValue || b.ResourceId == resourceId.Value))
            .OrderBy(b => b.StartTime)
            .Take(12)
            .ToListAsync();
        var upcomingCustomers = await CustomersFor(tenantId, upcoming);

        return Ok(new
        {
            asOf = now,
            date = localDay,
            isToday,
            stages = new
            {
                @new = feed.Count(f => f.stage == "new"),
                accepted = feed.Count(f => f.stage == "accepted"),
                preparing = feed.Count(f => f.stage == "preparing"),
                ready = feed.Count(f => f.stage == "ready"),
                completed = feed.Count(f => f.stage == "completed"),
                cancelled = feed.Count(f => f.stage == "cancelled"),
                noShow = feed.Count(f => f.stage == "noShow"),
            },
            kitchen = new
            {
                openTickets = open.Count,
                delayed = feed.Count(f => f.isDelayed),
                stale = feed.Count(f => f.isStale),
                lateStarts = feed.Count(f => f.isLateStart),
                longestOpenMinutes = open.Count > 0 ? open.Max(f => f.kitchenMinutes ?? 0) : (int?)null,
                avgPrepMinutesToday = prepToday.Count > 0 ? Math.Round(prepToday.Average(), 1) : (double?)null,
                onTimeRateToday = prepToday.Count > 0 ? Math.Round(onTimeToday / (double)prepToday.Count * 100, 1) : (double?)null,
                defaultTargetMinutes = RestaurantConfig.DefaultPrepTargetMinutes,
            },
            tables = new
            {
                total = tables.Count,
                occupied = occupiedTables,
                occupancyPercent = tables.Count > 0 ? Math.Round(occupiedTables / (double)tables.Count * 100, 1) : (double?)null,
            },
            sales = new
            {
                currency = "LKR",
                revenue = revenueToday,
                orders = completedToday.Count,
                covers = completedToday.Sum(CoversOf),
                averageOrderValue = completedToday.Count > 0 ? Math.Round(revenueToday / completedToday.Count, 2) : (decimal?)null,
                revenueBooked = bookings.Where(b => IsLive(b.Status) && b.Status != BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m),
                byHour = salesByHour,
            },
            labor = new
            {
                headcountRostered = staff.Count,
                onShiftNow = shifts.Count(s => s.onShift),
                scheduledToday = shifts.Count,
                hoursSoFar = Math.Round(shifts.Sum(s => s.hoursSoFar), 1),
                hoursScheduled = Math.Round(shifts.Sum(s => s.scheduledHours), 1),
                costSoFar = Math.Round(laborSoFar, 2),
                costScheduled = Math.Round(laborScheduled, 2),
                laborPercent = revenueToday > 0 && rated > 0 ? Math.Round((double)(laborSoFar / revenueToday) * 100, 1) : (double?)null,
                rated,
                shifts,
            },
            stations,
            upcoming = upcoming.Select(b =>
            {
                upcomingCustomers.TryGetValue(b.BookedFor ?? b.BookedBy, out var customer);
                return new
                {
                    bookingId = b.Id,
                    customerName = customer?.Role == UserRole.Customer ? customer.FullName : (TitleName(b.Title) ?? customer?.FullName ?? "Walk-in"),
                    customerPhone = customer?.Role == UserRole.Customer ? customer.Phone : null,
                    resourceName = b.Resource.Name,
                    menuItem = b.BookingType.Name,
                    serviceMode = RestaurantConfig.ServiceModeOf(b.BookingType),
                    channel = ChannelOf(b),
                    startTime = b.StartTime,
                    status = b.Status.ToString(),
                    covers = CoversOf(b),
                    totalCost = b.TotalCost,
                    notes = b.Notes,
                };
            }),
            feed,
        });
    }

    // ── Alerts ──────────────────────────────────────────────────────────

    /// <summary>Operational alerts: delayed tickets, unaccepted orders, a deep kitchen queue, late starts, low stock, high waste, high labor share, nobody rostered, high cancellations, stale reservation requests.</summary>
    [HttpGet("alerts")]
    public async Task<IActionResult> GetAlerts([FromQuery] Guid? branchId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);

        var now = DateTime.UtcNow;
        var (dayStart, dayEnd) = clock.Day(now);
        var alerts = new List<object>();

        var todays = await LoadBookingsAsync(tenantId, dayStart, dayEnd, branchId, null, null);

        var preparing = todays.Where(b => b.Status == BookingStatus.CheckedIn && b.CheckInAt != null).ToList();
        var delayed = preparing.Where(b => (now - b.CheckInAt!.Value).TotalMinutes > RestaurantConfig.PrepTargetMinutesOf(b.BookingType)).ToList();
        if (delayed.Count > 0)
        {
            var worst = delayed.Max(b => (now - b.CheckInAt!.Value).TotalMinutes / RestaurantConfig.PrepTargetMinutesOf(b.BookingType));
            var longest = (int)Math.Round(delayed.Max(b => (now - b.CheckInAt!.Value).TotalMinutes));
            alerts.Add(Alert("kitchen-delayed", worst >= 2 || delayed.Count >= 3 ? "critical" : "warning", "kitchen",
                $"{delayed.Count} ticket{(delayed.Count == 1 ? "" : "s")} over the prep-time target",
                $"Longest has been in the kitchen {longest} min. Check the station load on the order feed.", delayed.Count, "/dashboard#feed"));
        }

        var stale = todays.Where(b => b.Status == BookingStatus.Pending && (now - b.CreatedAt).TotalMinutes >= StaleNewOrderMinutes).ToList();
        if (stale.Count > 0)
        {
            alerts.Add(Alert("orders-unaccepted", "warning", "orders",
                $"{stale.Count} new order{(stale.Count == 1 ? "" : "s")} waiting over {StaleNewOrderMinutes} min to be accepted",
                "Accept or reject them from the order feed so the customer hears back.", stale.Count, "/dashboard#feed"));
        }

        var openTickets = todays.Count(b => b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress);
        if (openTickets >= DeepQueueTickets)
        {
            alerts.Add(Alert("kitchen-queue", "warning", "kitchen",
                $"{openTickets} tickets open in the kitchen",
                "The line is deep. Consider pausing online orders or moving a cook to the busiest station.", openTickets, "/dashboard#kitchen"));
        }

        var lateStarts = todays.Count(b => b.Status == BookingStatus.Confirmed && b.CheckInAt == null && b.StartTime.AddMinutes(LateStartGraceMinutes) < now);
        if (lateStarts > 0)
        {
            alerts.Add(Alert("orders-late-start", "warning", "orders",
                $"{lateStarts} accepted order{(lateStarts == 1 ? "" : "s")} past {LateStartGraceMinutes} min with no kitchen start",
                "Start prep, or mark the reservation a no-show so the table frees up.", lateStarts, "/dashboard#feed"));
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
                $"{lowStock.Count} stock item{(lowStock.Count == 1 ? "" : "s")} at or below reorder level",
                (outOfStock > 0 ? $"{outOfStock} out of stock. " : "") + preview, lowStock.Count, "/dashboard#inventory"));
        }

        var revenueToday = todays.Where(b => b.Status == BookingStatus.Completed).Sum(b => b.TotalCost ?? 0m);

        var wasteToday = await _db.StockMovements.AsNoTracking()
            .Where(m => m.TenantId == tenantId && m.MovementType == "Waste" && m.OccurredAt >= dayStart && m.OccurredAt < dayEnd
                && (!branchId.HasValue || m.BranchId == branchId.Value))
            .ToListAsync();
        if (wasteToday.Count > 0)
        {
            var wasteItemIds = wasteToday.Select(m => m.InventoryItemId).Distinct().ToList();
            var costs = await _db.InventoryItems.AsNoTracking()
                .Where(i => wasteItemIds.Contains(i.Id))
                .ToDictionaryAsync(i => i.Id, i => i.UnitCost ?? 0m);
            var wasteCost = wasteToday.Sum(m => -m.Quantity * (m.UnitCost ?? (costs.TryGetValue(m.InventoryItemId, out var c) ? c : 0m)));
            if (revenueToday > 0 && (double)(wasteCost / revenueToday) * 100 > HighWastePercent)
            {
                alerts.Add(Alert("waste-high", "warning", "waste",
                    $"Waste today is {Math.Round((double)(wasteCost / revenueToday) * 100, 1)}% of sales",
                    $"LKR {wasteCost:N0} written off across {wasteToday.Count} entr{(wasteToday.Count == 1 ? "y" : "ies")}. Over {HighWastePercent}% is worth a look at prep quantities.", wasteToday.Count, "/dashboard#inventory"));
            }
        }

        // Labor share right now: rostered hours so far x rate, against sales so far.
        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.DeletedAt == null && (!branchId.HasValue || r.BranchId == branchId.Value))
            .ToListAsync();
        var staff = StaffOf(resources, branchId);
        var staffIds = staff.Select(s => s.Id).ToList();
        var localNow = clock.Local(now);
        var dow = (int)localNow.DayOfWeek;
        var roster = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId != null && staffIds.Contains(s.ResourceId.Value) && s.IsAvailable && s.DayOfWeek == dow)
            .ToListAsync();
        var onShift = roster.Count(s => s.StartTime <= localNow.TimeOfDay && localNow.TimeOfDay < s.EndTime);
        var laborSoFar = roster.Sum(s =>
        {
            var member = staff.First(m => m.Id == s.ResourceId);
            var elapsed = Math.Clamp((localNow.TimeOfDay - s.StartTime).TotalHours, 0, Math.Max(0, (s.EndTime - s.StartTime).TotalHours));
            return (decimal)elapsed * (member.HourlyRate ?? 0m);
        });
        if (revenueToday > 0 && laborSoFar > 0 && (double)(laborSoFar / revenueToday) * 100 > HighLaborPercent)
        {
            alerts.Add(Alert("labor-high", "warning", "labor",
                $"Labor is {Math.Round((double)(laborSoFar / revenueToday) * 100, 1)}% of sales so far today",
                $"LKR {laborSoFar:N0} of rostered wages against LKR {revenueToday:N0} in sales. Above {HighLaborPercent}% - a quiet service or too many on the floor.", onShift, "/dashboard#staff"));
        }

        var openOrders = todays.Count(b => b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed
            || b.Status == BookingStatus.CheckedIn || b.Status == BookingStatus.InProgress);
        if (openOrders > 0 && staff.Count > 0 && onShift == 0)
        {
            alerts.Add(Alert("staff-none", "info", "labor",
                "Orders are open but nobody is rostered right now",
                "The roster (Resources > staff schedules) has no shift covering this hour. Update it if someone is in.", openOrders, "/resources"));
        }

        var cancelledToday = todays.Count(IsCancelled);
        if (todays.Count >= 4 && cancelledToday >= Math.Max(2, todays.Count / 4))
        {
            alerts.Add(Alert("cancellations-high", "warning", "orders",
                $"{cancelledToday} cancelled today ({Math.Round(cancelledToday / (double)todays.Count * 100)}% of the day's orders)",
                "Well above a normal day. Long prep times or an out-of-stock dish are the usual causes.", cancelledToday, "/dashboard#status"));
        }

        var stalePending = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.Status == BookingStatus.Pending
                && b.StartTime > now.AddHours(2)
                && b.CreatedAt < now.AddHours(-24)
                && (!branchId.HasValue || b.Resource.BranchId == branchId.Value))
            .CountAsync();
        if (stalePending > 0)
        {
            alerts.Add(Alert("reservations-stale", "info", "orders",
                $"{stalePending} reservation request{(stalePending == 1 ? "" : "s")} unconfirmed for over 24h",
                "Guests are waiting on a confirmation. Confirm or decline them from Bookings.", stalePending, "/bookings"));
        }

        return Ok(new { asOf = now, alerts });
    }

    // ── Inventory: stock levels, waste log, auto-consumption ────────────

    /// <summary>Stock levels with low-stock flags, the waste log and recipe consumption for a date range, and the latest movements.</summary>
    [HttpGet("inventory")]
    public async Task<IActionResult> GetInventory([FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? branchId, [FromQuery] int tz = 0)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        branchId = ResolveBranchScope(branchId);
        var clock = new LocalClock(tz);
        var (start, endExclusive) = clock.Range(from, to);
        var now = DateTime.UtcNow;

        var items = await _db.InventoryItems.AsNoTracking()
            .Include(i => i.Category)
            .Include(i => i.Unit)
            .Where(i => i.TenantId == tenantId && i.IsActive && (!branchId.HasValue || i.BranchId == branchId.Value))
            .OrderBy(i => i.Quantity - i.ReorderLevel)
            .ThenBy(i => i.Name)
            .ToListAsync();
        var itemsById = items.ToDictionary(i => i.Id);

        var movements = await _db.StockMovements.AsNoTracking()
            .Where(m => m.TenantId == tenantId && (!branchId.HasValue || m.BranchId == branchId.Value)
                && m.OccurredAt >= start && m.OccurredAt < endExclusive)
            .OrderByDescending(m => m.OccurredAt)
            .ToListAsync();
        var missingIds = movements.Select(m => m.InventoryItemId).Distinct().Where(id => !itemsById.ContainsKey(id)).ToList();
        if (missingIds.Count > 0)
        {
            var extra = await _db.InventoryItems.AsNoTracking().Where(i => missingIds.Contains(i.Id)).ToListAsync();
            foreach (var e in extra) itemsById[e.Id] = e;
        }
        decimal CostOf(StockMovement m) => -m.Quantity * (m.UnitCost ?? (itemsById.TryGetValue(m.InventoryItemId, out var i) ? i.UnitCost ?? 0m : 0m));
        string NameOf(StockMovement m) => itemsById.TryGetValue(m.InventoryItemId, out var i) ? i.Name : "Unknown item";

        var waste = movements.Where(m => m.MovementType == "Waste").ToList();
        var consumption = movements.Where(m => m.MovementType == RecipeConsumptionService.MovementType).ToList();

        return Ok(new
        {
            asOf = now,
            from = clock.Local(start).Date,
            to = clock.Local(endExclusive).Date.AddDays(-1),
            currency = "LKR",
            summary = new
            {
                items = items.Count,
                lowStock = items.Count(i => i.Quantity <= i.ReorderLevel),
                outOfStock = items.Count(i => i.Quantity <= 0),
                stockValue = items.Sum(i => i.Quantity * (i.UnitCost ?? 0m)),
                wasteEntries = waste.Count,
                wasteUnits = waste.Sum(m => -m.Quantity),
                wasteCost = waste.Sum(CostOf),
                consumptionMovements = consumption.Count,
                consumptionUnits = consumption.Sum(m => -m.Quantity),
                consumptionCost = consumption.Sum(CostOf),
                ordersConsumed = consumption.Select(m => m.Reference).Distinct().Count(),
            },
            items = items.Select(i => new
            {
                id = i.Id,
                name = i.Name,
                sku = i.Sku,
                category = i.Category?.Name,
                unit = i.Unit?.Name,
                quantity = i.Quantity,
                reorderLevel = i.ReorderLevel,
                unitCost = i.UnitCost,
                status = i.Quantity <= 0 ? "out" : i.Quantity <= i.ReorderLevel ? "low" : "ok",
                // Share of the reorder level on hand, capped at 200% so the
                // bar stays readable for a well-stocked item.
                levelPercent = i.ReorderLevel > 0 ? Math.Min(200, Math.Round((double)(i.Quantity / i.ReorderLevel) * 100)) : (double?)null,
                wastedInRange = waste.Where(m => m.InventoryItemId == i.Id).Sum(m => -m.Quantity),
                consumedInRange = consumption.Where(m => m.InventoryItemId == i.Id).Sum(m => -m.Quantity),
            }),
            waste = new
            {
                byItem = waste.GroupBy(m => m.InventoryItemId)
                    .Select(g => new { inventoryItemId = g.Key, name = NameOf(g.First()), entries = g.Count(), units = g.Sum(m => -m.Quantity), cost = g.Sum(CostOf) })
                    .OrderByDescending(x => x.cost).ToList(),
                byReason = waste.GroupBy(m => ReasonOf(m.Notes), StringComparer.OrdinalIgnoreCase)
                    .Select(g => new { reason = g.Key, entries = g.Count(), units = g.Sum(m => -m.Quantity), cost = g.Sum(CostOf) })
                    .OrderByDescending(x => x.cost).ToList(),
                log = waste.Take(25).Select(m => new
                {
                    id = m.Id,
                    occurredAt = m.OccurredAt,
                    item = NameOf(m),
                    units = -m.Quantity,
                    cost = CostOf(m),
                    reason = ReasonOf(m.Notes),
                    notes = m.Notes,
                    reference = m.Reference,
                }),
            },
            recentMovements = movements.Take(20).Select(m => new
            {
                id = m.Id,
                occurredAt = m.OccurredAt,
                item = NameOf(m),
                movementType = m.MovementType,
                quantity = m.Quantity,
                reference = m.Reference,
                notes = m.Notes,
            }),
        });
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private async Task<List<Booking>> LoadBookingsAsync(Guid tenantId, DateTime start, DateTime endExclusive, Guid? branchId, Guid? resourceId, Guid? bookingTypeId)
    {
        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource).ThenInclude(r => r.Branch)
            .Include(b => b.BookingType)
            .Where(b => b.TenantId == tenantId && b.DeletedAt == null
                && b.StartTime >= start && b.StartTime < endExclusive);
        if (branchId.HasValue) query = query.Where(b => b.Resource.BranchId == branchId.Value);
        if (resourceId.HasValue) query = query.Where(b => b.ResourceId == resourceId.Value);
        if (bookingTypeId.HasValue) query = query.Where(b => b.BookingTypeId == bookingTypeId.Value);
        return await query.ToListAsync();
    }

    private sealed record CustomerRow(Guid Id, string FullName, string Phone, UserRole Role);

    private async Task<Dictionary<Guid, CustomerRow>> CustomersFor(Guid tenantId, IEnumerable<Booking> bookings)
    {
        var ids = bookings.Select(b => b.BookedFor ?? b.BookedBy).Distinct().ToList();
        if (ids.Count == 0) return new Dictionary<Guid, CustomerRow>();
        return await _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && ids.Contains(u.Id))
            .Select(u => new CustomerRow(u.Id, u.FullName, u.Phone, u.Role))
            .ToDictionaryAsync(c => c.Id);
    }

    /// Walk-in and phone orders are booked by the desk, so the guest's
    /// name lives in the title ("Reservation: Nimal", "Table 4 - Perera").
    private static string? TitleName(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;
        var t = title.Trim();
        foreach (var sep in new[] { ": ", " - ", " – " })
        {
            var idx = t.IndexOf(sep, StringComparison.Ordinal);
            if (idx > 0 && idx + sep.Length < t.Length) return t[(idx + sep.Length)..].Trim();
        }
        return t;
    }

    private static string ChannelOf(Booking b) => string.IsNullOrWhiteSpace(b.Source) ? "POS" : b.Source.Trim();

    private static int CoversOf(Booking b) => Math.Max(1, b.AttendeeCount ?? 1);

    private static double? PrepMinutes(Booking b) =>
        b.CheckInAt != null && b.ConsultationStartedAt != null && b.ConsultationStartedAt >= b.CheckInAt
            ? (b.ConsultationStartedAt.Value - b.CheckInAt.Value).TotalMinutes
            : null;

    private static double? TicketMinutes(Booking b) =>
        b.CheckInAt != null && b.CheckOutAt != null && b.CheckOutAt >= b.CheckInAt
            ? (b.CheckOutAt.Value - b.CheckInAt.Value).TotalMinutes
            : null;

    private static string KindOf(Resource r) => r.Category switch
    {
        ResourceCategory.Equipment => "station",
        ResourceCategory.Room or ResourceCategory.Desk => "table",
        ResourceCategory.Vehicle => "rider",
        ResourceCategory.Staff => "staff",
        _ => "other",
    };

    private static List<Resource> StaffOf(IEnumerable<Resource> resources, Guid? branchId) =>
        resources.Where(r => r.Category == ResourceCategory.Staff && r.Status != ResourceStatus.Archived
            && (!branchId.HasValue || r.BranchId == branchId.Value)).ToList();

    private static double ShiftHours(ResourceSchedule s)
    {
        var hours = Math.Max(0, (s.EndTime - s.StartTime).TotalHours);
        if (s.LunchBreakStart.HasValue && s.LunchBreakEnd.HasValue && s.LunchBreakEnd > s.LunchBreakStart)
            hours -= (s.LunchBreakEnd.Value - s.LunchBreakStart.Value).TotalHours;
        return Math.Max(0, hours);
    }

    /// Rostered hours and wages over `days` local days from `firstDay`.
    private static (double hours, decimal cost, int ratedStaff) LaborOver(List<Resource> staff, List<ResourceSchedule> roster, DateTime firstDay, int days)
    {
        double hours = 0;
        decimal cost = 0;
        var byStaff = roster.GroupBy(s => s.ResourceId!.Value).ToDictionary(g => g.Key, g => g.ToList());
        for (var d = 0; d < days; d++)
        {
            var dow = (int)firstDay.AddDays(d).DayOfWeek;
            foreach (var member in staff)
            {
                if (!byStaff.TryGetValue(member.Id, out var rows)) continue;
                foreach (var s in rows.Where(s => s.DayOfWeek == dow))
                {
                    var h = ShiftHours(s);
                    hours += h;
                    cost += (decimal)h * (member.HourlyRate ?? 0m);
                }
            }
        }
        var rated = staff.Count(m => m.HourlyRate.HasValue && m.HourlyRate.Value > 0 && byStaff.ContainsKey(m.Id));
        return (hours, cost, rated);
    }

    private static string StageOf(BookingStatus status) => status switch
    {
        BookingStatus.Pending => "new",
        BookingStatus.Confirmed => "accepted",
        BookingStatus.CheckedIn => "preparing",
        BookingStatus.InProgress => "ready",
        BookingStatus.Completed => "completed",
        BookingStatus.NoShow => "noShow",
        _ => "cancelled",
    };

    private static bool IsCancelled(Booking b) =>
        b.Status == BookingStatus.Cancelled || b.Status == BookingStatus.WeatherCancelled || b.Status == BookingStatus.Rejected;

    private static bool IsLive(Booking b) => IsLive(b.Status);

    private static bool IsLive(BookingStatus status) =>
        status != BookingStatus.Cancelled && status != BookingStatus.WeatherCancelled
        && status != BookingStatus.Rejected && status != BookingStatus.NoShow;

    private static string ShiftOf(int localHour)
    {
        if (localHour >= 6 && localHour < 11) return "breakfast";
        if (localHour >= 11 && localHour < 16) return "lunch";
        if (localHour >= 16 && localHour < 23) return "dinner";
        return "late";
    }

    private static string? NormalizeShift(string? shift)
    {
        var s = shift?.Trim().ToLowerInvariant();
        return Shifts.Any(x => x.id == s) ? s : null;
    }

    /// Waste notes are written as "Reason: detail" by the waste endpoint.
    private static string ReasonOf(string? notes)
    {
        if (string.IsNullOrWhiteSpace(notes)) return "Unspecified";
        var idx = notes.IndexOf(':');
        var reason = idx > 0 ? notes[..idx] : notes;
        return reason.Trim().Length == 0 ? "Unspecified" : reason.Trim();
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

    private static List<object> BuildTrend(List<Booking> bookings, LocalClock clock, DateTime start, DateTime endExclusive, string grouping)
    {
        static DateTime BucketStart(DateTime local, string g) => g switch
        {
            "hour" => new DateTime(local.Year, local.Month, local.Day, local.Hour, 0, 0),
            "week" => local.Date.AddDays(-(((int)local.DayOfWeek + 6) % 7)), // Monday
            "month" => new DateTime(local.Year, local.Month, 1),
            _ => local.Date,
        };
        static DateTime NextBucket(DateTime d, string g) => g switch
        {
            "hour" => d.AddHours(1),
            "week" => d.AddDays(7),
            "month" => d.AddMonths(1),
            _ => d.AddDays(1),
        };
        static string Label(DateTime d, string g) => g switch
        {
            "hour" => d.ToString("HH:mm", CultureInfo.InvariantCulture),
            "week" => "Wk of " + d.ToString("dd MMM", CultureInfo.InvariantCulture),
            "month" => d.ToString("MMM yyyy", CultureInfo.InvariantCulture),
            _ => d.ToString("dd MMM", CultureInfo.InvariantCulture),
        };

        var grouped = bookings
            .GroupBy(b => BucketStart(clock.Local(b.StartTime), grouping))
            .ToDictionary(g => g.Key, g => g.ToList());

        var localStart = clock.Local(start);
        var localEnd = clock.Local(endExclusive);
        var result = new List<object>();
        // Hourly buckets over more than a couple of days would be hundreds
        // of points; the client only asks for "hour" on a one-day range.
        var limit = grouping == "hour" ? 24 * 3 : 800;
        for (var cursor = BucketStart(localStart, grouping); cursor < localEnd && result.Count < limit; cursor = NextBucket(cursor, grouping))
        {
            grouped.TryGetValue(cursor, out var inBucket);
            inBucket ??= new List<Booking>();
            var done = inBucket.Where(b => b.Status == BookingStatus.Completed).ToList();
            result.Add(new
            {
                bucket = cursor.ToString("yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture),
                label = Label(cursor, grouping),
                orders = inBucket.Count,
                completed = done.Count,
                cancelled = inBucket.Count(IsCancelled),
                revenue = done.Sum(b => b.TotalCost ?? 0m),
                covers = done.Sum(CoversOf),
                dineIn = inBucket.Count(b => IsLive(b) && RestaurantConfig.ServiceModeOf(b.BookingType) == RestaurantConfig.DineIn),
                offPremise = inBucket.Count(b => IsLive(b) && RestaurantConfig.ServiceModeOf(b.BookingType) != RestaurantConfig.DineIn),
            });
        }
        return result;
    }

    /// Local-time arithmetic for one request. `tz` is the viewer's offset
    /// in minutes east of UTC (JavaScript's -getTimezoneOffset()).
    private sealed class LocalClock
    {
        private readonly TimeSpan _offset;

        public LocalClock(int tzMinutes)
        {
            _offset = TimeSpan.FromMinutes(Math.Clamp(tzMinutes, -14 * 60, 14 * 60));
        }

        public DateTime Local(DateTime utc) => DateTime.SpecifyKind(utc + _offset, DateTimeKind.Unspecified);

        private DateTime Utc(DateTime local) => DateTime.SpecifyKind(local - _offset, DateTimeKind.Utc);

        /// The UTC bounds of the local calendar day containing `utc`.
        public (DateTime start, DateTime endExclusive) Day(DateTime utc)
        {
            var day = Local(utc).Date;
            return (Utc(day), Utc(day.AddDays(1)));
        }

        /// `from`/`to` are local calendar dates (the date inputs on the
        /// filter bar); the result is the UTC window covering them.
        public (DateTime start, DateTime endExclusive) Range(DateTime? from, DateTime? to)
        {
            var today = Local(DateTime.UtcNow).Date;
            var start = (from ?? today.AddDays(-29)).Date;
            var end = (to ?? today).Date;
            if (end < start) (start, end) = (end, start);
            // Cap at two years so a mistyped year cannot pull the whole table.
            if ((end - start).TotalDays > 731) start = end.AddDays(-731);
            return (Utc(start), Utc(end.AddDays(1)));
        }
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
