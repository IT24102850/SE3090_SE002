using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Services;

public interface ICustomerAccountService
{
    /// Creates the global identity, and - when a business is named - its
    /// first membership. Returns the row a token should be minted for.
    Task<User> RegisterAsync(string email, string password, string fullName, string phone, Guid? tenantId, Guid? branchId);

    /// The caller's membership in <paramref name="tenantId"/>, created on
    /// first contact. Returns null when the business cannot be joined.
    Task<User?> JoinAsync(Guid callerUserId, Guid tenantId);

    /// Every User.Id that is the same person: identity + all memberships.
    /// For non-customers this is just the caller's own id.
    Task<List<Guid>> AccountIdsAsync(Guid callerUserId);

    /// Applies a profile change to every row of the account at once.
    Task PropagateProfileAsync(Guid callerUserId, User source);
    Task PropagatePasswordAsync(Guid callerUserId, string passwordHash);
}

/// One customer, many businesses.
///
/// Rather than make User.TenantId nullable - which every dashboard, report,
/// notification and booking join assumes is a real business - a customer is
/// one *identity* row in a hidden pool tenant plus one *membership* row per
/// business, linked through User.LinkedAccountId (see Models/User.cs). The
/// tenant side never changes: a membership is exactly the per-business
/// Customer row it always had. The customer side gains a single sign-in and
/// an automatic join the first time they open a business.
///
/// Legacy customers (per-business rows with no link) keep working: they sign
/// in as before, and joining a second business turns their existing row into
/// the identity of the new membership.
public sealed class CustomerAccountService(AppDbContext db) : ICustomerAccountService
{
    public const string PoolBusinessType = "CustomerPool";
    public const string PoolTenantName = "Unify Customers";

    public async Task<User> RegisterAsync(string email, string password, string fullName, string phone, Guid? tenantId, Guid? branchId)
    {
        email = email.Trim().ToLowerInvariant();
        var pool = await GetOrCreatePoolTenantAsync();
        var hash = BCrypt.Net.BCrypt.HashPassword(password);

        var identity = new User
        {
            Tenant = pool,
            TenantId = pool.Id,
            Email = email,
            PasswordHash = hash,
            FullName = fullName.Trim(),
            Phone = phone?.Trim() ?? string.Empty,
            Role = UserRole.Customer,
            IsActive = true,
            IsApproved = true,
        };
        db.Users.Add(identity);

        if (tenantId is null)
        {
            await db.SaveChangesAsync();
            return identity;
        }

        var membership = new User
        {
            TenantId = tenantId.Value,
            BranchId = branchId,
            Email = email,
            PasswordHash = hash,
            FullName = identity.FullName,
            Phone = identity.Phone,
            Role = UserRole.Customer,
            IsActive = true,
            IsApproved = true,
            LinkedAccountId = identity.Id,
        };
        db.Users.Add(membership);
        await db.SaveChangesAsync();
        return membership;
    }

    public async Task<User?> JoinAsync(Guid callerUserId, Guid tenantId)
    {
        var caller = await db.Users.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(u => u.Id == callerUserId);
        if (caller is null || caller.Role != UserRole.Customer || !caller.IsActive) return null;

        var identityId = caller.LinkedAccountId ?? caller.Id;
        var identity = identityId == caller.Id
            ? caller
            : await db.Users.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(u => u.Id == identityId);
        if (identity is null || !identity.IsActive) return null;

        var tenant = await db.Tenants.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId);
        if (tenant is null || !tenant.IsActive || IsReserved(tenant.BusinessType)) return null;

        // Already a member (or the identity itself lives there).
        if (identity.TenantId == tenantId) return identity;
        var existing = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(u => u.TenantId == tenantId && u.LinkedAccountId == identity.Id);
        if (existing is not null) return existing;

