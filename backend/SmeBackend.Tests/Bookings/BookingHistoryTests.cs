using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests.Bookings;

/// <summary>
/// The booking timeline is written from EF Core's change tracker, so these
/// tests save bookings the way the application does and then read back what
/// was recorded. A gap here is worse than no timeline at all: an auditor
/// cannot tell "nothing happened" from "we forgot to record it".
/// </summary>
public sealed class BookingHistoryTests
{
    private sealed class Actor : ICurrentActor
    {
        public Guid? UserId { get; private set; }
        public string? Role { get; private set; }
        public void Set(Guid? userId, string? role) { UserId = userId; Role = role; }
    }

    private static readonly Guid TenantId = Guid.NewGuid();
    private static readonly DateTime Start = new(2026, 11, 3, 9, 0, 0, DateTimeKind.Utc);

    private static AppDbContext NewDb(ICurrentActor? actor, string name)
    {
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(TenantId);
        return new AppDbContext(
            new DbContextOptionsBuilder<AppDbContext>().UseInMemoryDatabase(name).Options,
            tenantContext, actor);
    }

    private static SmeBackend.Models.Booking NewBooking() => new()
    {
        TenantId = TenantId,
        ResourceId = Guid.NewGuid(),
        BookingTypeId = Guid.NewGuid(),
        BookedBy = Guid.NewGuid(),
        Title = "Consultation",
        StartTime = Start,
        EndTime = Start.AddHours(1),
        Status = BookingStatus.Pending,
    };

    private static async Task<List<BookingEvent>> EventsAsync(AppDbContext db, Guid bookingId) =>
        await db.BookingEvents.AsNoTracking()
            .Where(e => e.BookingId == bookingId)
            .OrderBy(e => e.CreatedAt).ThenBy(e => e.Id)
            .ToListAsync();

    [Fact]
    public async Task CreatingABooking_RecordsItWithTheActor()
    {
        var actor = new Actor();
        var userId = Guid.NewGuid();
        actor.Set(userId, "Manager");
        await using var db = NewDb(actor, nameof(CreatingABooking_RecordsItWithTheActor));

        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        var recorded = Assert.Single(await EventsAsync(db, booking.Id));
        Assert.Equal("Created", recorded.Type);
        Assert.Equal("Pending", recorded.ToValue);
        Assert.Equal(userId, recorded.ActorUserId);
        Assert.Equal("Manager", recorded.ActorRole);
    }

    [Fact]
    public async Task AStatusChange_RecordsBothSidesAndTheReason()
    {
        await using var db = NewDb(new Actor(), nameof(AStatusChange_RecordsBothSidesAndTheReason));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Status = BookingStatus.Cancelled;
        booking.CancellationReason = "Customer called to cancel";
        await db.SaveChangesAsync();

        var change = (await EventsAsync(db, booking.Id)).Last();
        Assert.Equal("StatusChanged", change.Type);
        Assert.Equal("Pending", change.FromValue);
        Assert.Equal("Cancelled", change.ToValue);
        Assert.Equal("Customer called to cancel", change.Reason);
    }

    [Fact]
    public async Task AReschedule_IsOneEventCarryingBothTimes()
    {
        await using var db = NewDb(new Actor(), nameof(AReschedule_IsOneEventCarryingBothTimes));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.StartTime = Start.AddDays(1);
        booking.EndTime = Start.AddDays(1).AddHours(1);
        await db.SaveChangesAsync();

        var moved = Assert.Single(await EventsAsync(db, booking.Id), e => e.Type == "Rescheduled");
        Assert.Equal("2026-11-03T09:00:00Z/2026-11-03T10:00:00Z", moved.FromValue);
        Assert.Equal("2026-11-04T09:00:00Z/2026-11-04T10:00:00Z", moved.ToValue);
    }

    [Fact]
    public async Task MovingToAnotherResource_IsRecorded()
    {
        await using var db = NewDb(new Actor(), nameof(MovingToAnotherResource_IsRecorded));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();
        var original = booking.ResourceId;

        booking.ResourceId = Guid.NewGuid();
        await db.SaveChangesAsync();

        var moved = Assert.Single(await EventsAsync(db, booking.Id), e => e.Type == "ResourceChanged");
        Assert.Equal(original.ToString(), moved.FromValue);
        Assert.Equal(booking.ResourceId.ToString(), moved.ToValue);
    }

    [Fact]
    public async Task AStatusChangeAndAReschedule_InOneSave_AreTwoEvents()
    {
        await using var db = NewDb(new Actor(), nameof(AStatusChangeAndAReschedule_InOneSave_AreTwoEvents));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Status = BookingStatus.Confirmed;
        booking.StartTime = Start.AddHours(2);
        booking.EndTime = Start.AddHours(3);
        await db.SaveChangesAsync();

        var types = (await EventsAsync(db, booking.Id)).Select(e => e.Type).ToList();
        Assert.Equal(new[] { "Created", "StatusChanged", "Rescheduled" }, types);
    }

    [Fact]
    public async Task ASoftDelete_IsRecordedAsDeleted_NotAsAStatusChange()
    {
        await using var db = NewDb(new Actor(), nameof(ASoftDelete_IsRecordedAsDeleted_NotAsAStatusChange));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Status = BookingStatus.Cancelled;
        booking.DeletedAt = DateTime.UtcNow;
        booking.CancellationReason = "Created by mistake";
        await db.SaveChangesAsync();

        var last = (await EventsAsync(db, booking.Id)).Last();
        Assert.Equal("Deleted", last.Type);
        Assert.Equal("Created by mistake", last.Reason);
        Assert.DoesNotContain(await EventsAsync(db, booking.Id), e => e.Type == "StatusChanged");
    }

    [Fact]
    public async Task ABackgroundServiceChange_IsAttributedToSystem()
    {
        // No actor: the hold sweeper and reminder dispatcher have no request.
        await using var db = NewDb(null, nameof(ABackgroundServiceChange_IsAttributedToSystem));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Status = BookingStatus.Expired;
        await db.SaveChangesAsync();

        var expiry = (await EventsAsync(db, booking.Id)).Last();
        Assert.Equal("System", expiry.ActorRole);
        Assert.Null(expiry.ActorUserId);
    }

    [Fact]
    public async Task SavingWithNothingChanged_AddsNoEvent()
    {
        await using var db = NewDb(new Actor(), nameof(SavingWithNothingChanged_AddsNoEvent));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Title = "Consultation"; // same value
        await db.SaveChangesAsync();

        Assert.Single(await EventsAsync(db, booking.Id));
    }

    [Fact]
    public async Task EditingAFieldWithNoTimelineMeaning_AddsNoEvent()
    {
        await using var db = NewDb(new Actor(), nameof(EditingAFieldWithNoTimelineMeaning_AddsNoEvent));
        var booking = NewBooking();
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        booking.Notes = "Bring previous scans";
        await db.SaveChangesAsync();

        Assert.Single(await EventsAsync(db, booking.Id));
    }
}
