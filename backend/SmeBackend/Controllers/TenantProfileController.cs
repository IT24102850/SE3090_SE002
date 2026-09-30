using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The shared, business-type-agnostic "TripAdvisor listing" profile shell -
/// works identically for a clinic, a restaurant, or a dive center. Nothing
/// here is Tourism/sub-type-specific; that content lives entirely in
/// BookingType. Route is plural ("api/tenants") deliberately, distinct from
/// the existing singular "api/tenant" (TenantController) so nothing there
/// needs to change.
[ApiController]
[Route("api/tenants")]
public class TenantProfileController : ControllerBase
{
    private const int MaxDescriptionLength = 5000;
    private const int MaxTaglineLength = 100;

    private readonly AppDbContext _db;
    public TenantProfileController(AppDbContext db) => _db = db;

    /// <summary>Gets a tenant's public business profile (logo, cover, gallery, description, amenities, contact, hours). Anonymous, matching how tenant browsing already works.</summary>
    [HttpGet("{id}/profile")]
    [AllowAnonymous]
    public async Task<IActionResult> GetProfile(Guid id)
    {
        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id);
        if (tenant == null) return NotFound();

        var address = await _db.Branches.AsNoTracking()
            .Where(b => b.TenantId == id)
            .OrderBy(b => b.CreatedAt)
            .Select(b => b.Address)
            .FirstOrDefaultAsync();

