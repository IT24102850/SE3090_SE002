using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests;

public class BranchesControllerTests
{
    [Fact]
    public async Task Create_RejectsIncompleteCoordinates()
    {
        var tenantId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        var controller = new BranchesController(db, Moq.Mock.Of<SmeBackend.Services.PlatformBilling.IEntitlementService>());

        var result = await controller.Create(new CreateBranchDto(
            tenantId,
            "North branch",
            null,
            null,
            6.9271m,
            null), default);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Empty(db.Branches);
    }

    [Theory]
    [InlineData(91, 0)]
    [InlineData(0, 181)]
    [InlineData(-91, 0)]
    public async Task Create_RejectsCoordinatesOutsideEarthBounds(
        decimal latitude,
        decimal longitude)
    {
        var tenantId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        var controller = new BranchesController(db, Moq.Mock.Of<SmeBackend.Services.PlatformBilling.IEntitlementService>());

        var result = await controller.Create(new CreateBranchDto(
            tenantId,
            "North branch",
            null,
            null,
            latitude,
            longitude), default);

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Empty(db.Branches);
    }

    [Fact]
    public async Task Create_PersistsValidOptionalCoordinates()
    {
        var tenantId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        var controller = new BranchesController(db, Moq.Mock.Of<SmeBackend.Services.PlatformBilling.IEntitlementService>());
        var latitude = 6.9271m;
        var longitude = 79.8612m;

        var result = await controller.Create(new CreateBranchDto(
            tenantId,
            "North branch",
            null,
            null,
            latitude,
            longitude), default);

        Assert.IsType<OkObjectResult>(result);
        var branch = Assert.Single(db.Branches);
        Assert.Equal(latitude, branch.Latitude);
        Assert.Equal(longitude, branch.Longitude);
    }

    private static AppDbContext CreateDbContext(Guid tenantId)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        return new AppDbContext(options, tenantContext);
    }
}
