using CloudinaryDotNet;
using CloudinaryDotNet.Actions;

namespace SmeBackend.Services;

/// Real Cloudinary integration, gated entirely by config. No Cloudinary
/// account exists in this environment yet, so with Cloudinary:CloudName/
/// ApiKey/ApiSecret unset this throws CloudinaryNotConfiguredException
/// cleanly instead of attempting a call - same honesty pattern as
/// FcmPushNotificationSender. Once real credentials are added to
/// appsettings/user-secrets, no code changes are needed for this to start
/// uploading for real.
public class CloudinaryImageService : ICloudinaryImageService
{
    private readonly IConfiguration _config;
    private readonly ILogger<CloudinaryImageService> _logger;

    public CloudinaryImageService(IConfiguration config, ILogger<CloudinaryImageService> logger)
    {
        _config = config;
        _logger = logger;
    }

    private Cloudinary GetClient()
    {
        var cloudName = _config["Cloudinary:CloudName"];
        var apiKey = _config["Cloudinary:ApiKey"];
        var apiSecret = _config["Cloudinary:ApiSecret"];

        if (string.IsNullOrWhiteSpace(cloudName) || string.IsNullOrWhiteSpace(apiKey) || string.IsNullOrWhiteSpace(apiSecret))
            throw new CloudinaryNotConfiguredException();

        return new Cloudinary(new Account(cloudName, apiKey, apiSecret));
    }

    public async Task<UploadedImage> UploadAsync(Stream file, string fileName, string purpose, CancellationToken ct = default)
    {
        var cloudinary = GetClient();

        var uploadParams = new ImageUploadParams
        {
            File = new FileDescription(fileName, file),
            Folder = $"sme-platform/{purpose}",
        };

        ImageUploadResult result;
        try
        {
            result = await cloudinary.UploadAsync(uploadParams, ct);
        }
        catch (Exception ex) when (ex is not CloudinaryNotConfiguredException)
        {
            _logger.LogWarning(ex, "Cloudinary upload threw for purpose {Purpose}.", purpose);
            throw new CloudinaryUploadException($"Image upload failed: {ex.Message}");
        }

        if (result.Error != null)
            throw new CloudinaryUploadException(result.Error.Message);
        if (result.StatusCode != System.Net.HttpStatusCode.OK || string.IsNullOrEmpty(result.SecureUrl?.ToString()))
            throw new CloudinaryUploadException($"Cloudinary returned status {result.StatusCode}.");

        return new UploadedImage(result.SecureUrl.ToString(), result.PublicId);
    }

    public async Task DeleteAsync(string publicId, CancellationToken ct = default)
    {
        var cloudinary = GetClient();
        try
        {
            var result = await cloudinary.DestroyAsync(new DeletionParams(publicId));
            if (result.Result != "ok" && result.Result != "not found")
                throw new CloudinaryUploadException($"Could not delete image: {result.Result}");
        }
        catch (Exception ex) when (ex is not CloudinaryNotConfiguredException and not CloudinaryUploadException)
        {
            _logger.LogWarning(ex, "Cloudinary delete threw for publicId {PublicId}.", publicId);
            throw new CloudinaryUploadException($"Image delete failed: {ex.Message}");
        }
    }
}
