using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.Authorization;
using SmeBackend.Controllers;
using SmeBackend.Models;

namespace SmeBackend.Tests;

public sealed class SuppliersControllerTests
{
    [Fact]
    public async Task DeleteSupplier_DeletesSupplierWithoutPurchaseOrderHistory()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var supplier = new Supplier { TenantId = tenantId, Name = "Solo Supplies" };
        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync();

        var controller = CreateController(db, tenantId);
        var result = await controller.DeleteSupplier(supplier.Id, CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Empty(await db.Suppliers.ToListAsync());
    }

    [Fact]
    public async Task DeleteSupplier_PreservesSupplierWithPurchaseOrderHistory()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var supplier = new Supplier { TenantId = tenantId, Name = "Historical Supplies" };
        db.Suppliers.Add(supplier);
        db.PurchaseOrders.Add(new PurchaseOrder
        {
            TenantId = tenantId,
            SupplierId = supplier.Id,
            BranchId = Guid.NewGuid(),
            Number = "PO-HISTORY",
            Status = "Received",
        });
        await db.SaveChangesAsync();

        var controller = CreateController(db, tenantId);
        var result = await controller.DeleteSupplier(supplier.Id, CancellationToken.None);

        var conflict = Assert.IsType<ConflictObjectResult>(result);
        var message = conflict.Value?.GetType().GetProperty("message")?.GetValue(conflict.Value) as string;
        Assert.NotNull(message);
        Assert.Contains("purchase order history", message, StringComparison.OrdinalIgnoreCase);
        Assert.Single(await db.Suppliers.ToListAsync());
        Assert.Single(await db.PurchaseOrders.ToListAsync());
    }

    [Fact]
    public async Task UpdateSupplier_PersistsPaymentTermsAndOtherEditableFields()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var supplier = new Supplier
        {
            TenantId = tenantId,
            Name = "Original Supplies",
            PaymentTerms = "Net 30",
            Address = "Old address",
            Notes = "Old notes",
        };
        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync();

        var request = new UpdateSupplierRequest(
            "Updated Supplies",
            "orders@example.test",
            "+94112223333",
            7,
            "Alex Silva",
            "42 New Street",
            "Net 14",
            "Updated delivery notes");
        var controller = CreateController(db, tenantId);

        var result = await controller.UpdateSupplier(supplier.Id, request, CancellationToken.None);

        var response = Assert.IsType<OkObjectResult>(result.Result);
        var updated = Assert.IsType<SupplierResponse>(response.Value);
        Assert.Equal("Net 14", updated.PaymentTerms);
        Assert.Equal("42 New Street", updated.Address);
        Assert.Equal("Updated delivery notes", updated.Notes);
        Assert.Equal("Net 14", (await db.Suppliers.SingleAsync(value => value.Id == supplier.Id)).PaymentTerms);
    }

    private static SuppliersController CreateController(SmeBackend.Data.AppDbContext db, Guid tenantId)
    {
        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService
            .Setup(service => service.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new SuppliersController(db, authorizationService.Object);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, "Admin");
        return controller;
    }
}
