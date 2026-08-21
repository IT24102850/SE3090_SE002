using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// Proxies image uploads to Cloudinary - the client never talks to
/// Cloudinary directly or holds its API secret. Deliberately doesn't touch
/// Tenant itself: "upload an image" and "attach it to the tenant profile"
/// (TenantProfileController) are separate, independently-retryable steps,
/// so an upload failure can never corrupt an already-saved LogoUrl/
/// GalleryImageUrls.
[ApiController]
[Route("api/media")]
[Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
public class MediaController : ControllerBase
{
    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/jpg", "image/png", "image/webp"
    };
    private const long MaxFileSizeBytes = 5 * 1024 * 1024;
    private static readonly HashSet<string> AllowedPurposes = new(StringComparer.OrdinalIgnoreCase) { "logo", "cover", "gallery", "avatar" };

    private readonly ICloudinaryImageService _images;
    public MediaController(ICloudinaryImageService images) => _images = images;

    /// <summary>Uploads an image (jpg/png/webp, max 5MB) to Cloudinary and returns its URL + publicId.</summary>
    [HttpPost("upload")]
    public async Task<IActionResult> Upload([FromForm] IFormFile file, [FromForm] string purpose)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file was uploaded." });
        if (!AllowedPurposes.Contains(purpose))
            return BadRequest(new { message = "purpose must be one of: logo, cover, gallery, avatar." });
        if (!AllowedContentTypes.Contains(file.ContentType))
            return BadRequest(new { message = "Only JPG, PNG, and WEBP images are allowed." });
        if (file.Length > MaxFileSizeBytes)
            return BadRequest(new { message = "Image must be 5MB or smaller." });

        try
        {
            await using var stream = file.OpenReadStream();
            var result = await _images.UploadAsync(stream, file.FileName, purpose.ToLowerInvariant());
            return Ok(new { url = result.Url, publicId = result.PublicId });
        }
        catch (CloudinaryNotConfiguredException ex)
        {
            return StatusCode(503, new { message = ex.Message });
        }
        catch (CloudinaryUploadException ex)
        {
            return StatusCode(502, new { message = ex.Message });
        }
    }

    /// <summary>Deletes an image from Cloudinary by its publicId (avoids orphaned storage when an admin removes it).</summary>
    [HttpDelete("{publicId}")]
    public async Task<IActionResult> Delete(string publicId)
    {
        try
        {
            await _images.DeleteAsync(Uri.UnescapeDataString(publicId));
            return NoContent();
        }
        catch (CloudinaryNotConfiguredException ex)
        {
            return StatusCode(503, new { message = ex.Message });
        }
        catch (CloudinaryUploadException ex)
        {
            return StatusCode(502, new { message = ex.Message });
        }
    }
}
