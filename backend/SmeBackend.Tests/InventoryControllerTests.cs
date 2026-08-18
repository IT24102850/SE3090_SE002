using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.Authorization;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Tenancy;
using System.Security.Claims;

namespace SmeBackend.Tests;

public class InventoryControllerTests
{
    [Fact]
    public async Task GetInventory_WhenTenantIdMissing_ReturnsUnauthorized()
    {
        var db = CreateDbContext();
        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity())
                }
            }
        };

        var result = await controller.GetInventory(null, false, null, 1, 20);

        Assert.IsType<UnauthorizedResult>(result.Result);
    }

    [Fact]
    public async Task AdjustInventoryItem_WhenStockIsAvailable_UpdatesQuantityAndPersistsMovement()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenant(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = "Coffee Beans",
            Sku = "SKU-001",
            BranchId = branchId,
            Quantity = 20m,
            ReorderLevel = 25m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var result = await controller.AdjustInventoryItem(item.Id, new AdjustInventoryRequest(-5m, "REF-001", "Cycle count"), CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<InventoryItemResponse>(okResult.Value);

        Assert.Equal(15m, response.Quantity);
        Assert.Equal(15m, db.InventoryItems.Single(x => x.Id == item.Id).Quantity);
        Assert.Contains(db.StockMovements, x => x.InventoryItemId == item.Id && x.Reference == "REF-001" && x.Quantity == -5m);
    }

    [Fact]
    public async Task AdjustInventoryItem_WhenAdjustmentWouldGoNegative_ReturnsConflict()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var tenantContext = new TenantContext();
        tenantContext.SetTenant(tenantId);

        await using var db = CreateDbContext(tenantContext);
        var item = new InventoryItem
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Name = "Tea",
            Sku = "SKU-002",
            BranchId = branchId,
            Quantity = 5m,
            ReorderLevel = 10m,
            IsActive = true,
        };
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();

        var authorizationService = CreateAuthorizationService();
        var controller = new InventoryController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var result = await controller.AdjustInventoryItem(item.Id, new AdjustInventoryRequest(-10m, "REF-002", "Shrinkage"), CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
    }

    private static Mock<IAuthorizationService> CreateAuthorizationService()
    {
        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService
            .Setup(x => x.AuthorizeAsync(It.IsAny<ClaimsPrincipal>(), It.IsAny<object>(), It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        return authorizationService;
    }

    private static ClaimsPrincipal CreateUser(Guid tenantId)
    {
        var identity = new ClaimsIdentity(new[]
        {
            new Claim(InventoryAccessHandler.TenantIdClaimType, tenantId.ToString())
        }, "TestAuth");

        return new ClaimsPrincipal(identity);
    }

    private static AppDbContext CreateDbContext(ITenantContext? tenantContext = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new AppDbContext(options, tenantContext ?? new TenantContext());
    }
}

public class InventoryAnalyticsTests
{
    [Fact]
    public void Predict_WhenUsageHistoryExists_ReturnsAverageAndSafetyStock()
    {
        var result = InventoryDemandPrediction.Predict(new[] { 12m, 18m, 30m }, forecastDays: 7, leadTimeDays: 7, safetyStockDays: 7);

        Assert.Equal(20m, result.AverageDailyDemand);
        Assert.Equal(140m, result.PredictedTotalDemand);
        Assert.Equal(140m, result.SafetyStock);
        Assert.InRange(result.Confidence, 0.55m, 0.99m);
    }

    [Fact]
    public void Calculate_WhenCurrentStockIsLow_UsesReorderFloorAndOrderMultiple()
    {
        var result = InventoryStockAdjustment.Calculate(
            currentStock: 18m,
            reorderLevel: 25m,
            predictedDemand: 98m,
            leadTimeDays: 7,
            safetyStockDays: 7,
            unitCost: 2.45m,
            orderMultiple: 10,
            budgetLimit: 1000m);

        Assert.Equal(180m, result.RecommendedQuantity);
        Assert.Equal("high", result.Priority);
        Assert.Equal(441m, result.TotalCost);
    }
}
