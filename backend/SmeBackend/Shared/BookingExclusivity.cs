using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// <summary>
/// Sets <see cref="Booking.OccupiesResourceExclusively"/>, the single bit the
/// database's overlap constraint needs on the row itself.
///
/// The rule is the one <see cref="CapacityRules"/> already applies: a
/// resource with a declared capacity above one (a boat, a class, a minibus)
/// sells seats, so its bookings may overlap and are summed; everything else -
/// a consulting room, a hire car, a table - is taken whole, so an overlap is
/// a double booking.
///
/// Call this before saving any booking whose resource, booking type,
/// departure or time has just been set or changed. It is deliberately a
/// separate explicit call rather than something hidden in SaveChanges: it
/// reads three other tables, and work that touches the database should be
/// visible at the call site.
/// </summary>
public static class BookingExclusivity
{
    /// <summary>Resolves the flag for one booking from its resource, booking type and departure.</summary>
    public static async Task<Booking> ApplyAsync(AppDbContext db, Booking booking, CancellationToken ct = default)
    {
        booking.OccupiesResourceExclusively = !await IsSharedAsync(
            db, booking.ResourceId, booking.BookingTypeId, booking.DepartureId, ct);
        return booking;
    }

    /// <summary>
    /// Resolves the flag for several bookings with one query per lookup table -
    /// the bulk and recurring paths create many bookings at once.
    /// </summary>
    public static async Task ApplyManyAsync(AppDbContext db, IReadOnlyCollection<Booking> bookings, CancellationToken ct = default)
    {
        if (bookings.Count == 0) return;

        var resourceIds = bookings.Select(b => b.ResourceId).Distinct().ToList();
        var typeIds = bookings.Select(b => b.BookingTypeId).Distinct().ToList();
        var departureIds = bookings.Where(b => b.DepartureId.HasValue).Select(b => b.DepartureId!.Value).Distinct().ToList();

        var resources = await db.Resources.AsNoTracking().IgnoreQueryFilters()
            .Where(r => resourceIds.Contains(r.Id)).ToDictionaryAsync(r => r.Id, ct);
        var types = await db.BookingTypes.AsNoTracking().IgnoreQueryFilters()
            .Where(t => typeIds.Contains(t.Id)).ToDictionaryAsync(t => t.Id, ct);
        var departures = departureIds.Count == 0
            ? new Dictionary<Guid, Departure>()
            : await db.Departures.AsNoTracking().IgnoreQueryFilters()
                .Where(d => departureIds.Contains(d.Id)).ToDictionaryAsync(d => d.Id, ct);

        foreach (var booking in bookings)
        {
            resources.TryGetValue(booking.ResourceId, out var resource);
            types.TryGetValue(booking.BookingTypeId, out var type);
            Departure? departure = null;
            if (booking.DepartureId.HasValue) departures.TryGetValue(booking.DepartureId.Value, out departure);

            booking.OccupiesResourceExclusively = !CapacityRules.IsShared(resource, type, departure);
        }
    }

    private static async Task<bool> IsSharedAsync(
        AppDbContext db, Guid resourceId, Guid bookingTypeId, Guid? departureId, CancellationToken ct)
    {
        // IgnoreQueryFilters: the anonymous website widget has no tenant
        // context, and this reads nothing a caller could not already see -
        // it only decides how the row is protected.
        var resource = await db.Resources.AsNoTracking().IgnoreQueryFilters()
            .FirstOrDefaultAsync(r => r.Id == resourceId, ct);
        var bookingType = await db.BookingTypes.AsNoTracking().IgnoreQueryFilters()
            .FirstOrDefaultAsync(t => t.Id == bookingTypeId, ct);
        var departure = departureId.HasValue
            ? await db.Departures.AsNoTracking().IgnoreQueryFilters()
                .FirstOrDefaultAsync(d => d.Id == departureId.Value, ct)
            : null;

        return CapacityRules.IsShared(resource, bookingType, departure);
    }
}
