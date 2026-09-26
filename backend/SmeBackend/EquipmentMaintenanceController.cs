using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend;

/// <summary>Provides tenant-scoped maintenance records for equipment.</summary>
[ApiController]
[Route("api/equipment-maintenance")]
[Authorize]
public sealed class EquipmentMaintenanceController(AppDbContext db) : ControllerBase
{
    /// <summary>Lists maintenance records belonging to the current tenant.</summary>
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<EquipmentMaintenanceResponse>>> GetAll(
        [FromQuery] Guid? equipmentItemId,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var query = db.EquipmentMaintenances
            .AsNoTracking()
            .Where(maintenance => maintenance.EquipmentItemId.HasValue &&
                db.EquipmentItems.Any(equipment =>
                    equipment.Id == maintenance.EquipmentItemId.Value &&
                    equipment.TenantId == tenantId));

        if (equipmentItemId.HasValue)
        {
            query = query.Where(maintenance => maintenance.EquipmentItemId == equipmentItemId);
        }

        var records = await query
            .OrderByDescending(maintenance => maintenance.MaintenanceDate)
            .ToListAsync(cancellationToken);

        return Ok(records.Select(ToResponse).ToList());
    }

    /// <summary>Gets one maintenance record belonging to the current tenant.</summary>
    [HttpGet("{id:guid}")]
    public async Task<ActionResult<EquipmentMaintenanceResponse>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var record = await db.EquipmentMaintenances
            .AsNoTracking()
            .Where(maintenance => maintenance.Id == id &&
                maintenance.EquipmentItemId.HasValue &&
                db.EquipmentItems.Any(equipment =>
                    equipment.Id == maintenance.EquipmentItemId.Value &&
                    equipment.TenantId == tenantId))
            .SingleOrDefaultAsync(cancellationToken);

