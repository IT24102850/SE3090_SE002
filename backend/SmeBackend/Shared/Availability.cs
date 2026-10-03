using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// The outcome of asking "can this booking go here?".
/// Exclusive resources fail with a conflict; shared vehicles fail with a
/// capacity error, which the caller renders as a 400 rather than a 409
/// because there is nothing conflicting - the boat is simply full.
public sealed record AvailabilityOutcome(
    string? Error, string? Warning, bool IsCapacityFailure, int? Capacity, int? SeatsRemaining);

/// The one availability rule for every path that creates or moves a booking:
/// the authenticated booking endpoints and the public website widget. Lifted
/// out of BookingsController so the anonymous path cannot drift from it.
public static class Availability
{
    public static async Task<bool> HasConflictAsync(
        AppDbContext db, Guid resourceId, DateTime start, DateTime end,
        Guid? excludeBookingId = null, bool excludeRejected = false)
    {
        return await db.Bookings.AnyAsync(b =>
            b.ResourceId == resourceId
            && b.DeletedAt == null
            && b.Status != BookingStatus.Cancelled
            && (!excludeRejected || b.Status != BookingStatus.Rejected)
            && (excludeBookingId == null || b.Id != excludeBookingId)
            && b.StartTime < end
            && b.EndTime > start);
    }

    // Sits in front of HasConflictAsync rather than replacing it.
    //
    // Exclusive occupancy (any overlap is a conflict) stays the rule for
    // every resource that has no declared passenger capacity above one -
    // consulting rooms, hire cars, and every resource that existed before
    // departures did. Only a resource whose operator has actually set a
    // capacity (CustomAttributes.capacity, Resource.Capacity, or the
    // booking type's MaxParticipants) switches to summing seats, because
    // only there does "twenty bookings on one boat" mean twenty guests on
    // one sailing rather than twenty double-bookings.
    ///
    /// <paramref name="ignoreTenantFilters"/> is for the anonymous website
    /// widget, which has no tenant context and so would never see the
    /// resource through the global TenantId filter; it has already verified
    /// the resource belongs to the tenant on the route. Signed-in callers
    /// leave it false and keep the filter as their tenant isolation.
    public static async Task<AvailabilityOutcome> CheckAsync(
        AppDbContext db, Guid resourceId, Guid bookingTypeId, Guid? departureId,
        DateTime start, DateTime end, int seats, Guid? excludeBookingId = null,
        bool ignoreTenantFilters = false)
    {
        var resources = db.Resources.AsNoTracking();
        if (ignoreTenantFilters) resources = resources.IgnoreQueryFilters().Where(r => r.DeletedAt == null);
        var resource = await resources.FirstOrDefaultAsync(r => r.Id == resourceId);
        var bookingType = await db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(bt => bt.Id == bookingTypeId);
        var departure = departureId.HasValue
            ? await db.Departures.AsNoTracking().FirstOrDefaultAsync(d => d.Id == departureId)
            : null;

        var capacity = CapacityRules.Resolve(resource, bookingType, departure);
        if (capacity is not > 1)
        {
            return await HasConflictAsync(db, resourceId, start, end, excludeBookingId)
                ? new AvailabilityOutcome("This time slot is already booked.", null, false, null, null)
                : new AvailabilityOutcome(null, null, false, null, null);
        }

        // Seats already sold on the same sailing. Matched by departure when
        // there is one, and by overlapping time otherwise, so a shared
        // resource still enforces capacity for tenants that book it without
        // creating Departure rows at all.
        var query = db.Bookings.AsNoTracking()
            .Where(b => b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected
                && (excludeBookingId == null || b.Id != excludeBookingId));

        query = departureId.HasValue
            ? query.Where(b => b.DepartureId == departureId)
            : query.Where(b => b.ResourceId == resourceId && b.StartTime < end && b.EndTime > start);

        var existing = await query
            .Select(b => new { b.TicketBreakdown, b.AttendeeCount })
            .ToListAsync();

        var seatsTaken = existing.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount));
        var check = CapacityRules.Check(capacity.Value, seatsTaken, seats);

        return new AvailabilityOutcome(
            check.Error, check.Warning, check.Error != null, check.Capacity, check.SeatsRemaining);
    }
}
