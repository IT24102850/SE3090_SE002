using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/suppliers")]
// Paid feature: the tenant's Unify plan decides whether this module is
// available at all (Authorization/RequiresPlanAttribute.cs).
[RequiresPlanFeature(PlanFeatures.InventoryPro)]
public sealed class SuppliersController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<SuppliersListResponse>> GetSuppliers(
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var isStaff = User.IsInRole(UserRole.Staff.ToString());
        Guid? assignedBranchId = null;
        if (!User.IsInRole(UserRole.Admin.ToString()))
        {
            if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var parsedBranchId))
            {
                return Forbid();
            }

            assignedBranchId = parsedBranchId;
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryMetadataRead,
                tenantId,
                branchId: null))
        {
            return Forbid();
        }

        var purchaseOrderQuery = db.PurchaseOrders.AsNoTracking();
        if (assignedBranchId.HasValue)
        {
            purchaseOrderQuery = purchaseOrderQuery.Where(order => order.BranchId == assignedBranchId.Value);
        }

        var purchaseOrders = await purchaseOrderQuery
            .Select(order => new SupplierOrderRow(order.Id, order.SupplierId, order.Status, order.CreatedAt))
            .ToListAsync(cancellationToken);
        var supplierIds = purchaseOrders.Select(order => order.SupplierId).Distinct().ToList();

        var supplierQuery = db.Suppliers
            .AsNoTracking()
            .AsQueryable();
        if (isStaff && assignedBranchId.HasValue)
        {
            supplierQuery = supplierQuery.Where(supplier => supplierIds.Contains(supplier.Id));
        }

        var suppliers = await supplierQuery
            .OrderBy(supplier => supplier.Name)
            .ToListAsync(cancellationToken);
        var orderTotals = await db.PurchaseOrderItems
            .AsNoTracking()
            .GroupBy(item => item.PurchaseOrderId)
            .Select(group => new PurchaseOrderValue(group.Key, group.Sum(item => item.Quantity * item.UnitPrice)))
            .ToDictionaryAsync(value => value.PurchaseOrderId, value => value.TotalValue, cancellationToken);
        var orderSummaries = purchaseOrders
            .GroupBy(order => order.SupplierId)
            .ToDictionary(
                group => group.Key,
                group => new SupplierOrderSummary(
                    group.Count(),
                    group.Count(order =>
                        !string.Equals(order.Status, "Cancelled", StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(order.Status, "Rejected", StringComparison.OrdinalIgnoreCase)),
                    group.Where(order =>
                            !string.Equals(order.Status, "Cancelled", StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(order.Status, "Rejected", StringComparison.OrdinalIgnoreCase))
                        .Sum(order => orderTotals.GetValueOrDefault(order.Id)),
                    group.Max(order => order.CreatedAt)));

        var responses = suppliers.Select(supplier =>
        {
            var summary = orderSummaries.GetValueOrDefault(supplier.Id) ?? new SupplierOrderSummary(0, 0, 0m, null);
            return new SupplierResponse(
                supplier.Id,
                supplier.Name,
                supplier.ContactPerson,
                supplier.Email,
                supplier.Phone,
                supplier.Address,
                supplier.PaymentTerms,
                supplier.Notes,
                supplier.LeadTimeDays,
                supplier.CreatedAt,
                supplier.UpdatedAt,
                summary.OrderCount,
                summary.ActiveOrderCount,
                summary.TotalOrderValue,
                summary.LastOrderAt);
        }).ToList();

        return Ok(new SuppliersListResponse(responses));
    }

    [HttpPost]
    public async Task<ActionResult<SupplierResponse>> CreateSupplier(
        CreateSupplierRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (User.IsInRole(UserRole.Staff.ToString()))
        {
            return Forbid();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryMetadataWrite,
                tenantId,
                branchId: null))
        {
            return Forbid();
        }

        var name = request.Name?.Trim();
        var email = request.Email?.Trim();
        var phone = request.Phone?.Trim();

        if (request.LeadTimeDays is < 1 or > 90)
        {
            ModelState.AddModelError("leadTimeDays", "Lead time must be between 1 and 90 days.");
            return ValidationProblem(ModelState);
        }

        if (string.IsNullOrWhiteSpace(name))
        {
            ModelState.AddModelError("name", "Name is required.");
            return ValidationProblem(ModelState);
        }

        if (await db.Suppliers.IgnoreQueryFilters()
            .AnyAsync(supplier => supplier.TenantId == tenantId && supplier.Name == name, cancellationToken))
        {
            return Conflict(new { message = $"A supplier named '{name}' already exists." });
        }

        var supplier = new Supplier
        {
            Name = name,
            ContactPerson = NormalizeOptional(request.ContactPerson),
            Email = email ?? string.Empty,
            Phone = phone ?? string.Empty,
            Address = NormalizeOptional(request.Address),
            PaymentTerms = NormalizeOptional(request.PaymentTerms),
            Notes = NormalizeOptional(request.Notes),
            LeadTimeDays = request.LeadTimeDays,
        };

        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync(cancellationToken);

        return CreatedAtAction(nameof(GetSuppliers), new { }, ToResponse(supplier));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<SupplierResponse>> UpdateSupplier(
        Guid id,
        UpdateSupplierRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        if (User.IsInRole(UserRole.Staff.ToString())) return Forbid();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryMetadataWrite, tenantId, branchId: null))
            return Forbid();

        var supplier = await db.Suppliers.SingleOrDefaultAsync(value => value.Id == id, cancellationToken);
        if (supplier is null) return NotFound();

        if (request.LeadTimeDays is < 1 or > 90)
        {
            ModelState.AddModelError("leadTimeDays", "Lead time must be between 1 and 90 days.");
            return ValidationProblem(ModelState);
        }

        var name = request.Name?.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            ModelState.AddModelError("name", "Name is required.");
            return ValidationProblem(ModelState);
        }

        if (await db.Suppliers.IgnoreQueryFilters().AnyAsync(
                other => other.TenantId == tenantId && other.Id != id && other.Name == name,
                cancellationToken))
            return Conflict(new { message = $"A supplier named '{name}' already exists." });

        supplier.Name = name;
        supplier.ContactPerson = NormalizeOptional(request.ContactPerson);
        supplier.Email = request.Email?.Trim() ?? string.Empty;
        supplier.Phone = request.Phone?.Trim() ?? string.Empty;
        supplier.Address = NormalizeOptional(request.Address);
        supplier.PaymentTerms = NormalizeOptional(request.PaymentTerms);
        supplier.Notes = NormalizeOptional(request.Notes);
        supplier.LeadTimeDays = request.LeadTimeDays;
        supplier.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(supplier));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteSupplier(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        if (User.IsInRole(UserRole.Staff.ToString())) return Forbid();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryMetadataWrite, tenantId, branchId: null))
            return Forbid();

        var supplier = await db.Suppliers.SingleOrDefaultAsync(value => value.Id == id, cancellationToken);
        if (supplier is null) return NotFound();

        if (await db.PurchaseOrders.AnyAsync(order => order.SupplierId == id, cancellationToken))
        {
            return Conflict(new
            {
                message = "This supplier has purchase order history and cannot be deleted without removing those records.",
            });
        }

        db.Suppliers.Remove(supplier);
        await db.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static SupplierResponse ToResponse(Supplier supplier) =>
        new(
            supplier.Id,
            supplier.Name,
            supplier.ContactPerson,
            supplier.Email,
            supplier.Phone,
            supplier.Address,
            supplier.PaymentTerms,
            supplier.Notes,
            supplier.LeadTimeDays,
            supplier.CreatedAt,
            supplier.UpdatedAt);
}

