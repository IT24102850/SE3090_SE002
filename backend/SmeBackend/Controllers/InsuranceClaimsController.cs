using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/insurance-claims")]
[Authorize]
[Produces("application/json")]
public class InsuranceClaimsController : BillingControllerBase
{
    private static readonly HashSet<string> AllowedDocumentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/png", "image/webp", "image/heic", "application/pdf",
    };
    private const long MaxDocumentBytes = 10 * 1024 * 1024;

    private readonly IBillingService _billingService;
    private readonly ICloudinaryImageService _uploads;

    public InsuranceClaimsController(IBillingService billingService, ICloudinaryImageService uploads)
    {
        _billingService = billingService;
        _uploads = uploads;
    }

    /// <summary>
    /// Lists insurance claims. Customers only see claims on their own invoices.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(InsuranceClaimListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InsuranceClaimListResponse>> GetInsuranceClaims(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _billingService.GetInsuranceClaimsAsync(actor, page, pageSize, status, ct));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InsuranceClaimResponse>> GetInsuranceClaim(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.GetInsuranceClaimAsync(actor, id, ct));
    }

    /// <summary>
    /// Submits a claim against an invoice. Policy rules are checked first
    /// (claim within the invoice amount, well-formed policy number, ...).
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<InsuranceClaimResponse>> CreateInsuranceClaim([FromBody] CreateInsuranceClaimRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.CreateInsuranceClaimAsync(actor, request, ct));
    }

    /// <summary>
    /// Moves a claim through Submitted -> UnderReview -> Approved/Rejected.
    /// Approving a claim above the threshold needs an Admin (202 otherwise).
    /// </summary>
    [HttpPut("{id:guid}/status")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(UpdateClaimStatusResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(UpdateClaimStatusResult), StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<UpdateClaimStatusResult>> UpdateClaimStatus(Guid id, [FromBody] UpdateInsuranceClaimStatusRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.UpdateInsuranceClaimStatusAsync(actor, id, request, ct));
    }

    /// <summary>Attaches a supporting document (photo or PDF) to a claim.</summary>
    [HttpPost("{id:guid}/documents")]
    [RequestSizeLimit(MaxDocumentBytes + 64 * 1024)]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<InsuranceClaimResponse>> UploadDocument(Guid id, IFormFile? file, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (file is null || file.Length == 0) return BadRequest(new { message = "Attach a file." });
        if (file.Length > MaxDocumentBytes) return BadRequest(new { message = "Documents can be at most 10 MB." });
        if (!AllowedDocumentTypes.Contains(file.ContentType))
            return BadRequest(new { message = "Only JPEG, PNG, WebP, HEIC images or PDF documents are accepted." });

        // Check the claim is reachable before spending an upload on it.
        var claim = await _billingService.GetInsuranceClaimAsync(actor, id, ct);
        if (!claim.Success) return FromResult(claim);

        try
        {
            await using var stream = file.OpenReadStream();
            var uploaded = await _uploads.UploadAsync(stream, file.FileName, "insurance-claim", ct);
            return FromResult(await _billingService.AddClaimDocumentAsync(actor, id, uploaded.Url, Path.GetFileName(file.FileName), ct));
        }
        catch (CloudinaryNotConfiguredException ex)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = ex.Message });
        }
        catch (CloudinaryUploadException ex)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new { message = ex.Message });
        }
    }

    /// <summary>
    /// Attaches a document that was already uploaded (via /api/media).
    /// </summary>
    [HttpPost("{id:guid}/documents/link")]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InsuranceClaimResponse>> LinkDocument(Guid id, [FromBody] ClaimDocumentLinkRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!Uri.TryCreate(request.Url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
            return BadRequest(new { message = "The document URL must be an https:// link." });
        return FromResult(await _billingService.AddClaimDocumentAsync(actor, id, request.Url, request.FileName ?? Path.GetFileName(uri.AbsolutePath), ct));
    }
}

public record ClaimDocumentLinkRequest(string Url, string? FileName);
