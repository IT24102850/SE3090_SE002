using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;
using Xunit;

namespace SmeBackend.Tests;

public class TenantProfileControllerTests
{
    private static (AppDbContext db, Tenant tenant) SeedTenant(string businessType = "Tourism")
    {
        var db = TestHelpers.NewInMemoryDb();
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "Weligama Bay Dive Center", BusinessType = businessType, IsActive = true };
        db.Tenants.Add(tenant);
        db.SaveChanges();
        return (db, tenant);
    }

    [Fact]
    public async Task NonAdminCustomer_CannotUpdateProfile_Returns403()
    {
        var (db, tenant) = SeedTenant();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Customer);

        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            "New description", null, null, null, null, null, null, null));

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task Staff_CannotUpdateProfile_Returns403()
    {
        // Staff is a real role in this platform but never Admin/Manager-equivalent for tenant profile edits.
        var (db, tenant) = SeedTenant();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Staff);

        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            "New description", null, null, null, null, null, null, null));

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task AdminOfDifferentTenant_CannotEditThisTenantsProfile_Returns403()
    {
        // Proves tenant isolation holds even when the caller IS a real
        // Admin - just of a different tenant than the {id} in the URL.
        var (db, tenant) = SeedTenant();
        var otherTenantId = Guid.NewGuid();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), otherTenantId, Roles.Admin);

        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            "Hijacked description", null, null, null, null, null, null, null));

        Assert.IsType<ForbidResult>(result);
        // And the victim tenant's data must be completely untouched.
        var reloaded = db.Tenants.Find(tenant.Id)!;
        Assert.Null(reloaded.Description);
    }

    [Fact]
    public async Task Admin_CanUpdateOwnTenantsProfile_Succeeds()
    {
        var (db, tenant) = SeedTenant();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Admin);

        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            "A great dive center.", "PADI 5-Star Dive Center",
            new List<string> { "Free WiFi", "Parking", " Free WiFi " }, // duplicate + whitespace, should dedupe/trim
            "+94771234567", "hello@example.com", "https://example.com",
            new Dictionary<string, string> { ["instagram"] = "https://instagram.com/x" },
            null));

        Assert.IsType<OkObjectResult>(result);
        var reloaded = db.Tenants.Find(tenant.Id)!;
        Assert.Equal("A great dive center.", reloaded.Description);
        Assert.Contains("Free WiFi", reloaded.Amenities);
        Assert.DoesNotContain("\"Free WiFi\",\"Free WiFi\"", reloaded.Amenities); // no duplicate entries
        Assert.NotNull(reloaded.ProfileUpdatedAt);
    }

    [Fact]
    public async Task BusinessHours_OpenTimeAfterCloseTime_IsRejected()
    {
        var (db, tenant) = SeedTenant();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Admin);

        var badHours = new List<BusinessHourDto> { new("Monday", "18:00", "08:00", false) };
        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            null, null, null, null, null, null, null, badHours));

        Assert.IsType<BadRequestObjectResult>(result);
        var reloaded = db.Tenants.Find(tenant.Id)!;
        Assert.Null(reloaded.BusinessHours); // rejected update must not partially apply
    }

    [Fact]
    public async Task BusinessHours_ClosedDay_SkipsTimeValidation()
    {
        var (db, tenant) = SeedTenant();
        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Admin);

        var hours = new List<BusinessHourDto> { new("Sunday", null, null, true) };
        var result = await controller.UpdateProfile(tenant.Id, new UpdateTenantProfileDto(
            null, null, null, null, null, null, null, hours));

        Assert.IsType<OkObjectResult>(result);
    }

    [Fact]
    public async Task GalleryReorder_MismatchedList_IsRejected()
    {
        var (db, tenant) = SeedTenant();
        tenant.GalleryImageUrls = "[\"https://a.jpg\",\"https://b.jpg\",\"https://c.jpg\"]";
        db.SaveChanges();

        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Admin);

        // Drops "b.jpg" and injects a URL that was never uploaded.
        var tampered = new List<string> { "https://a.jpg", "https://evil.jpg", "https://c.jpg" };
        var result = await controller.ReorderGalleryImages(tenant.Id, new ReorderGalleryDto(tampered));

        Assert.IsType<BadRequestObjectResult>(result);
        var reloaded = db.Tenants.Find(tenant.Id)!;
        Assert.Equal("[\"https://a.jpg\",\"https://b.jpg\",\"https://c.jpg\"]", reloaded.GalleryImageUrls);
    }

    [Fact]
    public async Task GalleryReorder_ValidPermutation_Succeeds()
    {
        var (db, tenant) = SeedTenant();
        tenant.GalleryImageUrls = "[\"https://a.jpg\",\"https://b.jpg\",\"https://c.jpg\"]";
        db.SaveChanges();

        var controller = new TenantProfileController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenant.Id, Roles.Admin);

        var reordered = new List<string> { "https://c.jpg", "https://a.jpg", "https://b.jpg" };
        var result = await controller.ReorderGalleryImages(tenant.Id, new ReorderGalleryDto(reordered));

        Assert.IsType<OkObjectResult>(result);
        var reloaded = db.Tenants.Find(tenant.Id)!;
        Assert.Equal("[\"https://c.jpg\",\"https://a.jpg\",\"https://b.jpg\"]", reloaded.GalleryImageUrls);
    }

    [Fact]
    public async Task GetProfile_ReturnsExpectedShape_ForAnonymousCaller()
    {
        var (db, tenant) = SeedTenant();
        tenant.ShortTagline = "PADI 5-Star Dive Center";
        db.Branches.Add(new Branch { Id = Guid.NewGuid(), TenantId = tenant.Id, Name = "Main", Address = "no.134, Hettiwidiya, Weligama, Matara" });
        await db.SaveChangesAsync();

        var controller = new TenantProfileController(db);
        // No SetUser call - GetProfile is [AllowAnonymous], must work with no auth at all.

        var result = await controller.GetProfile(tenant.Id);

        var ok = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(ok.Value);
    }
}
