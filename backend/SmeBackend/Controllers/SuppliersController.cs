using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/suppliers")]
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

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId: null))
        {
            return Forbid();
        }

        var suppliers = await db.Suppliers
            .AsNoTracking()
            .OrderBy(supplier => supplier.Name)
            .Select(supplier => new SupplierResponse(
                supplier.Id,
                supplier.Name,
                supplier.Email,
                supplier.Phone,
                supplier.CreatedAt,
                supplier.UpdatedAt))
            .ToListAsync(cancellationToken);

        return Ok(new SuppliersListResponse(suppliers));
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

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                branchId: null))
        {
            return Forbid();
        }

        var name = request.Name?.Trim();
        var email = request.Email?.Trim();
        var phone = request.Phone?.Trim();

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
            Email = email ?? string.Empty,
            Phone = phone ?? string.Empty,
        };

        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync(cancellationToken);

        return CreatedAtAction(nameof(GetSuppliers), new { }, ToResponse(supplier));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private static SupplierResponse ToResponse(Supplier supplier) =>
        new(
            supplier.Id,
            supplier.Name,
            supplier.Email,
            supplier.Phone,
            supplier.CreatedAt,
            supplier.UpdatedAt);
}

public sealed record SuppliersListResponse(IReadOnlyList<SupplierResponse> Items);

public sealed record SupplierResponse(
    Guid Id,
    string Name,
    string Email,
    string Phone,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed record CreateSupplierRequest(
    string? Name,
    string? Email = null,
    string? Phone = null);
