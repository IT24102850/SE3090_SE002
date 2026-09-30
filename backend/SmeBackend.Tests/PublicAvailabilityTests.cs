using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using Xunit;

namespace SmeBackend.Tests;

/// GET /api/bookings/available-slots is AllowAnonymous because the booking
/// widget runs on the business's own website with no token.
///
/// That is the whole point of these tests. Resource carries a global
/// TenantId == CurrentTenantId filter, and an anonymous request has no
/// tenant context, so the resource lookup matched nothing and the endpoint
/// answered 404 for every real resource. The widget catches the failure and
/// renders an empty list, which reads as "No times available that day" - so
/// a live booking page showed every business as permanently full, with
/// nothing in the UI to suggest a fault.
///
/// The authenticated path kept working throughout, which is exactly why it
/// survived: every test and every manual check went through a token.
public class PublicAvailabilityTests
{
    private static readonly DateTime Monday = new(2026, 9, 21, 0, 0, 0, DateTimeKind.Utc);

    private sealed record Seeded(AppDbContext Db, Guid TenantId, Guid ResourceId);

    /// Built with no tenant in context - the shape of an anonymous request.
    private static async Task<Seeded> SeedAsync(bool tenantActive = true)
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId: null);

        db.Tenants.Add(new Tenant
        {
            Id = tenantId,
            Name = "Mirissa Jet Liner",
            BusinessType = "Tourism",
            IsActive = tenantActive,
        });

        var resource = new Resource
        {
            TenantId = tenantId,
            Name = "Whale Watching Boat",
            Category = ResourceCategory.Equipment,
            Status = ResourceStatus.Available,
        };
        db.Resources.Add(resource);
        db.ResourceSchedules.Add(new ResourceSchedule
        {
            ResourceId = resource.Id,
            DayOfWeek = (int)Monday.DayOfWeek,
            StartTime = TimeSpan.FromHours(9),
            EndTime = TimeSpan.FromHours(17),
            IsAvailable = true,
        });
        await db.SaveChangesAsync();

        return new Seeded(db, tenantId, resource.Id);
    }

    private static BookingsController Anonymous(AppDbContext db)
    {
        var controller = new BookingsController(db, new NullReminderSender(), new NullPushSender());
        // No ClaimsPrincipal at all: nothing has set a tenant, which is what
        // the middleware leaves behind for an unauthenticated caller.
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        return controller;
    }

    private static T Body<T>(IActionResult result) where T : class
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        return Assert.IsAssignableFrom<T>(ok.Value!);
    }

    [Fact]
    public async Task Anonymous_caller_gets_the_slots_for_a_real_resource()
    {
        var s = await SeedAsync();

        var result = await Anonymous(s.Db).GetAvailableSlots(s.ResourceId, Monday);

        // The regression: this used to be NotFoundObjectResult.
        Assert.IsType<OkObjectResult>(result);
    }

    [Fact]
    public async Task Anonymous_and_authenticated_callers_see_the_same_day()
    {
        var anon = await SeedAsync();
        var anonResult = await Anonymous(anon.Db).GetAvailableSlots(anon.ResourceId, Monday);

        // The same fixture, this time with a tenant in context.
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = new Resource
        {
            TenantId = tenantId,
            Name = "Whale Watching Boat",
            Category = ResourceCategory.Equipment,
            Status = ResourceStatus.Available,
        };
        db.Resources.Add(resource);
        db.ResourceSchedules.Add(new ResourceSchedule
        {
            ResourceId = resource.Id,
            DayOfWeek = (int)Monday.DayOfWeek,
            StartTime = TimeSpan.FromHours(9),
            EndTime = TimeSpan.FromHours(17),
            IsAvailable = true,
        });
        db.Tenants.Add(new Tenant { Id = tenantId, Name = "T", BusinessType = "Tourism", IsActive = true });
        await db.SaveChangesAsync();

        var authed = new BookingsController(db, new NullReminderSender(), new NullPushSender());
        TestHelpers.SetUser(authed, Guid.NewGuid(), tenantId, "Admin");
        var authedResult = await authed.GetAvailableSlots(resource.Id, Monday);

        // A public visitor and a signed-in member of staff must not disagree
        // about whether the boat sails.
        Assert.Equal(SlotCount(authedResult), SlotCount(anonResult));
        Assert.True(SlotCount(anonResult) > 0, "A nine-to-five Monday has bookable hours.");
    }

    [Fact]
    public async Task An_unknown_resource_is_still_not_found()
    {
        var s = await SeedAsync();

        var result = await Anonymous(s.Db).GetAvailableSlots(Guid.NewGuid(), Monday);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    /// Dropping the tenant filter must not become a way to read a suspended
    /// business's diary - or to keep selling seats it can no longer honour.
    [Fact]
    public async Task A_suspended_business_exposes_nothing()
    {
        var s = await SeedAsync(tenantActive: false);

        var result = await Anonymous(s.Db).GetAvailableSlots(s.ResourceId, Monday);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task A_soft_deleted_resource_is_not_bookable()
    {
        var s = await SeedAsync();
        var resource = await s.Db.Resources.IgnoreQueryFilters()
            .FirstAsync(r => r.Id == s.ResourceId);
        resource.DeletedAt = DateTime.UtcNow;
        await s.Db.SaveChangesAsync();

        var result = await Anonymous(s.Db).GetAvailableSlots(s.ResourceId, Monday);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    private static int SlotCount(IActionResult result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        var slots = ok.Value!.GetType().GetProperty("slots")!.GetValue(ok.Value!);
        return ((System.Collections.IEnumerable)slots!).Cast<object>().Count();
    }

    /// This endpoint sends nothing; the controller just needs its collaborators.
    private sealed class NullReminderSender : IReminderChannelSender
    {
        public Task<ReminderDeliveryResult> SendAsync(Booking booking, string channel, CancellationToken ct = default) =>
            Task.FromResult(ReminderDeliveryResult.Simulated("test"));
    }

    private sealed class NullPushSender : IPushNotificationSender
    {
        public Task SendAsync(Guid tenantId, Guid userId, string title, string message) => Task.CompletedTask;
    }
}
