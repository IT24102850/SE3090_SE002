using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

namespace SmeBackend.Data;

/// Creates the platform owner's account on first start, in every
/// environment (the console is meant for the deployed site).
///
/// Configuration (appsettings / user-secrets / Platform__* env vars):
///   Platform:OwnerEmail            who the owner is (defaults below)
///   Platform:OwnerPasswordHash     a BCrypt hash - preferred, the plaintext
///                                  never touches a server
///   Platform:OwnerInitialPassword  fallback: plaintext, hashed on the way in
///
/// Only the *first* run reads the password; afterwards the hash in the
/// database is the truth and the owner rotates it from the console. The
/// account lives in its own "Unify Platform" tenant because User.TenantId
/// is required; that tenant is not a business and is skipped by every
/// platform report.
public static class PlatformOwnerSeeder
{
    public const string DefaultOwnerEmail = "hasiruchamika2004@gmail.com";
    public const string PlatformTenantName = "Unify Platform";
    public const string PlatformBusinessType = "Platform";

    public static async Task SeedAsync(AppDbContext db, IConfiguration config, ILogger logger)
    {
        var email = (config["Platform:OwnerEmail"] ?? DefaultOwnerEmail).Trim().ToLowerInvariant();

        var existing = await db.Users.IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.Role == UserRole.SuperAdmin && u.Email == email);
        if (existing != null)
        {
            if (!await db.PlatformAdmins.AnyAsync(a => a.UserId == existing.Id))
            {
                db.PlatformAdmins.Add(new PlatformAdmin { UserId = existing.Id });
                await db.SaveChangesAsync();
            }
            return;
        }

        var passwordHash = config["Platform:OwnerPasswordHash"];
        if (string.IsNullOrWhiteSpace(passwordHash))
        {
            var plain = config["Platform:OwnerInitialPassword"];
            if (string.IsNullOrWhiteSpace(plain))
            {
                logger.LogWarning(
                    "Platform owner {Email} not created: set Platform:OwnerPasswordHash (preferred) or Platform:OwnerInitialPassword.",
                    email);
                return;
            }
            // Work factor 12: roughly twice as slow to brute-force as the
            // default tenant accounts get, on the one account worth it.
            passwordHash = BCrypt.Net.BCrypt.HashPassword(plain, workFactor: 12);
        }

        var tenant = await db.Tenants.IgnoreQueryFilters()
            .FirstOrDefaultAsync(t => t.BusinessType == PlatformBusinessType);
        if (tenant == null)
        {
            tenant = new Tenant { Name = PlatformTenantName, BusinessType = PlatformBusinessType, IsActive = true };
            db.Tenants.Add(tenant);
        }

        var owner = new User
        {
            Tenant = tenant,
            TenantId = tenant.Id,
            Email = email,
            FullName = config["Platform:OwnerName"] ?? "Platform Owner",
            Phone = string.Empty,
            Role = UserRole.SuperAdmin,
            PasswordHash = passwordHash,
            IsActive = true,
            IsApproved = true,
        };
        db.Users.Add(owner);
        db.PlatformAdmins.Add(new PlatformAdmin { User = owner, UserId = owner.Id, PasswordChangedAt = DateTime.UtcNow });
        db.PlatformAuditLogs.Add(new PlatformAuditLog
        {
            ActorEmail = "system",
            Action = "owner.seeded",
            TargetType = "user",
            TargetId = owner.Id,
            TargetLabel = email,
            Detail = "Platform owner account created from configuration.",
        });
        await db.SaveChangesAsync();
        logger.LogInformation("Platform owner {Email} created. MFA enrolment happens on first sign-in.", email);
    }
}