        // A legacy per-business row with the same email becomes the
        // membership rather than a duplicate patient on that business's
        // books. ExecuteUpdate: the row is outside the caller's tenant, and
        // the DbContext save guard would refuse a tracked edit.
        var legacy = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(u => u.TenantId == tenantId && u.Email == identity.Email && u.Role == UserRole.Customer && u.LinkedAccountId == null);
        if (legacy is not null)
        {
            await db.Users.IgnoreQueryFilters().Where(u => u.Id == legacy.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.LinkedAccountId, identity.Id).SetProperty(u => u.UpdatedAt, DateTime.UtcNow));
            legacy.LinkedAccountId = identity.Id;
            return legacy;
        }

        var membership = new User
        {
            TenantId = tenantId,
            Email = identity.Email,
            PasswordHash = identity.PasswordHash,
            FullName = identity.FullName,
            Phone = identity.Phone,
            ProfilePictureUrl = identity.ProfilePictureUrl,
            Address = identity.Address,
            DateOfBirth = identity.DateOfBirth,
            Gender = identity.Gender,
            Role = UserRole.Customer,
            IsActive = true,
            IsApproved = true,
            LinkedAccountId = identity.Id,
        };
        db.Users.Add(membership);
        await db.SaveChangesAsync();
        return membership;
    }

    public async Task<List<Guid>> AccountIdsAsync(Guid callerUserId)
    {
        var caller = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.Id == callerUserId)
            .Select(u => new { u.Id, u.Role, u.LinkedAccountId })
            .FirstOrDefaultAsync();
        if (caller is null) return new List<Guid>();
        if (caller.Role != UserRole.Customer) return new List<Guid> { caller.Id };

        var identityId = caller.LinkedAccountId ?? caller.Id;
        var ids = await db.Users.IgnoreQueryFilters()
            .Where(u => u.LinkedAccountId == identityId)
            .Select(u => u.Id)
            .ToListAsync();
        ids.Add(identityId);
        if (!ids.Contains(caller.Id)) ids.Add(caller.Id);
        return ids;
    }

    public async Task PropagateProfileAsync(Guid callerUserId, User source)
    {
        // The caller's own row was already saved by the controller; only the
        // rest of the account needs the bulk update.
        var ids = (await AccountIdsAsync(callerUserId)).Where(id => id != callerUserId).ToList();
        if (ids.Count == 0) return;
        var now = DateTime.UtcNow;
        await db.Users.IgnoreQueryFilters().Where(u => ids.Contains(u.Id))
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.FullName, source.FullName)
                .SetProperty(u => u.Phone, source.Phone)
                .SetProperty(u => u.Address, source.Address)
                .SetProperty(u => u.InsuranceProvider, source.InsuranceProvider)
                .SetProperty(u => u.InsuranceNumber, source.InsuranceNumber)
                .SetProperty(u => u.MedicalNotes, source.MedicalNotes)
                .SetProperty(u => u.ProfilePictureUrl, source.ProfilePictureUrl)
                .SetProperty(u => u.UpdatedAt, now));
    }

    public async Task PropagatePasswordAsync(Guid callerUserId, string passwordHash)
    {
        var ids = (await AccountIdsAsync(callerUserId)).Where(id => id != callerUserId).ToList();
        if (ids.Count == 0) return;
        var now = DateTime.UtcNow;
        await db.Users.IgnoreQueryFilters().Where(u => ids.Contains(u.Id))
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.PasswordHash, passwordHash).SetProperty(u => u.UpdatedAt, now));
    }

    public static bool IsReserved(string businessType) =>
        businessType == PoolBusinessType || businessType == PlatformOwnerSeeder.PlatformBusinessType;

    private async Task<Tenant> GetOrCreatePoolTenantAsync()
    {
        var pool = await db.Tenants.IgnoreQueryFilters().FirstOrDefaultAsync(t => t.BusinessType == PoolBusinessType);
        if (pool is not null) return pool;
        pool = new Tenant { Name = PoolTenantName, BusinessType = PoolBusinessType, IsActive = true };
        db.Tenants.Add(pool);
        return pool;
    }
}
