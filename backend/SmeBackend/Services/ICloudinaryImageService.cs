namespace SmeBackend.Services;

/// Thrown when Cloudinary:CloudName/ApiKey/ApiSecret aren't configured.
/// Callers turn this into a clean 503, never a raw crash - same
/// "configured or clean failure" contract as IPushNotificationSender.
public class CloudinaryNotConfiguredException : Exception
{
    public CloudinaryNotConfiguredException()
        : base("Image uploads are not configured on this server yet. No Cloudinary credentials are set.") { }
}

/// Thrown for any Cloudinary-side failure (timeout, quota, invalid file
/// rejected by Cloudinary itself) after credentials ARE configured.
public class CloudinaryUploadException : Exception
{
    public CloudinaryUploadException(string message) : base(message) { }
}

public record UploadedImage(string Url, string PublicId);

public interface ICloudinaryImageService
{
    Task<UploadedImage> UploadAsync(Stream file, string fileName, string purpose, CancellationToken ct = default);
    Task DeleteAsync(string publicId, CancellationToken ct = default);
}
