using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Tests.Api;

/// <summary>
/// Boots the real ASP.NET Core pipeline - routing, JWT authentication, role
/// policies, tenant middleware, model validation, the global exception
/// handler - over an in-memory database, so tests go through HTTP exactly as
/// React and Flutter do. Replaces the old factory that sat, never compiled,
/// under frontend/src.
/// </summary>
public sealed class ApiWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string Password = "Passw0rd!Test";
    public Guid TenantId { get; } = Guid.NewGuid();
    private readonly string _databaseName = $"api-tests-{Guid.NewGuid()}";

    public static string EmailFor(UserRole role) => $"{role.ToString().ToLowerInvariant()}@api-tests.local";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Not Development: the development seeder must not run here.
        builder.UseEnvironment("Testing");
        builder.UseSetting("Jwt:Key", "api-integration-tests-signing-key-0123456789abcdef");
        builder.UseSetting("Jwt:Issuer", "SmeBackend.Tests");
        builder.UseSetting("Jwt:Audience", "SmeBackend.Tests");
        builder.UseSetting("ConnectionStrings:DefaultConnection", "Host=unused");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options => options.UseInMemoryDatabase(_databaseName));

            // Reminder, billing and renewal loops would poll the database
            // on timers; nothing here is about them.
            services.RemoveAll<IHostedService>();
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(TenantId);
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.Tenants.Add(new Tenant { Id = TenantId, Name = "API Test Clinic", BusinessType = "Clinic", IsActive = true });
        var hash = BCrypt.Net.BCrypt.HashPassword(Password, workFactor: 4);
        foreach (var role in new[] { UserRole.Admin, UserRole.Manager, UserRole.Staff, UserRole.Customer })
        {
            db.Users.Add(new User
            {
                TenantId = TenantId,
                Email = EmailFor(role),
                FullName = $"Test {role}",
                PasswordHash = hash,
                Role = role,
                IsActive = true,
            });
        }
        db.SaveChanges();
        return host;
    }
}
