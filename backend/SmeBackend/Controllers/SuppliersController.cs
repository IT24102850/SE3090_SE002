using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
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
                supplier.LeadTimeDays,
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
            Email = email ?? string.Empty,
            Phone = phone ?? string.Empty,
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
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryWrite, tenantId, branchId: null))
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
        supplier.Email = request.Email?.Trim() ?? string.Empty;
        supplier.Phone = request.Phone?.Trim() ?? string.Empty;
        supplier.LeadTimeDays = request.LeadTimeDays;
        supplier.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(supplier));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private static SupplierResponse ToResponse(Supplier supplier) =>
        new(
            supplier.Id,
            supplier.Name,
            supplier.Email,
            supplier.Phone,
            supplier.LeadTimeDays,
            supplier.CreatedAt,
            supplier.UpdatedAt);
}

public sealed record SuppliersListResponse(IReadOnlyList<SupplierResponse> Items);

public sealed record SupplierResponse(
    Guid Id,
    string Name,
    string Email,
    string Phone,
    int? LeadTimeDays,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed record CreateSupplierRequest(
    string? Name,
    string? Email = null,
    string? Phone = null,
    int? LeadTimeDays = null);

public sealed record UpdateSupplierRequest(
    string? Name,
    string? Email = null,
    string? Phone = null,
    int? LeadTimeDays = null);
