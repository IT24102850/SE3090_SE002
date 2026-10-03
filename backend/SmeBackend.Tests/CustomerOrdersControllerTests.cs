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
using SmeBackend.Services.Billing;
using SmeBackend.DTOs;
using Moq;

namespace SmeBackend.Tests;

public class CustomerOrdersControllerTests
{
    [Fact]
    public async Task GetProducts_ReturnsOnlyPricedInStockItemsFromSelectedBranch()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var availableProduct = Product(tenantId, branchId, "Available", 4m, 200m);
        availableProduct.ImageUrl = "https://images.example.test/available.jpg";
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.AddRange(
            availableProduct,
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
        Assert.Equal(availableProduct.ImageUrl, product.ImageUrl);
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
        db.Users.Add(new User
        {
            Id = customerId,
            TenantId = tenantId,
            Email = "customer@example.test",
            FullName = "Test Customer",
            Role = UserRole.Customer,
        });
        await db.SaveChangesAsync();
        var messenger = new NoopBillingMessenger();
        var controller = CreateController(db, tenantId, customerId, messenger);

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
        Assert.Single(messenger.SentEmails);
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
    public async Task PlaceOrder_StoresOptionalDeliveryPinAndInitialTrackingUpdate()
    {
        var tenantId = Guid.NewGuid();
        var customerId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 10m, 75m);
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        db.Users.Add(new User
        {
            Id = customerId,
            TenantId = tenantId,
            Email = "customer@example.test",
            FullName = "Test Customer",
            Role = UserRole.Customer,
        });
        await db.SaveChangesAsync();
        var messenger = new NoopBillingMessenger();
        var controller = CreateController(db, tenantId, customerId, messenger);

        var result = await controller.PlaceOrder(
            new PlaceCustomerOrderRequest(
                branchId,
                "Delivery",
                "12 Main Road",
                null,
                [new PlaceCustomerOrderLineRequest(item.Id, 1m)],
                6.9271m,
                79.8612m),
            CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(result.Result);
        var order = Assert.IsType<CustomerOrderResponse>(created.Value);
        Assert.Equal(6.9271m, order.DeliveryLatitude);
        Assert.Equal(79.8612m, order.DeliveryLongitude);
        Assert.Equal("Pending", Assert.Single(order.StatusUpdates).Status);
        Assert.Single(messenger.SentEmails);
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

    [Fact]
    public async Task ManagerCanCancelOrderAndReleaseReservedStockOnce()
    {
        var tenantId = Guid.NewGuid();
        var customerId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 8m, 75m);
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        var order = new CustomerOrder
        {
            TenantId = tenantId,
            CustomerId = customerId,
            BranchId = branchId,
            Number = "ORD-CANCEL",
            Status = "Pending",
        };
        order.Items.Add(new CustomerOrderItem
        {
            TenantId = tenantId,
            CustomerOrderId = order.Id,
            InventoryItemId = item.Id,
            ItemName = item.Name,
            Sku = item.Sku,
            Quantity = 2m,
            UnitPrice = 75m,
            LineTotal = 150m,
        });
        db.CustomerOrders.Add(order);
        var customer = new User
        {
            Id = customerId,
            TenantId = tenantId,
            Email = "customer@example.test",
            FullName = "Test Customer",
            Role = UserRole.Customer,
        };
        db.Users.Add(customer);
        await db.SaveChangesAsync();
        var messenger = new NoopBillingMessenger();
        var controller = CreateManagerController(db, tenantId, messenger);

        var result = await controller.UpdateStatus(
            order.Id,
            new UpdateCustomerOrderStatusRequest("Cancelled", null),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(10m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Equal("Cancelled", (await db.CustomerOrders.SingleAsync()).Status);
        Assert.Equal("CustomerOrderCancellation", Assert.Single(await db.StockMovements.ToListAsync()).MovementType);
        Assert.Single(messenger.SentEmails);
        var secondUpdate = await controller.UpdateStatus(
            order.Id,
            new UpdateCustomerOrderStatusRequest("Cancelled", null),
            CancellationToken.None);
        Assert.IsType<ConflictObjectResult>(secondUpdate);
        Assert.Equal(10m, (await db.InventoryItems.SingleAsync()).Quantity);
        Assert.Single(messenger.SentEmails);
    }

    [Fact]
    public async Task CompleteOrder_RecordsSalesWithoutDeductingReservedStockAgain()
    {
        var tenantId = Guid.NewGuid();
        var customerId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        var item = Product(tenantId, branchId, "Tea", 8m, 75m);
        item.UnitCost = 30m;
        await using var db = CreateDbContext(tenantId);
        db.Branches.Add(new Branch { TenantId = tenantId, Id = branchId, Name = "Main" });
        db.InventoryItems.Add(item);
        db.Users.Add(new User
        {
            Id = customerId,
            TenantId = tenantId,
            Email = "customer@example.test",
            FullName = "Test Customer",
            Role = UserRole.Customer,
        });
        var order = new CustomerOrder
        {
            TenantId = tenantId,
            CustomerId = customerId,
            BranchId = branchId,
            Number = "ORD-FULFILLED",
            Status = "ReadyForPickup",
            FulfillmentMethod = "Pickup",
            Total = 150m,
        };
        order.Items.Add(new CustomerOrderItem
        {
            TenantId = tenantId,
            CustomerOrderId = order.Id,
            InventoryItemId = item.Id,
            ItemName = item.Name,
            Sku = item.Sku,
            Quantity = 2m,
            UnitPrice = 75m,
            LineTotal = 150m,
        });
        db.CustomerOrders.Add(order);
        db.StockMovements.Add(new StockMovement
        {
            TenantId = tenantId,
            BranchId = branchId,
            InventoryItemId = item.Id,
            MovementType = "CustomerOrder",
            Quantity = -2m,
            UnitCost = item.UnitCost,
            Reference = order.Number,
        });
        await db.SaveChangesAsync();
        var controller = CreateManagerController(db, tenantId);

        var result = await controller.UpdateStatus(
            order.Id,
            new UpdateCustomerOrderStatusRequest("Completed", null),
            CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        var sale = Assert.Single(await db.Sales.ToListAsync());
        Assert.Equal(branchId, sale.BranchId);
        Assert.Equal(150m, sale.Amount);
        Assert.Equal(order.Number, sale.Reference);
        Assert.Equal(8m, (await db.InventoryItems.SingleAsync()).Quantity);
        var movement = Assert.Single(await db.StockMovements.ToListAsync());
        Assert.Equal("CustomerOrder", movement.MovementType);
        Assert.Equal(-2m, movement.Quantity);

        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService
            .Setup(service => service.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());
        var reportController = new ReportsController(db, authorizationService.Object)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(
                    [
                        new Claim("tenantId", tenantId.ToString()),
                        new Claim(ClaimTypes.Role, UserRole.Admin.ToString()),
                    ], "Tests")),
                },
            },
        };
        var reportResult = await reportController.GetSalesActivity(
            DateTime.UtcNow.AddDays(-1),
            DateTime.UtcNow.AddDays(1),
            null,
            1,
            10,
            CancellationToken.None);
        var report = Assert.IsType<SalesActivityReportResponse>(
            Assert.IsType<OkObjectResult>(reportResult.Result).Value);
        Assert.Equal(1, report.SalesCount);
        Assert.Equal(150m, report.TotalRevenue);
        Assert.Equal(60m, report.CostOfGoodsSold);
        Assert.Equal(90m, report.GrossProfit);
        var reportedSale = Assert.Single(report.RecentSales);
        Assert.Equal(order.Number, reportedSale.Reference);
        Assert.Equal(2m, reportedSale.Quantity);
        Assert.Equal("Tea", Assert.Single(reportedSale.Items));
        db.Sales.Add(new Sale
        {
            TenantId = tenantId,
            BranchId = branchId,
            OccurredAt = DateTime.UtcNow,
            Amount = 40m,
            Reference = "MANUAL-001",
        });
        await db.SaveChangesAsync();
        var branchCommerceResult = await reportController.GetBranchCommerce(
            DateTime.UtcNow.AddDays(-1),
            DateTime.UtcNow.AddDays(1),
            null,
            CancellationToken.None);
        var branchCommerce = Assert.IsType<BranchCommerceReportResponse>(
            Assert.IsType<OkObjectResult>(branchCommerceResult.Result).Value);
        Assert.Equal(2, branchCommerce.SalesCount);
        Assert.Equal(190m, branchCommerce.SalesRevenue);
        Assert.Equal(1, branchCommerce.ManualSalesCount);
        Assert.Equal(40m, branchCommerce.ManualSalesRevenue);
        Assert.Equal(1, branchCommerce.CustomerOrderSalesCount);
        Assert.Equal(150m, branchCommerce.CustomerOrderSalesRevenue);
        Assert.Equal(1, branchCommerce.CustomerOrderCount);
        Assert.Equal(150m, branchCommerce.CustomerOrderValue);
        Assert.Equal(1, branchCommerce.CompletedOrders);
        var branchSummary = Assert.Single(branchCommerce.Branches);
        Assert.Equal(190m, branchSummary.SalesRevenue);
        Assert.Equal(40m, branchSummary.ManualSalesRevenue);
        Assert.Equal(150m, branchSummary.CustomerOrderSalesRevenue);
        Assert.Equal(150m, branchSummary.CustomerOrderValue);

        var duplicateResult = await controller.UpdateStatus(
            order.Id,
            new UpdateCustomerOrderStatusRequest("Completed", null),
            CancellationToken.None);

        Assert.IsType<ConflictObjectResult>(duplicateResult);
        Assert.Equal(2, await db.Sales.CountAsync());
    }

