using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

public class ChangePasswordTests
{
    private sealed class StubJwtService : IJwtService
    {
        public string GenerateAccessToken(User user) => "stub";
        public string GeneratePlatformAccessToken(User user, string jti, DateTime expiresAt) => "stub";
        public string GenerateRefreshToken() => "stub";
        public ClaimsPrincipal? ValidateToken(string token) => null;
    }

    private static async Task<(AuthController Controller, User User)> SetupAsync(string password)
    {
        var db = TestHelpers.NewInMemoryDb();
        var user = new User
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Email = "owner@example.com",
            FullName = "Owner",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
            Role = UserRole.Admin,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();

        var controller = new AuthController(db, new StubJwtService(), new CustomerAccountService(db));
        TestHelpers.SetUser(controller, user.Id, user.TenantId, Roles.Admin);
        return (controller, user);
    }

    [Fact]
    public async Task ChangePassword_WithCorrectCurrent_RehashesAndOldOneStopsWorking()
    {
        var (controller, user) = await SetupAsync("Demo@12345");

        var result = await controller.ChangePassword(new ChangePasswordDto { CurrentPassword = "Demo@12345", NewPassword = "nandana2004" });

        Assert.IsType<OkObjectResult>(result);
        Assert.True(BCrypt.Net.BCrypt.Verify("nandana2004", user.PasswordHash));
        Assert.False(BCrypt.Net.BCrypt.Verify("Demo@12345", user.PasswordHash));
    }

    [Fact]
    public async Task ChangePassword_WithWrongCurrent_IsRejectedAndNothingChanges()
    {
        var (controller, user) = await SetupAsync("Demo@12345");
        var before = user.PasswordHash;

        var result = await controller.ChangePassword(new ChangePasswordDto { CurrentPassword = "wrong", NewPassword = "nandana2004" });

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(before, user.PasswordHash);
    }

    [Fact]
    public async Task ChangePassword_SameAsCurrent_IsRejected()
    {
        var (controller, _) = await SetupAsync("Demo@12345");
        var result = await controller.ChangePassword(new ChangePasswordDto { CurrentPassword = "Demo@12345", NewPassword = "Demo@12345" });
        Assert.IsType<BadRequestObjectResult>(result);
    }
}
