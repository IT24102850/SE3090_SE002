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
[Route("api/purchase-orders/{orderId:guid}/receipts/{receiptId:guid}/photos")]
public sealed class PurchaseOrderReceiptPhotosController(
    AppDbContext db,
    IAuthorizationService authorizationService,
    ICloudinaryImageService images) : ControllerBase
{
    private const long MaxPhotoBytes = 5 * 1024 * 1024;
    private const int MaxPhotosPerReceipt = 5;

    [HttpPost]
    [RequestSizeLimit(MaxPhotoBytes + 64 * 1024)]
    [ProducesResponseType(typeof(PurchaseOrderReceiptPhotoResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    [ProducesResponseType(StatusCodes.Status502BadGateway)]
    public async Task<ActionResult<PurchaseOrderReceiptPhotoResponse>> UploadPhoto(
        Guid orderId,
        Guid receiptId,
        [FromForm] IFormFile? file,
        CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out var tenantId))
        {
            return Unauthorized();
        }

        var order = await db.PurchaseOrders
            .SingleOrDefaultAsync(candidate => candidate.Id == orderId, cancellationToken);
        if (order is null)
        {
            return NotFound();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                order.BranchId))
        {
            return Forbid();
        }

        var receipt = await db.PurchaseOrderReceipts
            .SingleOrDefaultAsync(
                candidate => candidate.Id == receiptId &&
                             candidate.PurchaseOrderId == orderId &&
                             candidate.TenantId == tenantId,
                cancellationToken);
        if (receipt is null)
        {
            return NotFound();
        }

        if (file is null || file.Length == 0)
        {
            return BadRequest(new { message = "Choose a photo to upload." });
        }
        if (file.Length > MaxPhotoBytes)
        {
            return BadRequest(new { message = "Receipt photos must be 5 MB or smaller." });
        }
        if (!AllowedContentTypes.Contains(file.ContentType))
        {
            return BadRequest(new { message = "Receipt photos must be JPEG, PNG, or WebP images." });
        }

        var photoUrls = string.IsNullOrWhiteSpace(receipt.PhotoUrlsJson)
            ? new List<string>()
            : JsonSerializer.Deserialize<List<string>>(receipt.PhotoUrlsJson) ?? [];
        if (photoUrls.Count >= MaxPhotosPerReceipt)
        {
            return Conflict(new { message = $"A receipt can have at most {MaxPhotosPerReceipt} photos." });
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var uploaded = await images.UploadAsync(
                stream,
                Path.GetFileName(file.FileName),
                "purchase-receipts",
                cancellationToken);

            photoUrls.Add(uploaded.Url);
            receipt.PhotoUrlsJson = JsonSerializer.Serialize(photoUrls);
            receipt.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(cancellationToken);

            return Ok(new PurchaseOrderReceiptPhotoResponse(receipt.Id, photoUrls));
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

    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
    };
}

public sealed record PurchaseOrderReceiptPhotoResponse(Guid ReceiptId, IReadOnlyList<string> PhotoUrls);
