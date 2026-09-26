using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests;

// The same email can exist in more than one tenant (no global unique index),
// which is how a seeded demo tenant shadowed a real business's admin
// account. Login must pick the account whose password matches, not the
// first row it happens to find.
public class LoginAcrossTenantsTests
{
    private sealed class StubJwtService : IJwtService
    {
        public string GenerateAccessToken(User user) => "stub";
        public string GeneratePlatformAccessToken(User user, string jti, DateTime expiresAt) => "stub";
        public string GenerateRefreshToken() => "stub";
        public ClaimsPrincipal? ValidateToken(string token) => null;
    }

    private const string Email = "owner@mirissa.example";
    private static readonly Guid DemoTenantId = Guid.NewGuid();
    private static readonly Guid RealTenantId = Guid.NewGuid();

    private static async Task<AuthController> SetupAsync()
    {
        var db = TestHelpers.NewInMemoryDb();
        db.Tenants.Add(new Tenant { Id = DemoTenantId, Name = "Mirissa (demo seed)", BusinessType = "Tourism" });
        db.Tenants.Add(new Tenant { Id = RealTenantId, Name = "Mirissa JetLiner", BusinessType = "Tourism" });

        // The demo copy was created first, so a naive FirstOrDefault finds it.
        db.Users.Add(new User
        {
            TenantId = DemoTenantId, Email = Email, FullName = "Demo Admin", Role = UserRole.Admin,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("Demo@12345"), CreatedAt = DateTime.UtcNow.AddDays(-30),
        });
        db.Users.Add(new User
        {
            TenantId = RealTenantId, Email = Email, FullName = "Real Owner", Role = UserRole.Admin,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("nandana2004"), CreatedAt = DateTime.UtcNow.AddDays(-2),
        });
        await db.SaveChangesAsync();
        return new AuthController(db, new StubJwtService(), new CustomerAccountService(db));
    }

    private static async Task<Guid?> LoginTenant(AuthController controller, string password)
    {
        var result = await controller.Login(new LoginDto { Email = Email, Password = password });
        if (result.Result is UnauthorizedObjectResult) return null;
        var ok = Assert.IsType<OkObjectResult>(result.Result);
        return Assert.IsType<AuthResponseDto>(ok.Value).User.TenantId;
    }

    [Fact]
    public async Task RealOwnersPassword_SignsIntoTheRealTenant_NotTheDemoCopy()
    {
        var controller = await SetupAsync();
        Assert.Equal(RealTenantId, await LoginTenant(controller, "nandana2004"));
    }

    [Fact]
    public async Task DemoPassword_StillSignsIntoTheDemoTenant()
    {
        var controller = await SetupAsync();
        Assert.Equal(DemoTenantId, await LoginTenant(controller, "Demo@12345"));
    }

    [Fact]
    public async Task WrongPassword_IsRejected_EvenThoughTheEmailExistsTwice()
    {
        var controller = await SetupAsync();
        Assert.Null(await LoginTenant(controller, "not-either"));
    }
}
