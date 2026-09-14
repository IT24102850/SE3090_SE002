using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Services;

namespace SmeBackend.Tests;

public static class TestHelpers
{
    /// A fresh, isolated in-memory AppDbContext per call - fast, no real
    /// Postgres needed, matches the "unit/service test" scope. Pass
    /// [tenantId] when the entities under test carry a tenant query filter
    /// (the Inventory ones do); leaving it null mirrors an unresolved tenant.
    public static AppDbContext NewInMemoryDb(Guid? tenantId = null)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        var tenantContext = new TenantContext();
        if (tenantId.HasValue) tenantContext.SetTenantId(tenantId.Value);
        return new AppDbContext(options, tenantContext);
    }

    /// Sets a fake authenticated ClaimsPrincipal on the controller, matching
    /// the exact claim shape (ClaimTypes.NameIdentifier, ClaimTypes.Role,
    /// "tenantId") every real controller in this codebase already reads
    /// from the JWT.
    public static void SetUser(ControllerBase controller, Guid userId, Guid tenantId, string role)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, userId.ToString()),
            new(ClaimTypes.Role, role),
            new("tenantId", tenantId.ToString()),
        };
        var identity = new ClaimsIdentity(claims, "TestAuth");
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(identity) }
        };
    }
}
