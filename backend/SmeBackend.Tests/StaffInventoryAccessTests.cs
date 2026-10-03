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

    private static User NewUser(UserRole role, Guid? branchId = null) => new()
    {
        Id = Guid.NewGuid(),
        TenantId = Guid.NewGuid(),
        Email = $"{role}@example.test".ToLowerInvariant(),
        FullName = $"{role} User",
        Role = role,
        BranchId = branchId,
    };

    private static ClaimsPrincipal PrincipalFromToken(string token)
    {
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        // Mirror what the JWT bearer middleware does with the role claim.
        var claims = jwt.Claims.Select(c => c.Type == "role" ? new Claim(ClaimTypes.Role, c.Value) : c);
        return new ClaimsPrincipal(new ClaimsIdentity(claims, "TestAuth", "sub", ClaimTypes.Role));
    }

    private static async Task<bool> Authorize(
        ClaimsPrincipal user,
        string component,
        Guid tenantId,
        Guid? branchId,
        bool allowsBranchlessMetadata = false)
    {
        var requirement = new InventoryAccessRequirement(component, allowsBranchlessMetadata);
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
        Assert.Contains("purchase-orders.write", components);
        Assert.DoesNotContain("*", components);
    }

    [Fact]
    public void MobileLoginToken_IsMarkedMobileWhileWebTokenIsNot()
    {
        var user = NewUser(UserRole.Manager);
        var jwt = new JwtService(Config);

        var webClaims = new JwtSecurityTokenHandler().ReadJwtToken(jwt.GenerateAccessToken(user)).Claims;
        var mobileClaims = new JwtSecurityTokenHandler().ReadJwtToken(jwt.GenerateMobileAccessToken(user)).Claims;

        Assert.DoesNotContain(webClaims, claim => claim.Type == InventoryAccessHandler.ClientPlatformClaimType);
        Assert.Contains(mobileClaims, claim =>
            claim.Type == InventoryAccessHandler.ClientPlatformClaimType && claim.Value == "mobile");
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
    [InlineData("inventory.read", false)]
    [InlineData("inventory.write", false)]
    [InlineData("purchase-orders.read", false)]
    [InlineData("purchase-orders.write", false)]
    public async Task StaffToken_IsAuthorizedByInventoryAccessHandler(string component, bool expected)
    {
        var user = NewUser(UserRole.Staff);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        // Purchase-order operations require a branch-scoped resource.
        Assert.Equal(expected, await Authorize(principal, component, user.TenantId, null));
    }

    [Theory]
    [InlineData("inventory.read", true)]
    [InlineData("inventory.write", true)]
    [InlineData("purchase-orders.read", true)]
    [InlineData("purchase-orders.write", true)]
    public async Task StaffToken_IsAuthorizedForGrantedOperationsOnlyOnAssignedBranch(string component, bool expected)
    {
        var assignedBranchId = Guid.NewGuid();
        var user = NewUser(UserRole.Staff, assignedBranchId);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        Assert.Equal(expected, await Authorize(principal, component, user.TenantId, assignedBranchId));
        Assert.False(await Authorize(principal, component, user.TenantId, Guid.NewGuid()));
    }

    [Fact]
    public async Task ManagerToken_IsAuthorizedOnlyForAssignedInventoryBranch()
    {
        var branchId = Guid.NewGuid();
        var user = NewUser(UserRole.Manager, branchId);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        Assert.True(await Authorize(principal, "inventory.read", user.TenantId, branchId));
        Assert.False(await Authorize(principal, "inventory.read", user.TenantId, Guid.NewGuid()));
        Assert.False(await Authorize(principal, "inventory.read", user.TenantId, null));
    }

    [Fact]
    public async Task BranchlessMetadataAccess_IsExplicitAndStillRequiresAssignedBranch()
    {
        var branchId = Guid.NewGuid();
        var manager = NewUser(UserRole.Manager, branchId);
        var managerPrincipal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(manager));
        var staff = NewUser(UserRole.Staff, branchId);
        var staffPrincipal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(staff));

        Assert.True(await Authorize(managerPrincipal, "inventory.read", manager.TenantId, null, true));
        Assert.True(await Authorize(managerPrincipal, "inventory.write", manager.TenantId, null, true));
        Assert.True(await Authorize(staffPrincipal, "inventory.read", staff.TenantId, null, true));
        Assert.False(await Authorize(staffPrincipal, "inventory.write", staff.TenantId, null, true));

        var unassignedManager = NewUser(UserRole.Manager);
        var unassignedPrincipal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(unassignedManager));
        Assert.False(await Authorize(unassignedPrincipal, "inventory.read", unassignedManager.TenantId, null, true));
    }

    [Theory]
    [InlineData("purchase-orders.read")]
    [InlineData("purchase-orders.write")]
    public async Task StaffToken_IsAuthorizedOnlyForAssignedPurchaseOrderBranch(string component)
    {
        var branchId = Guid.NewGuid();
        var user = NewUser(UserRole.Staff, branchId);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        Assert.True(await Authorize(principal, component, user.TenantId, branchId));
        Assert.False(await Authorize(principal, component, user.TenantId, Guid.NewGuid()));
    }

    [Fact]
    public async Task StaffToken_IsNotAuthorizedForAnotherTenant()
    {
        var user = NewUser(UserRole.Staff);
        var principal = PrincipalFromToken(new JwtService(Config).GenerateAccessToken(user));

        Assert.False(await Authorize(principal, "inventory.read", Guid.NewGuid(), null));
    }
}
