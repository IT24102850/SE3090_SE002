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
    public async Task GetSuppliers_StaffSeesOnlySuppliersAndOrdersForAssignedBranch()
    {
        var tenantId = Guid.NewGuid();
        var assignedBranchId = Guid.NewGuid();
        var otherBranchId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var assignedSupplier = new Supplier { TenantId = tenantId, Name = "Assigned Supplier" };
        var otherSupplier = new Supplier { TenantId = tenantId, Name = "Other Supplier" };
        db.Suppliers.AddRange(assignedSupplier, otherSupplier);
        db.PurchaseOrders.AddRange(
            new PurchaseOrder
            {
                TenantId = tenantId,
                BranchId = assignedBranchId,
                SupplierId = assignedSupplier.Id,
                Number = "PO-ASSIGNED",
                Status = "Placed",
            },
            new PurchaseOrder
            {
                TenantId = tenantId,
                BranchId = otherBranchId,
                SupplierId = assignedSupplier.Id,
                Number = "PO-OTHER-SAME-SUPPLIER",
                Status = "Placed",
            },
            new PurchaseOrder
            {
                TenantId = tenantId,
                BranchId = otherBranchId,
                SupplierId = otherSupplier.Id,
                Number = "PO-OTHER",
                Status = "Placed",
            });
        await db.SaveChangesAsync();

        var controller = CreateController(db, tenantId, UserRole.Staff, assignedBranchId);

        var result = await controller.GetSuppliers(CancellationToken.None);

        var response = Assert.IsType<SuppliersListResponse>(
            Assert.IsType<OkObjectResult>(result.Result).Value);
        var supplier = Assert.Single(response.Items);
        Assert.Equal(assignedSupplier.Id, supplier.Id);
        Assert.Equal(1, supplier.OrderCount);
        Assert.Equal(1, supplier.ActiveOrderCount);
    }

    [Fact]
    public async Task GetSuppliers_StaffWithoutAssignedBranchIsForbidden()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);

        var controller = CreateController(db, tenantId, UserRole.Staff);

        var result = await controller.GetSuppliers(CancellationToken.None);

        Assert.IsType<ForbidResult>(result.Result);
    }

    [Fact]
    public async Task StaffCannotCreateUpdateOrDeleteSuppliers()
    {
        var tenantId = Guid.NewGuid();
        var branchId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var supplier = new Supplier { TenantId = tenantId, Name = "Existing Supplier" };
        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync();

        var controller = CreateController(db, tenantId, UserRole.Staff, branchId);
        var create = await controller.CreateSupplier(
            new CreateSupplierRequest("New Supplier"),
            CancellationToken.None);
        var update = await controller.UpdateSupplier(
            supplier.Id,
            new UpdateSupplierRequest("Renamed Supplier"),
            CancellationToken.None);
        var delete = await controller.DeleteSupplier(supplier.Id, CancellationToken.None);

        Assert.IsType<ForbidResult>(create.Result);
        Assert.IsType<ForbidResult>(update.Result);
        Assert.IsType<ForbidResult>(delete);
        Assert.Equal("Existing Supplier", (await db.Suppliers.SingleAsync()).Name);
    }

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

    private static SuppliersController CreateController(
        SmeBackend.Data.AppDbContext db,
        Guid tenantId,
        UserRole role = UserRole.Admin,
        Guid? branchId = null)
    {
        var authorizationService = new Mock<IAuthorizationService>();
        authorizationService
            .Setup(service => service.AuthorizeAsync(
                It.IsAny<ClaimsPrincipal>(),
                It.IsAny<object?>(),
                It.IsAny<string>()))
            .ReturnsAsync(AuthorizationResult.Success());

        var controller = new SuppliersController(db, authorizationService.Object);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, role.ToString());
        if (branchId.HasValue)
        {
            ((ClaimsIdentity)controller.User.Identity!).AddClaim(
                new Claim(InventoryAccessHandler.BranchIdClaimType, branchId.Value.ToString()));
        }
        return controller;
    }
}