        return record is null ? NotFound() : Ok(ToResponse(record));
    }

    /// <summary>Creates a maintenance record for equipment in the current tenant.</summary>
    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager},{Roles.Staff}")]
    public async Task<ActionResult<EquipmentMaintenanceResponse>> Create(
        CreateEquipmentMaintenanceRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!ValidateDatesAndStatus(request.MaintenanceDate, request.NextDueDate, request.Cost, request.Status))
        {
            return ValidationProblem(ModelState);
        }

        if (!await EquipmentBelongsToTenant(request.EquipmentItemId, tenantId, cancellationToken))
        {
            return NotFound(new { message = "The equipment item was not found." });
        }

        var maintenance = new EquipmentMaintenance
        {
            EquipmentItemId = request.EquipmentItemId,
            MaintenanceDate = request.MaintenanceDate.UtcDateTime,
            NextDueDate = request.NextDueDate.UtcDateTime,
            Cost = request.Cost,
            Notes = request.Notes?.Trim(),
            Status = request.Status.Trim(),
            PhotoUrls = SerializePhotoUrls(request.PhotoUrls)
        };

        db.EquipmentMaintenances.Add(maintenance);
        await db.SaveChangesAsync(cancellationToken);

        return CreatedAtAction(nameof(GetById), new { id = maintenance.Id }, ToResponse(maintenance));
    }

    /// <summary>Replaces a maintenance record belonging to the current tenant.</summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager},{Roles.Staff}")]
    public async Task<ActionResult<EquipmentMaintenanceResponse>> Update(
        Guid id,
        UpdateEquipmentMaintenanceRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!ValidateDatesAndStatus(request.MaintenanceDate, request.NextDueDate, request.Cost, request.Status))
        {
            return ValidationProblem(ModelState);
        }

        var maintenance = await db.EquipmentMaintenances
            .Where(record => record.Id == id &&
                record.EquipmentItemId.HasValue &&
                db.EquipmentItems.Any(equipment =>
                    equipment.Id == record.EquipmentItemId.Value &&
                    equipment.TenantId == tenantId))
            .SingleOrDefaultAsync(cancellationToken);

        if (maintenance is null)
        {
            return NotFound();
        }

        if (!await EquipmentBelongsToTenant(request.EquipmentItemId, tenantId, cancellationToken))
        {
            return NotFound(new { message = "The equipment item was not found." });
        }

        maintenance.EquipmentItemId = request.EquipmentItemId;
        maintenance.MaintenanceDate = request.MaintenanceDate.UtcDateTime;
        maintenance.NextDueDate = request.NextDueDate.UtcDateTime;
        maintenance.Cost = request.Cost;
        maintenance.Notes = request.Notes?.Trim();
        maintenance.Status = request.Status.Trim();
        if (request.PhotoUrls is not null)
        {
            maintenance.PhotoUrls = SerializePhotoUrls(request.PhotoUrls);
        }
        maintenance.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(maintenance));
    }

    /// <summary>Deletes a maintenance record belonging to the current tenant.</summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var maintenance = await db.EquipmentMaintenances
            .Where(record => record.Id == id &&
                record.EquipmentItemId.HasValue &&
                db.EquipmentItems.Any(equipment =>
                    equipment.Id == record.EquipmentItemId.Value &&
                    equipment.TenantId == tenantId))
            .SingleOrDefaultAsync(cancellationToken);

        if (maintenance is null)
        {
            return NotFound();
        }

        db.EquipmentMaintenances.Remove(maintenance);
        await db.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    private async Task<bool> EquipmentBelongsToTenant(
        Guid equipmentItemId,
        Guid tenantId,
        CancellationToken cancellationToken) =>
        await db.EquipmentItems.AnyAsync(
            equipment => equipment.Id == equipmentItemId &&
                equipment.TenantId == tenantId,
            cancellationToken);

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);

    private bool ValidateDatesAndStatus(
        DateTimeOffset maintenanceDate,
        DateTimeOffset nextDueDate,
        decimal cost,
        string status)
    {
        if (nextDueDate < maintenanceDate)
        {
            ModelState.AddModelError(nameof(nextDueDate), "Next due date cannot be before the maintenance date.");
        }

        if (cost < 0)
        {
            ModelState.AddModelError(nameof(cost), "Cost cannot be negative.");
        }

        if (string.IsNullOrWhiteSpace(status) || status.Trim().Length > 20)
        {
            ModelState.AddModelError(nameof(status), "Status is required and must be 20 characters or fewer.");
        }

        return ModelState.IsValid;
    }

    private static EquipmentMaintenanceResponse ToResponse(EquipmentMaintenance maintenance) =>
        new(
            maintenance.Id,
            maintenance.EquipmentItemId!.Value,
            maintenance.MaintenanceDate,
            maintenance.NextDueDate,
            maintenance.Cost,
            maintenance.Notes,
            maintenance.Status,
            DeserializePhotoUrls(maintenance.PhotoUrls),
            maintenance.CreatedAt,
            maintenance.UpdatedAt);

    private static string SerializePhotoUrls(IReadOnlyCollection<string>? urls) =>
        JsonSerializer.Serialize((urls ?? Array.Empty<string>())
            .Where(url => Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
                (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp))
            .Distinct(StringComparer.Ordinal)
            .Take(20));

    private static IReadOnlyList<string> DeserializePhotoUrls(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<string>();
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>(); }
        catch (JsonException) { return Array.Empty<string>(); }
    }
}

/// <summary>Payload for creating an equipment maintenance record.</summary>
public sealed record CreateEquipmentMaintenanceRequest(
    Guid EquipmentItemId,
    DateTimeOffset MaintenanceDate,
    DateTimeOffset NextDueDate,
    decimal Cost,
    string Status,
    string? Notes = null,
    IReadOnlyList<string>? PhotoUrls = null);

/// <summary>Payload for replacing an equipment maintenance record.</summary>
public sealed record UpdateEquipmentMaintenanceRequest(
    Guid EquipmentItemId,
    DateTimeOffset MaintenanceDate,
    DateTimeOffset NextDueDate,
    decimal Cost,
    string Status,
    string? Notes = null,
    IReadOnlyList<string>? PhotoUrls = null);

/// <summary>Represents an equipment maintenance record returned by the API.</summary>
public sealed record EquipmentMaintenanceResponse(
    Guid Id,
    Guid EquipmentItemId,
    DateTimeOffset MaintenanceDate,
    DateTimeOffset NextDueDate,
    decimal Cost,
    string? Notes,
    string Status,
    IReadOnlyList<string> PhotoUrls,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
