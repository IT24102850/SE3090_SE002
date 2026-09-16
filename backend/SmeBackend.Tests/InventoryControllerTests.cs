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
        tenantContext.SetTenantId(tenantId);

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
        tenantContext.SetTenantId(tenantId);

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

public class PurchaseOrdersControllerTests
{
    [Fact]
    public async Task CreatePurchaseOrder_WithItems_PersistsItemsAndComputesTotals()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();
        var itemId = Guid.NewGuid();

        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.Add(new Supplier { Id = supplierId, TenantId = tenantId, Name = "Acme Supplies" });
        db.InventoryItems.Add(new InventoryItem
        {
            Id = itemId,
            TenantId = tenantId,
            BranchId = branchId,
            Name = "Organic Coffee",
            Sku = "SKU-COF-01",
            Quantity = 10,
            UnitCost = 1500m,
            IsActive = true,
        });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var request = new CreatePurchaseOrderRequest(
            branchId,
            supplierId,
            "PO-TEST-001",
            "Draft",
            new List<PurchaseOrderItemRequest>
            {
                new(itemId, null, 10m, 1400m),
                new(null, "Paper cups (x100)", 5m, 800m),
            });

        var actionResult = await controller.CreatePurchaseOrder(request, CancellationToken.None);
        var createdResult = Assert.IsType<CreatedAtActionResult>(actionResult.Result);
        var response = Assert.IsType<PurchaseOrderResponse>(createdResult.Value);

        Assert.Equal("PO-TEST-001", response.Number);
        Assert.Equal(2, response.LineItems);
        Assert.Equal(18000m, response.TotalAmount);
        Assert.NotNull(response.Items);
        Assert.Equal(2, response.Items!.Count);
        var coffeeItem = response.Items.Single(i => i.InventoryItemId == itemId);
        Assert.Equal("Organic Coffee", coffeeItem.ItemName);
        Assert.Equal(10m, coffeeItem.Quantity);
        Assert.Equal(1400m, coffeeItem.UnitPrice);
        Assert.Equal(14000m, coffeeItem.LineTotal);

        var customItem = response.Items.Single(i => i.InventoryItemId == null);
        Assert.Equal("Paper cups (x100)", customItem.Description);
        Assert.Equal(5m, customItem.Quantity);
        Assert.Equal(800m, customItem.UnitPrice);
        Assert.Equal(4000m, customItem.LineTotal);
    }

    [Fact]
    public async Task CreatePurchaseOrder_WithNegativeQuantity_ReturnsValidationProblem()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var supplierId = Guid.NewGuid();

        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);

        await using var db = CreateDbContext(tenantContext);
        db.Branches.Add(new Branch { Id = branchId, TenantId = tenantId, Name = "Main Branch" });
        db.Suppliers.Add(new Supplier { Id = supplierId, TenantId = tenantId, Name = "Acme Supplies" });
        await db.SaveChangesAsync();

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService.Setup(x => x.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new PurchaseOrdersController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = CreateUser(tenantId)
                }
            }
        };

        var request = new CreatePurchaseOrderRequest(
            branchId,
            supplierId,
            "PO-TEST-002",
            "Draft",
            new List<PurchaseOrderItemRequest>
            {
                new(null, "Test item", -5m, 100m),
            });

        var actionResult = await controller.CreatePurchaseOrder(request, CancellationToken.None);
        Assert.IsType<ObjectResult>(actionResult.Result);
    }

    private static ClaimsPrincipal CreateUser(Guid tenantId)
    {
        var claims = new[]
        {
            new Claim(InventoryAccessHandler.TenantIdClaimType, tenantId.ToString()),
            new Claim(ClaimTypes.Role, UserRole.Admin.ToString()),
        };
        return new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth"));
    }

    private static AppDbContext CreateDbContext(ITenantContext? tenantContext = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new AppDbContext(options, tenantContext ?? new TenantContext());
    }
}
