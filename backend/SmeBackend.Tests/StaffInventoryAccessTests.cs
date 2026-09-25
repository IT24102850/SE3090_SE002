using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using SmeBackend.Authorization;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests;

// Staff are gated on "component" claims by InventoryAccessHandler, so the
// token JwtService issues for a Staff user must carry the grants the mobile
// device app depends on - otherwise every Staff login is a 403 on inventory.
public class StaffInventoryAccessTests
{
    private static readonly IConfiguration Config = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Jwt:Key"] = "unit-test-signing-key-that-is-at-least-32-bytes-long",
            ["Jwt:Issuer"] = "SmePlatform",
            ["Jwt:Audience"] = "SmePlatformClients",
        })
        .Build();

    private static User NewUser(UserRole role) => new()
    {
        Id = Guid.NewGuid(),
        TenantId = Guid.NewGuid(),
        Email = $"{role}@example.test".ToLowerInvariant(),
        FullName = $"{role} User",
        Role = role,
    };

    private static ClaimsPrincipal PrincipalFromToken(string token)
    {
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        // Mirror what the JWT bearer middleware does with the role claim.
        var claims = jwt.Claims.Select(c => c.Type == "role" ? new Claim(ClaimTypes.Role, c.Value) : c);
        return new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth", "sub", ClaimTypes.Role));
    }

    private static async Task<bool> Authorize(ClaimsPrincipal user, string component, Guid tenantId, Guid? branchId)
    {
        var requirement = new InventoryAccessRequirement(component);
        var context = new AuthorizationHandlerContext(
            new[] { requirement }, user, new InventoryAccessResource(tenantId, branchId));
        await new InventoryAccessHandler().HandleAsync(context);
        return context.HasSucceeded;
    }

    [Fact]
    public void StaffToken_CarriesMobileComponentGrants()
    {
        var token = new JwtService(Config).GenerateAccessToken(NewUser(UserRole.Staff));

        var components = new JwtSecurityTokenHandler().ReadJwtToken(token)
            .Claims.Where(c => c.Type == InventoryAccessHandler.ComponentClaimType)
            .Select(c => c.Value)
            .ToArray();

        Assert.Equal(JwtService.StaffComponentGrants.OrderBy(c => c), components.OrderBy(c => c));
        Assert.Contains("inventory.read", components);
        Assert.Contains("inventory.write", components);
        Assert.Contains("purchase-orders.read", components);
        Assert.DoesNotContain("purchase-orders.write", components);
        Assert.DoesNotContain("*", components);
    }

    [Theory]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.Manager)]
    [InlineData(UserRole.Customer)]
    public void NonStaffToken_HasNoComponentGrants(UserRole role)
    {
        var token = new JwtService(Config).GenerateAccessToken(NewUser(role));

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.DoesNotContain(jwt.Claims, c => c.Type == InventoryAccessHandler.ComponentClaimType);
    }

    [Theory]
    [InlineData("inventory.read", true)]
    [InlineData("inventory.write", true)]
    [InlineData("purchase-orders.read", true)]
    [InlineData("purchase-orders.write", false)]
    public async Task StaffToken_IsAuthorizedByInventoryAccessHandler(string component, bool expected)
    {
        var user = NewUser(UserRole.Staff);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        // Tenant-wide scope (no branch), which is what the mobile list calls use.
        Assert.Equal(expected, await Authorize(principal, component, user.TenantId, null));
    }

    [Fact]
    public async Task StaffToken_IsNotAuthorizedForAnotherTenant()
    {
        var user = NewUser(UserRole.Staff);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        Assert.False(await Authorize(principal, "inventory.read", Guid.NewGuid(), null));
    }
}
