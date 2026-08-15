using SmeBackend.Services;

namespace SmeBackend.Tests;

/// Stands in for a real Cloudinary account/HTTP call in tests - the spec
/// calls for "a test Cloudinary account or a mocked HTTP client"; this mocks
/// at the ICloudinaryImageService boundary instead, which is the same
/// approach the rest of this codebase's DI-interface services already use
/// for testability (IPushNotificationSender, IReminderChannelSender, ...).
public class FakeCloudinaryImageService : ICloudinaryImageService
{
    public int UploadCallCount { get; private set; }
    public int DeleteCallCount { get; private set; }
    public bool ThrowNotConfigured { get; set; }

    public Task<UploadedImage> UploadAsync(Stream file, string fileName, string purpose, CancellationToken ct = default)
    {
        if (ThrowNotConfigured) throw new CloudinaryNotConfiguredException();
        UploadCallCount++;
        var publicId = $"sme-platform/{purpose}/{Guid.NewGuid()}";
        return Task.FromResult(new UploadedImage($"https://res.cloudinary.com/demo/image/upload/{publicId}.jpg", publicId));
    }

    public Task DeleteAsync(string publicId, CancellationToken ct = default)
    {
        DeleteCallCount++;
        return Task.CompletedTask;
    }
}
