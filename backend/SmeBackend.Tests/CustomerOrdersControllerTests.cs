using System.Security.Claims;
using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests;

public class CustomerOrdersControllerTests
{
    [Fact]
    public async Task GetProducts_ReturnsOnlyPricedInStockItemsFromSelectedBranch()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.AddRange(
            Product(tenantId, branchId, "Available", 4m, 200m),
            Product(tenantId, branchId, "No price", 4m, null),
            Product(tenantId, branchId, "Bad price", 4m, -1m),
            Product(tenantId, branchId, "Out of stock", 0m, 200m),
            Product(tenantId, Guid.NewGuid(), "Other branch", 4m, 200m));
        await db.SaveChangesAsync();
        var controller = CreateController(db, tenantId, Guid.NewGuid());

        var result = await controller.GetProducts(branchId, CancellationToken.None);

        var products = Assert.IsType<OkObjectResult>(result.Result).Value
            as IReadOnlyList<CustomerProductResponse>;
        var product = Assert.Single(Assert.IsAssignableFrom<IEnumerable<CustomerProductResponse>>(products));
        Assert.Equal("Available", product.Name);
        Assert.Equal(200m, product.Price);
    }

    [Fact]
    public async Task PlaceOrder_UsesServerPriceAndReservesStockForCustomer()
    {
        var tenantId = Guid.NewGuid();
        var customerId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 10m, 75m);
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();
        var controller = CreateController(db, tenantId, customerId);

        var result = await controller.PlaceOrder(
            new PlaceCustomerOrderRequest(
                branchId,
                "Pickup",
                null,
                null,
                [new PlaceCustomerOrderLineRequest(item.Id, 2m)]),
            CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(result.Result);
        var order = Assert.IsType<CustomerOrderResponse>(created.Value);
        Assert.Equal("Pending", order.Status);
        Assert.Equal("DueOnFulfillment", order.PaymentStatus);
        Assert.Equal("Pickup", order.FulfillmentMethod);
        Assert.Equal(150m, order.Total);
        Assert.Equal(75m, Assert.Single(order.Items).UnitPrice);
        Assert.Equal(8m, (await db.InventoryItems.SingleAsync()).Quantity);
        var movement = Assert.Single(await db.StockMovements.ToListAsync());
        Assert.Equal("CustomerOrder", movement.MovementType);
        Assert.Equal(-2m, movement.Quantity);
        var notification = Assert.Single(await db.Notifications.ToListAsync());
        Assert.Equal(customerId, notification.UserId);

        var ordersResult = await controller.GetMyOrders(CancellationToken.None);
        var orders = Assert.IsType<OkObjectResult>(ordersResult.Result).Value
            as IReadOnlyList<CustomerOrderResponse>;
        Assert.Equal(order.Id, Assert.Single(Assert.IsAssignableFrom<IEnumerable<CustomerOrderResponse>>(orders)).Id);
    }

    [Fact]
    public async Task PlaceOrder_RejectsDeliveryWithoutAddressAndDoesNotReserveStock()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 10m, 75m);
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();
        var controller = CreateController(db, tenantId, Guid.NewGuid());

        var result = await controller.PlaceOrder(
            new PlaceCustomerOrderRequest(
                branchId,
                "Delivery",
                " ",
                null,
                [new PlaceCustomerOrderLineRequest(item.Id, 2m)]),
            CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result.Result);
        Assert.Equal(10m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Empty(await db.CustomerOrders.ToListAsync());
    }

    [Fact]
    public async Task PlaceOrder_RejectsUnavailableQuantityWithoutCreatingOrder()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 1m, 75m);
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        await db.SaveChangesAsync();
        var controller = CreateController(db, tenantId, Guid.NewGuid());

        var result = await controller.PlaceOrder(
            new PlaceCustomerOrderRequest(
                branchId,
                "Pickup",
                null,
                null,
                [new PlaceCustomerOrderLineRequest(item.Id, 2m)]),
            CancellationToken.None);

        Assert.IsType<ConflictObjectResult>(result.Result);
        Assert.Equal(1m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Empty(await db.CustomerOrders.ToListAsync());
    }

    [Fact]
    public async Task GetMyOrders_DoesNotReturnAnotherCustomersOrders()
    {
        var tenantId = Guid.NewGuid();
        var customerId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.CustomerOrders.AddRange(
            new CustomerOrder { TenantId = tenantId, CustomerId = customerId, BranchId = branchId, Number = "ORD-MINE" },
            new CustomerOrder { TenantId = tenantId, CustomerId = Guid.NewGuid(), BranchId = branchId, Number = "ORD-OTHER" });
        await db.SaveChangesAsync();
        var controller = CreateController(db, tenantId, customerId);

        var result = await controller.GetMyOrders(CancellationToken.None);

        var orders = Assert.IsType<OkObjectResult>(result.Result).Value
            as IReadOnlyList<CustomerOrderResponse>;
        Assert.Equal("ORD-MINE", Assert.Single(Assert.IsAssignableFrom<IEnumerable<CustomerOrderResponse>>(orders)).Number);
    }

    [Fact]
    public void CustomerOrderEndpoints_AreLimitedToCustomerRole()
    {
        var authorize = typeof(CustomerOrdersController).GetCustomAttribute<AuthorizeAttribute>();

        Assert.NotNull(authorize);
        Assert.Equal(nameof(UserRole.Customer), authorize.Roles);
    }

    private static InventoryItem Product(Guid tenantId, Guid branchId, string name, decimal quantity, decimal? price) =>
        new()
        {
            TenantId = tenantId,
            BranchId = branchId,
            Name = name,
            Sku = $"{name.ToUpperInvariant()}-{Guid.NewGuid():N}"[..16],
            Quantity = quantity,
            SellingPrice = price,
            IsActive = true,
        };

    private static CustomerOrdersController CreateController(
        AppDbContext db,
        Guid tenantId,
        Guid customerId)
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim(ClaimTypes.NameIdentifier, customerId.ToString()),
            new Claim(ClaimTypes.Role, UserRole.Customer.ToString()),
        };
        return new CustomerOrdersController(db)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(claims, "Tests")),
                },
            },
        };
    }

    private static AppDbContext CreateDbContext(Guid tenantId)
    {
        var tenantContext = new TenantContext();
        tenantContext.SetTenantId(tenantId);
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new AppDbContext(options, tenantContext);
    }
}
