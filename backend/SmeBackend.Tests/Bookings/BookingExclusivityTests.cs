using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests.Bookings;

/// <summary>
/// The one bit the overlap exclusion constraint reads off the booking row.
/// Getting it wrong either lets a room be double booked (false when it should
/// be true) or stops a boat selling its second seat (true when it should be
/// false), so each capacity source is pinned here.
/// </summary>
public sealed class BookingExclusivityTests
{
    private static AppDbContext NewDb()
    {
        var tenantContext = new TenantContext();
        var db = new AppDbContext(
            new DbContextOptionsBuilder<AppDbContext>()
                .UseInMemoryDatabase($"exclusivity-{Guid.NewGuid()}").Options,
            tenantContext);
        return db;
    }

    private static async Task<(AppDbContext Db, Resource Resource, BookingType Type)> SeedAsync(
        int? resourceCapacity = null, int? maxParticipants = null, string? customAttributes = null)
    {
        var db = NewDb();
        var resource = new Resource
        {
            TenantId = Guid.NewGuid(),
            Name = "Thing",
            Capacity = resourceCapacity,
            CustomAttributes = customAttributes,
        };
        var type = new BookingType { TenantId = resource.TenantId, Name = "Visit", MaxParticipants = maxParticipants };
        db.Resources.Add(resource);
        db.BookingTypes.Add(type);
        await db.SaveChangesAsync();
        return (db, resource, type);
    }

    private static SmeBackend.Models.Booking BookingFor(Resource r, BookingType t, Guid? departureId = null) => new()
    {
        TenantId = r.TenantId,
        ResourceId = r.Id,
        BookingTypeId = t.Id,
        DepartureId = departureId,
        StartTime = DateTime.UtcNow,
        EndTime = DateTime.UtcNow.AddHours(1),
    };

    [Fact]
    public async Task AConsultingRoomWithNoCapacity_IsExclusive()
    {
        var (db, resource, type) = await SeedAsync();

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.True(booking.OccupiesResourceExclusively);
    }

    [Theory]
    [InlineData(1)]   // a capacity of one is still one thing at a time
    [InlineData(0)]   // zero means "not declared", per CapacityRules
    public async Task ACapacityOfOneOrZero_IsStillExclusive(int capacity)
    {
        var (db, resource, type) = await SeedAsync(resourceCapacity: capacity);

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.True(booking.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task AResourceCapacityAboveOne_SellsSeats()
    {
        var (db, resource, type) = await SeedAsync(resourceCapacity: 20);

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.False(booking.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task ABookingTypeMaxParticipantsAboveOne_SellsSeats()
    {
        var (db, resource, type) = await SeedAsync(maxParticipants: 12);

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.False(booking.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task ACustomCapacityAttributeAboveOne_SellsSeats()
    {
        var (db, resource, type) = await SeedAsync(customAttributes: """{"capacity": 40}""");

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.False(booking.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task MalformedCustomAttributes_FallBackToExclusive_RatherThanThrowing()
    {
        var (db, resource, type) = await SeedAsync(customAttributes: "not json at all");

        var booking = await BookingExclusivity.ApplyAsync(db, BookingFor(resource, type));

        Assert.True(booking.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task ApplyMany_ResolvesEachBookingAgainstItsOwnResource()
    {
        var (db, exclusiveResource, type) = await SeedAsync();
        var sharedResource = new Resource { TenantId = exclusiveResource.TenantId, Name = "Boat", Capacity = 30 };
        db.Resources.Add(sharedResource);
        await db.SaveChangesAsync();

        var onRoom = BookingFor(exclusiveResource, type);
        var onBoat = BookingFor(exclusiveResource, type);
        onBoat.ResourceId = sharedResource.Id;

        await BookingExclusivity.ApplyManyAsync(db, new[] { onRoom, onBoat });

        Assert.True(onRoom.OccupiesResourceExclusively);
        Assert.False(onBoat.OccupiesResourceExclusively);
    }

    [Fact]
    public async Task ApplyMany_OnAnEmptyListDoesNothing()
    {
        var (db, _, _) = await SeedAsync();

        await BookingExclusivity.ApplyManyAsync(db, Array.Empty<SmeBackend.Models.Booking>());
    }

    [Fact]
    public async Task AMissingResource_DefaultsToExclusive_SoTheSlotIsProtected()
    {
        var (db, resource, type) = await SeedAsync();
        var booking = BookingFor(resource, type);
        booking.ResourceId = Guid.NewGuid(); // never seeded

        await BookingExclusivity.ApplyAsync(db, booking);

        Assert.True(booking.OccupiesResourceExclusively);
    }
}
