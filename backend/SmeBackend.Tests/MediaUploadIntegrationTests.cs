using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Models;
using SmeBackend.Shared;
using Xunit;

namespace SmeBackend.Tests;

/// Chains MediaController -> TenantProfileController against the same
/// in-memory AppDbContext, proving upload -> attach -> fetch works together
/// end-to-end, not just in isolation.
public class MediaUploadIntegrationTests
{
    private static IFormFile MakeFormFile(byte[] bytes, string fileName, string contentType) =>
        new FormFile(new MemoryStream(bytes), 0, bytes.Length, "file", fileName) { Headers = new HeaderDictionary(), ContentType = contentType };

    [Fact]
    public async Task UploadThenSetLogoThenFetchProfile_RoundTripsCorrectly()
    {
        var db = TestHelpers.NewInMemoryDb();
        var tenant = new Tenant { Id = Guid.NewGuid(), Name = "Test Dive Co", BusinessType = "Tourism", IsActive = true };
        db.Tenants.Add(tenant);
        await db.SaveChangesAsync();

        var fakeCloudinary = new FakeCloudinaryImageService();
        var mediaController = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(mediaController, Guid.NewGuid(), tenant.Id, Roles.Admin);

        var formFile = MakeFormFile(new byte[] { 1, 2, 3, 4 }, "logo.jpg", "image/jpeg");

        var uploadResult = await mediaController.Upload(formFile, "logo");
        var uploadOk = Assert.IsType<OkObjectResult>(uploadResult);
        var uploadedUrl = (string)uploadOk.Value!.GetType().GetProperty("url")!.GetValue(uploadOk.Value)!;
        Assert.False(string.IsNullOrEmpty(uploadedUrl));
        Assert.Equal(1, fakeCloudinary.UploadCallCount);

        var profileController = new TenantProfileController(db);
        TestHelpers.SetUser(profileController, Guid.NewGuid(), tenant.Id, Roles.Admin);
        var setLogoResult = await profileController.SetLogo(tenant.Id, new SetImageDto(uploadedUrl));
        Assert.IsType<OkObjectResult>(setLogoResult);

        var getResult = await profileController.GetProfile(tenant.Id);
        var getOk = Assert.IsType<OkObjectResult>(getResult);
        var returnedLogoUrl = (string)getOk.Value!.GetType().GetProperty("logoUrl")!.GetValue(getOk.Value)!;
        Assert.Equal(uploadedUrl, returnedLogoUrl);
    }

    [Fact]
    public async Task Upload_RejectsOversizedFile_NeverReachesCloudinary()
    {
        var fakeCloudinary = new FakeCloudinaryImageService();
        var mediaController = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(mediaController, Guid.NewGuid(), Guid.NewGuid(), Roles.Admin);

        var formFile = MakeFormFile(new byte[6 * 1024 * 1024], "big.jpg", "image/jpeg"); // 6MB > 5MB cap

        var result = await mediaController.Upload(formFile, "gallery");

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, fakeCloudinary.UploadCallCount);
    }

    [Fact]
    public async Task Upload_RejectsDisallowedFileType_NeverReachesCloudinary()
    {
        var fakeCloudinary = new FakeCloudinaryImageService();
        var mediaController = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(mediaController, Guid.NewGuid(), Guid.NewGuid(), Roles.Admin);

        var formFile = MakeFormFile(new byte[] { 1, 2, 3 }, "malware.exe", "application/octet-stream");

        var result = await mediaController.Upload(formFile, "gallery");

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(0, fakeCloudinary.UploadCallCount);
    }

    [Fact]
    public async Task Upload_WhenCloudinaryNotConfigured_Returns503NotACrash()
    {
        var fakeCloudinary = new FakeCloudinaryImageService { ThrowNotConfigured = true };
        var mediaController = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(mediaController, Guid.NewGuid(), Guid.NewGuid(), Roles.Admin);

        var formFile = MakeFormFile(new byte[] { 1, 2, 3 }, "logo.jpg", "image/jpeg");

        var result = await mediaController.Upload(formFile, "logo");

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, statusResult.StatusCode);
    }
}