public sealed record SuppliersListResponse(IReadOnlyList<SupplierResponse> Items);
internal sealed record SupplierOrderRow(Guid Id, Guid SupplierId, string Status, DateTime CreatedAt);
internal sealed record PurchaseOrderValue(Guid PurchaseOrderId, decimal TotalValue);
internal sealed record SupplierOrderSummary(int OrderCount, int ActiveOrderCount, decimal TotalOrderValue, DateTime? LastOrderAt);

public sealed record SupplierResponse(
    Guid Id,
    string Name,
    string? ContactPerson,
    string Email,
    string Phone,
    string? Address,
    string? PaymentTerms,
    string? Notes,
    int? LeadTimeDays,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    int OrderCount = 0,
    int ActiveOrderCount = 0,
    decimal TotalOrderValue = 0,
    DateTime? LastOrderAt = null);

public sealed record CreateSupplierRequest(
    string? Name,
    string? Email = null,
    string? Phone = null,
    int? LeadTimeDays = null,
    [MaxLength(160)] string? ContactPerson = null,
    [MaxLength(500)] string? Address = null,
    [MaxLength(160)] string? PaymentTerms = null,
    [MaxLength(1000)] string? Notes = null);

public sealed record UpdateSupplierRequest(
    string? Name,
    string? Email = null,
    string? Phone = null,
    int? LeadTimeDays = null,
    [MaxLength(160)] string? ContactPerson = null,
    [MaxLength(500)] string? Address = null,
    [MaxLength(160)] string? PaymentTerms = null,
    [MaxLength(1000)] string? Notes = null);
