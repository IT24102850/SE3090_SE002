using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services;

/// Materialises AvailabilitySlots (spec 2.3) from a resource's weekly
/// ResourceSchedules.
///
/// Availability has always been *computed* on the fly from the weekly
/// pattern plus whatever bookings exist. That is correct but it cannot be
/// held: there is nothing to price differently, nothing to close for one
/// afternoon without closing the whole day, and nothing a second process
/// can take a lock on. A materialised slot is a row the business owns —
/// it can be published, withheld, marked booked, and counted.
///
/// The two views are kept deliberately consistent: generation uses the same
/// <see cref="SlotCalculator"/> the on-the-fly endpoints use, so a
/// materialised day and a computed day never disagree about where the
/// boundaries fall.
public static class AvailabilitySlotService
{
    /// A day either side is the most a caller can ask for in one go; a year
    /// of 15-minute slots is a quarter of a million rows and nobody meant it.
    public const int MaxDaysPerGeneration = 92;

    public record GenerationResult(int Created, int Skipped, int Days, DateTime From, DateTime To);

    /// Writes one slot row per free window in [from, to] for this resource.
    ///
    /// Idempotent by (ResourceId, Date, StartTime): re-running over a range
    /// that is already generated adds nothing and reports it as skipped,
    /// so a nightly job and a manual click cannot double the inventory.
    public static async Task<GenerationResult> GenerateAsync(
        AppDbContext db,
        Resource resource,
        DateTime from,
        DateTime to,
        int slotMinutes,
        CancellationToken ct = default)
    {
        from = from.Date;
        to = to.Date;

        var schedules = await db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId == resource.Id)
            .ToListAsync(ct);
        var byDay = schedules.ToDictionary(s => s.DayOfWeek);

        var closedDates = await db.ResourceScheduleExceptions.AsNoTracking()
            .Where(e => e.ResourceId == resource.Id && e.Date >= from && e.Date <= to)
            .Select(e => e.Date.Date)
            .ToListAsync(ct);
        var closed = closedDates.ToHashSet();

        // What already exists in the window, so a re-run is a no-op rather
        // than a duplicate.
        var existing = await db.AvailabilitySlots.AsNoTracking()
            .Where(s => s.ResourceId == resource.Id && s.Date >= from && s.Date <= to)
            .Select(s => new { s.Date, s.StartTime })
            .ToListAsync(ct);
        var already = existing.Select(s => (s.Date.Date, s.StartTime)).ToHashSet();

        // Bookings already on the books: a slot that is taken is generated
        // as taken, not silently offered.
        var booked = await db.Bookings.AsNoTracking()
            .Where(b => b.ResourceId == resource.Id
                && b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.Rejected
                && b.Status != BookingStatus.WeatherCancelled
                && b.StartTime < to.AddDays(1)
                && b.EndTime > from)
            .Select(b => new { b.Id, b.StartTime, b.EndTime })
            .ToListAsync(ct);

        var created = 0;
        var skipped = 0;
        var days = 0;

        for (var day = from; day <= to; day = day.AddDays(1))
        {
            days++;
            byDay.TryGetValue((int)day.DayOfWeek, out var schedule);

            var (isOpen, slots) = SlotCalculator.Calculate(
                day, schedule, slotMinutes, 0, 0,
                Array.Empty<(DateTime, DateTime)>(),
                // A generation run is about capacity, not about what is left
                // today, so "now" is the start of the day: generating this
                // morning's slots this afternoon must still produce them.
                day.Date,
                closed.Contains(day.Date));
            if (!isOpen) continue;

            foreach (var slot in slots)
            {
                var startOfDay = slot.StartTime - slot.StartTime.Date;
                if (already.Contains((day.Date, startOfDay)))
                {
                    skipped++;
                    continue;
                }

                var taken = booked.FirstOrDefault(b => b.StartTime < slot.EndTime && slot.StartTime < b.EndTime);

                db.AvailabilitySlots.Add(new AvailabilitySlot
                {
                    ResourceId = resource.Id,
                    Date = DateTime.SpecifyKind(day.Date, DateTimeKind.Utc),
                    StartTime = startOfDay,
                    EndTime = slot.EndTime - slot.EndTime.Date,
                    IsBooked = taken != null,
                    BookingId = taken?.Id,
                });
                created++;
            }
        }

        await db.SaveChangesAsync(ct);
        return new GenerationResult(created, skipped, days, from, to);
    }

    /// Marks whichever materialised slots this booking covers as taken.
    ///
    /// Silent when the resource has no materialised slots: a tenant that has
    /// never generated any is on the computed-availability path, and must
    /// keep booking normally.
    public static async Task MarkBookedAsync(AppDbContext db, Booking booking, CancellationToken ct = default)
    {
        var slots = await OverlappingAsync(db, booking, ct);
        foreach (var slot in slots)
        {
            slot.IsBooked = true;
            slot.BookingId = booking.Id;
            slot.UpdatedAt = DateTime.UtcNow;
        }
    }

    /// Hands the slots back when a booking is cancelled, rejected or moved.
    /// Only releases what this booking itself holds, so a slot another
    /// booking took is never freed by someone else's cancellation.
    public static async Task ReleaseAsync(AppDbContext db, Guid bookingId, CancellationToken ct = default)
    {
        var held = await db.AvailabilitySlots
            .Where(s => s.BookingId == bookingId)
            .ToListAsync(ct);
        foreach (var slot in held)
        {
            slot.IsBooked = false;
            slot.BookingId = null;
            slot.UpdatedAt = DateTime.UtcNow;
        }
    }

    private static async Task<List<AvailabilitySlot>> OverlappingAsync(AppDbContext db, Booking booking, CancellationToken ct)
    {
        var date = booking.StartTime.Date;
        var start = booking.StartTime - booking.StartTime.Date;
        var end = booking.EndTime - booking.StartTime.Date;

        return await db.AvailabilitySlots
            .Where(s => s.ResourceId == booking.ResourceId
                && s.Date == date
                && s.StartTime < end
                && start < s.EndTime)
            .ToListAsync(ct);
    }
}