        return Ok(BuildProfileDto(tenant, address));
    }

    /// <summary>Updates the editable profile fields (description, tagline, amenities, contact, hours). Admin/Manager of this exact tenant only.</summary>
    [HttpPut("{id}/profile")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> UpdateProfile(Guid id, [FromBody] UpdateTenantProfileDto dto)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        if (dto.Description != null)
        {
            if (dto.Description.Length > MaxDescriptionLength)
                return BadRequest(new { message = $"Description must be {MaxDescriptionLength} characters or fewer." });
            tenant.Description = dto.Description;
        }

        if (dto.ShortTagline != null)
        {
            if (dto.ShortTagline.Length > MaxTaglineLength)
                return BadRequest(new { message = $"Tagline must be {MaxTaglineLength} characters or fewer." });
            tenant.ShortTagline = dto.ShortTagline;
        }

        if (dto.Amenities != null)
        {
            var cleaned = dto.Amenities
                .Select(a => a.Trim())
                .Where(a => a.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
            tenant.Amenities = JsonSerializer.Serialize(cleaned);
        }

        if (dto.ContactPhone != null) tenant.ContactPhone = dto.ContactPhone;
        if (dto.ContactEmail != null) tenant.ContactEmail = dto.ContactEmail;
        if (dto.Website != null) tenant.Website = dto.Website;
        if (dto.SocialLinks != null) tenant.SocialLinks = JsonSerializer.Serialize(dto.SocialLinks);

        if (dto.BusinessHours != null)
        {
            foreach (var hour in dto.BusinessHours)
            {
                if (hour.IsClosed) continue;
                if (string.IsNullOrEmpty(hour.OpenTime) || string.IsNullOrEmpty(hour.CloseTime))
                    return BadRequest(new { message = $"{hour.DayOfWeek}: openTime and closeTime are required unless isClosed is true." });
                if (string.CompareOrdinal(hour.OpenTime, hour.CloseTime) >= 0)
                    return BadRequest(new { message = $"{hour.DayOfWeek}: openTime must be before closeTime." });
            }
            tenant.BusinessHours = JsonSerializer.Serialize(dto.BusinessHours);
        }

        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var address = await _db.Branches.AsNoTracking()
            .Where(b => b.TenantId == id).OrderBy(b => b.CreatedAt).Select(b => b.Address).FirstOrDefaultAsync();
        return Ok(BuildProfileDto(tenant, address));
    }

    /// <summary>Replaces the tenant's logo image URL. Admin/Manager of this exact tenant only.</summary>
    [HttpPut("{id}/logo")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> SetLogo(Guid id, [FromBody] SetImageDto dto)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        tenant.LogoUrl = dto.ImageUrl;
        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { tenant.LogoUrl });
    }

    /// <summary>Replaces the tenant's cover/banner image URL. Admin/Manager of this exact tenant only.</summary>
    [HttpPut("{id}/cover-image")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> SetCoverImage(Guid id, [FromBody] SetImageDto dto)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        tenant.CoverImageUrl = dto.ImageUrl;
        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { tenant.CoverImageUrl });
    }

    /// <summary>Appends an image to the tenant's photo gallery. Admin/Manager of this exact tenant only.</summary>
    [HttpPost("{id}/gallery-images")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> AddGalleryImage(Guid id, [FromBody] SetImageDto dto)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        var urls = ParseStringArray(tenant.GalleryImageUrls);
        urls.Add(dto.ImageUrl);
        tenant.GalleryImageUrls = JsonSerializer.Serialize(urls);
        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { galleryImageUrls = urls });
    }

    /// <summary>Removes the gallery image at the given position. Admin/Manager of this exact tenant only.</summary>
    [HttpDelete("{id}/gallery-images/{index}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> RemoveGalleryImage(Guid id, int index)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        var urls = ParseStringArray(tenant.GalleryImageUrls);
        if (index < 0 || index >= urls.Count)
            return BadRequest(new { message = "No gallery image at that position." });

        urls.RemoveAt(index);
        tenant.GalleryImageUrls = JsonSerializer.Serialize(urls);
        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { galleryImageUrls = urls });
    }

    /// <summary>Reorders the gallery to the given URL order (drag-to-reorder). Rejects any list that isn't exactly a reordering of the existing images. Admin/Manager of this exact tenant only.</summary>
    [HttpPut("{id}/gallery-images/reorder")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> ReorderGalleryImages(Guid id, [FromBody] ReorderGalleryDto dto)
    {
        var ownership = CheckTenantOwnership(id);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.FindAsync(id);
        if (tenant == null) return NotFound();

        var existing = ParseStringArray(tenant.GalleryImageUrls);
        var incoming = dto.OrderedUrls ?? new List<string>();

        // Must be an exact permutation - same multiset of URLs, just
        // reordered. Rejects silently dropping or injecting images via a
        // tampered reorder request.
        var existingSorted = existing.OrderBy(u => u, StringComparer.Ordinal).ToList();
        var incomingSorted = incoming.OrderBy(u => u, StringComparer.Ordinal).ToList();
        if (!existingSorted.SequenceEqual(incomingSorted))
            return BadRequest(new { message = "orderedUrls must contain exactly the same images as the current gallery, just reordered." });

        tenant.GalleryImageUrls = JsonSerializer.Serialize(incoming);
        tenant.ProfileUpdatedAt = DateTime.UtcNow;
        tenant.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { galleryImageUrls = incoming });
    }

    // Admin/Manager can only ever edit their OWN tenant's profile, even if
    // they adjust {id} in the URL to point at another tenant. Role is
    // re-checked here (not just via [Authorize(Roles=...)] on the action)
    // as defense-in-depth, same pattern as BookingsController.CheckOwnership
    // - also makes this directly unit-testable without a full HTTP pipeline.
    private IActionResult? CheckTenantOwnership(Guid id)
    {
        var role = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
        if (role != Roles.Admin && role != Roles.Manager) return Forbid();

        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        if (!Guid.TryParse(tenantIdClaim, out var callerTenantId)) return Unauthorized();
        if (callerTenantId != id) return Forbid();
        return null;
    }

    private static List<string> ParseStringArray(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<string>();
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>();
        }
        catch (JsonException)
        {
            return new List<string>();
        }
    }

    private static Dictionary<string, string> ParseStringDict(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new Dictionary<string, string>();
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new Dictionary<string, string>();
        }
        catch (JsonException)
        {
            return new Dictionary<string, string>();
        }
    }

    private static List<BusinessHourDto> ParseBusinessHours(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<BusinessHourDto>();
        try
        {
            return JsonSerializer.Deserialize<List<BusinessHourDto>>(json) ?? new List<BusinessHourDto>();
        }
        catch (JsonException)
        {
            return new List<BusinessHourDto>();
        }
    }

    private static object BuildProfileDto(Tenant tenant, string? address) => new
    {
        tenantId = tenant.Id,
        name = tenant.Name,
        businessType = tenant.BusinessType,
        logoUrl = tenant.LogoUrl,
        coverImageUrl = tenant.CoverImageUrl,
        galleryImageUrls = ParseStringArray(tenant.GalleryImageUrls),
        description = tenant.Description,
        shortTagline = tenant.ShortTagline,
        amenities = ParseStringArray(tenant.Amenities),
        contactPhone = tenant.ContactPhone,
        contactEmail = tenant.ContactEmail,
        website = tenant.Website,
        socialLinks = ParseStringDict(tenant.SocialLinks),
        businessHours = ParseBusinessHours(tenant.BusinessHours),
        averageRating = tenant.AverageRating,
        reviewCount = tenant.ReviewCount,
        address
    };
}

public record SetImageDto(string ImageUrl);
public record ReorderGalleryDto(List<string> OrderedUrls);
public record BusinessHourDto(string DayOfWeek, string? OpenTime, string? CloseTime, bool IsClosed);
public record UpdateTenantProfileDto(
    string? Description,
    string? ShortTagline,
    List<string>? Amenities,
    string? ContactPhone,
    string? ContactEmail,
    string? Website,
    Dictionary<string, string>? SocialLinks,
    List<BusinessHourDto>? BusinessHours
);
