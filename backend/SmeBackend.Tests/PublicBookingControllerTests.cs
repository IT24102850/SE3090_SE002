using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

// The website widget's anonymous endpoints. The DbContext here has NO tenant
// context, exactly like a real anonymous request, so these tests also prove
// the global TenantId query filters are bypassed where they must be.
public class PublicBookingControllerTests
{
    private static readonly Guid TenantId = Guid.NewGuid();

    private sealed record Seeded(AppDbContext Db, Guid ResourceId, Guid BookingTypeId, Guid DepartureId);

    private static async Task<Seeded> SeedAsync(int capacity = 20)
    {
        var db = TestHelpers.NewInMemoryDb(tenantId: null);

        db.Tenants.Add(new Tenant { Id = TenantId, Name = "Mirissa Jetliner", BusinessType = "Tourism", SubType = "Whale / dolphin watching" });

        var resource = new Resource { TenantId = TenantId, Name = "Sea Guardian", Category = ResourceCategory.Vehicle, Status = ResourceStatus.Available, Capacity = capacity };
        var bookingType = new BookingType
        {
            TenantId = TenantId, Name = "Whale Watching Tour", Slug = "whale-watching", Status = BookingTypeStatus.Active,
            DefaultDurationMinutes = 240,
            ConfigJson = """{ "pricing": { "adult": 7500, "child": 4000, "infant": 0, "currency": "LKR" } }""",
        };
        var departure = new Departure
        {
            TenantId = TenantId, ResourceId = resource.Id, Resource = resource, BookingTypeId = bookingType.Id, BookingType = bookingType,
            ScheduledDeparture = DateTime.UtcNow.AddDays(3).Date.AddHours(6.5), ScheduledReturn = DateTime.UtcNow.AddDays(3).Date.AddHours(10.5),
            Status = DepartureStatus.Scheduled,
        };
        db.Resources.Add(resource);
        db.BookingTypes.Add(bookingType);
        db.Departures.Add(departure);
        await db.SaveChangesAsync();

        return new Seeded(db, resource.Id, bookingType.Id, departure.Id);
    }

    private static PublicBookingRequest Request(Guid departureId, int adults = 2, int children = 1) => new()
    {
        FullName = "Amaya Perera", Email = "Amaya.Test@Example.com", Phone = "+94 77 123 4567",
        DepartureId = departureId, Adults = adults, Children = children, Notes = "Vegetarian snacks please",
    };

    [Fact]
    public async Task Catalog_ListsUpcomingDeparturesAndResources_WithoutTenantContext()
    {
        var s = await SeedAsync();
        var result = await new PublicBookingController(s.Db).Catalog(TenantId);

        var ok = Assert.IsType<OkObjectResult>(result);
        var json = System.Text.Json.JsonSerializer.Serialize(ok.Value);
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        var root = doc.RootElement;

        Assert.Equal("Mirissa Jetliner", root.GetProperty("tenant").GetProperty("Name").GetString());
        Assert.Equal(1, root.GetProperty("departures").GetArrayLength());
        Assert.Equal(1, root.GetProperty("resources").GetArrayLength());
        var dep = root.GetProperty("departures")[0];
        Assert.Equal("Sea Guardian", dep.GetProperty("vesselName").GetString());
        Assert.Equal(20, dep.GetProperty("capacity").GetInt32());
        Assert.Equal(20, dep.GetProperty("seatsRemaining").GetInt32());
        var pricing = root.GetProperty("bookingTypes")[0].GetProperty("pricing");
        Assert.Equal(7500, pricing.GetProperty("adult").GetDecimal());
        Assert.Equal(4000, pricing.GetProperty("child").GetDecimal());
    }

    [Fact]
    public async Task Catalog_UnknownTenant_Is404()
    {
        var s = await SeedAsync();
        Assert.IsType<NotFoundObjectResult>(await new PublicBookingController(s.Db).Catalog(Guid.NewGuid()));
    }