    [Fact]
    public async Task StaffCannotUpdateAnOrderOutsideTheirAssignedBranch()
    {
        var tenantId = Guid.NewGuid();
        var assignedBranchId = Guid.NewGuid();
        var otherBranchId = Guid.NewGuid();
        await using var db = CreateDbContext(tenantId);
        var order = new CustomerOrder
        {
            TenantId = tenantId,
            CustomerId = Guid.NewGuid(),
            BranchId = otherBranchId,
            Number = "ORD-OTHER-BRANCH",
        };
        db.CustomerOrders.Add(order);
        await db.SaveChangesAsync();
        var controller = CreateStaffController(db, tenantId, assignedBranchId);

        var result = await controller.UpdateStatus(
            order.Id,
            new UpdateCustomerOrderStatusRequest("Confirmed", null),
            CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
        Assert.Equal("Pending", (await db.CustomerOrders.SingleAsync()).Status);
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
        Guid customerId,
        NoopBillingMessenger? messenger = null)
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim(ClaimTypes.NameIdentifier, customerId.ToString()),
            new Claim(ClaimTypes.Role, UserRole.Customer.ToString()),
        };
        return new CustomerOrdersController(db, messenger ?? new NoopBillingMessenger())
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

    private static CustomerOrderManagementController CreateManagerController(
        AppDbContext db,
        Guid tenantId,
        NoopBillingMessenger? messenger = null)
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.Role, UserRole.Manager.ToString()),
        };
        return new CustomerOrderManagementController(db, messenger ?? new NoopBillingMessenger())
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

    private static CustomerOrderManagementController CreateStaffController(
        AppDbContext db,
        Guid tenantId,
        Guid branchId)
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim("branchId", branchId.ToString()),
            new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.Role, UserRole.Staff.ToString()),
        };
        return new CustomerOrderManagementController(db, new NoopBillingMessenger())
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

    private sealed class NoopBillingMessenger : IBillingMessenger
    {
        public List<(string To, string Subject, string Html)> SentEmails { get; } = [];

        public Task<MessageDeliveryResponse> SendEmailAsync(
            string to,
            string subject,
            string html,
            EmailAttachment? attachment = null,
            CancellationToken ct = default)
        {
            SentEmails.Add((to, subject, html));
            return Task.FromResult(new MessageDeliveryResponse("Email", to, false, true, null, null));
        }

        public Task<MessageDeliveryResponse> SendTextAsync(
            string channel,
            string to,
            string body,
            CancellationToken ct = default) =>
            Task.FromResult(new MessageDeliveryResponse(channel, to, false, true, null, null));
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
