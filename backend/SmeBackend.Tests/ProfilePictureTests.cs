using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;
using Xunit;

namespace SmeBackend.Tests;

/// Covers the profile-photo path shared by the web admin app and the mobile
/// customer app: any signed-in user may upload their own avatar, only
/// Admin/Manager may upload branding, and an empty URL means "remove it".
public class ProfilePictureTests
{
    private sealed class StubJwtService : IJwtService
    {
        public string GenerateAccessToken(User user) => "stub";
        public string GenerateRefreshToken() => "stub";
        public ClaimsPrincipal? ValidateToken(string token) => null;
    }

    private static IFormFile MakeFormFile(string fileName, string contentType) =>
        new FormFile(new MemoryStream(new byte[] { 1, 2, 3, 4 }), 0, 4, "file", fileName)
        { Headers = new HeaderDictionary(), ContentType = contentType };

    [Theory]
    [InlineData(Roles.Customer)]
    [InlineData(Roles.Staff)]
    public async Task Upload_AvatarPurpose_IsAllowedForNonAdminRoles(string role)
    {
        var fakeCloudinary = new FakeCloudinaryImageService();
        var controller = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(controller, Guid.NewGuid(), Guid.NewGuid(), role);

        var result = await controller.Upload(MakeFormFile("me.jpg", "image/jpeg"), "avatar");

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(1, fakeCloudinary.UploadCallCount);
    }

    [Theory]
    [InlineData("logo")]
    [InlineData("cover")]
    [InlineData("gallery")]
    public async Task Upload_BrandingPurposes_StayAdminOnly(string purpose)
    {
        var fakeCloudinary = new FakeCloudinaryImageService();
        var controller = new MediaController(fakeCloudinary);
        TestHelpers.SetUser(controller, Guid.NewGuid(), Guid.NewGuid(), Roles.Customer);

        var result = await controller.Upload(MakeFormFile("brand.jpg", "image/jpeg"), purpose);

        Assert.IsType<ForbidResult>(result);
        Assert.Equal(0, fakeCloudinary.UploadCallCount);
    }

    [Fact]
    public async Task UpdateCurrentUser_EmptyProfilePictureUrl_ClearsTheStoredPhoto()
    {
        var db = TestHelpers.NewInMemoryDb();
        var user = new User
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Email = "customer@example.com",
            FullName = "Ada Perera",
            PasswordHash = "x",
            Role = UserRole.Customer,
            ProfilePictureUrl = "https://cdn.example.com/old.jpg"
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();

        var controller = new AuthController(db, new StubJwtService());
        TestHelpers.SetUser(controller, user.Id, user.TenantId, Roles.Customer);

        var result = await controller.UpdateCurrentUser(new UpdateProfileDto { ProfilePictureUrl = "" });

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Null(Assert.IsType<UserResponseDto>(ok.Value).ProfilePictureUrl);
        Assert.Null(db.Users.Find(user.Id)!.ProfilePictureUrl);
    }

    [Fact]
    public async Task UpdateCurrentUser_NullProfilePictureUrl_LeavesThePhotoAlone()
    {
        var db = TestHelpers.NewInMemoryDb();
        var user = new User
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Email = "customer2@example.com",
            FullName = "Ada Perera",
            PasswordHash = "x",
            Role = UserRole.Customer,
            ProfilePictureUrl = "https://cdn.example.com/keep.jpg"
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();

        var controller = new AuthController(db, new StubJwtService());
        TestHelpers.SetUser(controller, user.Id, user.TenantId, Roles.Customer);

        var result = await controller.UpdateCurrentUser(new UpdateProfileDto { Phone = "0771234567" });

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.Equal("https://cdn.example.com/keep.jpg", Assert.IsType<UserResponseDto>(ok.Value).ProfilePictureUrl);
    }
}