    [Fact]
    public async Task Create_BooksADeparture_AsPendingWebsiteBooking_ForAGuestAccount()
    {
        var s = await SeedAsync();
        var result = await new PublicBookingController(s.Db).Create(TenantId, Request(s.DepartureId));

        Assert.IsType<OkObjectResult>(result);

        var booking = await s.Db.Bookings.IgnoreQueryFilters().SingleAsync();
        Assert.Equal(TenantId, booking.TenantId);
        Assert.Equal(BookingStatus.Pending, booking.Status);
        Assert.Equal(PublicBookingController.Source, booking.Source);
        Assert.Equal(s.DepartureId, booking.DepartureId);
        Assert.Equal(s.ResourceId, booking.ResourceId);
        Assert.Equal(s.BookingTypeId, booking.BookingTypeId);
        Assert.Equal(3, booking.AttendeeCount);
        Assert.Equal(2 * 7500m + 4000m, booking.TotalCost);
        Assert.Equal("Vegetarian snacks please", booking.Notes);

        // Priced server-side from the booking type, never from the request.
        var lines = TicketPricing.Parse(booking.TicketBreakdown);
        Assert.Equal(7500m, lines.Single(l => l.Type == "Adult").UnitPrice);
        Assert.Equal(4000m, lines.Single(l => l.Type == "Child").UnitPrice);

        // The guest got a Customer account in this tenant, keyed on a
        // normalised email, and the booking is theirs.
        var guest = await s.Db.Users.IgnoreQueryFilters().SingleAsync();
        Assert.Equal("amaya.test@example.com", guest.Email);
        Assert.Equal(UserRole.Customer, guest.Role);
        Assert.Equal(TenantId, guest.TenantId);
        Assert.Equal(guest.Id, booking.BookedBy);

        // And the whole team hears about it (tenant-wide notification).
        var note = await s.Db.Notifications.IgnoreQueryFilters().SingleAsync();
        Assert.Equal("WebsiteBooking", note.Type);
        Assert.Null(note.UserId);
        Assert.Equal(TenantId, note.TenantId);
    }

    [Fact]
    public async Task Create_SecondBookingBySameEmail_ReusesTheGuestAccount()
    {
        var s = await SeedAsync();
        var controller = new PublicBookingController(s.Db);
        Assert.IsType<OkObjectResult>(await controller.Create(TenantId, Request(s.DepartureId)));
        Assert.IsType<OkObjectResult>(await controller.Create(TenantId, Request(s.DepartureId, adults: 1, children: 0)));

        Assert.Equal(1, await s.Db.Users.IgnoreQueryFilters().CountAsync());
        Assert.Equal(2, await s.Db.Bookings.IgnoreQueryFilters().CountAsync());
    }

    [Fact]
    public async Task Create_RespectsTheSailingsCapacity()
    {
        var s = await SeedAsync(capacity: 5);
        var controller = new PublicBookingController(s.Db);

        Assert.IsType<OkObjectResult>(await controller.Create(TenantId, Request(s.DepartureId, adults: 3, children: 0)));

        var full = await controller.Create(TenantId, Request(s.DepartureId, adults: 3, children: 0));
        var bad = Assert.IsType<BadRequestObjectResult>(full);
        var json = System.Text.Json.JsonSerializer.Serialize(bad.Value);
        Assert.Contains("seatsRemaining", json);
        Assert.Equal(1, await s.Db.Bookings.IgnoreQueryFilters().CountAsync());
    }

    [Fact]
    public async Task Create_HoneypotFilled_PretendsToSucceedAndStoresNothing()
    {
        var s = await SeedAsync();
        var req = Request(s.DepartureId);
        req.Website = "http://spam.example";

        Assert.IsType<OkObjectResult>(await new PublicBookingController(s.Db).Create(TenantId, req));
        Assert.Equal(0, await s.Db.Bookings.IgnoreQueryFilters().CountAsync());
        Assert.Equal(0, await s.Db.Users.IgnoreQueryFilters().CountAsync());
    }

    [Theory]
    [InlineData(0, 2)]   // children cannot travel alone
    [InlineData(0, 0)]   // nothing at all
    [InlineData(21, 0)]  // over the per-booking cap
    public async Task Create_RejectsBadTicketCounts(int adults, int children)
    {
        var s = await SeedAsync(capacity: 100);
        var result = await new PublicBookingController(s.Db).Create(TenantId, Request(s.DepartureId, adults, children));
        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, await s.Db.Bookings.IgnoreQueryFilters().CountAsync());
    }

    [Fact]
    public async Task Create_DepartureOfAnotherTenant_Is404()
    {
        var s = await SeedAsync();
        var result = await new PublicBookingController(s.Db).Create(Guid.NewGuid(), Request(s.DepartureId));
        Assert.IsType<NotFoundObjectResult>(result);
    }
}
