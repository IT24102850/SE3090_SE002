using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/inventory")]
public sealed class PhysicalStockCountsController(
    AppDbContext db,
    IAuthorizationService authorizationService,
    ICloudinaryImageService images) : ControllerBase
{
    private const long MaxPhotoBytes = 5 * 1024 * 1024;
    private const int MaxPhotosPerCount = 3;

    [HttpGet("physical-counts")]
    public async Task<ActionResult<PhysicalStockCountListResponse>> GetPhysicalCounts(
        [FromQuery] Guid? branchId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 100,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }
        if (!User.IsInRole(UserRole.Admin.ToString()) &&
            !Guid.TryParse(
                User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value,
                out _))
        {
            return Forbid();
        }

        branchId = ResolveBranchScope(branchId);
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);
        var query = db.PhysicalStockCounts.AsNoTracking()
            .OrderByDescending(count => count.CountedAt)
            .ThenByDescending(count => count.Id)
            .AsQueryable();
        if (branchId.HasValue)
        {
            query = query.Where(count => count.BranchId == branchId.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);
        page = totalPages == 0 ? 1 : Math.Min(page, totalPages);
        var counts = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        return Ok(new PhysicalStockCountListResponse(
            counts.Select(InventoryController.ToPhysicalCountResponse).ToList(),
            page,
            pageSize,
            totalCount,
            totalPages));
    }

    [HttpGet("physical-count-approvals")]
    public async Task<ActionResult<PhysicalCountApprovalListResponse>> GetPendingApprovals(
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!User.IsInRole(UserRole.Admin.ToString()) &&
            !Guid.TryParse(
                User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value,
                out _))
        {
            return Forbid();
        }

        var branchId = ResolveBranchScope();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        var counts = await db.PhysicalStockCounts.AsNoTracking()
            .Where(count =>
                count.Status == "PendingApproval" &&
                (!branchId.HasValue || count.BranchId == branchId.Value))
            .OrderBy(count => count.CountedAt)
            .Take(100)
            .ToListAsync(cancellationToken);
        return Ok(new PhysicalCountApprovalListResponse(
            counts.Select(count =>
                InventoryController.ToPhysicalCountResponse(count) with
                {
                    CanReview = CanApprove() &&
                        count.CountedByUserId.HasValue &&
                        count.CountedByUserId != CurrentUserId(),
                }).ToList(),
            CanApprove()));
    }

    [HttpPost("physical-count-approvals/{countId:guid}/review")]
    public async Task<ActionResult<PhysicalStockCountResponse>> ReviewPhysicalCount(
        Guid countId,
        ReviewPhysicalStockCountRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }
        if (!CanApprove())
        {
            return Forbid();
        }

        var count = await db.PhysicalStockCounts
            .SingleOrDefaultAsync(candidate => candidate.Id == countId, cancellationToken);
        if (count is null)
        {
            return NotFound();
        }
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                count.BranchId))
        {
            return Forbid();
        }
        if (request.Decision is not ("Approve" or "Reject"))
        {
            return BadRequest(new { message = "Choose Approve or Reject." });
        }
        if (request.Decision == "Reject" &&
            string.IsNullOrWhiteSpace(request.Notes))
        {
            return BadRequest(new { message = "Enter a reason when rejecting a stock-count adjustment." });
        }
        if (request.Notes is { Length: > 1000 })
        {
            return BadRequest(new { message = "Review notes cannot exceed 1000 characters." });
        }
        if (count.Status != "PendingApproval")
        {
            return Conflict(new { message = $"This count is {count.Status.ToLowerInvariant()} and can no longer be reviewed." });
        }

        var reviewerId = CurrentUserId();
        if (!reviewerId.HasValue ||
            !count.CountedByUserId.HasValue ||
            reviewerId == count.CountedByUserId)
        {
            return Forbid();
        }

        await using var transaction = db.Database.IsRelational()
            ? await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken)
            : null;
        count.ReviewedByUserId = reviewerId;
        count.ReviewedBy = CurrentActorName();
        count.ReviewedAt = DateTime.UtcNow;
        count.ReviewNotes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim();

        if (request.Decision == "Reject")
        {
            count.Status = "Rejected";
            NotificationHelper.Queue(
                db,
                tenantId,
                count.CountedByUserId,
                "PhysicalCountRejected",
                "Physical stock count rejected",
                $"{count.ItemName}: {count.ReviewNotes}");
            await db.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
                await transaction.CommitAsync(cancellationToken);
            return Ok(InventoryController.ToPhysicalCountResponse(count));
        }

        var item = await db.InventoryItems
            .SingleOrDefaultAsync(candidate => candidate.Id == count.InventoryItemId, cancellationToken);
        if (item is null)
        {
            count.Status = "NeedsRecount";
            count.ReviewNotes = "Inventory item no longer exists; recount or correct the catalog.";
            await db.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
                await transaction.CommitAsync(cancellationToken);
            return Conflict(new
            {
                message = count.ReviewNotes,
                currentQuantity = (decimal?)null,
                changedMovements = Array.Empty<PhysicalCountChangedMovement>()
            });
        }

        var changedMovements = await GetMovementsAfterCountAsync(
            count.InventoryItemId,
            count.CountedAt,
            cancellationToken);
        if (changedMovements.Count > 0 || item.Quantity != count.SystemQuantityAtCount)
        {
            count.Status = "NeedsRecount";
            count.ReviewNotes = "Stock changed after the count. Recount the item before applying an adjustment.";
            await db.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
                await transaction.CommitAsync(cancellationToken);
            return Conflict(new
            {
                message = count.ReviewNotes,
                currentQuantity = item.Quantity,
                changedMovements
            });
        }

        if (db.Database.IsRelational())
        {
            var updated = await db.InventoryItems
                .Where(candidate =>
                    candidate.Id == item.Id &&
                    candidate.Quantity == count.SystemQuantityAtCount)
                .ExecuteUpdateAsync(updates => updates
                    .SetProperty(candidate => candidate.Quantity, count.CountedQuantity)
                    .SetProperty(candidate => candidate.UpdatedAt, DateTime.UtcNow),
                    cancellationToken);
            if (updated == 0)
            {
                return Conflict(new
                {
                    message = "Stock changed while this approval was being processed. Recount before applying.",
                    currentQuantity = item.Quantity,
                    changedMovements = await GetMovementsAfterCountAsync(
                        count.InventoryItemId,
                        count.CountedAt,
                        cancellationToken)
                });
            }
        }
        else
        {
            item.Quantity = count.CountedQuantity;
            item.UpdatedAt = DateTime.UtcNow;
        }

        count.Status = "Applied";
        db.StockMovements.Add(new StockMovement
        {
            TenantId = tenantId,
            InventoryItemId = count.InventoryItemId,
            BranchId = count.BranchId,
            MovementType = "Adjustment",
            Quantity = count.Variance,
            Reference = count.Reference,
            Notes = $"Approved physical count {count.Reference}: counted {count.CountedQuantity:0.###}; system had {count.SystemQuantityAtCount:0.###}; reason: {count.Reason}{(count.ReasonNotes is null ? string.Empty : $": {count.ReasonNotes}")}. Approved by {count.ReviewedBy}.",
            OccurredAt = DateTime.UtcNow,
            PerformedBy = count.ReviewedBy,
        });
        NotificationHelper.Queue(
            db,
            tenantId,
            null,
            "StockAdjusted",
            "Physical stock count approved",
            $"{count.ItemName} adjustment {count.Variance:+0.###;-0.###} was approved by {count.ReviewedBy}.");
        await db.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
            await transaction.CommitAsync(cancellationToken);
        return Ok(InventoryController.ToPhysicalCountResponse(count));
    }

    [HttpPost("physical-count-audits/{countId:guid}/photos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(MaxPhotoBytes + 64 * 1024)]
    [ProducesResponseType(typeof(PhysicalStockCountResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    [ProducesResponseType(StatusCodes.Status502BadGateway)]
    public async Task<ActionResult<PhysicalStockCountResponse>> UploadPhoto(
        Guid countId,
        [FromForm] IFormFile? file,
        [FromForm] string? evidenceKey,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }
        var count = await db.PhysicalStockCounts
            .SingleOrDefaultAsync(candidate => candidate.Id == countId, cancellationToken);
        if (count is null)
        {
            return NotFound();
        }
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                count.BranchId))
        {
            return Forbid();
        }
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { message = "Choose a photo to upload." });
        }
        if (file.Length > MaxPhotoBytes)
        {
            return BadRequest(new { message = "Evidence photos must be 5 MB or smaller." });
        }
        if (string.IsNullOrWhiteSpace(evidenceKey) || evidenceKey.Length > 100)
        {
            return BadRequest(new { message = "A valid evidence upload key is required." });
        }
        if (!AllowedPhotoTypes.Contains(file.ContentType))
        {
            return BadRequest(new { message = "Evidence photos must be JPEG, PNG, or WebP images." });
        }

        var photoUrls = string.IsNullOrWhiteSpace(count.PhotoUrlsJson)
            ? new List<string>()
            : JsonSerializer.Deserialize<List<string>>(count.PhotoUrlsJson) ?? [];
        var uploadKeys = string.IsNullOrWhiteSpace(count.PhotoUploadKeysJson)
            ? new List<string>()
            : JsonSerializer.Deserialize<List<string>>(count.PhotoUploadKeysJson) ?? [];
        if (uploadKeys.Contains(evidenceKey, StringComparer.Ordinal))
        {
            return Ok(InventoryController.ToPhysicalCountResponse(count));
        }
        if (photoUrls.Count >= MaxPhotosPerCount)
        {
            return Conflict(new { message = $"A physical count can have at most {MaxPhotosPerCount} photos." });
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var uploaded = await images.UploadAsync(
                stream,
                Path.GetFileName(file.FileName),
                "stock-count-evidence",
                cancellationToken);
            photoUrls.Add(uploaded.Url);
            count.PhotoUrlsJson = JsonSerializer.Serialize(photoUrls);
            uploadKeys.Add(evidenceKey);
            count.PhotoUploadKeysJson = JsonSerializer.Serialize(uploadKeys);
            count.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(cancellationToken);
            return Ok(InventoryController.ToPhysicalCountResponse(count));
        }
        catch (CloudinaryNotConfiguredException exception)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = exception.Message });
        }
        catch (CloudinaryUploadException exception)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new { message = exception.Message });
        }
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private Guid? CurrentUserId() =>
        Guid.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var userId)
            ? userId
            : null;

    private string CurrentActorName() =>
        User.FindFirst("fullName")?.Value ?? User.Identity?.Name ?? "Authorized user";

    private bool CanApprove() =>
        User.IsInRole(UserRole.Admin.ToString()) ||
        User.IsInRole(UserRole.Manager.ToString());

    private Guid? ResolveBranchScope(Guid? requestedBranchId = null) =>
        User.IsInRole(UserRole.Admin.ToString())
            ? requestedBranchId
            : Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId)
                ? branchId
                : null;

    private async Task<IReadOnlyList<PhysicalCountChangedMovement>> GetMovementsAfterCountAsync(
        Guid inventoryItemId,
        DateTime countedAt,
        CancellationToken cancellationToken) =>
        await db.StockMovements.AsNoTracking()
            .Where(movement =>
                movement.InventoryItemId == inventoryItemId &&
                movement.OccurredAt > countedAt)
            .OrderBy(movement => movement.OccurredAt)
            .Take(20)
            .Select(movement => new PhysicalCountChangedMovement(
                movement.MovementType,
                movement.Quantity,
                movement.OccurredAt,
                movement.Reference,
                movement.PerformedBy,
                movement.Notes))
            .ToListAsync(cancellationToken);

    private static readonly HashSet<string> AllowedPhotoTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
    };
}

public sealed record PhysicalStockCountListResponse(
    IReadOnlyList<PhysicalStockCountResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages);

public sealed record PhysicalCountApprovalListResponse(
    IReadOnlyList<PhysicalStockCountResponse> Items,
    bool CanApprove);

public sealed record ReviewPhysicalStockCountRequest(string Decision, string? Notes = null);
